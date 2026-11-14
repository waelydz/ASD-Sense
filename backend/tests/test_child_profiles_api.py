"""Synthetic-data persistence and ownership tests. Run: pytest -q backend/tests/test_child_profiles_api.py"""
import sqlite3
import sys
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from child_profiles_api import create_child_profiles_router, require_user_id

SCHEMA = Path(__file__).resolve().parents[1] / "asd_sense_database_schema.sql"


@pytest.fixture
def database(tmp_path):
    path = tmp_path / "synthetic-asd-sense.db"
    with sqlite3.connect(path) as connection:
        connection.executescript(SCHEMA.read_text(encoding="utf-8"))
        connection.execute(
            "INSERT INTO Users (user_id, full_name, email, password_hash, role) VALUES (1, 'Test A', 'test-a@example.invalid', 'dummy', 'guardian')"
        )
        connection.execute(
            "INSERT INTO Users (user_id, full_name, email, password_hash, role) VALUES (2, 'Test B', 'test-b@example.invalid', 'dummy', 'guardian')"
        )
    return path


def client_for(path, user_id=None):
    app = FastAPI()
    app.include_router(create_child_profiles_router(path))
    if user_id is not None:
        app.dependency_overrides[require_user_id] = lambda: user_id
    return TestClient(app)


def create_child(client, first_name="Synthetic"):
    return client.post("/api/children", json={
        "first_name": first_name,
        "date_of_birth": "2022-06-10",
        "sex": "prefer_not_to_say",
    })


def test_rejects_unauthenticated(database):
    with client_for(database) as client:
        assert client.get("/api/children").status_code == 401
        assert create_child(client).status_code == 401


def test_crud_survives_new_app_instance(database):
    with client_for(database, 1) as client:
        created = create_child(client)
        assert created.status_code == 201, created.text
        child_id = created.json()["child_id"]
        assert created.json()["user_id"] == 1
        assert isinstance(child_id, int)
        assert client.get("/api/children").json()[0]["child_id"] == child_id
        patch = client.patch(f"/api/children/{child_id}", json={"first_name": "Updated"})
        assert patch.status_code == 200, patch.text
        assert patch.json()["first_name"] == "Updated"
    # Recreating the API mimics a restart without using any Python in-memory state.
    with client_for(database, 1) as restarted:
        found = restarted.get(f"/api/children/{child_id}")
        assert found.status_code == 200
        assert found.json()["first_name"] == "Updated"
        assert restarted.delete(f"/api/children/{child_id}").status_code == 204
        assert restarted.get(f"/api/children/{child_id}").status_code == 404


def test_other_guardian_cannot_access_child(database):
    with client_for(database, 1) as guardian_a:
        child_id = create_child(guardian_a).json()["child_id"]
    with client_for(database, 2) as guardian_b:
        assert guardian_b.get("/api/children").json() == []
        assert guardian_b.get(f"/api/children/{child_id}").status_code == 404
        assert guardian_b.patch(f"/api/children/{child_id}", json={"first_name":"No"}).status_code == 404
        assert guardian_b.delete(f"/api/children/{child_id}").status_code == 404


def test_validates_input(database):
    with client_for(database, 1) as client:
        assert client.post("/api/children", json={"first_name":"  ","date_of_birth":"2022-06-10"}).status_code == 422
        assert client.post("/api/children", json={"first_name":"Demo","date_of_birth":"2999-01-01"}).status_code == 422
        assert client.post("/api/children", json={"first_name":"Demo","date_of_birth":"2022-06-10", "user_id":2}).status_code == 422
        child_id = create_child(client).json()["child_id"]
        assert client.patch(f"/api/children/{child_id}", json={"date_of_birth":None}).status_code == 422
        assert client.patch(f"/api/children/{child_id}", json={}).status_code == 400


def test_history_prevents_cascading_delete(database):
    with client_for(database, 1) as client:
        child_id = create_child(client).json()["child_id"]
        with sqlite3.connect(database) as connection:
            connection.execute(
                "INSERT INTO Screening_Records(child_id, model_name, predicted_class) VALUES (?, 'Synthetic_Test_Model', 'inconclusive')",
                (child_id,),
            )
        resp = client.delete(f"/api/children/{child_id}")
        assert resp.status_code == 409, resp.text
        assert client.get(f"/api/children/{child_id}").status_code == 200
        with sqlite3.connect(database) as connection:
            count = connection.execute("SELECT count(*) FROM Screening_Records WHERE child_id=?", (child_id,)).fetchone()[0]
            assert count == 1


def test_database_foreign_keys_enforced(database):
    with sqlite3.connect(database) as connection:
        connection.execute("PRAGMA foreign_keys = ON")
        with pytest.raises(sqlite3.IntegrityError):
            connection.execute("INSERT INTO Screening_Records(child_id, model_name, predicted_class) VALUES (9999, 'Synthetic', 'inconclusive')")


def test_appointment_history_prevents_delete(database):
    with client_for(database, 1) as client:
        child_id = create_child(client).json()["child_id"]
        with sqlite3.connect(database) as connection:
            connection.execute(
                """INSERT INTO Appointments(child_id, user_id, scheduled_at, status)
                VALUES (?, 1, '2027-01-03T09:00:00', 'scheduled')""",
                (child_id,),
            )
        assert client.delete(f"/api/children/{child_id}").status_code == 409
        assert client.get(f"/api/children/{child_id}").status_code == 200
