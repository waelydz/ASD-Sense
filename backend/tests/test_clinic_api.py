"""Clinician portal routes (clinic_api.py). Synthetic data only, model-free."""
import io
import sqlite3
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from dev_persistence_app import create_app
from manage import create_user

PNG = b'\x89PNG\r\n\x1a\n' + b'synthetic'
GUARDIAN_PASSWORD = 'test-only-strong-password-123'
CLINICIAN_PASSWORD = 'test-only-clinician-pass-456'


@pytest.fixture
def clinic(tmp_path):
    database = tmp_path / 'synthetic.db'
    with TestClient(create_app(database)) as client:
        g = client.post('/api/auth/register', json={
            'full_name': 'Guardian One', 'email': 'one@example.test', 'password': GUARDIAN_PASSWORD,
        }).json()
        hg = {'Authorization': f'Bearer {g["access_token"]}'}
        child = client.post('/api/children', headers=hg, json={
            'first_name': 'Fake Child', 'date_of_birth': '2022-02-03'}).json()['child_id']
        with sqlite3.connect(database) as conn:
            create_user(conn, 'Dr Synthetic', 'doc@example.test', CLINICIAN_PASSWORD, 'clinician')
        login = client.post('/api/clinic/auth/login', json={
            'email': 'doc@example.test', 'password': CLINICIAN_PASSWORD})
        assert login.status_code == 200, login.text
        hc = {'Authorization': f'Bearer {login.json()["access_token"]}'}
        yield client, database, hg, hc, child


def test_roles_are_kept_apart(clinic):
    client, _, hg, hc, child = clinic
    # Guardians cannot sign in to the portal or call it with their session.
    r = client.post('/api/clinic/auth/login', json={'email': 'one@example.test', 'password': GUARDIAN_PASSWORD})
    assert r.status_code == 403
    assert client.get('/api/clinic/state', headers=hg).status_code == 403
    assert client.get('/api/clinic/state').status_code == 401
    # Clinicians cannot sign in to, or use, the guardian app's routes.
    r = client.post('/api/auth/login', json={'email': 'doc@example.test', 'password': CLINICIAN_PASSWORD})
    assert r.status_code == 401
    assert client.get('/api/children', headers=hc).status_code == 401
    # Wrong password.
    r = client.post('/api/clinic/auth/login', json={'email': 'doc@example.test', 'password': 'wrong-password-000'})
    assert r.status_code == 401


def test_portal_sees_guardian_data_and_follows_changes(clinic):
    client, _, hg, hc, child = clinic
    state = client.get('/api/clinic/state', headers=hc).json()
    assert [p['child_id'] for p in state['patients']] == [child]
    assert state['patients'][0]['guardian_email'] == 'one@example.test'
    assert state['user']['email'] == 'doc@example.test'
    before = client.get('/api/clinic/sync/revision', headers=hc).json()['revision']

    # The guardian screens, books and uploads in the app.
    r = client.post('/predict/facial', headers=hg, data={'child_id': str(child)},
                    files={'file': ('x.png', b'synthetic image', 'image/png')})
    assert r.status_code == 200, r.text
    r = client.post(f'/api/children/{child}/appointments', headers=hg, json={
        'scheduled_at': '2030-01-02T10:00:00+04:00', 'location': 'Demo Clinic'})
    assert r.status_code == 201, r.text
    appointment = r.json()['appointment_id']
    r = client.post(f'/api/children/{child}/medical-records', headers=hg,
                    data={'record_type': 'imaging'}, files={'file': ('scan.png', PNG, 'image/png')})
    assert r.status_code == 201, r.text
    record = r.json()['record_id']

    assert client.get('/api/clinic/sync/revision', headers=hc).json()['revision'] > before
    state = client.get('/api/clinic/state', headers=hc).json()
    assert len(state['screenings']) == 1 and state['screenings'][0]['has_image'] is False
    assert state['appointments'][0]['scheduled_at'] == '2030-01-02T10:00:00+04:00'
    assert state['records'][0]['has_file'] == 1

    # The clinician confirms the visit; the guardian sees the new status.
    r = client.patch(f'/api/clinic/appointments/{appointment}', headers=hc, json={'status': 'confirmed'})
    assert r.status_code == 200
    mine = client.get(f'/api/children/{child}/appointments', headers=hg).json()
    assert mine[0]['status'] == 'confirmed'

    # The clinician opens the uploaded file through a single-use link.
    path = client.post(f'/api/clinic/records/{record}/link', headers=hc).json()['path']
    opened = client.get(path)
    assert opened.status_code == 200 and opened.content == PNG
    assert client.get(path).status_code == 404


