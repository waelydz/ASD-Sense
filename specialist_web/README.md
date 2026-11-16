# ASD-Sense clinician portal (web)

A separate web front end for clinicians, in its own Flutter project. It talks
to the `/api/clinic/...` routes of the backend (`backend/clinic_api.py`), which
share one database with the guardian app's `/api/...` routes.

`lib/theme/app_theme.dart` is a copy of the guardian app's
(`../asd_sense/lib/theme/app_theme.dart`), so both look the same.
**If you change one, copy the change to the other.**

```
lib/main.dart                    entry point
lib/theme/app_theme.dart         copied from asd_sense
lib/data/http_api.dart           HTTP helper, ApiException, saved session
lib/clinician/
  models.dart                    Patient, Screening, ClinicalReview, ClinicAppointment
  api_client.dart                calls the backend's /api/clinic/... routes
  clinic_data.dart               copy of GET /api/clinic/state, kept in sync
  nav.dart                       which page is showing
  shell.dart                     sidebar layout (drawer on narrow screens)
  widgets.dart                   panels, tags, tables, probability chart
  review_dialog.dart             confirm/override a model result
  pages/                         sign-in, overview, review queue, patients,
                                 patient record, schedule, run a screening, models & system
```

## Run it

```
cd specialist_web
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

Build static files (output in `build/web`):

```
flutter build web --dart-define=API_BASE_URL=http://localhost:8000
```

## Tests

`test/backend_sync_test.dart` checks that the guardian app and the portal stay
in sync through a running backend. It is skipped unless `RUN_BACKEND_TESTS` is
set; the comment at the top of the file explains how to run it. Because it
drives both apps, `pubspec.yaml` lists `../asd_sense` as a dev dependency (it is
not part of the portal build).

## How it differs from the guardian app

| Guardian app | Clinician portal |
|---|---|
| Manages their own children | Caseload of many patients, search, filter by status, sort by concern |
| Soft-worded result ("some signs may be worth looking into") | Full model output: raw class, probability, confidence, model, routing, escalation |
| No review step | Screenings page, flagged results first; record finding, next step and clinical note |
| Adds appointments (date, time, place) | Sees them in a weekly schedule and updates their status (confirmed, completed, cancelled, no-show). Clinicians cannot add or move appointments |
| Self sign-up | Sign in with a clinic-issued account only |
| - | Probability trend per patient, copyable summary for referral letters |
| - | Model status page and an explanation of the thresholds |

Navigation is a sidebar menu (no tab bar), and the portal uses no icon set.
Status is shown with text and coloured tags.

**Settings** (like the guardian app's Profile screen): professional profile
(name, title, specialty, clinic, licence number, work phone, languages, short
bio) with a live preview, password change with strength rules, and the
12-hour / 24-hour clock option (12-hour by default). Your name and title appear
on reviews; the copied patient summary includes your specialty, clinic, licence
and phone.

**Security**: this session, automatic sign-out after inactivity (5, 15, 30, 60
minutes or never; 15 by default), recent activity, what a clinician can and
cannot do, and five good-practice points.

The portal uses DM Sans everywhere, the same font as the mobile app. Even the
dropdown arrows are drawn, not taken from an icon font.

## How it uses the backend

Everything the portal shows comes from the backend; nothing is hard-coded or
kept only in the browser. See `docs/SETUP.md` for how to start the backend and
create a clinician account, and `docs/API.md` for every route.

- **Sign-in** is `POST /api/clinic/auth/login`. Only `clinician` and `admin`
  accounts are accepted. They are issued with `python manage.py create-clinician`;
  there is no self sign-up. Guardian accounts are refused, and clinician
  accounts cannot sign in to the guardian app.
- **Data** is one snapshot, `GET /api/clinic/state`: every child (added by
  families in the app, or here), all screenings, reviews, appointments, the
  families' uploaded records and your recent activity.
- **Live updates**: the portal asks `GET /api/clinic/sync/revision` every 4
  seconds and reloads the snapshot when the number changes. Database triggers
  raise the number on every change, so a child, screening, appointment or
  upload added in the guardian app appears without reloading the page.
- **Changes** are saved straight away: reviews
  (`PUT /api/clinic/screenings/{id}/review`), appointment status
  (`PATCH /api/clinic/appointments/{id}`), new patients
  (`POST /api/clinic/patients`), profile and preferences (`PATCH /api/clinic/me`),
  password (`POST /api/clinic/me/password`). The family's app shows a
  review's next step and an appointment's new status, with a notification
  (and an email if they turned that on). The clinical note is never included.
- **Screening images**: the review dialog shows the image the model scored
  (`GET /api/clinic/screenings/{id}/image`, clinicians only). Screenings whose
  upload was not a PNG, JPEG, GIF or WebP show "No image is stored".
- **Family's records**: files a guardian uploads in the app are listed on the
  patient record and open in a new tab through a single-use, one-minute link.
  Opening one is written to your activity log.
- **Session**: the sign-in token is kept in the browser, so a reload keeps you
  signed in. It ends on Sign out, after the inactivity limit set on the Security
  page (also counted while the tab was closed), or after 8 hours.

## Things to keep in mind while testing

- **One clinic.** Every clinician account sees every child and every
  appointment.
- **Patients added in the portal are not linked to a guardian account.** A
  family that later signs up in the app with the same email does not see that
  child.
- **Simulated results.** If no model of a type is loaded, the backend returns a
  fixed test value (0.885 gesture, 0.86 facial) and the model name starts with
  `Simulated_`. Check "Models & system" before trusting a result.
- **Demo data** comes from `python manage.py seed-demo`, not from the portal.
- **Backend offline.** Sign-in shows that the server could not be reached.
  While signed in, the last loaded data stays on screen; check "Models & system".
