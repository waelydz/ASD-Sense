"""Google sign-in for guardians (mobile app only), brokered by Clerk.

The mobile app signs the guardian in with Google through Clerk, then posts the
short-lived Clerk session token here. We verify it (signature from Clerk's JWKS,
expiry, issuer) and look up the user's *verified* primary email with the Clerk
Backend API. We then find or create the matching guardian account and issue the
app's normal bearer session, so every other endpoint is unchanged.

Clinician/admin accounts are always refused here: they sign in to the clinician
portal with their hospital credentials only.

Configuration (environment variables):
  CLERK_SECRET_KEY       sk_test_... / sk_live_...  Required to enable the endpoint.
                         Secret: never commit it.
  CLERK_PUBLISHABLE_KEY  pk_test_... / pk_live_...  Optional. Defaults to the project's
                         shared Clerk app (public key, safe to commit); it pins the
                         token issuer, so set it when using a different Clerk app.
"""

from __future__ import annotations

import base64
import json
import os
import sqlite3
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

import logging

import jwt
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from auth_api import TokenResponse, _db, _new_session

CLERK_API_BASE = "https://api.clerk.com/v1"
# Clerk's edge rejects Python's default "Python-urllib" User-Agent (Cloudflare 1010).
_USER_AGENT = "asd-sense-backend"
_log = logging.getLogger("asd_sense.clerk")
# The project's shared Clerk app (development instance). Public by design.
DEFAULT_PUBLISHABLE_KEY = "pk_test_Z2VudGxlLXdhc3AtODA2LmNsZXJrLmFjY291bnRzLmRldiQ"
# Never a valid scrypt record, so _password_matches() always rejects it: accounts
# created through Google cannot sign in by password until the guardian sets one
# with the "Forgot password" email-code flow.
EXTERNAL_ONLY_PASSWORD = "!external-sign-in-only"
_GUARDIAN_ROLES = ("parent", "guardian")


class ClerkExchange(BaseModel):
    model_config = ConfigDict(extra="forbid")
    session_token: str = Field(min_length=20, max_length=8192)


@dataclass(frozen=True)
class ClerkIdentity:
    subject: str
    email: str
    full_name: str


class ClerkVerificationError(Exception):
    """The token or the Clerk user is not acceptable. Message is safe to log, not to show."""


def issuer_from_publishable_key(publishable_key: str) -> str:
    """pk_test_<base64("<frontend-api-host>$")> -> "https://<frontend-api-host>"."""
    try:
        encoded = publishable_key.split("_", 2)[2]
        encoded += "=" * (-len(encoded) % 4)
        host = base64.b64decode(encoded).decode("ascii").rstrip("$")
    except (IndexError, ValueError, UnicodeDecodeError) as exc:
        raise ValueError("CLERK_PUBLISHABLE_KEY is not a valid Clerk publishable key") from exc
    if not host or "/" in host:
        raise ValueError("CLERK_PUBLISHABLE_KEY is not a valid Clerk publishable key")
    return f"https://{host}"


class ClerkVerifier:
    """Verifies Clerk session tokens and resolves the user's verified email."""

    def __init__(self, secret_key: str, issuer: str | None = None, *,
                 jwk_client: jwt.PyJWKClient | None = None,
                 fetch_user: Callable[[str], dict] | None = None):
        self._secret_key = secret_key
        self._issuer = issuer
        self._jwk_client = jwk_client or jwt.PyJWKClient(
            f"{CLERK_API_BASE}/jwks",
            headers={"Authorization": f"Bearer {secret_key}", "User-Agent": _USER_AGENT},
            cache_keys=True, lifespan=3600, timeout=10,
        )
        self._fetch_user = fetch_user or self._fetch_user_from_clerk

    def __call__(self, session_token: str) -> ClerkIdentity:
        try:
            signing_key = self._jwk_client.get_signing_key_from_jwt(session_token)
            claims = jwt.decode(
                session_token, signing_key.key, algorithms=["RS256"],
                issuer=self._issuer, leeway=5,
                options={"require": ["exp", "iat", "sub", "iss"], "verify_aud": False},
            )
        except jwt.PyJWKClientConnectionError as exc:
            raise ConnectionError("Could not reach Clerk to fetch signing keys") from exc
        except jwt.PyJWTError as exc:
            raise ClerkVerificationError(f"Invalid Clerk session token: {exc}") from exc

        subject = claims["sub"]
        if not isinstance(subject, str) or not subject.startswith("user_"):
            raise ClerkVerificationError("Token subject is not a Clerk user")
        return self._identity(subject, self._fetch_user(subject))

    @staticmethod
    def _identity(subject: str, user: dict) -> ClerkIdentity:
        primary_id = user.get("primary_email_address_id")
        email = None
        for address in user.get("email_addresses") or []:
            if address.get("id") == primary_id:
                if (address.get("verification") or {}).get("status") == "verified":
                    email = address.get("email_address")
                break
        if not email:
            raise ClerkVerificationError("Clerk user has no verified primary email")
        name = " ".join(p.strip() for p in (user.get("first_name") or "",
                                             user.get("last_name") or "") if p and p.strip())
        return ClerkIdentity(subject=subject, email=email.strip().casefold(),
                             full_name=(name or email.split("@")[0])[:150])

    def _fetch_user_from_clerk(self, subject: str) -> dict:
        request = urllib.request.Request(
            f"{CLERK_API_BASE}/users/{urllib.parse.quote(subject, safe='')}",
            headers={"Authorization": f"Bearer {self._secret_key}",
                     "Accept": "application/json", "User-Agent": _USER_AGENT},
        )
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                raise ClerkVerificationError("Clerk user not found") from exc
            raise ConnectionError(f"Clerk Backend API returned HTTP {exc.code}") from exc
        except (urllib.error.URLError, TimeoutError) as exc:
            raise ConnectionError("Could not reach the Clerk Backend API") from exc


