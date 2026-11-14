"""Child profile CRUD endpoints for ASD-Sense.

The identity dependency intentionally fails closed. A separate, verified authentication
layer must set request.state.user_id. Tests can override require_user_id with a
synthetic user; a user-supplied child_id or user_id is never accepted as identity.
"""

import sqlite3
from contextlib import contextmanager
from datetime import date
from pathlib import Path
from typing import Generator, Literal

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from pydantic import BaseModel, ConfigDict, Field, field_validator


class ChildCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    first_name: str = Field(min_length=1, max_length=100)
    last_name: str | None = Field(default=None, max_length=100)
    date_of_birth: date
    sex: Literal["female", "male", "other", "prefer_not_to_say"] | None = None
    relationship_to_user: str | None = Field(default=None, max_length=100)
    notes: str | None = Field(default=None, max_length=5000)

    @field_validator("first_name", "last_name", "relationship_to_user", "notes")
    @classmethod
    def normalize_text(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        return value or None

    @field_validator("first_name")
    @classmethod
    def nonempty_name(cls, value: str | None) -> str:
        if not value:
            raise ValueError("first_name must contain non-whitespace characters")
        return value

    @field_validator("date_of_birth")
    @classmethod
    def reasonable_birthdate(cls, value: date | None) -> date | None:
        if value is not None and value > date.today():
            raise ValueError("date_of_birth cannot be in the future")
        return value


class ChildUpdate(ChildCreate):
    # A partial update may omit all fields; the route rejects empty payloads.
    first_name: str | None = Field(default=None, min_length=1, max_length=100)
    date_of_birth: date | None = None


class ChildResponse(BaseModel):
    child_id: int
    user_id: int
    first_name: str
    last_name: str | None
    date_of_birth: date
    sex: str | None
    relationship_to_user: str | None
    notes: str | None
    created_at: str
    updated_at: str


def require_user_id(request: Request) -> int:
    """Identity must originate from verified auth middleware, not request input.

    Do not replace this with an unverified X-User-Id request header.
    """
    user_id = getattr(request.state, "user_id", None)
    if type(user_id) is not int or user_id <= 0:
        raise HTTPException(status_code=401, detail="Authentication required")
    return user_id


def create_child_profiles_router(db_path: str | Path) -> APIRouter:
    router = APIRouter(prefix="/api/children", tags=["child-profiles"])
    path = str(db_path)

    @contextmanager
    def database() -> Generator[sqlite3.Connection, None, None]:
        connection = sqlite3.connect(path, timeout=10)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        try:
            yield connection
            connection.commit()
        except BaseException:
            connection.rollback()
            raise
        finally:
            connection.close()

    def get_owned_child(connection: sqlite3.Connection, child_id: int, user_id: int) -> sqlite3.Row:
        row = connection.execute(
            "SELECT * FROM Child_Profiles WHERE child_id=? AND user_id=?",
            (child_id, user_id),
        ).fetchone()
        if row is None:
            # Do not disclose whether a different guardian owns the child.
            raise HTTPException(status_code=404, detail="Child profile not found")
        return row

    @router.post("", response_model=ChildResponse, status_code=status.HTTP_201_CREATED)
    def create_child(child: ChildCreate, user_id: int = Depends(require_user_id)):
        with database() as connection:
            user = connection.execute(
                "SELECT 1 FROM Users WHERE user_id=?", (user_id,)
            ).fetchone()
            if user is None:
                raise HTTPException(status_code=401, detail="Authenticated account unavailable")
            cursor = connection.execute(
                """INSERT INTO Child_Profiles
                (user_id, first_name, last_name, date_of_birth, sex,
                 relationship_to_user, notes)
                VALUES (?, ?, ?, ?, ?, ?, ?)""",
                (user_id, child.first_name, child.last_name,
                 child.date_of_birth.isoformat(), child.sex,
                 child.relationship_to_user, child.notes),
            )
            row = get_owned_child(connection, cursor.lastrowid, user_id)
            return dict(row)

    @router.get("", response_model=list[ChildResponse])
    def list_children(user_id: int = Depends(require_user_id)):
        with database() as connection:
            rows = connection.execute(
                """SELECT * FROM Child_Profiles WHERE user_id=?
                ORDER BY child_id ASC""", (user_id,)
            ).fetchall()
            return [dict(row) for row in rows]

    @router.get("/{child_id}", response_model=ChildResponse)
    def read_child(child_id: int, user_id: int = Depends(require_user_id)):
        with database() as connection:
            return dict(get_owned_child(connection, child_id, user_id))

    @router.patch("/{child_id}", response_model=ChildResponse)
    def update_child(child_id: int, changes: ChildUpdate,
                     user_id: int = Depends(require_user_id)):
        fields = changes.model_dump(exclude_unset=True)
        if not fields:
            raise HTTPException(status_code=400, detail="No fields supplied")
        if fields.get("first_name", "placeholder") is None or fields.get("date_of_birth", "placeholder") is None:
            raise HTTPException(status_code=422, detail="Required fields cannot be null")
        if "date_of_birth" in fields:
            fields["date_of_birth"] = fields["date_of_birth"].isoformat()
        with database() as connection:
            get_owned_child(connection, child_id, user_id)
            assignments = ", ".join(f"{field}=?" for field in fields)
            connection.execute(
                f"UPDATE Child_Profiles SET {assignments}, updated_at=CURRENT_TIMESTAMP WHERE child_id=? AND user_id=?",
                [*fields.values(), child_id, user_id],
            )
            return dict(get_owned_child(connection, child_id, user_id))

    @router.delete("/{child_id}", status_code=status.HTTP_204_NO_CONTENT)
    def delete_child(child_id: int, user_id: int = Depends(require_user_id)):
        with database() as connection:
            get_owned_child(connection, child_id, user_id)
            screening_count = connection.execute(
                "SELECT COUNT(*) FROM Screening_Records WHERE child_id=?", (child_id,)
            ).fetchone()[0]
            appointment_count = connection.execute(
                "SELECT COUNT(*) FROM Appointments WHERE child_id=?", (child_id,)
            ).fetchone()[0]
            if screening_count or appointment_count:
                raise HTTPException(
                    status_code=409,
                    detail="Cannot delete a child profile with screening or appointment history",
                )
            connection.execute(
                "DELETE FROM Child_Profiles WHERE child_id=? AND user_id=?",
                (child_id, user_id),
            )
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    return router
