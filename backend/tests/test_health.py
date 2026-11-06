import httpx
import pytest

from app.core.config import Settings
from app.main import create_app


@pytest.mark.anyio
async def test_liveness_returns_minimal_response(client):
    response = await client.get("/health/live")
    assert response.status_code == 200
    assert response.headers["content-type"] == "application/json"
    assert response.json() == {"status": "ok"}


@pytest.mark.anyio
async def test_liveness_is_read_only(client):
    assert (await client.post("/health/live")).status_code == 405


@pytest.mark.anyio
async def test_only_health_business_route_is_registered(client):
    for path in (
        "/api/v1/plants",
        "/api/v1/auth/login",
        "/api/v1/sync/push",
        "/device-api/v1/commands/claim",
        "/health/ready",
    ):
        assert (await client.get(path)).status_code == 404
    assert list((await client.get("/openapi.json")).json()["paths"]) == ["/health/live"]


@pytest.mark.anyio
async def test_disabled_docs_do_not_disable_liveness():
    app = create_app(Settings(_env_file=None, docs_enabled=False))
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://testserver"
    ) as client:
        assert (await client.get("/health/live")).json() == {"status": "ok"}
        assert (await client.get("/docs")).status_code == 404
        assert (await client.get("/openapi.json")).status_code == 404


def test_app_factory_has_independent_configuration():
    first = create_app(Settings(_env_file=None, app_name="Instancia A"))
    second = create_app(Settings(_env_file=None, app_name="Instancia B"))
    assert first.title == "Instancia A"
    assert second.title == "Instancia B"
