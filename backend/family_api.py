"""What the clinic sends back to families, and password reset by email.

- Notifications: when a clinician reviews a screening or changes an
  appointment's status, the child's guardian gets an update in the app
  (GET /api/notifications) and, if they turned on email notifications in the
  app (User_Preferences.email_notifications), by email.
- Password reset: POST /api/auth/forgot emails a 6-digit code;
  POST /api/auth/reset sets a new password with it and ends every session.

Guardian identity comes from the session middleware in auth_api.py, like every
other /api route. Emails go through mailer.py (printed in the backend's
terminal when no mail server is configured).
"""
from __future__ import annotations

import hashlib
import hmac
import secrets
import sqlite3
import time
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, SecretStr

import mailer
from auth_api import _password_hash
from child_profiles_api import require_user_id
from clinical_api import database

GUARDIAN_ROLES = ("parent", "guardian")
RESET_CODE_SECONDS = 15 * 60
RESET_MAX_ATTEMPTS = 5

# What a family is told about each review outcome. The clinician's note and
# finding are never sent: they are for the clinic only.
NEXT_STEPS = {
    "refer_diagnostic": "A full developmental assessment is recommended. The clinic will contact you to arrange it.",
    "rescreen": "The clinician would like a new image. Please submit another screening.",
    "monitor": "No action is needed now. The clinician will look again at the next visit.",
    "no_further_action": "No further action is needed.",
}

STATUS_OUTCOMES = {
    "scheduled": "is waiting for the clinic to confirm",
    "confirmed": "was confirmed by the clinic",
    "completed": "was marked as completed",
    "cancelled": "was cancelled by the clinic",
    "no_show": "was marked as missed",
}


# ---- notifications -------------------------------------------------------------


def notify(conn: sqlite3.Connection, child_id: int, title: str, body: str) -> None:
    """Sends an update to the guardian of a child. Children a clinician added
    in the portal have no guardian account, so nothing is sent for them."""
    owner = conn.execute(
        """SELECT u.user_id, u.full_name, u.email, COALESCE(p.email_notifications, 0) AS by_email
        FROM Child_Profiles c
        JOIN Users u ON u.user_id = c.user_id
        LEFT JOIN User_Preferences p ON p.user_id = u.user_id
        WHERE c.child_id = ? AND u.role IN ('parent', 'guardian')""",
        (child_id,),
    ).fetchone()
    if owner is None:
        return
    conn.execute("INSERT INTO Notifications (user_id, child_id, title, body) VALUES (?, ?, ?, ?)",
                 (owner["user_id"], child_id, title, body))
    if owner["by_email"]:
        mailer.send(owner["email"], f"ASD-Sense: {title}",
                    f"Hello {owner['full_name']},\n\n{body}\n\n"
                    "Open the ASD-Sense app for details. You can turn these emails off in the app "
                    "under Profile > Notifications.")


def review_notice(child_name: str, action: str) -> tuple[str, str]:
    return "Screening reviewed", f"A clinician reviewed {child_name}'s screening. {NEXT_STEPS[action]}"


def appointment_notice(child_name: str, location: str, scheduled_at: str, status: str) -> tuple[str, str]:
    label = status.replace("_", " ")
    when = scheduled_at.replace("T", " ")[:16]
    return (f"Appointment {label}",
            f"{child_name}'s appointment at {location or 'the clinic'} on {when} {STATUS_OUTCOMES[status]}.")


# ---- request bodies -----------------------------------------------------------


class ForgotBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: str = Field(min_length=3, max_length=254)


class ResetBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: str = Field(min_length=3, max_length=254)
    code: str = Field(min_length=6, max_length=6, pattern=r"^\d{6}$")
    # Same rule as registration (auth_api.Credentials).
    new_password: SecretStr = Field(min_length=12, max_length=128)


