from app.modules.common.mutation import mutate, read_response, representation, mutation_contract
from uuid import UUID
from fastapi import APIRouter,Depends,Query,Request
from app.modules.auth.router import token
from app.modules.common.dependencies import resources
from app.modules.common.schemas import Page
from app.modules.watering.schemas import WateringCreate,WateringRead
from app.modules.watering.service import WateringService

router=APIRouter(prefix='/api/v1',tags=['manual watering'])


def service(repository=Depends(resources)): return WateringService(repository)


@router.post('/plants/{identifier}/watering-events',response_model=WateringRead,status_code=201,openapi_extra=mutation_contract())
def create(request:Request,identifier:UUID,body:WateringCreate,access=Depends(token),svc=Depends(service)):
    return mutate(request,access,svc.repository,'watering_event.create',body,identifier)


@router.get('/plants/{identifier}/watering-events',response_model=Page[WateringRead])
def individual(identifier:UUID,limit:int=Query(20,ge=1,le=100),offset:int=Query(0,ge=0,le=1000000),access=Depends(token),svc=Depends(service)):
    return representation(svc.individual(access,identifier,limit,offset),'watering')


@router.get('/watering-events',response_model=Page[WateringRead])
def listing(limit:int=Query(20,ge=1,le=100),offset:int=Query(0,ge=0,le=1000000),plant_id:UUID|None=None,access=Depends(token),svc=Depends(service)):
    return representation(svc.list(access,limit,offset,plant_id),'watering')


@router.get('/watering-events/{identifier}',response_model=WateringRead)
def get(identifier:UUID,access=Depends(token),svc=Depends(service)):
    return read_response(svc.get(access,identifier),'watering')
