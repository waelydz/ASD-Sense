"""Keeps the image behind each screening, so a clinician reviewing the result
can see what the model saw.

Stored like the medical records in clinical_api.py: outside the Git checkout
(ASD_SENSE_SCREENINGS_DIR), under random names, and linked to the screening in
Screening_Images. The original filename is not kept. Only clinicians can read
them back (GET /api/clinic/screenings/{id}/image).
"""
from __future__ import annotations

import os
import secrets
import sqlite3
from pathlib import Path

from clinical_api import database

# Recognised from the file's first bytes, never from its name.
_SIGNATURES = (
    (b"\x89PNG\r\n\x1a\n", "image/png"),
    (b"\xff\xd8\xff", "image/jpeg"),
    (b"GIF87a", "image/gif"),
    (b"GIF89a", "image/gif"),
)


def content_type(data: bytes) -> str | None:
    for signature, kind in _SIGNATURES:
        if data.startswith(signature):
            return kind
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    return None


def save(db_path: str | Path, images_dir: str | Path, screening_id: int, data: bytes) -> bool:
    """Stores the image for a screening that was just saved. Returns False
    (and keeps nothing) when the bytes are not a recognised image format."""
    kind = content_type(data)
    if kind is None:
        return False
    root = Path(images_dir).expanduser().resolve()
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    key = secrets.token_hex(24)
    path = root / key
    with path.open("xb") as target:
        target.write(data)
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass
    try:
        with database(db_path) as conn:
            conn.execute("INSERT INTO Screening_Images (screening_id, storage_key, content_type) VALUES (?, ?, ?)",
                         (screening_id, key, kind))
    except BaseException:
        path.unlink(missing_ok=True)
        raise
    return True


def find(conn: sqlite3.Connection, images_dir: str | Path, screening_id: int) -> tuple[Path, str] | None:
    """(file, content type) for a screening, or None when there is no image."""
    row = conn.execute("SELECT storage_key, content_type FROM Screening_Images WHERE screening_id = ?",
                       (screening_id,)).fetchone()
    if row is None:
        return None
    path = Path(images_dir).expanduser().resolve() / row["storage_key"]
    return (path, row["content_type"]) if path.is_file() else None
