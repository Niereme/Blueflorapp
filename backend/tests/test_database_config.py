import pytest
from app.core.config import Settings
from app.db.connection import DatabaseConfigurationError, create_database_engine, database_url


def settings(url=None, test_url=None):
    return Settings(_env_file=None, database_url=url, test_database_url=test_url)


def url(database="blueflora_dev", user="blueflora_dev", host="127.0.0.1"):
    return f"postgresql+psycopg://{user}:not-a-real-password@{host}:5432/{database}"


def test_missing_url_fails_without_leaking_credentials():
    with pytest.raises(DatabaseConfigurationError, match="Falta configurar"):
        database_url(settings())


@pytest.mark.parametrize("value", [
    "sqlite:///tmp.db", url(host="example.com"), url(database="postgres"),
    url(user="postgres"), url(database="blueflora_test", user="blueflora_test"),
    url()+"?host=example.com", url().replace(":5432", ":5555"),
    "not-a-url", url().replace(":not-a-real-password", ""),
])
def test_development_rejects_wrong_database_driver_host_or_role(value):
    with pytest.raises(DatabaseConfigurationError) as exc:
        database_url(settings(value))
    assert "not-a-real-password" not in str(exc.value)


def test_test_database_never_falls_back_to_development():
    with pytest.raises(DatabaseConfigurationError):
        database_url(settings(url()), "test")
    with pytest.raises(DatabaseConfigurationError):
        database_url(settings(test_url=url()), "test")


def test_urls_are_secret_in_settings_representation():
    config = settings(url())
    assert "not-a-real-password" not in repr(config)
    assert "not-a-real-password" not in config.model_dump_json()


def test_engine_creation_does_not_connect():
    engine = create_database_engine(settings(url()))
    assert engine.dialect.driver == "psycopg"
    assert engine.hide_parameters is True
    engine.dispose()


def test_invalid_purpose_is_rejected():
    with pytest.raises(DatabaseConfigurationError):
        database_url(settings(url()), "production")


def test_api_engine_never_uses_migration_credentials_as_fallback():
    from app.db.connection import create_api_engine
    with pytest.raises(DatabaseConfigurationError):
        create_api_engine(settings(url()))


@pytest.mark.parametrize('value', [
    'postgresql+psycopg://blueflora_dev:not-real@127.0.0.1:5432/blueflora_dev',
    'postgresql+psycopg://blueflora_api:not-real@127.0.0.1:5432/blueflora_test',
    'postgresql+psycopg://blueflora_api:not-real@example.com:5432/blueflora_dev',
    'postgresql+psycopg://blueflora_api:not-real@127.0.0.1:5432/blueflora_dev?host=elsewhere',
])
def test_api_engine_rejects_incorrect_role_database_or_host(value):
    from app.db.connection import create_api_engine
    with pytest.raises(DatabaseConfigurationError):
        create_api_engine(Settings(_env_file=None,api_database_url=value))


def test_api_connection_secrets_are_masked():
    config = Settings(_env_file=None,api_database_url='not-a-real-secret',test_api_database_url='other-secret')
    assert 'not-a-real-secret' not in repr(config)
    assert 'other-secret' not in config.model_dump_json()
