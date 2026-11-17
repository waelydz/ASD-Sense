"""Validate the development API on a fresh, isolated SQLite database."""
import sqlite3
import sys
from pathlib import Path

from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from dev_persistence_app import create_app  # noqa: E402


def test_development_app_persists_after_new_process_like_app_instance(tmp_path):
    path = tmp_path / "synthetic_only.db"
    with TestClient(create_app(path)) as client:
        account = client.post('/api/auth/register', json={
            'full_name': 'Synthetic Guardian',
            'email': 'guardian@example.test',
            'password': 'not-a-real-password-123',
        })
        assert account.status_code == 201
        token = account.json()['access_token']
        headers = {'Authorization': f'Bearer {token}'}
        child = client.post('/api/children', headers=headers, json={
            'first_name': 'Synthetic Child', 'date_of_birth': '2021-03-04',
        })
        assert child.status_code == 201
        child_id = child.json()['child_id']

    with TestClient(create_app(path)) as client:
        children = client.get('/api/children', headers=headers)
        assert children.status_code == 200
        assert children.json()[0]['child_id'] == child_id
    with sqlite3.connect(path) as conn:
        assert conn.execute('SELECT COUNT(*) FROM Child_Profiles').fetchone()[0] == 1
