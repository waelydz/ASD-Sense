"""Guardian profile and notification-preference persistence (session authorized)."""
from pathlib import Path
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, field_validator
from child_profiles_api import require_user_id
from clinical_api import database


class ProfilePatch(BaseModel):
    model_config = ConfigDict(extra='forbid')
    full_name: str = Field(min_length=1, max_length=150)
    phone: str | None = Field(default=None, max_length=40)

    @field_validator('full_name')
    @classmethod
    def strip_name(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError('Name is required')
        return value


class Preferences(BaseModel):
    model_config = ConfigDict(extra='forbid')
    push_notifications: bool = True
    email_notifications: bool = False


def create_account_router(path: str | Path) -> APIRouter:
    router = APIRouter(prefix='/api/account', tags=['guardian-account'])

    @router.patch('/profile')
    def update_profile(body: ProfilePatch, user_id: int = Depends(require_user_id)):
        with database(path) as conn:
            conn.execute('''UPDATE Users SET full_name=?, phone=?, updated_at=CURRENT_TIMESTAMP
                WHERE user_id=? AND role IN ('parent','guardian')''',
                (body.full_name, body.phone, user_id))
            user = conn.execute('''SELECT user_id, full_name, email, phone, role
                FROM Users WHERE user_id=?''', (user_id,)).fetchone()
            if user is None:
                raise HTTPException(401, detail='Account unavailable')
            return dict(user)

    @router.get('/preferences', response_model=Preferences)
    def preferences(user_id: int = Depends(require_user_id)):
        with database(path) as conn:
            row = conn.execute('''SELECT push_notifications, email_notifications
                FROM User_Preferences WHERE user_id=?''', (user_id,)).fetchone()
            if row is None:
                return Preferences()
            return Preferences(push_notifications=bool(row[0]),
                               email_notifications=bool(row[1]))

    @router.put('/preferences', response_model=Preferences)
    def set_preferences(body: Preferences, user_id: int = Depends(require_user_id)):
        with database(path) as conn:
            conn.execute('''INSERT INTO User_Preferences
                (user_id, push_notifications, email_notifications)
                VALUES (?, ?, ?) ON CONFLICT(user_id) DO UPDATE SET
                push_notifications=excluded.push_notifications,
                email_notifications=excluded.email_notifications,
                updated_at=CURRENT_TIMESTAMP''',
                (user_id, int(body.push_notifications), int(body.email_notifications)))
        return body

    return router