def _code_hash(user_id: int, code: str) -> str:
    return hashlib.sha256(f"{user_id}:{code}".encode("ascii")).hexdigest()


# ---- routes -------------------------------------------------------------------


def create_family_router(db_path: str | Path) -> APIRouter:
    router = APIRouter(prefix="/api", tags=["family-updates"])

    @router.get("/notifications")
    def notifications(user_id: int = Depends(require_user_id)):
        """The guardian's updates, newest first (at most 50)."""
        with database(db_path) as conn:
            rows = conn.execute(
                """SELECT notification_id, child_id, title, body, created_at, read_at IS NOT NULL AS is_read
                FROM Notifications WHERE user_id = ? ORDER BY notification_id DESC LIMIT 50""",
                (user_id,),
            ).fetchall()
            return [dict(r) | {"is_read": bool(r["is_read"])} for r in rows]

    @router.post("/notifications/read", status_code=204)
    def mark_read(user_id: int = Depends(require_user_id)):
        with database(db_path) as conn:
            conn.execute("UPDATE Notifications SET read_at = CURRENT_TIMESTAMP WHERE user_id = ? AND read_at IS NULL",
                         (user_id,))

    @router.post("/auth/forgot")
    def forgot_password(body: ForgotBody):
        """Emails a 6-digit code to a guardian account. Answers the same whether
        or not the email has an account, so it cannot reveal who is registered."""
        email = body.email.strip().casefold()
        with database(db_path) as conn:
            user = conn.execute("SELECT * FROM Users WHERE email = ? AND role IN ('parent', 'guardian')",
                                (email,)).fetchone()
            if user is not None:
                code = f"{secrets.randbelow(1_000_000):06d}"
                conn.execute(
                    """INSERT OR REPLACE INTO Password_Resets (user_id, code_hash, expires_at, attempts)
                    VALUES (?, ?, ?, 0)""",
                    (user["user_id"], _code_hash(user["user_id"], code), int(time.time()) + RESET_CODE_SECONDS))
                mailer.send(
                    user["email"], "ASD-Sense: your password reset code",
                    f"Hello {user['full_name']},\n\nYour ASD-Sense password reset code is {code}\n\n"
                    f"It works for {RESET_CODE_SECONDS // 60} minutes. If you did not ask for it, ignore this "
                    "email; your password has not changed.")
        return {"ok": True}

    @router.post("/auth/reset")
    def reset_password(body: ResetBody):
        invalid = HTTPException(400, detail="That code is not valid or has expired. Request a new one.")
        email = body.email.strip().casefold()
        with database(db_path) as conn:
            row = conn.execute(
                """SELECT r.* FROM Password_Resets r JOIN Users u ON u.user_id = r.user_id
                WHERE u.email = ? AND u.role IN ('parent', 'guardian')""", (email,)).fetchone()
            if row is None:
                raise invalid
            if row["expires_at"] <= time.time() or row["attempts"] >= RESET_MAX_ATTEMPTS:
                conn.execute("DELETE FROM Password_Resets WHERE user_id = ?", (row["user_id"],))
                conn.commit()
                raise invalid
            if not hmac.compare_digest(_code_hash(row["user_id"], body.code), row["code_hash"]):
                conn.execute("UPDATE Password_Resets SET attempts = attempts + 1 WHERE user_id = ?",
                             (row["user_id"],))
                conn.commit()  # count the wrong guess even though this request fails
                raise invalid
            conn.execute("UPDATE Users SET password_hash = ?, updated_at = CURRENT_TIMESTAMP WHERE user_id = ?",
                         (_password_hash(body.new_password.get_secret_value()), row["user_id"]))
            conn.execute("DELETE FROM Password_Resets WHERE user_id = ?", (row["user_id"],))
            # Signed out everywhere: whoever had the old password loses access.
            conn.execute("UPDATE Auth_Sessions SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL",
                         (int(time.time()), row["user_id"]))
        return {"ok": True}

    return router
