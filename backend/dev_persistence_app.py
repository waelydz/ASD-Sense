"""Synthetic-data-only ASGI app for testing auth and child-profile persistence.

Run with ASD_SENSE_DB_PATH set to a NEW development database path. Deliberately
omits TensorFlow and inference; run main:app for model regression tests.
"""

from __future__ import annotations

import os
import sqlite3
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI

from auth_api import attach_auth
from child_profiles_api import create_child_profiles_router

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

    @app.get("/")
    def health():
        return {"status": "development-persistence-only"}

    app.include_router(create_child_profiles_router(path))
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
