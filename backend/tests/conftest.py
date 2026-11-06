import httpx
import pytest

from app.core.config import Settings
from app.main import create_app


@pytest.fixture(autouse=True)
def isolated_environment(monkeypatch):
    for key in ("BLUEFLORA_ENVIRONMENT", "BLUEFLORA_APP_NAME", "BLUEFLORA_DOCS_ENABLED"):
        monkeypatch.delenv(key, raising=False)


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.fixture
async def client():
    config = Settings(_env_file=None, environment="test")
    transport = httpx.ASGITransport(app=create_app(config))
    async with httpx.AsyncClient(transport=transport, base_url="http://testserver") as test_client:
        yield test_client
