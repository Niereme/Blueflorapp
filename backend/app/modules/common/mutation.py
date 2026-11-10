"""Adaptador REST versionado; el estado y las decisiones semánticas pertenecen a SQL."""
from datetime import datetime, timezone
from uuid import UUID
import json
import re
import rfc8785
from fastapi import HTTPException, Request, Response
from fastapi.encoders import jsonable_encoder

LIMIT=65536


def invalid(status=422):
    return HTTPException(status, detail={'code':'invalid_request','message':'Revisa los campos y el formato de la solicitud.'})


def normalize(value):
    if isinstance(value, UUID): return str(value)
    if isinstance(value, datetime): return value.astimezone(timezone.utc).isoformat(timespec='microseconds').replace('+00:00','Z')
    if isinstance(value, dict): return {k:normalize(v) for k,v in value.items()}
    if isinstance(value, list): return [normalize(v) for v in value]
    return value


def canonical(operation_id,action,target,payload,if_match=None):
    try:
        envelope=normalize(dict(format='rest-v1',operation_id=operation_id,action=action,target=target,if_match=if_match,payload=payload))
        result=rfc8785.dumps(envelope)
    except (ValueError, OverflowError, rfc8785.CanonicalizationError): raise invalid() from None
    if len(result)>LIMIT: raise invalid(413)
    return result.decode('utf-8')


def etag(kind,row):
    return f'"bf1-{kind}-{row["id"]}-r{row.get("revision","1")}"'


def representation(row,kind):
    # Sin joins ni campos derivados mutables. Mismo formato que la respuesta SQL.
    if isinstance(row,list): return [representation(x,kind) for x in row]
    row=dict(row)
    if 'items' in row:
        return {**row,'items':[representation(x,kind) for x in row['items']]}
    for k in ('owner_id','baseline_last_watered_at','baseline_source','__body_hex'): row.pop(k,None)
    if kind!='species': row['revision']=str(row.get('revision','1'))
    return jsonable_encoder(normalize(row))


def read_response(row,kind):
    rep=representation(row,kind)
    return Response(bytes.fromhex(row['__body_hex']),media_type='application/json',headers={'ETag':etag(kind,rep)})


def durable_response(result):
    headers={k:v for k,v in [('Location',result.get('location')),('ETag',result.get('etag')),('Content-Type',result.get('content_type'))] if v is not None}
    return Response(bytes.fromhex(result['body_hex']),status_code=result['status'],headers=headers)


def mutate(request:Request,access,repository,action,body=None,target=None):
    def single(name,required=True):
        values=request.headers.getlist(name)
        if not values and not required: return None
        if len(values)!=1: raise invalid()
        return values[0]
    try: operation_id=UUID(single('Idempotency-Key'))
    except (ValueError,TypeError,AttributeError): raise invalid() from None
    match=single('If-Match',False)
    kind,verb=action.split('.')
    if verb in ('update','delete'):
        if match is None: raise invalid(428)
        pattern=r'"bf1-'+kind+'-'+str(target)+r'-r([1-9][0-9]{0,18})"'
        parsed=re.fullmatch(pattern,match)
        if not parsed or int(parsed[1])>9223372036854775807: raise invalid()
    elif match is not None: raise invalid()
    payload={} if body is None else body.model_dump(exclude_unset=True)
    frozen=canonical(operation_id,action,target,payload,match)
    return durable_response(repository.apply(access,operation_id,frozen))


class ResourceInputLimits:
    """ASGI: limitar bytes/profundidad antes de json.loads y detectar claves repetidas."""
    def __init__(self,app): self.app=app

    async def __call__(self,scope,receive,send):
        path=scope.get('path','')
        resource=path.startswith('/api/v1/') and not any(path.startswith('/api/v1/'+p) for p in ('auth/','me'))
        if scope['type']!='http' or scope.get('method') not in ('POST','PATCH','DELETE') or not resource:
            return await self.app(scope,receive,send)
        data=bytearray(); size=0
        async def fail(status):
            response=Response(b'{"detail":{"code":"invalid_request","message":"Solicitud invalida."}}',status_code=status,media_type='application/json',headers={'Cache-Control':'no-store','Pragma':'no-cache'})
            await response(scope,receive,send)
        while True:
            message=await receive()
            if message['type']=='http.disconnect': return
            part=message.get('body',b''); size+=len(part)
            if size>LIMIT: return await fail(413)
            data.extend(part)
            if not message.get('more_body',False): break
        depth=0; quoted=False; escaped=False
        for ch in data:
            if quoted:
                if escaped: escaped=False
                elif ch==92: escaped=True
                elif ch==34: quoted=False
            elif ch==34: quoted=True
            elif ch in (123,91):
                depth+=1
                if depth>16: return await fail(422)
            elif ch in (125,93): depth-=1
        if data:
            content_types=[v.decode('latin1') for k,v in scope['headers'] if k==b'content-type']
            if len(content_types)!=1 or content_types[0].split(';')[0].strip().lower()!='application/json': return await fail(415)
            try:
                def pairs(values):
                    result={}
                    for key,value in values:
                        if key in result: raise ValueError('Clave duplicada')
                        result[key]=value
                    return result
                def constant(value): raise ValueError('No finito')
                def valid_text(value):
                    if isinstance(value,str):
                        if '\x00' in value: raise ValueError('PostgreSQL text no admite NUL')
                        value.encode('utf-8')
                    elif isinstance(value,dict):
                        for k,v in value.items(): valid_text(k); valid_text(v)
                    elif isinstance(value,list):
                        for v in value: valid_text(v)
                parsed=json.loads(data,object_pairs_hook=pairs,parse_constant=constant)
                # Rechaza surrogates antes de perderlos en los DTO.
                valid_text(parsed)
                if scope['method']=='DELETE': raise ValueError('DELETE no acepta cuerpo')
            except (ValueError,UnicodeError,RecursionError): return await fail(422)
        consumed=False
        async def replay():
            nonlocal consumed
            if not consumed:
                consumed=True
                return {'type':'http.request','body':bytes(data),'more_body':False}
            return await receive()
        await self.app(scope,replay,send)


def mutation_contract(cas=False):
    parameters=[{'name':'Idempotency-Key','in':'header','required':True,
        'description':'UUID estable de la intención; namespace por propietario compartido entre recursos.',
        'schema':{'type':'string','format':'uuid'}}]
    if cas:
        parameters.append({'name':'If-Match','in':'header','required':True,
            'description':'Un ETag fuerte individual bf1; sin wildcard, listas o W/.',
            'schema':{'type':'string'}})
    return {'parameters':parameters,'responses':{
        '409':{'description':'Conflicto durable o clave reutilizada con otra intención.'},
        '412':{'description':'Revisión propia obsoleta; resultado durable.'},
        '422':{'description':'Entrada estructural inválida o rechazo semántico durable.'},
        '428':{'description':'If-Match ausente en PATCH/DELETE.'},
        '503':{'description':'Almacenamiento/esquema no disponible; no se confirma un recibo parcial.'}}}