def verifier_from_environment() -> ClerkVerifier | None:
    secret_key = os.environ.get("CLERK_SECRET_KEY", "").strip()
    if not secret_key:
        return None
    publishable_key = (os.environ.get("CLERK_PUBLISHABLE_KEY", "").strip()
                       or DEFAULT_PUBLISHABLE_KEY)
    return ClerkVerifier(secret_key, issuer_from_publishable_key(publishable_key))


def _guardian_for_identity(conn: sqlite3.Connection, identity: ClerkIdentity) -> int:
    linked = conn.execute(
        """SELECT u.user_id, u.role FROM User_Identities AS i
        JOIN Users AS u ON u.user_id = i.user_id
        WHERE i.provider = 'clerk' AND i.subject = ?""",
        (identity.subject,),
    ).fetchone()
    if linked is not None:
        if linked["role"] not in _GUARDIAN_ROLES:
            raise HTTPException(status_code=403, detail=_CLINICIAN_MESSAGE)
        return int(linked["user_id"])

    existing = conn.execute("SELECT user_id, role FROM Users WHERE email = ?",
                            (identity.email,)).fetchone()
    if existing is not None:
        if existing["role"] not in _GUARDIAN_ROLES:
            raise HTTPException(status_code=403, detail=_CLINICIAN_MESSAGE)
        # Google (via Clerk) verified this address, so link it to the existing
        # guardian account; their children and records stay where they are.
        user_id = int(existing["user_id"])
    else:
        user_id = int(conn.execute(
            """INSERT INTO Users (full_name, email, phone, password_hash, role)
            VALUES (?, ?, NULL, ?, 'guardian')""",
            (identity.full_name, identity.email, EXTERNAL_ONLY_PASSWORD),
        ).lastrowid)
    conn.execute("INSERT INTO User_Identities (user_id, provider, subject) VALUES (?, 'clerk', ?)",
                 (user_id, identity.subject))
    return user_id


_CLINICIAN_MESSAGE = ("This email belongs to a clinician account. "
                      "Sign in to the clinician portal with your hospital account.")


def create_clerk_router(db_path: str | Path,
                        verifier: Callable[[str], ClerkIdentity] | None = None) -> APIRouter:
    router = APIRouter(prefix="/api/auth", tags=["authentication"])

    @router.post("/clerk", response_model=TokenResponse)
    def clerk_sign_in(body: ClerkExchange):
        if verifier is None:
            raise HTTPException(status_code=503,
                                detail="Google sign-in is not configured on this server")
        try:
            identity = verifier(body.session_token)
        except ClerkVerificationError as exc:
            _log.warning("Clerk sign-in rejected: %s", exc)
            raise HTTPException(status_code=401, detail="Google sign-in could not be verified")
        except ConnectionError as exc:
            _log.error("Clerk unreachable: %s (cause: %s)", exc, exc.__cause__)
            raise HTTPException(status_code=502,
                                detail="Could not reach the sign-in service. Try again.")
        with _db(db_path) as conn:
            user_id = _guardian_for_identity(conn, identity)
            user = conn.execute(
                "SELECT user_id, full_name, email, phone, role FROM Users WHERE user_id=?",
                (user_id,),
            ).fetchone()
            return _new_session(conn, user_id, user)

    return router
