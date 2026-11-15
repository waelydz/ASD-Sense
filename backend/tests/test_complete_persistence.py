"""Synthetic only, no real medical or identity data. Tests remain model-free."""
import io
import sqlite3
import sys
import zipfile
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from clinical_api import save_screening_result
from dev_persistence_app import create_app


@pytest.fixture
def setup(tmp_path):
    database = tmp_path / 'synthetic.db'
    with TestClient(create_app(database)) as client:
        def register(email, name):
            response = client.post('/api/auth/register', json={
                'full_name': name, 'email': email, 'password': 'test-only-strong-password-123',
            })
            assert response.status_code == 201, response.text
            return response.json()
        a = register('one@example.test', 'Guardian One')
        b = register('two@example.test', 'Guardian Two')
        ha = {'Authorization': f'Bearer {a["access_token"]}'}
        hb = {'Authorization': f'Bearer {b["access_token"]}'}
        def create_child(headers, name):
            r = client.post('/api/children', headers=headers, json={
                'first_name': name, 'date_of_birth': '2022-02-03',
            })
            assert r.status_code == 201
            return r.json()['child_id']
        c1 = create_child(ha, 'Fake Child One')
        c2 = create_child(ha, 'Fake Child Two')
        c3 = create_child(hb, 'Other Fake Child')
        yield client, database, a, b, ha, hb, c1, c2, c3


def test_screening_belongs_to_correct_child_and_blocks_cross_guardian(setup):
    client, db, a, b, ha, hb, c1, c2, c3 = setup
    save_screening_result(db, child_id=c2, user_id=a['user']['user_id'],
        model_used='Synthetic_Unit_Test_Only', predicted_class='inconclusive',
        prob_autistic=0.5, confidence=0.5, routing_tier='synthetic-only')
    one = client.get(f'/api/children/{c1}/screenings', headers=ha)
    two = client.get(f'/api/children/{c2}/screenings', headers=ha)
    assert one.status_code == two.status_code == 200
    assert one.json() == []
    assert len(two.json()) == 1
    assert two.json()[0]['child_id'] == c2
    assert 'image_reference' not in two.json()[0]
    assert client.get(f'/api/children/{c2}/screenings', headers=hb).status_code == 404
    assert client.get(f'/api/children/{c2}/screenings').status_code == 401
    with pytest.raises(Exception):
        save_screening_result(db, child_id=c2, user_id=b['user']['user_id'],
            model_used='Fake', predicted_class='inconclusive',
            prob_autistic=.5, confidence=.5, routing_tier='unit')
    with sqlite3.connect(db) as conn:
        assert conn.execute('SELECT performed_by_user_id FROM Screening_Records WHERE child_id=?',
                            (c2,)).fetchone()[0] == a['user']['user_id']


def test_appointment_crud_and_cross_guardian_protection(setup):
    client, db, a, b, ha, hb, c1, c2, c3 = setup
    path = f'/api/children/{c1}/appointments'
    r = client.post(path, headers=ha, json={
        'scheduled_at': '2031-05-07T14:30:00+04:00',
        'location': 'Synthetic Care Centre',
    })
    assert r.status_code == 201, r.text
    obj = r.json()
    assert obj['status'] == 'scheduled'
    assert 'not provider-confirmed' in obj['appointment_type']
    appt = obj['appointment_id']
    assert client.get(path, headers=ha).json()[0]['appointment_id'] == appt
    assert client.get(path, headers=hb).status_code == 404
    assert client.get(path).status_code == 401
    assert client.patch(f'{path}/{appt}', headers=hb, json={'status':'cancelled'}).status_code == 404
    assert client.patch(f'{path}/{appt}', headers=ha, json={'status':'confirmed'}).status_code == 422
    r = client.patch(f'{path}/{appt}', headers=ha, json={'status':'cancelled'})
    assert r.status_code == 200 and r.json()['status'] == 'cancelled'
    assert client.delete(f'{path}/{appt}', headers=hb).status_code == 404
    assert client.delete(f'{path}/{appt}', headers=ha).status_code == 204
    assert client.get(path, headers=ha).json() == []
    assert client.post(path, headers=ha, json={
        'scheduled_at': '2031-05-07T14:30:00', 'location': 'Test'
    }).status_code == 422


