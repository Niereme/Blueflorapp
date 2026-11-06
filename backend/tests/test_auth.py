"""HTTP y permisos con el rol API real; nunca credenciales de migración en la API."""
from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4
from types import SimpleNamespace

import httpx
import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError
from app.core.config import BACKEND_ROOT, Settings
from app.db.connection import create_api_engine, create_database_engine, set_owner, verify_api
from app.main import create_app
from app.modules.auth.repository import AuthRepository
from app.modules.auth.security import digest, HASHER
from app.modules.auth.service import AuthService

pytestmark = pytest.mark.postgres
PASSWORD = 'Una contraseña larga para pruebas'


@pytest.fixture
def auth_db():
    config = Settings()
    if config.test_database_url is None or config.test_api_database_url is None:
        pytest.skip('Faltan las conexiones PostgreSQL de pruebas y de ejecución de pruebas.')
    migrator = create_database_engine(config, 'test')
    runtime = create_api_engine(config, 'test')
    schema = f'bf_test_{uuid4().hex}'
    created = False
    try:
        with migrator.begin() as c:
            c.execute(text(f'CREATE SCHEMA "{schema}"'))
            created = True
            c.execute(text(f'GRANT USAGE ON SCHEMA "{schema}" TO blueflora_api_test'))
            c.execute(text(f'SET LOCAL search_path = "{schema}", pg_catalog'))
            migration = Config(str(BACKEND_ROOT/'alembic.ini'))
            migration.attributes.update(connection=c, test_schema=schema)
            command.upgrade(migration, 'head')
        repository = AuthRepository(runtime, 'test', schema=schema)
        service = AuthService(repository)
        application = create_app(Settings(_env_file=None, environment='test'), auth_service=service)
        yield SimpleNamespace(migrator=migrator, runtime=runtime, schema=schema,
                              repository=repository, service=service, app=application)
    finally:
        # Solo objetos efímeros creados por esta prueba, jamás public ni datos previos.
        if created:
            with migrator.begin() as c:
                exists = c.scalar(text('SELECT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname=:schema)'), {'schema': schema})
                if exists:
                    c.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        runtime.dispose()
        migrator.dispose()


@pytest.fixture
async def auth_client(auth_db):
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=auth_db.app), base_url='http://testserver') as client:
        yield client


async def register(client, email='alice@example.com', password=PASSWORD):
    response = await client.post('/api/v1/auth/register', json={'email': email, 'password': password})
    assert response.status_code == 202
    return response


async def login(client, email='alice@example.com', password=PASSWORD):
    response = await client.post('/api/v1/auth/login', json={'email': email, 'password': password})
    assert response.status_code == 200
    return response.json()


def bearer(tokens):
    return {'Authorization': 'Bearer '+tokens['access_token']}


def private_rows(db, sql, params=None):
    with db.migrator.begin() as c:
        c.execute(text("SELECT set_config('blueflora.auth_internal','on',true)"))
        if 'UPDATE SCHEMA.users' in sql:
            user = c.scalar(text(f'SELECT id FROM "{db.schema}".users LIMIT 1'))
            if user:
                set_owner(c, user)
        return c.execute(text(sql.replace('SCHEMA', f'"{db.schema}"')), params or {}).mappings().all()


@pytest.mark.anyio
async def test_registration_two_users_me_and_owner_injection(auth_client, auth_db):
    await register(auth_client)
    await register(auth_client, 'bob@example.com')
    alice = await login(auth_client)
    bob = await login(auth_client, 'bob@example.com')
    a = (await auth_client.get('/api/v1/me', headers=bearer(alice))).json()
    b = (await auth_client.get('/api/v1/me', headers=bearer(bob))).json()
    assert a['id'] != b['id'] and a['email'] == 'alice@example.com' and b['email'] == 'bob@example.com'
    attack = await auth_client.get('/api/v1/me', params={'owner_id': b['id']}, headers={**bearer(alice), 'X-Owner-ID': b['id']})
    assert attack.json() == a
    assert set(a) == {'id','email','is_active','created_at'}
    with auth_db.runtime.begin() as c:
        verify_api(c, 'test')
        c.execute(text("SELECT set_config('blueflora.auth_internal','on',true)"))
        for mine, other in ((a,b),(b,a)):
            set_owner(c, mine['id'])
            assert c.execute(text(f'SELECT id FROM "{auth_db.schema}".users')).scalars().all() == [__import__('uuid').UUID(mine['id'])]
            assert c.execute(text(f'SELECT id FROM "{auth_db.schema}".users WHERE id=:other'), {'other':other['id']}).all() == []
        c.execute(text("SELECT set_config('blueflora.owner_id','',true)"))
        assert c.execute(text(f'SELECT id FROM "{auth_db.schema}".users')).all() == []


