# ASD-Sense API reference

The backend (`backend/main.py`) is a FastAPI app with two sets of routes:

- `/api/...` for the **guardian mobile app** (`asd_sense`): `auth_api.py`,
  `child_profiles_api.py`, `clinical_api.py`, `account_api.py`
- `/api/clinic/...` for the **clinician web portal** (`specialist_web`): `clinic_api.py`

Both use the same database, so what a family does in the app shows up in the portal.

- Base URL: `http://<host>:8000`
- Interactive docs: `http://localhost:8000/docs` (try any endpoint from the browser)
- JSON in and out, except file uploads (`multipart/form-data`)
- Database timestamps are UTC (`YYYY-MM-DD HH:MM:SS`). Appointment times are ISO 8601
  with the offset the app sent (`2026-11-20T10:00:00+04:00`). Dates are `YYYY-MM-DD`.

## Authentication

Sign in, then send the returned `access_token` on every request:

```
Authorization: Bearer <access_token>
```

Sessions last 8 hours. Passwords are 12 to 128 characters.

| Account | Created by | Signs in at | Can use |
|---|---|---|---|
| Guardian | Self sign-up in the app | `POST /api/auth/login` | `/api/...` and `/predict/...`, only for their own children |
| Clinician / admin | `python manage.py create-clinician` | `POST /api/clinic/auth/login` | `/api/clinic/...`, every child in the clinic |

Each account type is refused by the other set of routes (`401` or `403`).
Errors come back as `{"detail": "<message>"}`.

## Guardian app routes

### Account

| Method | Path | What it does |
|---|---|---|
| `POST` | `/api/auth/register` | `{full_name, email, password, phone?}` → `{access_token, token_type, expires_in, user}` |
| `POST` | `/api/auth/login` | `{email, password}` → same as register |
| `GET` | `/api/auth/me` | The signed-in guardian |
| `POST` | `/api/auth/logout` | Ends this session |
| `PATCH` | `/api/account/profile` | `{full_name, phone?}` |
| `GET` / `PUT` | `/api/account/preferences` | `{push_notifications, email_notifications}` |
| `POST` | `/api/auth/forgot` | `{email}`: emails a 6-digit reset code (valid 15 minutes). Same answer whether or not the account exists. |
| `POST` | `/api/auth/reset` | `{email, code, new_password}`: sets the password and signs out every session. `400` for a wrong or expired code; 5 wrong guesses use the code up. |
| `GET` | `/api/notifications` | Updates from the clinic, newest first: `{notification_id, child_id, title, body, created_at, is_read}` |
| `POST` | `/api/notifications/read` | Marks them all as read |

### Children

| Method | Path | What it does |
|---|---|---|
| `GET` | `/api/children` | The guardian's children |
| `POST` | `/api/children` | `{first_name, date_of_birth, last_name?, sex?, relationship_to_user?, notes?}` |
| `GET` / `PATCH` | `/api/children/{child_id}` | Read or change one child |
| `DELETE` | `/api/children/{child_id}` | Only while the child has no screenings, appointments or records (else `409`) |

### Screenings, appointments, records

| Method | Path | What it does |
|---|---|---|
| `POST` | `/predict/gesture`, `/predict/facial` | Form fields `file` (image) and `child_id`. Scores the image and saves the result; a PNG, JPEG, GIF or WebP image is kept for the clinician's review (not the filename). |
| `GET` | `/api/children/{child_id}/screenings` | Screening history, with the clinician's review outcome (`review_action`, `reviewer_name`, `reviewed_at`) once reviewed. The clinical note is never included. |
| `GET` / `POST` | `/api/children/{child_id}/appointments` | List, or add `{scheduled_at, location, ...}` (a reminder the family sets) |
| `PATCH` / `DELETE` | `/api/children/{child_id}/appointments/{id}` | Reschedule, cancel (`{status: "cancelled"}`) or delete |
| `GET` / `POST` | `/api/children/{child_id}/medical-records` | List, or upload `file` + `record_type` (`document` / `imaging`). PDF, PNG, JPEG or DOCX, up to 10 MB. |
| `GET` | `/api/children/{child_id}/medical-records/{id}/download` | The file |
| `DELETE` | `/api/children/{child_id}/medical-records/{id}` | Deletes the record and its file |

Screening results:

```json
{"screening_id": 12, "filename": "face.jpg", "model_name": "Facial_MobileNetV2",
 "routing": "Edge / API screening", "predicted_class": "autistic",
 "autism_probability": 0.8731, "confidence": 0.8731}
```

`predicted_class` is `autistic`, `non_autistic` or `inconclusive` (confidence below 0.60).
If no model of that type is loaded, the backend returns a fixed test result and
`model_name` starts with `Simulated_`.

## Clinician portal routes

| Method | Path | What it does |
|---|---|---|
| `POST` | `/api/clinic/auth/login` | `{email, password}` → `{access_token, token_type, expires_in, user}`. Guardian accounts get `403`. |
| `POST` | `/api/clinic/auth/logout` | Ends this session |
| `GET` | `/api/clinic/state` | Everything the portal shows: `user`, `patients`, `screenings`, `reviews`, `appointments`, `records`, `activity`, `revision` |
| `GET` | `/api/clinic/sync/revision` | `{revision}`: goes up on every change by anyone. The portal polls it every 4 seconds and reloads `/state` when it changes. |
| `PATCH` | `/api/clinic/me` | Profile and preferences: `full_name`, `phone`, `job_title`, `specialty`, `clinic_name`, `licence_number`, `languages`, `bio`, `use_24_hour_time`, `auto_sign_out_minutes` |
| `POST` | `/api/clinic/me/password` | `{current_password, new_password}`. Signs out the account's other sessions. |
| `POST` | `/api/clinic/patients` | Add a child referred directly: `{first_name, last_name?, date_of_birth, sex?, guardian_name, guardian_phone?, guardian_email?, referral_source?}` |
| `POST` | `/api/clinic/predict/gesture`, `/api/clinic/predict/facial` | Same as `/predict/...`, for any patient |
| `PUT` | `/api/clinic/screenings/{id}/review` | `{finding, action, note}`. The family sees the outcome (`action`) and gets a notification; the note and finding stay in the clinic. |
| `DELETE` | `/api/clinic/screenings/{id}/review` | Reopen a review |
| `GET` | `/api/clinic/screenings/{id}/image` | The screened image (`404` when none is stored) |
| `PATCH` | `/api/clinic/appointments/{id}` | `{status}`: `scheduled`, `confirmed`, `completed`, `cancelled`, `no_show`. The family gets a notification and sees it in the app. |
| `POST` | `/api/clinic/records/{id}/link` | `{path}`: a single-use link, valid for one minute, for opening a family's file in a new tab |
| `GET` | `/api/clinic/files/{ticket}` | The file behind such a link (no header needed) |

`finding` is `agree`, `disagree` or `needs_more_info`. `action` is
`refer_diagnostic`, `rescreen`, `monitor` or `no_further_action`.

## Other

| Method | Path | What it does |
|---|---|---|
| `GET` | `/` | Backend status and which models loaded. No sign-in needed. |
| `GET` | `/records/screenings?child_id=` | Older form of the screening history (guardian) |
