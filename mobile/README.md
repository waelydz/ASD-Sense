# ASD-Sense — Flutter App

## What changed in this pass

- **Welcome screen removed.** The app opens straight to Log In. Branding
  ("ASD-Sense") now lives at the top of the Log In screen.
- **Log In** — added a working "Remember me" checkbox (tap the label or the
  box) and a "Continue with Google" option.
- **Create Account** — collects full name, email, phone number, and
  password, plus a "Sign up with Google" option. No separate verification
  step; account creation goes straight into the app.
- **No more "demo" language** anywhere in the UI copy.
- **Dashboard (Home)** — removed the "Welcome to your demo care space"
  banner.
- **Child profiles** — guardians can add multiple children and switch
  between them (tap the Child Profile card on Home). Medical records and
  the booked appointment are scoped to whichever child is currently
  selected.
- **Profile** — added Notifications settings (push/email toggles) and a
  Privacy & Security page with real policy-style content.
- **Medical Records** — "History" record type removed (now just Documents
  and Imaging), the "Demo data only" warning banner removed, and adding a
  record now uses an actual file picker (`file_picker` package) instead of
  typing a name.
- **Detection** — result screen no longer states a confidence
  level/percentage. It now says the evaluation suggests something *may be
  possible* and recommends consulting a medical professional.
- **Appointments** — rebuilt around a searchable list of centers instead of
  fixed date/time slots. The centers list (`AppData.centers`) is
  intentionally empty — add your real center data there. Search matches by
  name, address, or city, which is the "near you" mechanism (no GPS/
  location permissions involved). No date/time picking — booking just
  sends a request to the chosen center.

## Run it

```bash
flutter pub get
flutter run
```

Two dependencies beyond default Flutter: `google_fonts` (Fraunces + DM
Sans) and `file_picker` (medical record uploads).

## Project structure

```
lib/
  main.dart
  theme/app_theme.dart
  models/models.dart            # Child, MedicalRecord, Center, Appointment
  data/app_data.dart            # Shared state, per-child records/appointments
  widgets/common_widgets.dart
  screens/
    login_screen.dart
    create_account_screen.dart
    main_shell.dart             # 5-tab bottom nav host
    home_screen.dart            # child switcher lives here
    records_screen.dart         # file upload via file_picker
    detection_screen.dart
    appointments_screen.dart    # center search + booking
    profile_screen.dart
    privacy_security_screen.dart
```

## Adding your center data

Open `lib/data/app_data.dart` and populate the `centers` list, e.g.:

```dart
final List<Center> centers = [
  Center(name: 'Example Clinic', address: '123 Main St', city: 'Dubai'),
];
```