@pytest.mark.anyio
async def test_passwords_argon2_tokens_hashed_and_no_sensitive_output(auth_client, auth_db):
    await register(auth_client)
    tokens = await login(auth_client)
    users = private_rows(auth_db, 'SELECT password_hash FROM SCHEMA.users')
    assert HASHER.verify(users[0]['password_hash'], PASSWORD)
    assert users[0]['password_hash'].startswith('$argon2id$')
    sessions = private_rows(auth_db, 'SELECT access_token_hash FROM SCHEMA.auth_sessions')
    refresh = private_rows(auth_db, 'SELECT token_hash FROM SCHEMA.auth_refresh_tokens')
    assert sessions[0]['access_token_hash'] == digest(tokens['access_token'])
    assert refresh[0]['token_hash'] == digest(tokens['refresh_token'])
    me = await auth_client.get('/api/v1/me', headers=bearer(tokens))
    assert 'password' not in me.text and tokens['access_token'] not in me.text
    assert me.headers['cache-control'] == 'no-store'


@pytest.mark.anyio
async def test_duplicate_registration_is_indistinguishable_and_preserves_password(auth_client):
    first = await register(auth_client)
    second = await register(auth_client, password='Otra contraseña larga diferente')
    assert first.json() == second.json()
    await login(auth_client)
    bad = await auth_client.post('/api/v1/auth/login', json={'email':'alice@example.com','password':'Otra contraseña larga diferente'})
    assert bad.status_code == 401


@pytest.mark.anyio
async def test_bad_password_unknown_account_and_inactive_account_uniform(auth_client, auth_db):
    await register(auth_client)
    bad = await auth_client.post('/api/v1/auth/login', json={'email':'alice@example.com','password':'incorrecta'})
    missing = await auth_client.post('/api/v1/auth/login', json={'email':'missing@example.com','password':'incorrecta'})
    private_rows(auth_db, 'UPDATE SCHEMA.users SET is_active=false RETURNING id')
    inactive = await auth_client.post('/api/v1/auth/login', json={'email':'alice@example.com','password':PASSWORD})
    assert bad.status_code == missing.status_code == inactive.status_code == 401
    assert bad.json() == missing.json() == inactive.json()


@pytest.mark.anyio
@pytest.mark.parametrize('token', ['', 'invalid', 'bf_r_'+'a'*43, 'bf_a_'+'a'*43])
async def test_invalid_access_tokens_are_uniform(auth_client, token):
    response = await auth_client.get('/api/v1/me', headers={'Authorization':'Bearer '+token})
    assert response.status_code == 401
    assert response.json()['detail']['code'] == 'authentication_failed'


@pytest.mark.anyio
async def test_rotation_refresh_replay_revokes_whole_session(auth_client):
    await register(auth_client)
    original = await login(auth_client)
    response = await auth_client.post('/api/v1/auth/refresh', json={'refresh_token':original['refresh_token']})
    assert response.status_code == 200
    rotated = response.json()
    assert rotated['access_token'] != original['access_token']
    assert rotated['refresh_token'] != original['refresh_token']
    assert (await auth_client.get('/api/v1/me', headers=bearer(original))).status_code == 401
    assert (await auth_client.get('/api/v1/me', headers=bearer(rotated))).status_code == 200
    assert (await auth_client.post('/api/v1/auth/refresh', json={'refresh_token':original['refresh_token']})).status_code == 401
    assert (await auth_client.get('/api/v1/me', headers=bearer(rotated))).status_code == 401
    assert (await auth_client.post('/api/v1/auth/refresh', json={'refresh_token':rotated['refresh_token']})).status_code == 401


@pytest.mark.anyio
async def test_logout_revokes_access_and_refresh_idempotently(auth_client):
    await register(auth_client)
    tokens = await login(auth_client)
    for _ in range(2):
        assert (await auth_client.post('/api/v1/auth/logout', headers=bearer(tokens))).status_code == 204
    assert (await auth_client.get('/api/v1/me', headers=bearer(tokens))).status_code == 401
    assert (await auth_client.post('/api/v1/auth/refresh', json={'refresh_token':tokens['refresh_token']})).status_code == 401


