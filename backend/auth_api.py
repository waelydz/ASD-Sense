"""Minimal credential-based guardian auth for ASD-Sense's development backend.

Sessions are random bearer tokens, stored as SHA-256 digests in SQLite. They do
not identify users based on untrusted client-supplied user IDs. Use HTTPS before
connecting devices outside a trusted local development environment.
"""

from __future__ import annotations

import hashlib
import hmac
import re
import secrets
import sqlite3
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Generator

from fastapi import APIRouter, Depends, FastAPI, HTTPException, Request, status
from pydantic import BaseModel, ConfigDict, Field, SecretStr, field_validator

from child_profiles_api import require_user_id

SESSION_LIFETIME_SECONDS = 60 * 60 * 8  # 8 hours; renew by signing in again.
_SCRYPT_N, _SCRYPT_R, _SCRYPT_P = 2**14, 8, 1
_EMAIL_PATTERN = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
_TOKEN_PATTERN = re.compile(r"^[A-Za-z0-9_-]{40,70}$")


class Credentials(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: str = Field(min_length=3, max_length=254)
    password: SecretStr = Field(min_length=12, max_length=128)

    @field_validator("email")
    @classmethod
    def normalise_email(cls, value: str) -> str:
        value = value.strip().casefold()
        if not _EMAIL_PATTERN.fullmatch(value):
            raise ValueError("Enter a valid email address")
        return value


class Registration(Credentials):
    full_name: str = Field(min_length=1, max_length=150)
    phone: str | None = Field(default=None, max_length=40)

    @field_validator("full_name")
    @classmethod
    def normalise_name(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Full name is required")
        return value


class PublicUser(BaseModel):
    user_id: int
    full_name: str
    email: str
    phone: str | None
    role: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    user: PublicUser


def _password_hash(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode("utf-8"), salt=salt,
                            n=_SCRYPT_N, r=_SCRYPT_R, p=_SCRYPT_P, dklen=32)
    return f"scrypt${_SCRYPT_N}${_SCRYPT_R}${_SCRYPT_P}${salt.hex()}${digest.hex()}"


def _password_matches(password: str, stored: str) -> bool:
    try:
        algorithm, n, r, p, salt, digest = stored.split("$")
        if algorithm != "scrypt":
            return False  # Existing 'hashed_pw' prototype accounts cannot sign in.
        if (int(n), int(r), int(p)) != (_SCRYPT_N, _SCRYPT_R, _SCRYPT_P):
            return False  # Avoid accepting attacker-controlled expensive work factors.
        calculated = hashlib.scrypt(password.encode("utf-8"), salt=bytes.fromhex(salt),
                                    n=_SCRYPT_N, r=_SCRYPT_R, p=_SCRYPT_P, dklen=32)
        return hmac.compare_digest(calculated, bytes.fromhex(digest))
    except (TypeError, ValueError, MemoryError):
        return False


@contextmanager
def _db(path: str | Path) -> Generator[sqlite3.Connection, None, None]:
    conn = sqlite3.connect(str(path), timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys=ON")
    try:
        yield conn
        conn.commit()
    except BaseException:
        conn.rollback()
        raise
    finally:
        conn.close()


def _new_session(conn: sqlite3.Connection, user_id: int, user: sqlite3.Row) -> TokenResponse:
    token = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(token.encode("ascii")).hexdigest()
    conn.execute("INSERT INTO Auth_Sessions (user_id, token_hash, expires_at) VALUES (?, ?, ?)",
                 (user_id, token_hash, int(time.time()) + SESSION_LIFETIME_SECONDS))
    return TokenResponse(access_token=token, expires_in=SESSION_LIFETIME_SECONDS,
                         user=PublicUser(**dict(user)))


def _bearer_token(header: str | None) -> str | None:
    if not header:
        return None
    pieces = header.split()
    if len(pieces) != 2 or pieces[0].lower() != "bearer":
        return None
    return pieces[1] if _TOKEN_PATTERN.fullmatch(pieces[1]) else None


def resolve_session_user_id(db_path: str | Path, header: str | None) -> int | None:
    """Return a verified guardian account ID or None. Never raise on a malformed token."""
    token = _bearer_token(header)
    if not token:
        return None
    try:
        with _db(db_path) as conn:
            row = conn.execute(
                """SELECT s.user_id FROM Auth_Sessions AS s
                JOIN Users AS u ON u.user_id=s.user_id
                WHERE s.token_hash=? AND s.revoked_at IS NULL
                  AND s.expires_at>? AND u.role IN ('parent','guardian')""",
                (hashlib.sha256(token.encode("ascii")).hexdigest(), int(time.time())),
            ).fetchone()
            return int(row[0]) if row else None
    except sqlite3.OperationalError:
        return None  # Database not initialized yet.


def create_auth_router(db_path: str | Path) -> APIRouter:
    router = APIRouter(prefix="/api/auth", tags=["authentication"])

    @router.post("/register", response_model=TokenResponse,
                 status_code=status.HTTP_201_CREATED)
    def register(credentials: Registration):
        with _db(db_path) as conn:
            try:
                cursor = conn.execute(
                    """INSERT INTO Users (full_name, email, phone, password_hash, role)
                    VALUES (?, ?, ?, ?, 'guardian')""",
                    (credentials.full_name, credentials.email, credentials.phone,
                     _password_hash(credentials.password.get_secret_value())),
                )
            except sqlite3.IntegrityError:
                raise HTTPException(status_code=409, detail="Account already exists")
            user = conn.execute(
                "SELECT user_id, full_name, email, phone, role FROM Users WHERE user_id=?",
                (cursor.lastrowid,),
            ).fetchone()
            return _new_session(conn, int(cursor.lastrowid), user)

    @router.post("/login", response_model=TokenResponse)
    def login(credentials: Credentials):
        with _db(db_path) as conn:
            row = conn.execute(
                "SELECT * FROM Users WHERE email=? AND role IN ('parent','guardian')",
                (credentials.email,),
            ).fetchone()
            if row is None or not _password_matches(
                credentials.password.get_secret_value(), row["password_hash"]
            ):
                raise HTTPException(status_code=401, detail="Invalid email or password")
            user = conn.execute(
                "SELECT user_id, full_name, email, phone, role FROM Users WHERE user_id=?",
                (row["user_id"],),
            ).fetchone()
            return _new_session(conn, int(row["user_id"]), user)

    @router.get("/me", response_model=PublicUser)
    def me(user_id: int = Depends(require_user_id)):
        with _db(db_path) as conn:
            row = conn.execute(
                "SELECT user_id, full_name, email, phone, role FROM Users WHERE user_id=?",
                (user_id,),
            ).fetchone()
            if row is None:
                raise HTTPException(status_code=401, detail="Account unavailable")
            return dict(row)

    @router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
    def logout(request: Request, user_id: int = Depends(require_user_id)):
        token = _bearer_token(request.headers.get("Authorization"))
        if token is None:
            raise HTTPException(status_code=401, detail="Authentication required")
        with _db(db_path) as conn:
            conn.execute("""UPDATE Auth_Sessions SET revoked_at=?
                WHERE user_id=? AND token_hash=? AND revoked_at IS NULL""",
                (int(time.time()), user_id,
                 hashlib.sha256(token.encode("ascii")).hexdigest()),
            )
        return None

    return router


def attach_auth(app: FastAPI, db_path: str | Path, clerk_verifier=None) -> None:
    """Install auth sessions without changing existing model or inference paths.

    Google sign-in (/api/auth/clerk) uses `clerk_verifier` if given, otherwise the
    CLERK_* environment variables; without either it answers 503.
    """
    from clerk_auth_api import create_clerk_router, verifier_from_environment

    app.include_router(create_auth_router(db_path))
    app.include_router(create_clerk_router(
        db_path, clerk_verifier or verifier_from_environment()))

    @app.middleware("http")
    async def authenticated_identity(request: Request, call_next):
        request.state.user_id = resolve_session_user_id(
            db_path, request.headers.get("Authorization")
        )
        return await call_next(request)
