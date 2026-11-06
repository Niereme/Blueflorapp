from uuid import UUID
from fastapi import APIRouter, Depends, Query, Response
from app.modules.auth.router import token
from app.modules.common.dependencies import resources
from app.modules.common.schemas import Page
from app.modules.gardens.schemas import GardenCreate, GardenPatch, GardenRead
from app.modules.gardens.service import GardenService

router = APIRouter(prefix='/api/v1/gardens', tags=['gardens'])


def service(repository=Depends(resources)): return GardenService(repository)


@router.post('', response_model=GardenRead, status_code=201)
def create(body: GardenCreate, access=Depends(token), svc=Depends(service)):
    return svc.create(access, body)


@router.get('', response_model=Page[GardenRead])
def listing(limit: int=Query(20,ge=1,le=100), offset: int=Query(0,ge=0,le=1000000), access=Depends(token), svc=Depends(service)):
    return svc.list(access, limit, offset)


@router.get('/{identifier}', response_model=GardenRead)
def get(identifier: UUID, access=Depends(token), svc=Depends(service)):
    return svc.get(access, identifier)


@router.patch('/{identifier}', response_model=GardenRead)
def patch(identifier: UUID, body: GardenPatch, access=Depends(token), svc=Depends(service)):
    return svc.patch(access, identifier, body)


@router.delete('/{identifier}', status_code=204)
def remove(identifier: UUID, access=Depends(token), svc=Depends(service)):
    svc.delete(access, identifier)
    return Response(status_code=204)