@pytest.mark.anyio
async def test_access_expiry_does_not_block_unexpired_refresh(auth_client, auth_db):
    await register(auth_client)
    tokens = await login(auth_client)
    private_rows(auth_db, "UPDATE SCHEMA.auth_sessions SET access_expires_at=clock_timestamp()-interval '1 second' RETURNING id")
    assert (await auth_client.get('/api/v1/me', headers=bearer(tokens))).status_code == 401
    assert (await auth_client.post('/api/v1/auth/refresh', json={'refresh_token':tokens['refresh_token']})).status_code == 200


@pytest.mark.anyio
async def test_session_expiry_rejects_access_and_refresh(auth_client, auth_db):
    await register(auth_client)
    tokens = await login(auth_client)
    private_rows(auth_db, "UPDATE SCHEMA.auth_sessions SET created_at=clock_timestamp()-interval '2 days', access_expires_at=clock_timestamp()-interval '1 day', expires_at=clock_timestamp()-interval '1 second' RETURNING id")
    assert (await auth_client.get('/api/v1/me', headers=bearer(tokens))).status_code == 401
    assert (await auth_client.post('/api/v1/auth/refresh', json={'refresh_token':tokens['refresh_token']})).status_code == 401


@pytest.mark.anyio
@pytest.mark.parametrize('body', [
    {'email':'bad','password':PASSWORD}, {'email':'alice@example.com','password':'short'},
    {'email':'alice@example.com','password':PASSWORD,'owner_id':str(uuid4())},
    {'email':'alice@example.com','password':PASSWORD,'id':str(uuid4())},
    {'email':'alice@example.com','password':'x'*1025},
])
async def test_invalid_registration_never_reflects_secrets(auth_client, body):
    response = await auth_client.post('/api/v1/auth/register', json=body)
    assert response.status_code == 422
    assert PASSWORD not in response.text and 'short' not in response.text
    assert response.json()['detail']['code'] == 'invalid_request'


@pytest.mark.anyio
async def test_exact_email_lookup_has_no_wildcards_or_sql_injection(auth_client, auth_db):
    await register(auth_client)
    for query in ('%', 'alice%', 'alice', "' OR true --", 'ALICE@example.com'):
        assert auth_db.repository.lookup(query) is None
    assert auth_db.repository.lookup('alice@example.com') is not None
    normalized = await login(auth_client, ' ALICE@EXAMPLE.COM ')
    assert normalized['token_type'] == 'bearer'


@pytest.mark.anyio
async def test_limit_is_shared_across_app_instances_and_does_not_enumerate(auth_client, auth_db):
    for _ in range(10):
        response = await auth_client.post('/api/v1/auth/login',json={'email':'missing@example.com','password':'bad'})
        assert response.status_code == 401
    second = create_app(Settings(_env_file=None), auth_service=AuthService(auth_db.repository))
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=second),base_url='http://testserver') as client:
        response = await client.post('/api/v1/auth/login',json={'email':'other@example.com','password':'bad'},headers={'X-Forwarded-For':'10.0.0.99'})
    assert response.status_code == 429
    assert response.headers['retry-after'] == '60'


def test_real_runtime_role_cannot_read_hashes_sessions_or_change_schema(auth_db):
    denied = [
        f'SELECT password_hash FROM "{auth_db.schema}".users',
        f'SELECT * FROM "{auth_db.schema}".auth_sessions',
        f'SELECT * FROM "{auth_db.schema}".auth_refresh_tokens',
        f'SELECT * FROM "{auth_db.schema}".auth_rate_limits',
        f'ALTER TABLE "{auth_db.schema}".users DISABLE ROW LEVEL SECURITY',
        f'CREATE TABLE "{auth_db.schema}".forbidden(id integer)',
        f'UPDATE "{auth_db.schema}".users SET is_active=false',
        'SET ROLE blueflora_test',
    ]
    with auth_db.runtime.begin() as c:
        verify_api(c, 'test')
        c.execute(text("SELECT set_config('blueflora.auth_internal','on',true)"))
        for sql in denied:
            with pytest.raises(DBAPIError):
                with c.begin_nested():
                    c.execute(text(sql))


def test_definers_have_safe_paths_distinct_owners_and_no_public_execute(auth_db):
    with auth_db.migrator.connect() as c:
        functions = c.execute(text("""
            SELECT p.proname,p.prosecdef,p.proconfig,pg_get_userbyid(p.proowner) owner,
            EXISTS(SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee=0 AND a.privilege_type='EXECUTE') public_exec
            FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname=:schema AND p.proname LIKE 'auth_%'
        """),{'schema':auth_db.schema}).mappings().all()
        assert len(functions) == 7
        assert all(f['prosecdef'] and f['owner']=='blueflora_test' and not f['public_exec'] for f in functions)
        assert all('search_path=pg_catalog, pg_temp' in f['proconfig'] for f in functions)
        rows = c.execute(text("SELECT relrowsecurity,relforcerowsecurity FROM pg_class WHERE relnamespace=to_regnamespace(:schema) AND relkind='r' AND relname NOT IN ('species','alembic_version')"),{'schema':auth_db.schema}).all()
        assert all(a and b for a,b in rows)


