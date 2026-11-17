"""Tests for Google sign-in via Clerk: token verification and guardian account linking.

No network: tokens are signed with a throwaway RSA key and the Clerk user lookup is faked.
"""
import base64
import sqlite3
import sys
import time
from pathlib import Path
from types import SimpleNamespace

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi import FastAPI
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from auth_api import attach_auth, _password_hash
from clerk_auth_api import (DEFAULT_PUBLISHABLE_KEY, ClerkIdentity, ClerkVerificationError,
                            ClerkVerifier, issuer_from_publishable_key)

SCHEMA = Path(__file__).resolve().parents[1] / "asd_sense_database_schema.sql"
ISSUER = "https://synthetic-test.clerk.accounts.dev"
PASSWORD = "Testing-only-passphrase-42"


@pytest.fixture
def db(tmp_path):
    path = tmp_path / "synthetic.db"
    with sqlite3.connect(path) as conn:
        conn.executescript(SCHEMA.read_text(encoding="utf-8"))
        conn.execute("""INSERT INTO Users (user_id, full_name, email, password_hash, role)
            VALUES (10, 'Existing Guardian', 'existing@example.invalid', ?, 'guardian')""",
                     (_password_hash(PASSWORD),))
        conn.execute("""INSERT INTO Users (user_id, full_name, email, password_hash, role)
            VALUES (20, 'Synthetic Clinician', 'clinician@example.invalid', ?, 'clinician')""",
                     (_password_hash(PASSWORD),))
    return path


class FakeVerifier:
    """Maps token strings to identities, like a verified Clerk lookup would."""

    def __init__(self, identities):
        self.identities = identities

    def __call__(self, token):
        if token not in self.identities:
            raise ClerkVerificationError("unknown token")
        return self.identities[token]


def client_for(db, verifier):
    app = FastAPI()
    attach_auth(app, db, clerk_verifier=verifier)
    return TestClient(app)


def identity(subject="user_new", email="new@example.invalid", name="New Guardian"):
    return ClerkIdentity(subject=subject, email=email, full_name=name)


def exchange(client, token):
    return client.post("/api/auth/clerk", json={"session_token": token})


TOKEN_A = "synthetic-session-token-a"
TOKEN_B = "synthetic-session-token-b"


def test_first_google_sign_in_creates_guardian_and_session(db):
    client = client_for(db, FakeVerifier({TOKEN_A: identity()}))
    res = exchange(client, TOKEN_A)
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["user"]["email"] == "new@example.invalid"
    assert body["user"]["role"] == "guardian"
    me = client.get("/api/auth/me", headers={"Authorization": f"Bearer {body['access_token']}"})
    assert me.status_code == 200 and me.json()["full_name"] == "New Guardian"
    # A Google-only account has no usable password.
    login = client.post("/api/auth/login",
                        json={"email": "new@example.invalid", "password": PASSWORD})
    assert login.status_code == 401


def test_google_sign_in_links_existing_password_guardian(db):
    client = client_for(db, FakeVerifier({
        TOKEN_A: identity(subject="user_existing", email="existing@example.invalid")}))
    res = exchange(client, TOKEN_A)
    assert res.status_code == 200, res.text
    assert res.json()["user"]["user_id"] == 10
    assert res.json()["user"]["full_name"] == "Existing Guardian"  # not overwritten
    with sqlite3.connect(db) as conn:
        assert conn.execute("SELECT user_id FROM User_Identities WHERE subject='user_existing'"
                            ).fetchone() == (10,)
    # Password sign-in still works for the linked account.
    login = client.post("/api/auth/login",
                        json={"email": "existing@example.invalid", "password": PASSWORD})
    assert login.status_code == 200 and login.json()["user"]["user_id"] == 10