def test_reviews_patients_and_clinic_screenings(clinic):
    client, db, hg, hc, child = clinic
    r = client.post('/api/clinic/predict/gesture', headers=hc, data={'child_id': str(child)},
                    files={'file': ('x.png', b'synthetic image', 'image/png')})
    assert r.status_code == 200, r.text
    screening = r.json()['screening_id']
    # Guardians cannot use the clinician screening route.
    assert client.post('/api/clinic/predict/gesture', headers=hg, data={'child_id': str(child)},
                       files={'file': ('x.png', b'x', 'image/png')}).status_code == 403

    r = client.put(f'/api/clinic/screenings/{screening}/review', headers=hc, json={
        'finding': 'agree', 'action': 'refer_diagnostic', 'note': 'Clinic only.'})
    assert r.status_code == 200
    review = client.get('/api/clinic/state', headers=hc).json()['reviews'][0]
    assert review['screening_id'] == screening and review['reviewer_name'] == 'Dr Synthetic'
    # The clinical note is not part of what the guardian app can read.
    assert 'Clinic only.' not in client.get(f'/api/children/{child}/screenings', headers=hg).text
    assert client.delete(f'/api/clinic/screenings/{screening}/review', headers=hc).status_code == 200
    assert client.get('/api/clinic/state', headers=hc).json()['reviews'] == []

    r = client.post('/api/clinic/patients', headers=hc, json={
        'first_name': 'Referred', 'last_name': 'Child', 'date_of_birth': '2021-06-01',
        'guardian_name': 'Parent Two', 'guardian_phone': '050 000 0000'})
    assert r.status_code == 201, r.text
    patients = {p['child_id']: p for p in client.get('/api/clinic/state', headers=hc).json()['patients']}
    added = patients[r.json()['child_id']]
    assert added['guardian_name'] == 'Parent Two'
    assert added['referral_source'] == 'Added in the clinician portal'
    # A portal-added child never shows up for a guardian.
    assert [c['child_id'] for c in client.get('/api/children', headers=hg).json()] == [child]


def test_profile_password_and_logout(clinic):
    client, _, _, hc, _ = clinic
    r = client.patch('/api/clinic/me', headers=hc, json={'job_title': 'Psychologist', 'use_24_hour_time': True})
    assert r.status_code == 200
    assert r.json()['job_title'] == 'Psychologist' and r.json()['use_24_hour_time'] is True

    second = client.post('/api/clinic/auth/login', json={
        'email': 'doc@example.test', 'password': CLINICIAN_PASSWORD}).json()['access_token']
    h2 = {'Authorization': f'Bearer {second}'}
    assert client.post('/api/clinic/me/password', headers=hc, json={
        'current_password': 'wrong-password-000', 'new_password': 'another-strong-pass-1'}).status_code == 400
    assert client.post('/api/clinic/me/password', headers=hc, json={
        'current_password': CLINICIAN_PASSWORD, 'new_password': 'short'}).status_code == 422
    r = client.post('/api/clinic/me/password', headers=hc, json={
        'current_password': CLINICIAN_PASSWORD, 'new_password': 'another-strong-pass-1'})
    assert r.status_code == 200 and r.json()['password_changed_at']
    # Other sessions end; this one stays.
    assert client.get('/api/clinic/state', headers=h2).status_code == 401
    assert client.get('/api/clinic/state', headers=hc).status_code == 200
    activity = [a['text'] for a in client.get('/api/clinic/state', headers=hc).json()['activity']]
    assert 'Changed password' in activity and 'Signed in' in activity

    assert client.post('/api/clinic/auth/logout', headers=hc).status_code == 204
    assert client.get('/api/clinic/state', headers=hc).status_code == 401
