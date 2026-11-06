"""Composición de la API. No inicializa PostgreSQL ni dispositivos."""
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy.exc import SQLAlchemyError
from app.db.connection import DatabaseConfigurationError, create_api_engine
from app.modules.auth.repository import AuthRepository
from app.modules.auth.service import AuthService
from app.modules.auth.router import router as auth_router
from app.modules.common.repository import ResourceRepository
from app.modules.gardens.router import router as gardens_router
from app.modules.plants.router import router as plants_router
from app.modules.watering.router import router as watering_router

from app.core.config import Settings
from app.modules.health.router import router as health_router


def create_app(settings: Settings | None = None, *, auth_service: AuthService | None = None) -> FastAPI:
    config = settings if settings is not None else Settings()
    application = FastAPI(
        title=config.app_name,
        docs_url="/docs" if config.docs_enabled else None,
        redoc_url=None,
        openapi_url="/openapi.json" if config.docs_enabled else None,
    )
    application.state.settings = config
    application.include_router(health_router)
    if auth_service is not None or config.api_database_url is not None:
        application.state.auth_service = auth_service or AuthService(AuthRepository(create_api_engine(config)))
        application.include_router(auth_router)
        if hasattr(application.state.auth_service.repository, 'transaction'):
            application.state.resource_repository = ResourceRepository(application.state.auth_service.repository)
            for router in (gardens_router, plants_router, watering_router):
                application.include_router(router)

    @application.exception_handler(RequestValidationError)
    async def validation_error(request: Request, exc: RequestValidationError):
        # No devolver exc.errors(): incluye inputs originales y podría exponer secretos.
        return JSONResponse(status_code=422, content={"detail": {
            "code": "invalid_request", "message": "Revisa los campos y el formato de la solicitud."}})

    async def database_error(request: Request, exc: Exception):
        return JSONResponse(status_code=503, content={"detail": {
            "code": "service_unavailable", "message": "Servicio temporalmente no disponible."}})

    application.add_exception_handler(SQLAlchemyError, database_error)
    application.add_exception_handler(DatabaseConfigurationError, database_error)

    @application.middleware("http")
    async def private_responses(request: Request, call_next):
        response = await call_next(request)
        if request.url.path.startswith('/api/v1/'):
            response.headers['Cache-Control'] = 'no-store'
            response.headers['Pragma'] = 'no-cache'
        return response

    return application
