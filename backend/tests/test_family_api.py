"""Screened images, notifications and reviews for families, and password
reset (screening_images.py, family_api.py). Synthetic data only, model-free."""
import re
import sqlite3
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import mailer
from dev_persistence_app import create_app
from manage import create_user

PNG = b'\x89PNG\r\n\x1a\n' + b'synthetic pixels'
GUARDIAN_PASSWORD = 'test-only-strong-password-123'
CLINICIAN_PASSWORD = 'test-only-clinician-pass-456'


@pytest.fixture
def outbox(monkeypatch):
    sent = []
    monkeypatch.setattr(mailer, 'send', lambda to, subject, body: sent.append((to, subject, body)))
    return sent


@pytest.fixture
def family(tmp_path, outbox):
    database = tmp_path / 'synthetic.db'
    with TestClient(create_app(database)) as client:
        g = client.post('/api/auth/register', json={
            'full_name': 'Guardian One', 'email': 'one@example.test', 'password': GUARDIAN_PASSWORD,
        }).json()
        hg = {'Authorization': f'Bearer {g["access_token"]}'}
        child = client.post('/api/children', headers=hg, json={
            'first_name': 'Sam', 'date_of_birth': '2022-02-03'}).json()['child_id']
        with sqlite3.connect(database) as conn:
            create_user(conn, 'Dr Synthetic', 'doc@example.test', CLINICIAN_PASSWORD, 'clinician')
        token = client.post('/api/clinic/auth/login', json={
            'email': 'doc@example.test', 'password': CLINICIAN_PASSWORD}).json()['access_token']
        hc = {'Authorization': f'Bearer {token}'}
        yield client, database, tmp_path, hg, hc, child


def screen(client, headers, child, data=PNG):
    r = client.post('/predict/facial', headers=headers, data={'child_id': str(child)},
                    files={'file': ('private-name.png', data, 'image/png')})
    assert r.status_code == 200, r.text
    return r.json()['screening_id']


def test_screened_image_is_kept_for_clinicians_only(family):
    client, db, tmp, hg, hc, child = family
    with_image = screen(client, hg, child)
    not_an_image = screen(client, hg, child, data=b'not an image')

    shown = {s['screening_id']: s['has_image'] for s in client.get('/api/clinic/state', headers=hc).json()['screenings']}
    assert shown == {with_image: True, not_an_image: False}
    r = client.get(f'/api/clinic/screenings/{with_image}/image', headers=hc)
    assert r.status_code == 200 and r.content == PNG and r.headers['content-type'] == 'image/png'
    assert client.get(f'/api/clinic/screenings/{not_an_image}/image', headers=hc).status_code == 404
    # Not readable by the guardian session or without a session.
    assert client.get(f'/api/clinic/screenings/{with_image}/image', headers=hg).status_code == 403
    assert client.get(f'/api/clinic/screenings/{with_image}/image').status_code == 401
    # Stored outside the database under a random name; the filename is not kept.
    files = list((tmp / 'asd_sense_dev_screenings').iterdir())
    assert len(files) == 1 and files[0].read_bytes() == PNG and 'private-name' not in files[0].name
    with sqlite3.connect(db) as conn:
        assert 'private-name' not in str(conn.execute('SELECT * FROM Screening_Images').fetchall())


