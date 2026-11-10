"""Una transacción para validar sesión, fijar propietario y operar con RLS."""
from contextlib import contextmanager
from dataclasses import dataclass
from uuid import UUID
from sqlalchemy import select, func, text
from sqlalchemy.exc import DBAPIError
from fastapi import HTTPException
from app.db.connection import set_owner
from app.modules.auth.security import digest, valid_token
from app.modules.auth.service import unauthorized


def not_found():
    return HTTPException(404, detail={'code':'resource_not_found','message':'Recurso no encontrado.'})


def conflict():
    return HTTPException(409, detail={'code':'resource_conflict','message':'La operación entra en conflicto con los datos actuales.'})


@dataclass
class OwnedSession:
    connection: object
    owner_id: UUID

    def one(self, table, identifier, *, lock=False, active=False):
        schema=self.connection.get_execution_options()['schema_translate_map'][None]
        expression="to_jsonb(t)-ARRAY['owner_id','baseline_last_watered_at','baseline_source']"
        if table.name!='species':
            revision="t.revision::text" if 'revision' in table.c else "'1'::text"
            expression+=f" || jsonb_build_object('revision',{revision})"
        for column in table.c:
            if column.name.endswith('_at') and column.name!='baseline_last_watered_at':
                expression+=f" || jsonb_build_object('{column.name}',to_char(t.{column.name} AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"'))"
        condition=' AND t.deleted_at IS NULL' if active else ''
        suffix=' FOR UPDATE' if lock else ''
        query=f'SELECT t.*,encode(convert_to(({expression})::text,\'UTF8\'),\'hex\') AS __body_hex FROM "{schema}".{table.name} t WHERE t.id=:id{condition}{suffix}'
        row=self.connection.execute(text(query),{'id':identifier}).mappings().first()
        if row is None: raise not_found()
        return dict(row)

    def page(self, table, limit, offset, *, conditions=(), order=None):
        total = self.connection.scalar(select(func.count()).select_from(table).where(*conditions))
        order = order or (table.c.created_at, table.c.id)
        rows = self.connection.execute(select(table).where(*conditions).order_by(*order).limit(limit).offset(offset)).mappings().all()
        return {'items':[dict(row) for row in rows], 'total':total, 'limit':limit, 'offset':offset}


class ResourceRepository:
    def __init__(self, auth_repository):
        self.auth = auth_repository

    @contextmanager
    def transaction(self, access):
        if not valid_token(access, 'a'):
            raise unauthorized()
        with self.auth.transaction() as connection:
            identity = connection.execute(text(f'SELECT * FROM {self.auth.schema}.auth_access(:hash)'),
                                          {'hash':digest(access)}).mappings().first()
            if identity is None:
                raise unauthorized()
            set_owner(connection, identity['user_id'])
            connection = connection.execution_options(schema_translate_map={None:self.auth.schema[1:-1]})
            self.verify_schema(connection)
            yield OwnedSession(connection, identity['user_id'])

    def apply(self, access, operation_id, frozen):
        for attempt in range(3):
            try:
                with self.transaction(access) as tx:
                    result=tx.connection.scalar(text(f'SELECT {self.auth.schema}.resource_apply(:id,:request)'), {'id':operation_id,'request':frozen})
                return result  # Solo después de confirmar la transacción.
            except DBAPIError as exc:
                if getattr(exc.orig,'sqlstate',None) not in ('40P01','40001') or attempt==2:
                    raise

    def verify_schema(self, connection):
        from app.db.connection import DatabaseConfigurationError
        s=self.auth.schema
        expected_owner='blueflora_test' if self.auth.purpose=='test' else 'blueflora_dev'
        if connection.scalar(text("SELECT has_schema_privilege(current_user,:schema,'CREATE') OR NOT has_schema_privilege(current_user,:schema,'USAGE')"),{'schema':s[1:-1]}):
            raise DatabaseConfigurationError('Permisos de esquema incompatibles.')
        # Bootstrap before invoking privileged code; the full manifest lives only
        # in SQL. No duplicate Python list of table/policy/constraint expectations.
        fn=connection.execute(text("""SELECT p.prosecdef,p.proconfig,pg_get_userbyid(p.proowner) owner,
            p.proisstrict,p.proretset,p.prokind,p.pronargdefaults,l.lanname,
            format_type(p.prorettype,NULL) result,
            (SELECT count(*) FROM pg_proc x WHERE x.pronamespace=p.pronamespace AND x.proname=p.proname) variants,
            has_function_privilege(current_user,p.oid,'EXECUTE') executable,
            NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE a.grantee=0 AND a.privilege_type='EXECUTE') private
            FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
            WHERE p.oid=to_regprocedure(:signature)"""),{'signature':s+'.resource_apply(uuid,text)'}).mappings().first()
        if (not fn or not fn['prosecdef'] or not fn['executable'] or not fn['private']
            or fn['owner']!=expected_owner or fn['proisstrict'] or fn['proretset']
            or fn['prokind']!='f' or fn['pronargdefaults']!=0 or fn['lanname']!='plpgsql'
            or fn['result']!='jsonb' or fn['variants']!=1
            or sorted(fn['proconfig'] or [])!=['TimeZone=UTC','search_path=pg_catalog, pg_temp']):
            raise DatabaseConfigurationError('Esquema de recursos incompatible.')
        try:
            result=connection.scalar(text(f'SELECT {s}.resource_apply(NULL,NULL)'))
        except DBAPIError as exc:
            if getattr(exc.orig,'sqlstate',None)=='55000':
                raise DatabaseConfigurationError('Capacidades de recursos incompatibles.') from None
            raise
        if result!={'ready':True,'manifest':'e4-r1-pg18'}:
            raise DatabaseConfigurationError('Esquema incompatible.')
