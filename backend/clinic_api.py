"""Clinician portal endpoints (/api/clinic/...), for the specialist_web app.

Built on the guardian persistence layer instead of replacing it:
- accounts, scrypt password hashes and Auth_Sessions come from auth_api.py;
- children, screenings, appointments and medical records are the same rows the
  guardian app writes through child_profiles_api.py and clinical_api.py.

Only clinician/admin accounts can use these routes. Guardian sessions are
refused here, and clinician sessions are refused by the guardian routes
(auth_api.resolve_session_user_id only accepts parent/guardian roles).

Clinic-only data lives in its own tables (see asd_sense_database_schema.sql):
Clinician_Profiles, Clinic_Patients, Screening_Reviews and Clinic_Activity.
Screened images are in Screening_Images (screening_images.py). Saving a review
or changing an appointment's status notifies the family (family_api.py); the
clinical note never leaves the clinic.
Sync_State.revision is bumped by triggers on every table, so the portal can
poll GET /api/clinic/sync/revision and reload only when something changed.
"""
from __future__ import annotations

import hashlib
import secrets
import sqlite3
import threading
import time
from datetime import date
from pathlib import Path
from typing import Callable, Literal

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import FileResponse
from pydantic import BaseModel, ConfigDict, Field, SecretStr, field_validator

import screening_images
from auth_api import (Credentials, TokenResponse, _bearer_token, _new_session,
                      _password_hash, _password_matches)
from clinical_api import database
from family_api import appointment_notice, notify, review_notice

CLINIC_ROLES = ("clinician", "admin")
FILE_LINK_SECONDS = 60


# ---- request bodies ------------------------------------------------------------


class ProfilePatch(BaseModel):
    """Every field is optional; only the ones sent are changed."""
    model_config = ConfigDict(extra="forbid")
    full_name: str | None = Field(default=None, min_length=1, max_length=150)
    phone: str | None = Field(default=None, max_length=40)
    job_title: str | None = Field(default=None, max_length=80)
    specialty: str | None = Field(default=None, max_length=80)
    clinic_name: str | None = Field(default=None, max_length=160)
    licence_number: str | None = Field(default=None, max_length=60)
    languages: str | None = Field(default=None, max_length=120)
    bio: str | None = Field(default=None, max_length=600)
    use_24_hour_time: bool | None = None
    auto_sign_out_minutes: int | None = Field(default=None, ge=0, le=240)


class PasswordChange(BaseModel):
    model_config = ConfigDict(extra="forbid")
    current_password: SecretStr = Field(max_length=128)
    # Same rule as guardian registration in auth_api.Credentials.
    new_password: SecretStr = Field(min_length=12, max_length=128)


class PatientCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    first_name: str = Field(min_length=1, max_length=100)
    last_name: str = Field(default="", max_length=100)
    date_of_birth: date
    sex: Literal["female", "male", "other"] | None = None
    guardian_name: str = Field(min_length=1, max_length=150)
    guardian_phone: str = Field(default="", max_length=40)
    guardian_email: str = Field(default="", max_length=254)
    referral_source: str = Field(default="", max_length=80)

    @field_validator("first_name", "guardian_name")
    @classmethod
    def nonblank(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("This field is required")
        return value

    @field_validator("date_of_birth")
    @classmethod
    def not_in_future(cls, value: date) -> date:
        if value > date.today():
            raise ValueError("date_of_birth cannot be in the future")
        return value


class ReviewBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    finding: Literal["agree", "disagree", "needs_more_info"]
    action: Literal["refer_diagnostic", "rescreen", "monitor", "no_further_action"]
    note: str = Field(default="", max_length=4000)


class AppointmentStatus(BaseModel):
    model_config = ConfigDict(extra="forbid")
    status: Literal["scheduled", "confirmed", "completed", "cancelled", "no_show"]


# ---- helpers -------------------------------------------------------------------


def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("ascii")).hexdigest()


def clinician_dependency(db_path: str | Path) -> Callable[[Request], sqlite3.Row]:
    """A FastAPI dependency returning the signed-in clinician's Users row."""

    def require_clinician(request: Request) -> sqlite3.Row:
        token = _bearer_token(request.headers.get("Authorization"))
        if token is None:
            raise HTTPException(401, detail="Sign in to continue.")
        with database(db_path) as conn:
            row = conn.execute(
                """SELECT u.* FROM Auth_Sessions AS s JOIN Users AS u ON u.user_id = s.user_id
                WHERE s.token_hash = ? AND s.revoked_at IS NULL AND s.expires_at > ?""",
                (_token_hash(token), int(time.time())),
            ).fetchone()
        if row is None:
            raise HTTPException(401, detail="Your session has expired. Please sign in again.")
        if row["role"] not in CLINIC_ROLES:
            raise HTTPException(403, detail="This action is only available to clinicians.")
        return row

    return require_clinician


