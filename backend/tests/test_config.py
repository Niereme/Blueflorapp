import pytest
from pydantic import ValidationError

from app.core.config import Settings


def test_defaults_do_not_require_external_services():
    config = Settings(_env_file=None)
    assert config.environment == "development"
    assert config.app_name == "BlueFlora API"
    assert config.docs_enabled is True


def test_environment_overrides_dotenv(monkeypatch, tmp_path):
    env = tmp_path / ".env"
    env.write_text(
        "BLUEFLORA_APP_NAME=Desde archivo\nBLUEFLORA_ENVIRONMENT=test\n",
        encoding="utf-8",
    )
    monkeypatch.setenv("BLUEFLORA_APP_NAME", "Desde entorno")
    config = Settings(_env_file=env)
    assert config.app_name == "Desde entorno"
    assert config.environment == "test"


def test_explicit_settings_override_environment(monkeypatch):
    monkeypatch.setenv("BLUEFLORA_APP_NAME", "Desde entorno")
    assert Settings(_env_file=None, app_name="Explícito").app_name == "Explícito"


@pytest.mark.parametrize(
    "field,value",
    [("environment", "staging-typo"), ("docs_enabled", "perhaps"), ("app_name", "")],
)
def test_invalid_configuration_fails_early(field, value):
    with pytest.raises(ValidationError):
        Settings(_env_file=None, **{field: value})


def test_dotenv_path_does_not_depend_on_working_directory(monkeypatch, tmp_path):
    from app.core.config import BACKEND_ROOT
    assert Settings.model_config["env_file"] == BACKEND_ROOT / ".env"
    monkeypatch.chdir(tmp_path)
    assert Settings.model_config["env_file"] == BACKEND_ROOT / ".env"
