from app.modules.common.mutation import mutate, read_response, representation, mutation_contract
from uuid import UUID
from fastapi import APIRouter, Depends, Query, Response, Request
from app.modules.auth.router import token
from app.modules.common.dependencies import resources
from app.modules.common.schemas import Page
from app.modules.gardens.schemas import GardenCreate, GardenPatch, GardenRead
from app.modules.gardens.service import GardenService

router = APIRouter(prefix='/api/v1/gardens', tags=['gardens'])


def service(repository=Depends(resources)): return GardenService(repository)


@router.post('', response_model=GardenRead, status_code=201,openapi_extra=mutation_contract())
def create(request: Request, body: GardenCreate, access=Depends(token), svc=Depends(service)):
    return mutate(request,access,svc.repository,'garden.create',body)


@router.get('', response_model=Page[GardenRead])
def listing(include_deleted: bool=False, limit: int=Query(20,ge=1,le=100), offset: int=Query(0,ge=0,le=1000000), access=Depends(token), svc=Depends(service)):
    return representation(svc.list(access, limit, offset,include_deleted),'garden')


@router.get('/{identifier}', response_model=GardenRead)
def get(identifier: UUID, access=Depends(token), svc=Depends(service)):
    return read_response(svc.get(access, identifier),'garden')


@router.patch('/{identifier}', response_model=GardenRead,openapi_extra=mutation_contract(True))
def patch(request: Request, identifier: UUID, body: GardenPatch, access=Depends(token), svc=Depends(service)):
    return mutate(request,access,svc.repository,'garden.update',body,identifier)


@router.delete('/{identifier}', status_code=204,openapi_extra=mutation_contract(True))
def remove(request: Request, identifier: UUID, access=Depends(token), svc=Depends(service)):
    return mutate(request,access,svc.repository,'garden.delete',target=identifier)
