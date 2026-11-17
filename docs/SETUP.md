# ASD-Sense setup guide (step by step)

This guide takes you from a fresh Windows PC to the whole project running: the
backend, the guardian app on an Android phone, and the clinician portal in
Chrome. It assumes no prior experience. For the endpoints, see [API.md](API.md).

Copy each grey box into **PowerShell**, press **Enter**, and wait for it to
finish before the next one. In the end you will have **three PowerShell
windows** open, one for each part.

## Contents

1. [Install the tools (once)](#1-install-the-tools-once)
2. [Set up the backend (once)](#2-set-up-the-backend-once)
3. [Start the backend](#3-start-the-backend)
4. [Prepare your Android phone (once)](#4-prepare-your-android-phone-once)
5. [Install and run the app on the phone](#5-install-and-run-the-app-on-the-phone)
6. [Start the clinician portal](#6-start-the-clinician-portal)
7. [Check everything works together](#7-check-everything-works-together)
8. [Every day after that](#8-every-day-after-that)
9. [Configuration](#9-configuration)
10. [Managing data](#10-managing-data)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. Install the tools (once)

| Tool | Why | Get it |
|---|---|---|
| Python 3.11–3.13 | Runs the backend | python.org. In the installer tick **Add python.exe to PATH**. |
| Flutter SDK | Builds the app and the portal | docs.flutter.dev → Get started → Windows → Android |
| Android Studio | Android SDK and `adb`, to install on the phone | developer.android.com/studio. Open it once and let it download the SDK. |
| Google Chrome | Runs the clinician portal | google.com/chrome |

Check that everything is found:

```powershell
python --version
flutter doctor
```

In `flutter doctor`, **Flutter**, **Android toolchain** and **Chrome** must
show `[√]`. A `[!]` next to **Visual Studio** only matters for Windows desktop
apps, which this project does not use, so ignore it. If Android toolchain
complains about licences, run `flutter doctor --android-licenses` and answer
`y` to each.

## 2. Set up the backend (once)

Open PowerShell and go to the backend folder (change the path if your copy is
somewhere else):

```powershell
cd C:\Users\<you>\OneDrive\Desktop\Projects\ASD-Sense\backend
```

Create a private Python environment for the project, so its packages do not
mix with other projects:

```powershell
python -m venv .venv
```

Install the packages. This downloads TensorFlow and takes several minutes:

```powershell
.venv\Scripts\python -m pip install -r requirements.txt
```

**If you used an older version of ASD-Sense on this PC:** its
`backend\asd_sense.db` uses a different layout that this backend cannot read
(old accounts cannot sign in, and record uploads fail). Rename it first, for
example to `asd_sense_old.db`; a new database is created on the next start.

Create the demo accounts and sample data:

```powershell
.venv\Scripts\python manage.py seed-demo
```

It prints two logins. Write them down:

| Where | Email | Password |
|---|---|---|
| Phone app (guardian) | `guardian@asdsense.com` | `Guardian#2026demo` |
| Clinician portal | `clinician@asdsense.com` | `Clinic#2026demo` |

These are for testing only; they are written in `manage.py`.

> **Why `.venv\Scripts\python` and not `activate`?** Many guides say to run
> `.venv\Scripts\activate` first. PowerShell blocks that by default with
> "running scripts is disabled on this system". Calling the environment's
> Python directly does the same thing without the error.

## 3. Start the backend

**Terminal 1.** In the `backend` folder:

```powershell
.venv\Scripts\python -m uvicorn main:app --host 0.0.0.0 --port 8000
```

- It is ready when you see `Uvicorn running on http://0.0.0.0:8000`. Loading
  the models takes a little while before that.
- If **Windows Firewall** asks, tick **Private networks** and click **Allow**.
  It asks only once per Python install, so no popup usually means it is
  already allowed.
- **Keep this window open.** Closing it, or pressing **Ctrl + C**, stops the
  backend.

**Check it:** open <http://localhost:8000/> in Chrome. You should see
`"ASD-Sense Backend Online"`. The `*_loaded` values say which screening models
loaded; see [Troubleshooting](#11-troubleshooting) if one is `false`.

<http://localhost:8000/docs> lists every endpoint and lets you try them; see
[API.md](API.md).

## 4. Prepare your Android phone (once)

1. **Settings → About phone** → tap **Build number** 7 times until it says
   "You are now a developer". (Samsung: Settings → About phone → Software
   information.)
2. **Settings → System → Developer options** (or search "Developer options")
   → turn on **USB debugging**.
3. Plug the phone into the PC. If the phone asks what the USB connection is
   for, choose **File transfer**.
4. Tap **Allow** on **"Allow USB debugging?"** (tick *Always allow from this
   computer*).

## 5. Install and run the app on the phone

**Terminal 2.** Open a new PowerShell window (leave Terminal 1 running):

```powershell
cd C:\Users\<you>\OneDrive\Desktop\Projects\ASD-Sense\asd_sense
flutter devices
```

Your phone should be in the list. If not, replug the cable and look for the
prompt from step 4.4.

Download the app's packages (once):

```powershell
flutter pub get
```

Build, install and start the app:

```powershell
powershell -ExecutionPolicy Bypass -File .\run_app.ps1
```

- The first build takes 5–10 minutes (`Running Gradle task 'assembleDebug'`).
  Later builds are much faster.
- The app opens on the phone by itself and stays installed afterwards.
- While this window is open: `r` reloads the app after a code change, `q`
  stops it.

### How the app finds the backend

`run_app.ps1` does two things before `flutter run`:

1. Finds this PC's Wi-Fi address and builds it into the app
   (`WIFI_BACKEND_URL=http://<PC-IP>:8000`).
2. Sets up a USB tunnel (`adb reverse tcp:8000 tcp:8000`), so on the phone
   `http://127.0.0.1:8000` reaches the PC.

The app tries the Wi-Fi address first and falls back to the tunnel after 2
seconds.

### Using the VS Code Run button instead

Selecting the phone in VS Code and pressing Run works, but skips both steps
above. The app then has an old Wi-Fi address that is not yours, so it depends
on the USB tunnel, which you set up yourself:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" reverse tcp:8000 tcp:8000
```

Keep the cable plugged in, and run this again after unplugging or restarting
the phone.

### Installing without a cable (APK)

To install a copy that works over Wi-Fi without the PC building it each time:

```powershell
ipconfig
```

Note the **IPv4 Address** of your Wi-Fi adapter (for example `192.168.1.25`).
Then:

```powershell
flutter build apk --release --dart-define=WIFI_BACKEND_URL=http://192.168.1.25:8000
```

Copy `build\app\outputs\flutter-apk\app-release.apk` to the phone (cable,
email, Drive), open it, and allow **Install unknown apps** when asked.

- The phone must be on the same Wi-Fi as the PC, and the backend must be
  running.
- The address is built into the APK. If the PC's IP changes (different
  network, router restart), rebuild it.

### iPhone

iOS builds need a Mac with Xcode; they cannot be made on Windows.

## 6. Start the clinician portal

**Terminal 3.** Open a third PowerShell window:

```powershell
cd C:\Users\<you>\OneDrive\Desktop\Projects\ASD-Sense\specialist_web
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

Chrome opens after a minute or two. Sign in with the clinician demo account.

To issue a real clinician account (clinicians cannot sign up themselves), in
the `backend` folder:

```powershell
.venv\Scripts\python manage.py create-clinician --name "Dr. Name" --email name@hospital.ae
```

It asks for the password in the terminal.

## 7. Check everything works together

1. On the **phone**, sign in as the guardian (or create an account).
2. Add a child, run a screening on the Detection screen, and add an
   appointment.
3. Within about 5 seconds these appear in the **portal** (Patients, Review
   queue, Schedule).
4. In the portal, open the screening (you see the image the model scored),
   review it, and confirm the appointment. Within about 15 seconds the phone
   shows a banner, the bell on the home screen counts the update, and Records
   shows the clinician's next step. The clinical note is never sent.

Watch Terminal 1 while you do this: each action shows as a line ending in
`200 OK`.

Automated checks:

```powershell
# Backend tests (in backend/). They use temporary databases, never asd_sense.db.
.venv\Scripts\python -m pytest tests -q
```

```powershell
# Guardian app tests (in asd_sense/) and portal tests (in specialist_web/)
flutter test
```

The end-to-end test that drives both apps against a running backend is
described at the top of `specialist_web/test/backend_sync_test.dart`.

## 8. Every day after that

Only these are needed once setup is done:

| Terminal | Folder | Command |
|---|---|---|
| 1 | `backend` | `.venv\Scripts\python -m uvicorn main:app --host 0.0.0.0 --port 8000` |
| 2 | `asd_sense` | `powershell -ExecutionPolicy Bypass -File .\run_app.ps1` |
| 3 | `specialist_web` | `flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000` |

If the app is already installed on the phone and you have not changed the
code, you can skip Terminal 2 and just open the app (with the tunnel or Wi-Fi
working).

## 9. Configuration

Set these in the backend terminal **before** starting uvicorn, for example
`$env:ASD_SENSE_DB_PATH = "C:\data\asd_sense.db"`. They last until that window
is closed. `manage.py` reads `ASD_SENSE_DB_PATH` too.

| Variable | Default | What it does |
|---|---|---|
| `ASD_SENSE_DB_PATH` | `backend/asd_sense.db` | Database file |
| `ASD_SENSE_RECORDS_DIR` | `.asd_sense_private_records` in your user folder | Uploaded medical records. Kept outside the project so they never end up in git. |
| `ASD_SENSE_SCREENINGS_DIR` | `.asd_sense_private_screenings` in your user folder | Screened images, for the clinician's review. Also outside the project. |
| `ASD_SENSE_SMTP_HOST` | not set | Mail server for reset codes and notification emails. Not set: emails are printed in the backend terminal instead. |
| `ASD_SENSE_SMTP_PORT` | `587` | Mail server port (STARTTLS) |
| `ASD_SENSE_SMTP_USER` | | Mail login, e.g. a Gmail address |
| `ASD_SENSE_SMTP_PASSWORD` | | Mail password (for Gmail, an app password) |
| `ASD_SENSE_SMTP_FROM` | the SMTP user | Sender address |
| `CLERK_SECRET_KEY` | not set | Turns on **Continue with Google** in the phone app (see below). Secret: never commit it or put it in the app. |
| `CLERK_PUBLISHABLE_KEY` | the project's Clerk app | Only to use a different Clerk app. Lets the backend check that sign-in tokens come from that app. |

App settings are passed to `flutter run` / `flutter build` with
`--dart-define`:

| Setting | Used by | What it does |
|---|---|---|
| `WIFI_BACKEND_URL` | Phone app | The PC's address over Wi-Fi (set by `run_app.ps1`) |
| `API_BASE_URL` | Portal, tests | The backend's address |
| `CLERK_PUBLISHABLE_KEY` | Phone app | Only to use a different Clerk app; defaults to the project's. `run_app.ps1` passes it on when `$env:CLERK_PUBLISHABLE_KEY` is set. |

### Google sign-in (phone app only, via Clerk)

The guardian app has **Continue with Google** on the login and create-account
screens. The clinician portal does not: clinicians sign in with their hospital
accounts only, and a clinician's email is refused on the Google route.

The project uses one shared Clerk app ("ASD-Sense"). Its publishable key is
public and already built into the app and the backend, so the phone app needs
no setup. **Only the backend needs the secret key**, once per PC:

1. Get access to the Clerk app: ask the project owner to invite you from the
   Clerk Dashboard (**Invite**, top right). Accept the email invitation.
2. In the Clerk Dashboard open **ASD-Sense → Configure → API keys**. Under
   **Secret keys**, click the copy icon next to the hidden key (no need to
   reveal it).
3. Save it for your Windows user, in any PowerShell window (paste between the
   quotes with **Ctrl+V**):

   ```powershell
   [Environment]::SetEnvironmentVariable("CLERK_SECRET_KEY", "<paste here>", "User")
   ```

4. Close and reopen PowerShell, then start the backend as usual. Check it with:

   ```powershell
   if ($env:CLERK_SECRET_KEY -like "sk_*") { "Secret key: OK" } else { "Secret key: MISSING" }
   ```

Never commit the secret key or send it in chat or email: it gives admin access
to the Clerk app. If it leaks, create a new one in the Dashboard (**Secret keys
→ Add new key**), delete the old one, and tell the team to update theirs.

How it works: Clerk shows Google's sign-in page inside the app, then the app
sends the Clerk token to `POST /api/auth/clerk`. The backend verifies it and
signs the guardian in with a normal app session. A first-time Google user gets a
new guardian account. If a guardian account already has that email, Google is
linked to it, and the password keeps working too. An account created with Google
has no password; use **Forgot password?** to set one.

Without the secret key the backend answers `503` and the app shows "Google
sign-in is not configured on this server"; email sign-in is unaffected. To use a different
Clerk app, set `CLERK_PUBLISHABLE_KEY` for both the backend and `run_app.ps1`.

## 10. Managing data

Back these up together:

- `backend\asd_sense.db`: accounts, children, screenings, reviews,
  appointments, record details.
- `C:\Users\<you>\.asd_sense_private_records\`: the uploaded files.
- `C:\Users\<you>\.asd_sense_private_screenings\`: the screened images.
  Only clinicians can open them, in the portal. The original filenames are
  not kept.

Files in both folders have random names; the database links them to records
and screenings. Deleting one by hand is safe: the portal then shows that no
file or image is stored.

**Deleting data:** in the app, a guardian can delete a record, an appointment,
or a child without history. There is no way to delete a single screening.

**Starting over:** stop the backend, delete (or rename) `asd_sense.db`, start
the backend again (it creates a new empty database), and run `seed-demo`
again.

## 11. Troubleshooting

| Problem | Fix |
|---|---|
| "running scripts is disabled on this system" | Use the commands as written here (`.venv\Scripts\python ...`, `powershell -ExecutionPolicy Bypass -File ...`). |
| `python` not found | Reinstall Python with **Add python.exe to PATH** ticked, then open a new PowerShell window. |
| `No module named 'tensorflow'` when starting | The packages are not installed in the Python that runs uvicorn. Run the install in step 2 with the same Python you start the backend with. |
| `No module named 'pkg_resources'` | `.venv\Scripts\python -m pip install "setuptools<81"`, then restart the backend. |
| `"gesture_vit_loaded": false` | `backend/models/best_gesture_vit.weights.h5` is missing (`.h5` files are not in git). Gesture screening still works with MobileNet. Copy the file saved by `Models_Gestures/Model_ViT.ipynb` into `backend/models/` and restart. |
| Results say `Simulated_...` | No model of that type is loaded; the backend returns a fixed test value. Check <http://localhost:8000/>. |
| Old accounts cannot sign in, or uploads fail with `500` | The database is from an older version. See step 2. |
| `GET /favicon.ico 404` in Terminal 1 | Harmless: Chrome asking for a tab icon. |
| `GET /api/clinic/sync/revision 401` in Terminal 1 | Normal when the portal's session has ended. |
| `Traceback` or `500 Internal Server Error` in Terminal 1 | A real error; the traceback says where. |
| Port 8000 already in use | The backend is already running in another window; use that one or close it. |
| Phone not in `flutter devices` | Replug, choose File transfer, accept the USB debugging prompt, try another cable (some only charge). |
| App says it cannot connect | Backend running? Cable in and tunnel set (section 5)? For Wi-Fi: same network as the PC, and `http://<PC-IP>:8000/` opens in the phone's browser. |
| Phone's browser cannot open `http://<PC-IP>:8000/` | Windows Firewall is blocking Python, or the network is set to Public. Settings → Network & internet → your Wi-Fi → **Private network**. |
| Password rejected when signing up | Passwords must be at least 12 characters. |
| Forgot-password email never arrives | No mail server is set (section 9), so the code is printed in Terminal 1. |
| A clinician forgot their password | `.venv\Scripts\python manage.py set-password --email name@hospital.ae` (the app's reset is for guardians). |
| No banner for clinic updates on the phone | Profile > Notifications > Push notifications is off, or the app was closed (updates are still under the bell). |
