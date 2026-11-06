"""Endpoints JSON de cuentas propias; sin cookies, correo ni servicios externos."""
from fastapi import APIRouter, Depends, Request, Response
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from app.modules.auth.schemas import (AccountResponse, Credentials, RefreshRequest,
                                      Registration, RegistrationResponse, TokenResponse)
from app.modules.auth.service import unauthorized

router = APIRouter(prefix='/api/v1', tags=['accounts'])
bearer = HTTPBearer(auto_error=False)


def token(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)):
    if not credentials or credentials.scheme.lower() != 'bearer':
        raise unauthorized()
    return credentials.credentials


def service(request: Request):
    return request.app.state.auth_service


def address(request):
    # No confiar en X-Forwarded-For enviado directamente por un cliente.
    return request.client.host if request.client else 'unknown'


def limit_auth_ip(request: Request):
    service(request).limit('auth', address(request))


@router.post('/auth/register', response_model=RegistrationResponse, status_code=202,
             dependencies=[Depends(limit_auth_ip)])
def register(body: Registration, request: Request):
    auth = service(request)
    auth.limit('register', address(request), body.email)
    auth.register(body)
    return RegistrationResponse()


@router.post('/auth/login', response_model=TokenResponse, dependencies=[Depends(limit_auth_ip)])
def login(body: Credentials, request: Request):
    auth = service(request)
    auth.limit('login', address(request), body.email)
    return auth.login(body)


@router.post('/auth/refresh', response_model=TokenResponse, dependencies=[Depends(limit_auth_ip)])
def refresh(body: RefreshRequest, request: Request):
    return service(request).refresh(body.refresh_token.get_secret_value())


@router.post('/auth/logout', status_code=204)
def logout(request: Request, access: str = Depends(token)):
    service(request).logout(access)
    return Response(status_code=204)


@router.get('/me', response_model=AccountResponse)
def me(request: Request, access: str = Depends(token)):
    return service(request).me(access)