def test_repeat_sign_in_follows_link_even_if_google_email_changes(db):
    client = client_for(db, FakeVerifier({
        TOKEN_A: identity(subject="user_same", email="first@example.invalid"),
        TOKEN_B: identity(subject="user_same", email="renamed@example.invalid"),
    }))
    first = exchange(client, TOKEN_A).json()["user"]["user_id"]
    second = exchange(client, TOKEN_B)
    assert second.status_code == 200
    assert second.json()["user"]["user_id"] == first
    with sqlite3.connect(db) as conn:
        assert conn.execute("SELECT COUNT(*) FROM Users WHERE email='renamed@example.invalid'"
                            ).fetchone() == (0,)


def test_clinician_email_is_refused(db):
    client = client_for(db, FakeVerifier({
        TOKEN_A: identity(subject="user_doc", email="clinician@example.invalid")}))
    res = exchange(client, TOKEN_A)
    assert res.status_code == 403
    assert "clinician" in res.json()["detail"].lower()
    with sqlite3.connect(db) as conn:
        assert conn.execute("SELECT COUNT(*) FROM User_Identities").fetchone() == (0,)


def test_unverifiable_token_is_rejected(db):
    client = client_for(db, FakeVerifier({}))
    assert exchange(client, "forged-or-expired-token-xyz").status_code == 401


def test_endpoint_is_disabled_without_configuration(db, monkeypatch):
    monkeypatch.delenv("CLERK_SECRET_KEY", raising=False)
    client = client_for(db, None)
    assert exchange(client, TOKEN_A).status_code == 503


# --- ClerkVerifier: real RS256 verification against a throwaway key ---------------

@pytest.fixture(scope="module")
def rsa_key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


def clerk_user(email="parent@example.invalid", status="verified"):
    return {
        "id": "user_abc",
        "first_name": "Synthetic", "last_name": "Parent",
        "primary_email_address_id": "idn_1",
        "email_addresses": [
            {"id": "idn_0", "email_address": "other@example.invalid",
             "verification": {"status": "verified"}},
            {"id": "idn_1", "email_address": email, "verification": {"status": status}},
        ],
    }


def make_verifier(key, user=None):
    jwk_client = SimpleNamespace(
        get_signing_key_from_jwt=lambda token: SimpleNamespace(key=key.public_key()))
    return ClerkVerifier("sk_test_synthetic", ISSUER, jwk_client=jwk_client,
                         fetch_user=lambda subject: user or clerk_user())


def sign(key, **overrides):
    now = int(time.time())
    claims = {"sub": "user_abc", "iss": ISSUER, "iat": now, "nbf": now, "exp": now + 60}
    claims.update(overrides)
    return jwt.encode(claims, key, algorithm="RS256")


def test_verifier_accepts_valid_token(rsa_key):
    result = make_verifier(rsa_key)(sign(rsa_key))
    assert result == ClerkIdentity("user_abc", "parent@example.invalid", "Synthetic Parent")


@pytest.mark.parametrize("overrides", [
    {"exp": int(time.time()) - 60},
    {"iss": "https://attacker.example.invalid"},
    {"sub": "not-a-clerk-user"},
])
def test_verifier_rejects_bad_claims(rsa_key, overrides):
    with pytest.raises(ClerkVerificationError):
        make_verifier(rsa_key)(sign(rsa_key, **overrides))


def test_verifier_rejects_token_signed_by_another_key(rsa_key):
    other = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    with pytest.raises(ClerkVerificationError):
        make_verifier(rsa_key)(sign(other))


def test_verifier_rejects_unverified_primary_email(rsa_key):
    with pytest.raises(ClerkVerificationError):
        make_verifier(rsa_key, clerk_user(status="unverified"))(sign(rsa_key))


def test_issuer_from_publishable_key():
    host = "synthetic-test.clerk.accounts.dev"
    key = "pk_test_" + base64.b64encode(f"{host}$".encode()).decode().rstrip("=")
    assert issuer_from_publishable_key(key) == f"https://{host}"
    with pytest.raises(ValueError):
        issuer_from_publishable_key("pk_test_%%%")


def test_default_publishable_key_is_the_project_clerk_app():
    assert DEFAULT_PUBLISHABLE_KEY.startswith("pk_test_")
    assert issuer_from_publishable_key(DEFAULT_PUBLISHABLE_KEY).endswith(".clerk.accounts.dev")