def log_activity(conn: sqlite3.Connection, user_id: int, text: str) -> None:
    conn.execute("INSERT INTO Clinic_Activity (user_id, text) VALUES (?, ?)", (user_id, text))


def child_name(child: sqlite3.Row) -> str:
    return f"{child['first_name']} {child['last_name'] or ''}".strip()


def child_or_404(conn: sqlite3.Connection, child_id: int) -> sqlite3.Row:
    """Clinicians can open any child in the clinic."""
    child = conn.execute("SELECT * FROM Child_Profiles WHERE child_id = ?", (child_id,)).fetchone()
    if child is None:
        raise HTTPException(404, detail="Patient not found.")
    return child


def _profile(conn: sqlite3.Connection, user_id: int) -> sqlite3.Row:
    conn.execute("INSERT OR IGNORE INTO Clinician_Profiles (user_id) VALUES (?)", (user_id,))
    return conn.execute("SELECT * FROM Clinician_Profiles WHERE user_id = ?", (user_id,)).fetchone()


def _user_json(conn: sqlite3.Connection, user: sqlite3.Row) -> dict:
    p = _profile(conn, user["user_id"])
    return {
        "user_id": user["user_id"],
        "full_name": user["full_name"],
        "email": user["email"],
        "phone": user["phone"] or "",
        "role": user["role"],
        "created_at": user["created_at"],
        "password_changed_at": p["password_changed_at"],
        "job_title": p["job_title"],
        "specialty": p["specialty"],
        "clinic_name": p["clinic_name"],
        "licence_number": p["licence_number"],
        "languages": p["languages"],
        "bio": p["bio"],
        "use_24_hour_time": bool(p["use_24_hour_time"]),
        "auto_sign_out_minutes": p["auto_sign_out_minutes"],
    }


def _signature(conn: sqlite3.Connection, user: sqlite3.Row) -> str:
    """Name with job title, as it appears on reviews."""
    title = _profile(conn, user["user_id"])["job_title"]
    return f"{user['full_name']}, {title}" if title else user["full_name"]


def revision(conn: sqlite3.Connection) -> int:
    row = conn.execute("SELECT revision FROM Sync_State WHERE id = 1").fetchone()
    return int(row[0]) if row else 0


