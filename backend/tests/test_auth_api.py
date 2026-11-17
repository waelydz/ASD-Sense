"""Tests for verified bearer identities, synthetic guardians, and session persistence."""
import hashlib
import sqlite3
import sys
import time
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from auth_api import attach_auth
from child_profiles_api import create_child_profiles_router

SCHEMA = Path(__file__).resolve().parents[1] / "asd_sense_database_schema.sql"


def make_client(db):
    app = FastAPI()
    app.include_router(create_child_profiles_router(db))
    attach_auth(app, db)
    return TestClient(app)


@pytest.fixture
def db(tmp_path):
    path = tmp_path / "synthetic.db"
    with sqlite3.connect(path) as conn:
        conn.executescript(SCHEMA.read_text(encoding="utf-8"))
        conn.execute("""INSERT INTO Users
            (user_id, full_name, email, password_hash, role)
            VALUES (1, 'Legacy Fake Guardian', 'legacy@example.invalid', 'hashed_pw', 'guardian')""")
    return path


def register(client, email="guardian-a@example.invalid"):
    return client.post("/api/auth/register", json={
        "full_name": "Synthetic Guardian", "email": email,
        "password": "Testing-only-passphrase-42", "phone": None,
    })


def auth(token):
    return {"Authorization": f"Bearer {token}"}


def test_registration_creates_hash_and_session(db):
    client = make_client(db)
    res = register(client)
    assert res.status_code == 201, res.text
    token = res.json()["access_token"]
    assert len(token) >= 40
    assert res.json()["user"]["role"] == "guardian"
    with sqlite3.connect(db) as conn:
        row = conn.execute("SELECT password_hash FROM Users WHERE email=?",
                           ("guardian-a@example.invalid",)).fetchone()
        assert row[0].startswith("scrypt$")
        assert "Testing-only-passphrase-42" not in row[0]
        session = conn.execute("SELECT token_hash FROM Auth_Sessions").fetchone()[0]
        assert session == hashlib.sha256(token.encode("ascii")).hexdigest()
        assert token != session


def test_registration_rejects_duplicates_and_short_passwords(db):
    client = make_client(db)
    assert register(client).status_code == 201
    assert register(client).status_code == 409
    assert client.post("/api/auth/register", json={
        "full_name": "Test", "email": "bad-email", "password": "short"
    }).status_code == 422


def test_login_and_wrong_password(db):
    client = make_client(db)
    assert register(client).status_code == 201
    assert client.post("/api/auth/login", json={
        "email": "guardian-a@example.invalid", "password": "not-the-password"
    }).status_code == 401
    res = client.post("/api/auth/login", json={
        "email": "GUARDIAN-A@EXAMPLE.INVALID", "password": "Testing-only-passphrase-42"
    })
    assert res.status_code == 200, res.text
    assert client.get("/api/auth/me", headers=auth(res.json()["access_token"])).status_code == 200
    assert client.post("/api/auth/login", json={
        "email": "legacy@example.invalid", "password": "hashed_pw"
    }).status_code == 422  # too short by design, never a valid credential


def test_unauthorized_header_and_cross_guardian(db):
    client = make_client(db)
    a = register(client).json()["access_token"]
    b = register(client, "guardian-b@example.invalid").json()["access_token"]
    for headers in ({}, {"X-User-Id": "1"}, {"Authorization": "Bearer fake"}):
        assert client.get("/api/children", headers=headers).status_code == 401
    saved = client.post("/api/children", headers=auth(a), json={
        "first_name": "Synthetic Child", "date_of_birth": "2021-09-10",
    })
    assert saved.status_code == 201, saved.text
    child_id = saved.json()["child_id"]
    assert client.get("/api/children", headers=auth(a)).json()[0]["child_id"] == child_id
    assert client.get("/api/children", headers=auth(b)).json() == []
    assert client.get(f"/api/children/{child_id}", headers=auth(b)).status_code == 404


def test_logout_revokes_token(db):
    client = make_client(db)
    token = register(client).json()["access_token"]
    assert client.post("/api/auth/logout", headers=auth(token)).status_code == 204
    assert client.get("/api/auth/me", headers=auth(token)).status_code == 401


def test_session_survives_app_recreation(db):
    client = make_client(db)
    token = register(client).json()["access_token"]
    new_client = make_client(db)
    assert new_client.get("/api/auth/me", headers=auth(token)).status_code == 200


def test_expired_token_rejected(db):
    client = make_client(db)
    token = register(client).json()["access_token"]
    with sqlite3.connect(db) as conn:
        conn.execute("UPDATE Auth_Sessions SET expires_at=?", (int(time.time()) - 5,))
    assert client.get("/api/auth/me", headers=auth(token)).status_code == 401


def test_existing_data_intact(db):
    with sqlite3.connect(db) as conn:
        conn.execute("""INSERT INTO Child_Profiles (child_id,user_id,first_name,date_of_birth)
            VALUES (123,1,'Existing Synthetic Child','2022-08-08')""")
        conn.execute("""INSERT INTO Screening_Records
            (child_id,model_name,predicted_class) VALUES (123,'SyntheticModel','inconclusive')""")
        before = conn.execute("SELECT * FROM Screening_Records").fetchall()
        conn.executescript(SCHEMA.read_text(encoding="utf-8"))
        after = conn.execute("SELECT * FROM Screening_Records").fetchall()
        assert before == after
