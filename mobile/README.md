# ASD-Sense — Flutter Prototype

An interactive Flutter build of the ASD-Sense Figma prototypes: Sign In, Sign
Up, Dashboard, New Screening, Medical Records, Appointments, and Profile &
Settings.

## What's interactive

- **Sign In / Sign Up** — form validation, password show/hide, "remember me",
  loading states, navigates into the app.
- **Dashboard** — quick-action cards route to the right tab or screen; shows
  live counts pulled from shared in-memory state.
- **New Screening** — "Capture Image" / "Upload Image" simulate an
  analysis (loading spinner → result dialog) and append a new entry to
  Medical Records.
- **Medical Records** — add new records via a bottom sheet, tap "View" for
  details.
- **Appointments** — add, reschedule (date picker), cancel (with
  confirmation), and a "Join Meeting" action for virtual appointments.
- **Profile & Settings** — edit email/phone inline, toggle notification
  preferences, log out back to Sign In.

All data lives in a single in-memory store (`lib/data/app_data.dart`) — there
is no backend or persistence yet, so state resets on app restart. That's the
natural place to wire up a real API later.

## Run it

1. Install the [Flutter SDK](https://docs.flutter.dev/get-started/install) if
   you haven't already, and make sure `flutter doctor` is happy.
2. Unzip this project (or copy the `lib/` folder and `pubspec.yaml` into a
   project created with `flutter create asd_sense`).
3. From the project root:
   ```bash
   flutter pub get
   flutter run
   ```
   Pick any connected device, simulator/emulator, or run `flutter run -d chrome`
   to try it in a browser.

- Camera & file picker are simulated (no `image_picker` dependency yet) to
  keep the prototype dependency-free. Wire up `image_picker` +
  `http`/`dio` to call a real screening model.
- Add persistence (e.g. `shared_preferences`, or a backend + `http`) so data
  survives app restarts.
- Swap the in-memory `AppData` singleton for a state-management package
  (Provider, Riverpod, Bloc) as the app grows.
