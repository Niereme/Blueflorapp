"""Reglas de autenticación; las credenciales se verifican solo en el servidor."""
from uuid import uuid4
from fastapi import HTTPException
from app.modules.auth.security import digest, hash_password, new_token, valid_token, verify_password


def unauthorized():
    return HTTPException(401, detail={"code": "authentication_failed", "message": "Credenciales o sesión no válidas."},
                         headers={"WWW-Authenticate": "Bearer"})


class AuthService:
    def __init__(self, repository):
        self.repository = repository

    def limit(self, action, ip, email=None):
        keys = [f'{action}:ip:{ip}']
        if email is not None:
            keys.append(f'{action}:email:{email}')
        allowed = [self.repository.attempt(digest(key)) for key in keys]
        if not all(allowed):
            raise HTTPException(429, detail={"code": "rate_limited", "message": "Demasiados intentos. Intenta de nuevo más tarde."},
                                headers={"Retry-After": "60"})

    def register(self, credentials):
        hashed = hash_password(credentials.password.get_secret_value())
        self.repository.register(uuid4(), credentials.email, hashed)

    def login(self, credentials):
        account = self.repository.lookup(credentials.email)
        valid = verify_password(credentials.password.get_secret_value(), account['password_hash'] if account else None)
        if not valid or not account or not account['is_active']:
            raise unauthorized()
        access, refresh = new_token('a'), new_token('r')
        if not self.repository.start(uuid4(), account['user_id'], digest(access), digest(refresh)):
            raise unauthorized()
        return {'access_token': access, 'refresh_token': refresh}

    def refresh(self, token):
        if not valid_token(token, 'r'):
            raise unauthorized()
        access, refresh = new_token('a'), new_token('r')
        if not self.repository.rotate(digest(token), digest(access), digest(refresh)):
            raise unauthorized()
        return {'access_token': access, 'refresh_token': refresh}

    def logout(self, token):
        if valid_token(token, 'a'):
            self.repository.logout(digest(token))

    def me(self, token):
        if not valid_token(token, 'a'):
            raise unauthorized()
        account = self.repository.account(digest(token))
        if not account:
            raise unauthorized()
        return dict(account)