def test_family_sees_review_outcome_and_gets_notified(family, outbox):
    client, db, _, hg, hc, child = family
    screening = screen(client, hg, child)
    client.put('/api/account/preferences', headers=hg, json={'push_notifications': True, 'email_notifications': True})

    r = client.put(f'/api/clinic/screenings/{screening}/review', headers=hc, json={
        'finding': 'disagree', 'action': 'refer_diagnostic', 'note': 'Clinic only note.'})
    assert r.status_code == 200
    history = client.get(f'/api/children/{child}/screenings', headers=hg)
    row = history.json()[0]
    assert row['review_action'] == 'refer_diagnostic' and row['reviewer_name'] == 'Dr Synthetic'
    assert row['reviewed_at']
    # The note and the finding stay in the clinic.
    assert 'Clinic only note' not in history.text and 'disagree' not in history.text

    notes = client.get('/api/notifications', headers=hg).json()
    assert [n['title'] for n in notes] == ['Screening reviewed']
    assert 'full developmental assessment' in notes[0]['body'] and notes[0]['is_read'] is False
    assert 'Clinic only note' not in str(notes)
    assert outbox and outbox[-1][0] == 'one@example.test' and 'Clinic only note' not in outbox[-1][2]

    # Editing only the note does not notify again; a new next step does.
    client.put(f'/api/clinic/screenings/{screening}/review', headers=hc, json={
        'finding': 'disagree', 'action': 'refer_diagnostic', 'note': 'Edited note.'})
    assert len(client.get('/api/notifications', headers=hg).json()) == 1
    client.put(f'/api/clinic/screenings/{screening}/review', headers=hc, json={
        'finding': 'agree', 'action': 'monitor', 'note': ''})
    assert len(client.get('/api/notifications', headers=hg).json()) == 2

    # Appointment status changes are announced too.
    appointment = client.post(f'/api/children/{child}/appointments', headers=hg, json={
        'scheduled_at': '2030-01-02T10:00:00+04:00', 'location': 'Demo Clinic'}).json()['appointment_id']
    client.patch(f'/api/clinic/appointments/{appointment}', headers=hc, json={'status': 'confirmed'})
    latest = client.get('/api/notifications', headers=hg).json()[0]
    assert latest['title'] == 'Appointment confirmed' and 'Demo Clinic' in latest['body']

    assert client.post('/api/notifications/read', headers=hg).status_code == 204
    assert all(n['is_read'] for n in client.get('/api/notifications', headers=hg).json())
    # Each guardian only sees their own; clinicians are not guardians.
    assert client.get('/api/notifications', headers=hc).status_code == 401
    assert client.get('/api/notifications').status_code == 401


def test_no_email_unless_the_guardian_turned_it_on(family, outbox):
    client, _, _, hg, hc, child = family
    screening = screen(client, hg, child)
    client.put(f'/api/clinic/screenings/{screening}/review', headers=hc, json={
        'finding': 'agree', 'action': 'monitor', 'note': ''})
    assert len(client.get('/api/notifications', headers=hg).json()) == 1
    assert outbox == []


def test_password_reset_by_email_code(family, outbox):
    client, _, _, hg, _, _ = family
    # Unknown addresses and clinician accounts get the same answer, and no email.
    assert client.post('/api/auth/forgot', json={'email': 'nobody@example.test'}).json() == {'ok': True}
    assert client.post('/api/auth/forgot', json={'email': 'doc@example.test'}).json() == {'ok': True}
    assert outbox == []

    assert client.post('/api/auth/forgot', json={'email': 'ONE@example.test'}).status_code == 200
    to, _, body = outbox[-1]
    assert to == 'one@example.test'
    code = re.search(r'\b(\d{6})\b', body).group(1)
    wrong = '000000' if code != '000000' else '111111'

    new_password = 'brand-new-password-789'
    r = client.post('/api/auth/reset', json={'email': 'one@example.test', 'code': wrong, 'new_password': new_password})
    assert r.status_code == 400
    r = client.post('/api/auth/reset', json={'email': 'one@example.test', 'code': code, 'new_password': 'short'})
    assert r.status_code == 422
    r = client.post('/api/auth/reset', json={'email': 'one@example.test', 'code': code, 'new_password': new_password})
    assert r.status_code == 200, r.text

    # Signed out everywhere, old password gone, new one works, code used up.
    assert client.get('/api/auth/me', headers=hg).status_code == 401
    assert client.post('/api/auth/login', json={'email': 'one@example.test', 'password': GUARDIAN_PASSWORD}).status_code == 401
    assert client.post('/api/auth/login', json={'email': 'one@example.test', 'password': new_password}).status_code == 200
    r = client.post('/api/auth/reset', json={'email': 'one@example.test', 'code': code, 'new_password': 'another-one-12345'})
    assert r.status_code == 400


def test_reset_code_stops_working_after_five_wrong_guesses(family, outbox):
    client, *_ = family
    client.post('/api/auth/forgot', json={'email': 'one@example.test'})
    code = re.search(r'\b(\d{6})\b', outbox[-1][2]).group(1)
    wrong = '000000' if code != '000000' else '111111'
    for _ in range(5):
        client.post('/api/auth/reset', json={'email': 'one@example.test', 'code': wrong, 'new_password': 'whatever-pass-123'})
    r = client.post('/api/auth/reset', json={'email': 'one@example.test', 'code': code, 'new_password': 'whatever-pass-123'})
    assert r.status_code == 400
