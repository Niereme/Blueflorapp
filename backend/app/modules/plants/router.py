from uuid import UUID
from fastapi import APIRouter, Depends, Query, Response
from app.modules.auth.router import token
from app.modules.common.dependencies import resources
from app.modules.common.schemas import Page
from app.modules.plants.schemas import GrowthCreate, GrowthRead, PlantCreate, PlantPatch, PlantRead, SpeciesRead
from app.modules.plants.service import GrowthService, PlantService, SpeciesService

router=APIRouter(prefix='/api/v1',tags=['plants'])


def service(repository=Depends(resources)): return PlantService(repository)
def catalog(repository=Depends(resources)): return SpeciesService(repository)
def history(repository=Depends(resources)): return GrowthService(repository)


@router.post('/plants',response_model=PlantRead,status_code=201)
def create(body:PlantCreate,access=Depends(token),svc=Depends(service)):
    return svc.create(access,body)


@router.get('/plants',response_model=Page[PlantRead])
def listing(limit:int=Query(20,ge=1,le=100),offset:int=Query(0,ge=0,le=1000000),include_deleted:bool=False,access=Depends(token),svc=Depends(service)):
    return svc.list(access,limit,offset,include_deleted)


@router.get('/plants/{identifier}',response_model=PlantRead)
def get(identifier:UUID,access=Depends(token),svc=Depends(service)):
    return svc.get(access,identifier)


@router.patch('/plants/{identifier}',response_model=PlantRead)
def patch(identifier:UUID,body:PlantPatch,access=Depends(token),svc=Depends(service)):
    return svc.patch(access,identifier,body)


@router.delete('/plants/{identifier}',status_code=204)
def remove(identifier:UUID,access=Depends(token),svc=Depends(service)):
    svc.delete(access,identifier)
    return Response(status_code=204)


@router.get('/species',response_model=Page[SpeciesRead],tags=['species'])
def species_list(limit:int=Query(20,ge=1,le=100),offset:int=Query(0,ge=0,le=1000000),access=Depends(token),svc=Depends(catalog)):
    return svc.list(access,limit,offset)


@router.get('/species/{identifier}',response_model=SpeciesRead,tags=['species'])
def species_get(identifier:UUID,access=Depends(token),svc=Depends(catalog)):
    return svc.get(access,identifier)


@router.post('/plants/{identifier}/growth-history',response_model=GrowthRead,status_code=201,tags=['growth'])
def growth_create(identifier:UUID,body:GrowthCreate,access=Depends(token),svc=Depends(history)):
    return svc.create(access,identifier,body)


@router.get('/plants/{identifier}/growth-history',response_model=Page[GrowthRead],tags=['growth'])
def growth_individual(identifier:UUID,limit:int=Query(20,ge=1,le=100),offset:int=Query(0,ge=0,le=1000000),access=Depends(token),svc=Depends(history)):
    return svc.individual(access,identifier,limit,offset)


@router.get('/growth-history',response_model=Page[GrowthRead],tags=['growth'])
def growth_list(limit:int=Query(20,ge=1,le=100),offset:int=Query(0,ge=0,le=1000000),plant_id:UUID|None=None,access=Depends(token),svc=Depends(history)):
    return svc.list(access,limit,offset,plant_id)


@router.get('/growth-history/{identifier}',response_model=GrowthRead,tags=['growth'])
def growth_get(identifier:UUID,access=Depends(token),svc=Depends(history)):
    return svc.get(access,identifier)