def save_clinic_screening(db_path: str | Path, clinician: sqlite3.Row, *, child_id: int, modality: str,
                          model_used: str, predicted_class: str, prob_autistic: float,
                          confidence: float, routing_tier: str) -> int:
    """Stores a screening a clinician ran in the portal. The caller then keeps
    the image with screening_images.save, as for guardian screenings."""
    with database(db_path) as conn:
        child = child_or_404(conn, child_id)
        cur = conn.execute(
            """INSERT INTO Screening_Records
            (child_id, performed_by_user_id, model_name, model_version,
             predicted_class, autism_probability, confidence, notes)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (child_id, clinician["user_id"], model_used, "1.0", predicted_class,
             round(prob_autistic, 4), round(confidence, 4), routing_tier),
        )
        log_activity(conn, clinician["user_id"], f"Ran a {modality} screening for {child_name(child)}")
        return int(cur.lastrowid)


class _FileLinks:
    """Short-lived links for opening a record in a new browser tab, which
    cannot send the Authorization header."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._links: dict[str, tuple[float, int]] = {}

    def issue(self, record_id: int) -> str:
        ticket = secrets.token_urlsafe(24)
        with self._lock:
            now = time.time()
            self._links = {k: v for k, v in self._links.items() if v[0] > now}
            self._links[ticket] = (now + FILE_LINK_SECONDS, record_id)
        return ticket

    def redeem(self, ticket: str) -> int | None:
        with self._lock:
            entry = self._links.pop(ticket, None)
        return entry[1] if entry and entry[0] > time.time() else None


# ---- routes --------------------------------------------------------------------


def create_clinic_router(db_path: str | Path, records_dir: str | Path, images_dir: str | Path) -> APIRouter:
    router = APIRouter(prefix="/api/clinic", tags=["clinician-portal"])
    records_root = Path(records_dir).expanduser().resolve()
    require_clinician = clinician_dependency(db_path)
    links = _FileLinks()

    @router.post("/auth/login", response_model=TokenResponse)
    def login(credentials: Credentials):
        with database(db_path) as conn:
            user = conn.execute("SELECT * FROM Users WHERE email = ?", (credentials.email,)).fetchone()
            if user is None or not _password_matches(credentials.password.get_secret_value(),
                                                     user["password_hash"]):
                raise HTTPException(401, detail="Incorrect email or password.")
            if user["role"] not in CLINIC_ROLES:
                raise HTTPException(403, detail="This is not a clinician account. "
                                                "Use the ASD-Sense mobile app instead.")
            log_activity(conn, user["user_id"], "Signed in")
            public = conn.execute("SELECT user_id, full_name, email, phone, role FROM Users WHERE user_id = ?",
                                  (user["user_id"],)).fetchone()
            return _new_session(conn, int(user["user_id"]), public)

    @router.post("/auth/logout", status_code=status.HTTP_204_NO_CONTENT)
    def logout(request: Request, user: sqlite3.Row = Depends(require_clinician)):
        token = _bearer_token(request.headers.get("Authorization"))
        with database(db_path) as conn:
            conn.execute("UPDATE Auth_Sessions SET revoked_at = ? WHERE token_hash = ? AND revoked_at IS NULL",
                         (int(time.time()), _token_hash(token)))

    @router.get("/sync/revision")
    def sync_revision(_: sqlite3.Row = Depends(require_clinician)):
        with database(db_path) as conn:
            return {"revision": revision(conn)}

    @router.get("/state")
    def state(user: sqlite3.Row = Depends(require_clinician)):
        """Everything the portal shows, in one snapshot."""
        with database(db_path) as conn:
            patients = conn.execute(
                """SELECT c.child_id, c.first_name, COALESCE(c.last_name, '') AS last_name,
                          c.date_of_birth, c.sex,
                          CASE WHEN p.child_id IS NULL THEN u.full_name ELSE p.guardian_name END AS guardian_name,
                          CASE WHEN p.child_id IS NULL THEN COALESCE(u.phone, '') ELSE p.guardian_phone END AS guardian_phone,
                          CASE WHEN p.child_id IS NULL THEN u.email ELSE p.guardian_email END AS guardian_email,
                          CASE WHEN p.child_id IS NULL THEN 'ASD-Sense guardian app'
                               ELSE p.referral_source END AS referral_source
                   FROM Child_Profiles c
                   JOIN Users u ON u.user_id = c.user_id
                   LEFT JOIN Clinic_Patients p ON p.child_id = c.child_id
                   ORDER BY c.child_id"""
            ).fetchall()
            screenings = conn.execute(
                """SELECT s.screening_id, s.child_id, s.screening_date, s.model_name, s.model_version,
                          s.predicted_class, s.autism_probability, s.confidence, s.image_reference, s.notes,
                          i.screening_id IS NOT NULL AS has_image
                   FROM Screening_Records s LEFT JOIN Screening_Images i ON i.screening_id = s.screening_id
                   ORDER BY s.screening_id"""
            ).fetchall()
            reviews = conn.execute(
                "SELECT screening_id, finding, action, note, reviewer_name, reviewed_at FROM Screening_Reviews"
            ).fetchall()
            records = conn.execute(
                """SELECT record_id, child_id, file_name, record_type, created_at, 1 AS has_file
                   FROM Medical_Records ORDER BY record_id DESC"""
            ).fetchall()
            appointments = conn.execute(
                """SELECT appointment_id, child_id, scheduled_at, appointment_type, location, status, notes
                   FROM Appointments ORDER BY scheduled_at"""
            ).fetchall()
            activity = conn.execute(
                "SELECT at, text FROM Clinic_Activity WHERE user_id = ? ORDER BY activity_id DESC LIMIT 20",
                (user["user_id"],),
            ).fetchall()
            return {
                "revision": revision(conn),
                "user": _user_json(conn, user),
                "patients": [dict(r) for r in patients],
                "screenings": [dict(r) | {"has_image": bool(r["has_image"])} for r in screenings],
                "reviews": [dict(r) for r in reviews],
                "records": [dict(r) for r in records],
                "appointments": [dict(r) for r in appointments],
                "activity": [dict(r) for r in activity],
            }

    @router.patch("/me")
    def update_me(body: ProfilePatch, user: sqlite3.Row = Depends(require_clinician)):
        changes = body.model_dump(exclude_unset=True, exclude_none=True)
        account = {k: v.strip() for k, v in changes.items() if k in ("full_name", "phone")}
        if account.get("full_name") == "":
            raise HTTPException(422, detail="Your name is required.")
        profile = {k: (v.strip() if isinstance(v, str) else int(v))
                   for k, v in changes.items() if k not in ("full_name", "phone")}
        with database(db_path) as conn:
            if account:
                conn.execute(
                    f"UPDATE Users SET {', '.join(f'{k} = ?' for k in account)}, updated_at = CURRENT_TIMESTAMP "
                    "WHERE user_id = ?", (*account.values(), user["user_id"]))
            if profile:
                _profile(conn, user["user_id"])
                conn.execute(
                    f"UPDATE Clinician_Profiles SET {', '.join(f'{k} = ?' for k in profile)} WHERE user_id = ?",
                    (*profile.values(), user["user_id"]))
            if account or profile:
                preference_only = not account and set(profile) <= {"use_24_hour_time", "auto_sign_out_minutes"}
                log_activity(conn, user["user_id"],
                             "Changed a preference" if preference_only else "Updated professional profile")
            fresh = conn.execute("SELECT * FROM Users WHERE user_id = ?", (user["user_id"],)).fetchone()
            return _user_json(conn, fresh)

    @router.post("/me/password")
    def change_password(body: PasswordChange, request: Request,
                        user: sqlite3.Row = Depends(require_clinician)):
        current = body.current_password.get_secret_value()
        new = body.new_password.get_secret_value()
        if not _password_matches(current, user["password_hash"]):
            raise HTTPException(400, detail="Current password is incorrect.")
        if new == current:
            raise HTTPException(400, detail="The new password must be different from the current one.")
        this_session = _token_hash(_bearer_token(request.headers.get("Authorization")))
        with database(db_path) as conn:
            conn.execute("UPDATE Users SET password_hash = ?, updated_at = CURRENT_TIMESTAMP WHERE user_id = ?",
                         (_password_hash(new), user["user_id"]))
            _profile(conn, user["user_id"])
            conn.execute("UPDATE Clinician_Profiles SET password_changed_at = CURRENT_TIMESTAMP WHERE user_id = ?",
                         (user["user_id"],))
            # Sign out every other browser that still holds a session.
            conn.execute("""UPDATE Auth_Sessions SET revoked_at = ?
                WHERE user_id = ? AND token_hash != ? AND revoked_at IS NULL""",
                         (int(time.time()), user["user_id"], this_session))
            log_activity(conn, user["user_id"], "Changed password")
            fresh = conn.execute("SELECT * FROM Users WHERE user_id = ?", (user["user_id"],)).fetchone()
            return _user_json(conn, fresh)

    @router.post("/patients", status_code=status.HTTP_201_CREATED)
    def add_patient(body: PatientCreate, user: sqlite3.Row = Depends(require_clinician)):
        """A child referred to the clinic directly, not through the guardian app.
        The row is owned by the clinician (guardian routes never see it); the
        family's contact details are kept in Clinic_Patients."""
        with database(db_path) as conn:
            cur = conn.execute(
                """INSERT INTO Child_Profiles (user_id, first_name, last_name, date_of_birth, sex)
                VALUES (?, ?, ?, ?, ?)""",
                (user["user_id"], body.first_name, body.last_name.strip() or None,
                 body.date_of_birth.isoformat(), body.sex),
            )
            child_id = int(cur.lastrowid)
            conn.execute(
                """INSERT INTO Clinic_Patients (child_id, added_by_user_id, guardian_name, guardian_phone,
                                                guardian_email, referral_source)
                VALUES (?, ?, ?, ?, ?, ?)""",
                (child_id, user["user_id"], body.guardian_name, body.guardian_phone.strip(),
                 body.guardian_email.strip(), body.referral_source.strip() or "Added in the clinician portal"),
            )
            log_activity(conn, user["user_id"], f"Added patient {body.first_name} {body.last_name}".strip())
            return {"child_id": child_id}

    def screening_child(conn: sqlite3.Connection, screening_id: int) -> sqlite3.Row:
        child = conn.execute(
            """SELECT c.* FROM Screening_Records s JOIN Child_Profiles c ON c.child_id = s.child_id
            WHERE s.screening_id = ?""", (screening_id,)).fetchone()
        if child is None:
            raise HTTPException(404, detail="Screening not found.")
        return child

    @router.put("/screenings/{screening_id}/review")
    def save_review(screening_id: int, body: ReviewBody, user: sqlite3.Row = Depends(require_clinician)):
        with database(db_path) as conn:
            child = screening_child(conn, screening_id)
            before = conn.execute("SELECT action FROM Screening_Reviews WHERE screening_id = ?",
                                  (screening_id,)).fetchone()
            conn.execute(
                """INSERT INTO Screening_Reviews
                    (screening_id, finding, action, note, reviewer_user_id, reviewer_name, reviewed_at)
                VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                ON CONFLICT(screening_id) DO UPDATE SET
                    finding = excluded.finding, action = excluded.action, note = excluded.note,
                    reviewer_user_id = excluded.reviewer_user_id, reviewer_name = excluded.reviewer_name,
                    reviewed_at = excluded.reviewed_at""",
                (screening_id, body.finding, body.action, body.note.strip(), user["user_id"],
                 _signature(conn, user)),
            )
            log_activity(conn, user["user_id"], f"Reviewed a screening for {child_name(child)}")
            # The family hears about a new review, or a changed next step; not
            # about edits to the clinical note, which they never see.
            if before is None or before["action"] != body.action:
                notify(conn, child["child_id"], *review_notice(child["first_name"], body.action))
        return {"ok": True}

    @router.delete("/screenings/{screening_id}/review")
    def reopen_review(screening_id: int, user: sqlite3.Row = Depends(require_clinician)):
        with database(db_path) as conn:
            child = screening_child(conn, screening_id)
            conn.execute("DELETE FROM Screening_Reviews WHERE screening_id = ?", (screening_id,))
            log_activity(conn, user["user_id"], f"Reopened a screening review for {child_name(child)}")
        return {"ok": True}

    @router.patch("/appointments/{appointment_id}")
    def set_appointment_status(appointment_id: int, body: AppointmentStatus,
                               user: sqlite3.Row = Depends(require_clinician)):
        with database(db_path) as conn:
            appointment = conn.execute("SELECT * FROM Appointments WHERE appointment_id = ?",
                                       (appointment_id,)).fetchone()
            if appointment is None:
                raise HTTPException(404, detail="Appointment not found.")
            child = child_or_404(conn, appointment["child_id"])
            conn.execute("UPDATE Appointments SET status = ?, updated_at = CURRENT_TIMESTAMP "
                         "WHERE appointment_id = ?", (body.status, appointment_id))
            log_activity(conn, user["user_id"],
                         f"Marked {child_name(child)}'s appointment as {body.status.replace('_', ' ')}")
            if body.status != appointment["status"]:
                notify(conn, child["child_id"], *appointment_notice(
                    child["first_name"], appointment["location"], appointment["scheduled_at"], body.status))
        return {"ok": True}

    @router.get("/screenings/{screening_id}/image")
    def screening_image(screening_id: int, _: sqlite3.Row = Depends(require_clinician)):
        """The image the model scored, for the review dialog. Clinicians only."""
        with database(db_path) as conn:
            found = screening_images.find(conn, images_dir, screening_id)
        if found is None:
            raise HTTPException(404, detail="No image is stored for this screening.")
        path, kind = found
        return FileResponse(str(path), media_type=kind,
                            headers={"X-Content-Type-Options": "nosniff", "Cache-Control": "private, no-store"})

    @router.post("/records/{record_id}/link")
    def record_link(record_id: int, user: sqlite3.Row = Depends(require_clinician)):
        """A one-minute link for opening a family's uploaded file in a new tab."""
        with database(db_path) as conn:
            record = conn.execute("SELECT * FROM Medical_Records WHERE record_id = ?", (record_id,)).fetchone()
            if record is None:
                raise HTTPException(404, detail="Record not found.")
            child = child_or_404(conn, record["child_id"])
            if not (records_root / record["storage_key"]).is_file():
                raise HTTPException(404, detail="The file for this record is missing on the server.")
            log_activity(conn, user["user_id"], f"Opened a record of {child_name(child)}")
        return {"path": f"/api/clinic/files/{links.issue(record_id)}"}

    @router.get("/files/{ticket}")
    def open_file(ticket: str):
        """Serves a file for a ticket from /records/{id}/link. The ticket is the
        credential: it is random, single-use and expires after a minute."""
        record_id = links.redeem(ticket)
        if record_id is None:
            raise HTTPException(404, detail="This link has expired. Open the file again from the portal.")
        with database(db_path) as conn:
            record = conn.execute("SELECT * FROM Medical_Records WHERE record_id = ?", (record_id,)).fetchone()
        path = records_root / record["storage_key"] if record else None
        if path is None or not path.is_file():
            raise HTTPException(404, detail="File unavailable.")
        return FileResponse(str(path), media_type=record["content_type"], filename=record["file_name"],
                            content_disposition_type="inline",
                            headers={"X-Content-Type-Options": "nosniff", "Cache-Control": "no-store"})

    return router
