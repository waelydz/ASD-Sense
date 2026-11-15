"""Authenticated appointment, screening-history, and private document persistence.

This module intentionally does not import TensorFlow or any model files.
No endpoint accepts a user_id as proof of identity: require_user_id comes from
verified session middleware, and every child lookup checks ownership.
"""
from __future__ import annotations

import os
import secrets
import sqlite3
import zipfile
from contextlib import contextmanager
from datetime import datetime
from io import BytesIO
from pathlib import Path
from typing import Generator, Literal

from fastapi import APIRouter, Depends, File, Form, HTTPException, Response, UploadFile, status
from fastapi.responses import FileResponse
from pydantic import BaseModel, ConfigDict, Field, field_validator

from child_profiles_api import require_user_id

MAX_DOCUMENT_SIZE = 10 * 1024 * 1024
_SUPPORTED_TYPES = {
    '.pdf': 'application/pdf',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
}


@contextmanager
def database(db_path: str | Path) -> Generator[sqlite3.Connection, None, None]:
    conn = sqlite3.connect(str(db_path), timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute('PRAGMA foreign_keys=ON')
    try:
        yield conn
        conn.commit()
    except BaseException:
        conn.rollback()
        raise
    finally:
        conn.close()


def ensure_owned_child(conn: sqlite3.Connection, child_id: int, user_id: int) -> None:
    row = conn.execute('SELECT 1 FROM Child_Profiles WHERE child_id=? AND user_id=?',
                       (child_id, user_id)).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail='Child profile not found')


def require_owned_child(db_path: str | Path, child_id: int, user_id: int) -> None:
    with database(db_path) as conn:
        ensure_owned_child(conn, child_id, user_id)


