"""Argon2id y tokens opacos de 256 bits; nunca registrar valores secretos."""
import hashlib
import re
import secrets
from threading import BoundedSemaphore
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError

HASHER = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=4)
HASH_SLOTS = BoundedSemaphore(4)
DUMMY_HASH = HASHER.hash(secrets.token_urlsafe(32))


def hash_password(password: str):
    with HASH_SLOTS:
        return HASHER.hash(password)


def verify_password(password: str, stored: str | None):
    with HASH_SLOTS:
        try:
            result = HASHER.verify(stored or DUMMY_HASH, password)
            return bool(stored) and result
        except (VerificationError, InvalidHashError):
            return False


def digest(value: str):
    return hashlib.sha256(value.encode('utf-8')).hexdigest()


def new_token(kind: str):
    return f"bf_{kind}_" + secrets.token_urlsafe(32)


def valid_token(token: str, kind: str):
    return bool(re.fullmatch(r"bf_" + kind + r"_[A-Za-z0-9_-]{43}", token))