def test_internal_context_is_restored_after_success_and_error(auth_db):
    with auth_db.runtime.begin() as c:
        c.execute(text("SELECT set_config('blueflora.auth_internal','off',true)"))
        assert c.execute(text(f'SELECT * FROM "{auth_db.schema}".auth_lookup(:email)'),{'email':'nobody@example.com'}).all() == []
        assert c.scalar(text("SELECT current_setting('blueflora.auth_internal')")) == 'off'
        with pytest.raises(DBAPIError):
            with c.begin_nested():
                c.execute(text(f'SELECT "{auth_db.schema}".auth_register(:id,:email,:hash)'),{'id':uuid4(),'email':'bad@example.com','hash':'invalid'})
        assert c.scalar(text("SELECT current_setting('blueflora.auth_internal')")) == 'off'


@pytest.mark.anyio
async def test_concurrent_rotation_has_one_success_and_replay_revokes(auth_client, auth_db):
    await register(auth_client)
    tokens = await login(auth_client)
    from app.modules.auth.security import new_token
    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(lambda _: auth_db.repository.rotate(digest(tokens['refresh_token']),digest(new_token('a')),digest(new_token('r'))), range(2)))
    assert sorted(results) == [False, True]
    rows = private_rows(auth_db, 'SELECT revoked_at FROM SCHEMA.auth_sessions')
    assert rows[0]['revoked_at'] is not None


@pytest.mark.anyio
async def test_unknown_refresh_and_using_access_as_refresh_fail(auth_client):
    await register(auth_client)
    tokens = await login(auth_client)
    from app.modules.auth.security import new_token
    for value in (new_token('r'), tokens['access_token'], 'malformed'):
        response = await auth_client.post('/api/v1/auth/refresh', json={'refresh_token':value})
        assert response.status_code == 401
        assert response.json()['detail']['code'] == 'authentication_failed'


@pytest.mark.anyio
async def test_limit_window_expires_without_restart(auth_client, auth_db):
    for _ in range(10):
        auth_db.service.limit('auth','127.0.0.1')
    response = await auth_client.post('/api/v1/auth/login', json={'email':'missing@example.com','password':'bad'})
    assert response.status_code == 429
    private_rows(auth_db, "UPDATE SCHEMA.auth_rate_limits SET window_started_at=clock_timestamp()-interval '2 minutes' RETURNING key_hash")
    response = await auth_client.post('/api/v1/auth/login', json={'email':'missing@example.com','password':'bad'})
    assert response.status_code == 401


@pytest.mark.anyio
async def test_login_rejects_forged_owner_and_http_validation_hides_input(auth_client):
    response = await auth_client.post('/api/v1/auth/login', json={
        'email':'alice@example.com', 'password':PASSWORD, 'owner_id':str(uuid4())})
    assert response.status_code == 422
    assert PASSWORD not in response.text
    assert 'input' not in response.text


@pytest.mark.anyio
async def test_database_failure_is_uniform_and_does_not_expose_diagnostics():
    from sqlalchemy.exc import OperationalError
    class Unavailable:
        def account(self, value):
            raise OperationalError('SQL containing private information', {}, RuntimeError('private diagnostics'))
    from app.modules.auth.security import new_token
    app = create_app(Settings(_env_file=None), auth_service=AuthService(Unavailable()))
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app),base_url='http://testserver') as client:
        response = await client.get('/api/v1/me',headers={'Authorization':'Bearer '+new_token('a')})
    assert response.status_code == 503
    assert response.json()['detail']['code'] == 'service_unavailable'
    assert 'private' not in response.text and 'SQL' not in response.text


@pytest.mark.anyio
async def test_logout_remains_available_when_auth_attempts_are_limited(auth_client, auth_db):
    await register(auth_client)
    tokens = await login(auth_client)
    for _ in range(8):
        auth_db.repository.attempt(digest('auth:ip:127.0.0.1'))
    assert (await auth_client.post('/api/v1/auth/logout', headers=bearer(tokens))).status_code == 204
    assert (await auth_client.get('/api/v1/me', headers=bearer(tokens))).status_code == 401
