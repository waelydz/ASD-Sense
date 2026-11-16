"""Synthetic-data-only ASGI app for testing auth and child-profile persistence.

Run with ASD_SENSE_DB_PATH set to a NEW development database path. Deliberately
omits TensorFlow and inference; run main:app for model regression tests.
"""

from __future__ import annotations

import os
import sqlite3
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Depends, File, Form, HTTPException, UploadFile

from auth_api import attach_auth
from child_profiles_api import create_child_profiles_router, require_user_id
from clinical_api import create_clinical_router, require_owned_child, save_screening_result
from account_api import create_account_router
from clinic_api import clinician_dependency, create_clinic_router, save_clinic_screening
from family_api import create_family_router
import screening_images

BASE_DIR = Path(__file__).resolve().parent
SCHEMA = BASE_DIR / "asd_sense_database_schema.sql"
TRACKED_DB = (BASE_DIR / "asd_sense.db").resolve()


def create_app(database_path: str | Path) -> FastAPI:
    if not database_path:
        raise RuntimeError("Set ASD_SENSE_DB_PATH to a separate synthetic-data database")
    path = Path(database_path).expanduser().resolve()
    if path == TRACKED_DB:
        raise RuntimeError("Refusing to use the tracked backend/asd_sense.db")

    @asynccontextmanager
    async def lifespan(_app: FastAPI):
        path.parent.mkdir(parents=True, exist_ok=True)
        with sqlite3.connect(path) as conn:
            conn.execute("PRAGMA foreign_keys=ON")
            conn.executescript(SCHEMA.read_text(encoding="utf-8"))
        yield

    app = FastAPI(title="ASD-Sense Persistence Test API", lifespan=lifespan)
    images_dir = path.parent / "asd_sense_dev_screenings"

    @app.get("/")
    def health():
        return {"status": "development-persistence-only"}

    @app.post('/predict/{modality}')
    async def synthetic_screening(modality: str, file: UploadFile = File(...),
                                  child_id: int = Form(...),
                                  user_id: int = Depends(require_user_id)):
        """Persistence smoke test only; NEVER performs AI classification."""
        if modality not in ('facial', 'gesture'):
            raise HTTPException(404, detail='Unsupported screening modality')
        require_owned_child(path, child_id, user_id)
        content = await file.read(10 * 1024 * 1024 + 1)
        if len(content) == 0 or len(content) > 10 * 1024 * 1024:
            raise HTTPException(422, detail='Invalid test image size')
        # Filenames are not kept; the image is, as in main.py (screening_images.py).
        record_id = save_screening_result(path, child_id=child_id, user_id=user_id,
            model_used='SYNTHETIC_NO_AI_TEST', predicted_class='inconclusive',
            prob_autistic=0.5, confidence=0.5,
            routing_tier='Synthetic persistence test (NOT inference)')
        screening_images.save(path, images_dir, record_id, content)
        return {'screening_id': record_id, 'predicted_class': 'inconclusive',
                'autism_probability': 0.5, 'confidence': 0.5,
                'model_name': 'SYNTHETIC_NO_AI_TEST',
                'routing': 'Synthetic persistence test only'}

    require_clinician = clinician_dependency(path)

    @app.post('/api/clinic/predict/{modality}')
    async def synthetic_clinic_screening(modality: str, file: UploadFile = File(...),
                                         child_id: int = Form(...),
                                         clinician=Depends(require_clinician)):
        """Clinician-portal version of the smoke test above; NEVER performs AI classification."""
        if modality not in ('facial', 'gesture'):
            raise HTTPException(404, detail='Unsupported screening modality')
        content = await file.read(10 * 1024 * 1024 + 1)
        if len(content) == 0 or len(content) > 10 * 1024 * 1024:
            raise HTTPException(422, detail='Invalid test image size')
        record_id = save_clinic_screening(path, clinician, child_id=child_id, modality=modality,
            model_used='SYNTHETIC_NO_AI_TEST', predicted_class='inconclusive',
            prob_autistic=0.5, confidence=0.5,
            routing_tier='Synthetic persistence test (NOT inference)')
        screening_images.save(path, images_dir, record_id, content)
        return {'screening_id': record_id, 'predicted_class': 'inconclusive',
                'autism_probability': 0.5, 'confidence': 0.5,
                'model_name': 'SYNTHETIC_NO_AI_TEST',
                'routing': 'Synthetic persistence test only'}

    records_dir = path.parent / "asd_sense_dev_records"
    app.include_router(create_child_profiles_router(path))
    app.include_router(create_clinical_router(path, records_dir))
    app.include_router(create_account_router(path))
    app.include_router(create_clinic_router(path, records_dir, images_dir))
    app.include_router(create_family_router(path))
    attach_auth(app, path)
    return app


# Fail at startup if the environment does not explicitly name a safe DB.
# Do not point this to the repository's existing database.
if os.environ.get("ASD_SENSE_DB_PATH"):
    app = create_app(os.environ["ASD_SENSE_DB_PATH"])
else:
    @asynccontextmanager
    async def missing_config(_app: FastAPI):
        raise RuntimeError("ASD_SENSE_DB_PATH must point to a synthetic-data database")
        yield  # pragma: no cover

    app = FastAPI(lifespan=missing_config)