def test_medical_record_bytes_securely_stored_not_in_db_and_restart(setup):
    client, db, a, b, ha, hb, c1, c2, c3 = setup
    url = f'/api/children/{c1}/medical-records'
    blob = b'%PDF-1.4\n%synthetic test file\n%%EOF\n'
    upload = client.post(url, headers=ha, data={'record_type':'document'},
                         files={'file':('synthetic-only.pdf',blob,'application/pdf')})
    assert upload.status_code == 201, upload.text
    record_id = upload.json()['record_id']
    assert upload.json()['file_size'] == len(blob)
    assert client.get(url, headers=ha).json()[0]['file_name'] == 'synthetic-only.pdf'
    get_url = f'{url}/{record_id}/download'
    assert client.get(get_url, headers=ha).content == blob
    assert client.get(get_url, headers=hb).status_code == 404
    assert client.get(get_url).status_code == 401
    assert client.get(url, headers=hb).status_code == 404
    assert client.delete(f'{url}/{record_id}', headers=hb).status_code == 404
    assert client.delete(f'/api/children/{c1}', headers=ha).status_code == 409
    assert blob not in db.read_bytes()

    # Fresh FastAPI app sees the persisted bytes and metadata.
    with TestClient(create_app(db)) as restarted:
        assert restarted.get(get_url, headers=ha).content == blob
        assert restarted.delete(f'{url}/{record_id}', headers=ha).status_code == 204
        assert restarted.get(url, headers=ha).json() == []
        assert restarted.get(get_url, headers=ha).status_code == 404


def test_upload_rejects_invalid_type_size_and_magic(setup):
    client, db, a, b, ha, hb, c1, c2, c3 = setup
    url = f'/api/children/{c1}/medical-records'
    def upload(name, blob):
        return client.post(url, headers=ha, files={'file':(name, blob)})
    assert upload('trick.exe', b'evil').status_code == 415
    assert upload('trick.pdf', b'not a pdf').status_code == 415
    assert upload('large.pdf', b'%PDF-' + b'A' * (10 * 1024 * 1024)).status_code == 413
    assert client.post(url, headers=hb, files={'file':('a.pdf',b'%PDF-1.7')}).status_code == 404
    assert client.get(url, headers=ha).json() == []


def test_profile_and_preferences_survive_restart(setup):
    client, db, a, b, ha, hb, c1, c2, c3 = setup
    assert client.get('/api/account/preferences', headers=ha).json() == {
        'push_notifications': True, 'email_notifications': False
    }
    assert client.put('/api/account/preferences', headers=ha, json={
        'push_notifications': False, 'email_notifications': True
    }).status_code == 200
    assert client.patch('/api/account/profile', headers=ha,
                        json={'full_name':'Guardian One Updated','phone':'000-000'}).status_code == 200
    assert client.get('/api/account/preferences', headers=hb).json()['push_notifications'] is True
    with TestClient(create_app(db)) as restarted:
        p = restarted.get('/api/account/preferences', headers=ha)
        assert p.json() == {'push_notifications':False,'email_notifications':True}
        me = restarted.get('/api/auth/me', headers=ha)
        assert me.json()['full_name'] == 'Guardian One Updated'
        assert me.json()['phone'] == '000-000'
    assert client.put('/api/account/preferences', json={
        'push_notifications': True, 'email_notifications': True
    }).status_code == 401


def test_existing_four_table_data_preserved_by_additive_migration(tmp_path):
    from dev_persistence_app import SCHEMA
    path = tmp_path / 'previous.db'
    with sqlite3.connect(path) as conn:
        sql = SCHEMA.read_text(encoding='utf-8')
        before_new_tables = sql.split('-- Additive persistence migration')[0]
        conn.executescript(before_new_tables)
        conn.execute('''INSERT INTO Users (user_id,full_name,email,password_hash,role)
            VALUES (101,'Synthetic Legacy','legacy@example.test','old-value','guardian')''')
        conn.execute('''INSERT INTO Child_Profiles (child_id,user_id,first_name,date_of_birth)
            VALUES (202,101,'Legacy Test Child','2022-01-01')''')
        conn.execute('''INSERT INTO Screening_Records
            (screening_id,child_id,model_name,predicted_class)
            VALUES (303,202,'Legacy Fake','inconclusive')''')
    with TestClient(create_app(path)):
        pass
    with sqlite3.connect(path) as conn:
        assert conn.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
        assert conn.execute('SELECT COUNT(*) FROM Screening_Records WHERE screening_id=303').fetchone()[0] == 1
        names = {r[0] for r in conn.execute('SELECT name FROM sqlite_master WHERE type="table"')}
        assert {'Medical_Records','User_Preferences','Auth_Sessions'} <= names


def test_synthetic_only_screening_route_validates_child_before_saving(setup):
    client, db, a, b, ha, hb, c1, c2, c3 = setup
    url = '/predict/facial'
    kwargs = {'data': {'child_id': str(c2)},
              'files': {'file': ('synthetic.png', b'fake synthetic image bytes', 'image/png')}}
    assert client.post(url, **kwargs).status_code == 401
    assert client.post(url, headers=hb, **kwargs).status_code == 404
    r = client.post(url, headers=ha, **kwargs)
    assert r.status_code == 200, r.text
    assert r.json()['model_name'] == 'SYNTHETIC_NO_AI_TEST'
    assert r.json()['predicted_class'] == 'inconclusive'
    assert client.get(f'/api/children/{c1}/screenings', headers=ha).json() == []
    assert len(client.get(f'/api/children/{c2}/screenings', headers=ha).json()) == 1
    assert client.post(url, headers=ha, files=kwargs['files']).status_code == 422