def save_screening_result(db_path: str | Path, *, child_id: int, user_id: int,
                          model_used: str, predicted_class: str,
                          prob_autistic: float, confidence: float,
                          routing_tier: str) -> int:
    # Recheck ownership inside the same transaction as insertion. Raw image
    # bytes and original image filenames are deliberately NOT stored.
    with database(db_path) as conn:
        ensure_owned_child(conn, child_id, user_id)
        cur = conn.execute('''INSERT INTO Screening_Records
            (child_id, performed_by_user_id, model_name, model_version,
             predicted_class, autism_probability, confidence, notes)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
            (child_id, user_id, model_used, '1.0', predicted_class,
             round(prob_autistic, 4), round(confidence, 4), routing_tier))
        return int(cur.lastrowid)


def list_screenings(db_path: str | Path, child_id: int, user_id: int) -> list[dict]:
    with database(db_path) as conn:
        ensure_owned_child(conn, child_id, user_id)
        rows = conn.execute('''SELECT screening_id, child_id, screening_date,
            model_name, model_version, predicted_class, autism_probability,
            confidence, notes, created_at FROM Screening_Records
            WHERE child_id=? ORDER BY screening_date DESC, screening_id DESC''',
            (child_id,)).fetchall()
        return [dict(row) for row in rows]


class AppointmentCreate(BaseModel):
    model_config = ConfigDict(extra='forbid')
    scheduled_at: datetime
    location: str = Field(min_length=1, max_length=250)
    clinician_name: str | None = Field(default=None, max_length=150)
    appointment_type: str = Field(default='Personal reminder (not provider-confirmed)', max_length=150)
    notes: str | None = Field(default=None, max_length=2000)

    @field_validator('scheduled_at')
    @classmethod
    def require_offset(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError('scheduled_at must include a timezone offset')
        return value

    @field_validator('location')
    @classmethod
    def nonblank_location(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError('A location is required')
        return value


class AppointmentUpdate(BaseModel):
    model_config = ConfigDict(extra='forbid')
    scheduled_at: datetime | None = None
    location: str | None = Field(default=None, max_length=250)
    clinician_name: str | None = Field(default=None, max_length=150)
    appointment_type: str | None = Field(default=None, max_length=150)
    notes: str | None = Field(default=None, max_length=2000)
    status: Literal['scheduled', 'cancelled'] | None = None

    @field_validator('scheduled_at')
    @classmethod
    def require_offset(cls, value: datetime | None) -> datetime | None:
        if value is not None and (value.tzinfo is None or value.utcoffset() is None):
            raise ValueError('scheduled_at must include a timezone offset')
        return value


class AppointmentOut(BaseModel):
    appointment_id: int
    child_id: int
    user_id: int
    scheduled_at: str
    clinician_name: str | None
    appointment_type: str | None
    location: str | None
    status: str
    notes: str | None
    created_at: str
    updated_at: str


class MedicalRecordOut(BaseModel):
    record_id: int
    child_id: int
    file_name: str
    record_type: Literal['document', 'imaging']
    content_type: str
    file_size: int
    created_at: str


def _valid_file(original_name: str, data: bytes) -> tuple[str, str]:
    name = original_name.replace('\\', '/').split('/')[-1].strip()
    if not name or len(name) > 180 or '/' in name or '\x00' in name:
        raise HTTPException(422, detail='Invalid filename')
    suffix = Path(name).suffix.lower()
    content_type = _SUPPORTED_TYPES.get(suffix)
    if content_type is None:
        raise HTTPException(415, detail='File type not supported')
    valid = {
        '.pdf': data.startswith(b'%PDF-'),
        '.png': data.startswith(b'\x89PNG\r\n\x1a\n'),
        '.jpg': data.startswith(b'\xff\xd8\xff'),
        '.jpeg': data.startswith(b'\xff\xd8\xff'),
        '.docx': zipfile.is_zipfile(BytesIO(data)),
    }[suffix]
    if suffix == '.docx' and valid:
        with zipfile.ZipFile(BytesIO(data)) as archive:
            names = set(archive.namelist())
            valid = '[Content_Types].xml' in names and 'word/document.xml' in names
    if not valid:
        raise HTTPException(415, detail='File contents do not match the extension')
    return name, content_type


def create_clinical_router(db_path: str | Path, records_dir: str | Path) -> APIRouter:
    router = APIRouter(prefix='/api/children', tags=['child-records'])
    records_root = Path(records_dir).expanduser().resolve()

    def owned_appointment(conn: sqlite3.Connection, child_id: int,
                          appointment_id: int, user_id: int) -> sqlite3.Row:
        ensure_owned_child(conn, child_id, user_id)
        row = conn.execute('''SELECT * FROM Appointments
            WHERE appointment_id=? AND child_id=? AND user_id=?''',
            (appointment_id, child_id, user_id)).fetchone()
        if row is None:
            raise HTTPException(404, detail='Appointment not found')
        return row

    def owned_record(conn: sqlite3.Connection, child_id: int,
                     record_id: int, user_id: int) -> sqlite3.Row:
        ensure_owned_child(conn, child_id, user_id)
        row = conn.execute('''SELECT m.* FROM Medical_Records m
            WHERE m.record_id=? AND m.child_id=? AND m.uploaded_by_user_id=?''',
            (record_id, child_id, user_id)).fetchone()
        if row is None:
            raise HTTPException(404, detail='Document not found')
        return row

    @router.get('/{child_id}/screenings')
    def screening_history(child_id: int, user_id: int = Depends(require_user_id)):
        return list_screenings(db_path, child_id, user_id)

    @router.post('/{child_id}/appointments', response_model=AppointmentOut,
                 status_code=status.HTTP_201_CREATED)
    def create_appointment(child_id: int, body: AppointmentCreate,
                           user_id: int = Depends(require_user_id)):
        with database(db_path) as conn:
            ensure_owned_child(conn, child_id, user_id)
            cur = conn.execute('''INSERT INTO Appointments
                (child_id, user_id, scheduled_at, location, clinician_name, appointment_type, notes)
                VALUES (?, ?, ?, ?, ?, ?, ?)''',
                (child_id, user_id, body.scheduled_at.isoformat(), body.location,
                 body.clinician_name, body.appointment_type, body.notes))
            return dict(owned_appointment(conn, child_id, int(cur.lastrowid), user_id))

    @router.get('/{child_id}/appointments', response_model=list[AppointmentOut])
    def get_appointments(child_id: int, user_id: int = Depends(require_user_id)):
        with database(db_path) as conn:
            ensure_owned_child(conn, child_id, user_id)
            rows = conn.execute('''SELECT * FROM Appointments WHERE child_id=? AND user_id=?
                ORDER BY scheduled_at DESC, appointment_id DESC''',
                (child_id, user_id)).fetchall()
            return [dict(row) for row in rows]

    @router.patch('/{child_id}/appointments/{appointment_id}', response_model=AppointmentOut)
    def patch_appointment(child_id: int, appointment_id: int, body: AppointmentUpdate,
                          user_id: int = Depends(require_user_id)):
        changes = body.model_dump(exclude_unset=True)
        if not changes:
            raise HTTPException(400, detail='No changes supplied')
        if any(value is None for key, value in changes.items() if key in
               {'scheduled_at', 'location', 'appointment_type', 'status'}):
            raise HTTPException(422, detail='Required appointment fields cannot be null')
        if isinstance(changes.get('scheduled_at'), datetime):
            changes['scheduled_at'] = changes['scheduled_at'].isoformat()
        with database(db_path) as conn:
            owned_appointment(conn, child_id, appointment_id, user_id)
            conn.execute('''UPDATE Appointments SET ''' + ', '.join(
                f'{field}=?' for field in changes) + ''', updated_at=CURRENT_TIMESTAMP
                WHERE appointment_id=? AND child_id=? AND user_id=?''',
                [*changes.values(), appointment_id, child_id, user_id])
            return dict(owned_appointment(conn, child_id, appointment_id, user_id))

    @router.delete('/{child_id}/appointments/{appointment_id}', status_code=204)
    def delete_appointment(child_id: int, appointment_id: int,
                           user_id: int = Depends(require_user_id)):
        with database(db_path) as conn:
            owned_appointment(conn, child_id, appointment_id, user_id)
            conn.execute('DELETE FROM Appointments WHERE appointment_id=?', (appointment_id,))
        return Response(status_code=204)

    @router.post('/{child_id}/medical-records', response_model=MedicalRecordOut,
                 status_code=201)
    async def upload_document(child_id: int, file: UploadFile = File(...),
                              record_type: Literal['document', 'imaging'] = Form('document'),
                              user_id: int = Depends(require_user_id)):
        # Authenticate and check ownership *before* reading uploaded medical data.
        require_owned_child(db_path, child_id, user_id)
        data = await file.read(MAX_DOCUMENT_SIZE + 1)
        await file.close()
        if not data:
            raise HTTPException(422, detail='The document is empty')
        if len(data) > MAX_DOCUMENT_SIZE:
            raise HTTPException(413, detail='The file exceeds the 10 MB limit')
        filename, content_type = _valid_file(file.filename or '', data)
        records_root.mkdir(mode=0o700, parents=True, exist_ok=True)
        key = secrets.token_hex(24)
        stored_file = records_root / key
        with stored_file.open('xb') as target:
            target.write(data)
        try:
            os.chmod(stored_file, 0o600)
        except OSError:
            pass
        try:
            with database(db_path) as conn:
                ensure_owned_child(conn, child_id, user_id)
                cur = conn.execute('''INSERT INTO Medical_Records
                    (child_id, uploaded_by_user_id, file_name, storage_key,
                     content_type, file_size, record_type)
                    VALUES (?, ?, ?, ?, ?, ?, ?)''',
                    (child_id, user_id, filename, key, content_type,
                     len(data), record_type))
                row = conn.execute('SELECT * FROM Medical_Records WHERE record_id=?',
                                   (cur.lastrowid,)).fetchone()
                return dict(row)
        except BaseException:
            stored_file.unlink(missing_ok=True)
            raise

    @router.get('/{child_id}/medical-records', response_model=list[MedicalRecordOut])
    def get_documents(child_id: int, user_id: int = Depends(require_user_id)):
        with database(db_path) as conn:
            ensure_owned_child(conn, child_id, user_id)
            rows = conn.execute('''SELECT * FROM Medical_Records WHERE child_id=?
                ORDER BY record_id DESC''', (child_id,)).fetchall()
            return [dict(row) for row in rows]

    @router.get('/{child_id}/medical-records/{record_id}/download')
    def download_document(child_id: int, record_id: int,
                          user_id: int = Depends(require_user_id)):
        with database(db_path) as conn:
            row = owned_record(conn, child_id, record_id, user_id)
            path = records_root / row['storage_key']
            if not path.is_file():
                raise HTTPException(404, detail='File unavailable')
            return FileResponse(str(path), media_type='application/octet-stream',
                                filename=row['file_name'],
                                headers={'X-Content-Type-Options': 'nosniff',
                                         'Cache-Control': 'no-store'})

    @router.delete('/{child_id}/medical-records/{record_id}', status_code=204)
    def delete_document(child_id: int, record_id: int,
                        user_id: int = Depends(require_user_id)):
        with database(db_path) as conn:
            row = owned_record(conn, child_id, record_id, user_id)
            key = row['storage_key']
            conn.execute('DELETE FROM Medical_Records WHERE record_id=?', (record_id,))
        (records_root / key).unlink(missing_ok=True)
        return Response(status_code=204)

    return router
