import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/http_api.dart';
import 'api_client.dart';
import 'models.dart';

/// The clinician portal's data: a copy of the backend's GET /clinic/state.
///
/// Every change (a review, an appointment status, a new patient, the profile)
/// is sent to the backend and the snapshot is reloaded. The portal also checks
/// every few seconds whether anything changed on the server, so a screening or
/// booking made in the guardian app appears here without a page reload.
class ClinicData extends ChangeNotifier {
  ClinicData._();
  static final ClinicData instance = ClinicData._();

  final ApiClient _api = ApiClient.instance;
  static const _session = SessionStore('clinician_token');
  static const _signedInAtStore = SessionStore('clinician_signed_in_at');
  static const _lastActivityStore = SessionStore('clinician_last_activity');
  static const _pollEvery = Duration(seconds: 4);

  /// Shows a message when a change made in the background could not be saved.
  /// Set by the app (see main.dart).
  void Function(String message)? onError;

  // ---- clinician profile (name and title shown to families on reviews) ----
  String clinicianName = '';
  String clinicianEmail = '';
  String jobTitle = '';
  String specialty = clinicianSpecialties.first;
  String clinicName = '';
  String licenceNumber = '';
  String workPhone = '';
  String languages = '';
  String bio = '';

  // ---- account security ----
  DateTime? signedInAt;
  DateTime? passwordChangedAt;
  DateTime lastActivity = DateTime.now();
  DateTime _activitySavedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Why the portal returned to the sign-in page by itself, if it did.
  String? signedOutReason;

  /// Minutes of inactivity before automatic sign-out. 0 means never.
  int autoSignOutMinutes = 15;

  /// What this clinician did recently, recorded by the backend.
  final List<ActivityEntry> activity = [];

  final List<Patient> patients = [];
  final List<Screening> _screenings = [];
  final Map<String, ClinicalReview> reviews = {};
  final List<ClinicAppointment> appointments = [];
  final List<FamilyRecord> _records = [];

  BackendStatus? backend;
  bool syncing = false;
  String? lastSyncError;
  DateTime? lastSyncAt;

  /// Clock style for appointment times.
  bool use24HourTime = false;

  int _revision = -1;
  Timer? _poll;
  bool _checking = false;

  // ---- session --------------------------------------------------------------

  bool get isSignedIn => signedInAt != null;

  /// Throws [ApiException] with the reason when the sign-in is refused.
  Future<void> signIn(String email, String password) async {
    final res = await _api.login(email, password);
    _api.http.token = res['access_token'] as String;
    signedInAt = DateTime.now();
    await _session.write(_api.http.token);
    await _signedInAtStore.write(signedInAt!.toIso8601String());
    await _enterSession();
  }

  /// Called at startup. True when this browser still has a valid session.
  /// Throws [ApiException] when the backend cannot be reached.
  Future<bool> restoreSession() async {
    final token = await _session.read();
    if (token == null) return false;
    _api.http.token = token;
    signedInAt = DateTime.tryParse(await _signedInAtStore.read() ?? '') ?? DateTime.now();
    final lastSeen = DateTime.tryParse(await _lastActivityStore.read() ?? '');
    try {
      await _enterSession();
    } on ApiException catch (e) {
      signedInAt = null;
      if (!e.unauthorized) rethrow;
      await _clearSession();
      return false;
    }
    // The inactivity limit also counts time the tab was closed.
    if (lastSeen != null && autoSignOutMinutes > 0) {
      if (DateTime.now().difference(lastSeen) > Duration(minutes: autoSignOutMinutes)) {
        await signOut(reason: 'You were signed out after $autoSignOutMinutes minutes of inactivity.');
        return false;
      }
    }
    return true;
  }

  Future<void> _enterSession() async {
    _apply(await _api.state());
    signedOutReason = null;
    touch();
    _poll ??= Timer.periodic(_pollEvery, (_) => _checkForChanges());
    unawaited(_checkBackend());
    notifyListeners();
  }

  Future<void> signOut({String? reason}) async {
    if (_api.http.token != null) {
      try {
        await _api.logout();
      } on ApiException {
        // Offline or already expired: the local sign-out below still happens.
      }
    }
    await _clearSession(reason: reason);
  }

  Future<void> _clearSession({String? reason}) async {
    _poll?.cancel();
    _poll = null;
    _api.http.token = null;
    await _session.write(null);
    await _signedInAtStore.write(null);
    await _lastActivityStore.write(null);
    clinicianName = '';
    clinicianEmail = '';
    signedInAt = null;
    signedOutReason = reason;
    activity.clear();
    patients.clear();
    _screenings.clear();
    reviews.clear();
    appointments.clear();
    _records.clear();
    _revision = -1;
    notifyListeners();
  }

  /// Called on any pointer or key input. Does not notify (it fires constantly).
  void touch() {
    lastActivity = DateTime.now();
    if (isSignedIn && lastActivity.difference(_activitySavedAt) > const Duration(seconds: 30)) {
      _activitySavedAt = lastActivity;
      unawaited(_lastActivityStore.write(lastActivity.toIso8601String()));
    }
  }

  bool get idleTooLong =>
      isSignedIn &&
      autoSignOutMinutes > 0 &&
      DateTime.now().difference(lastActivity) > Duration(minutes: autoSignOutMinutes);

  // ---- backend sync ---------------------------------------------------------

  /// The "Refresh data" / "Check again" buttons: model status and all data.
  Future<void> sync() async {
    if (syncing) return;
    syncing = true;
    notifyListeners();
    await _checkBackend();
    if (backend!.online) await _guard(refresh);
    syncing = false;
    notifyListeners();
  }

  Future<void> _checkBackend() async {
    backend = await _api.status();
    lastSyncError = backend!.online ? null : 'Backend not reachable at ${ApiClient.baseUrl}';
    notifyListeners();
  }

  /// Reloads everything from the backend.
  Future<void> refresh() async => _apply(await _api.state());

  Future<void> _checkForChanges() async {
    if (_checking || !isSignedIn) return;
    _checking = true;
    try {
      if (await _api.revision() != _revision) await refresh();
    } on ApiException catch (e) {
      // Offline moments are ignored; the next tick tries again.
      if (e.unauthorized) await _expire();
    } finally {
      _checking = false;
    }
  }

  Future<void> _expire() async {
    if (isSignedIn) await _clearSession(reason: 'Your session has ended. Please sign in again.');
  }

  /// Runs a backend call. An expired session signs the portal out; any other
  /// failure is rethrown for the page to show.
  Future<void> _guard(Future<void> Function() call) async {
    try {
      await call();
    } on ApiException catch (e) {
      if (!e.unauthorized) rethrow;
      await _expire();
    }
  }

  /// For changes made straight from a control (no Save button): shows the
  /// error and reloads, so the screen goes back to what the backend holds.
  Future<void> _saveInBackground(Future<void> Function() call) async {
    try {
      await _guard(() async {
        await call();
        await refresh();
      });
    } on ApiException catch (e) {
      onError?.call(e.message);
      unawaited(_guard(refresh).catchError((_) {}));
    }
  }

  void _apply(Map<String, dynamic> state) {
    _revision = state['revision'] as int;

    final user = state['user'] as Map<String, dynamic>;
    clinicianName = user['full_name'] as String;
    clinicianEmail = user['email'] as String;
    workPhone = (user['phone'] as String?) ?? '';
    jobTitle = user['job_title'] as String;
    final savedSpecialty = user['specialty'] as String;
    specialty = clinicianSpecialties.contains(savedSpecialty) ? savedSpecialty : clinicianSpecialties.first;
    clinicName = user['clinic_name'] as String;
    licenceNumber = user['licence_number'] as String;
    languages = user['languages'] as String;
    bio = user['bio'] as String;
    use24HourTime = user['use_24_hour_time'] == true;
    autoSignOutMinutes = user['auto_sign_out_minutes'] as int;
    final changed = user['password_changed_at'] as String?;
    passwordChangedAt = changed == null ? null : parseBackendDate(changed);

    List<Map<String, dynamic>> rows(String key) => (state[key] as List).cast<Map<String, dynamic>>();
    patients
      ..clear()
      ..addAll(rows('patients').map(Patient.fromApi));
    _screenings
      ..clear()
      ..addAll(rows('screenings').map(Screening.fromApi));
    reviews
      ..clear()
      ..addEntries(rows('reviews').map(ClinicalReview.fromApi).map((r) => MapEntry(r.screeningKey, r)));
    appointments
      ..clear()
      ..addAll(rows('appointments').map(ClinicAppointment.fromApi));
    _records
      ..clear()
      ..addAll(rows('records').map(FamilyRecord.fromApi));
    activity
      ..clear()
      ..addAll(rows('activity').map((a) => ActivityEntry(parseBackendDate(a['at'] as String?), a['text'] as String)));

    lastSyncAt = DateTime.now();
    notifyListeners();
  }

  // ---- settings -------------------------------------------------------------

  void setUse24HourTime(bool value) {
    use24HourTime = value;
    notifyListeners();
    _saveInBackground(() => _api.updateProfile({'use_24_hour_time': value}));
  }

  void setAutoSignOut(int minutes) {
    autoSignOutMinutes = minutes;
    notifyListeners();
    _saveInBackground(() => _api.updateProfile({'auto_sign_out_minutes': minutes}));
  }

  /// Throws [ApiException] when the profile could not be saved.
  Future<void> updateProfile({
    required String name,
    required String title,
    required String specialty,
    required String clinic,
    required String licence,
    required String phone,
    required String languages,
    required String bio,
  }) {
    return _guard(() async {
      await _api.updateProfile({
        'full_name': name,
        'job_title': title,
        'specialty': specialty,
        'clinic_name': clinic,
        'licence_number': licence,
        'phone': phone,
        'languages': languages,
        'bio': bio,
      });
      await refresh();
    });
  }

  /// Throws [ApiException] with the reason (e.g. wrong current password).
  Future<void> changePassword(String current, String next) {
    return _guard(() async {
      await _api.changePassword(current, next);
      await refresh();
    });
  }

  /// Name with title, as other people see it on notes and summaries.
  String get signature => jobTitle.isEmpty ? clinicianName : '$clinicianName, $jobTitle';

  // ---- queries --------------------------------------------------------------

  Patient? patient(String id) {
    for (final p in patients) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<Screening> screeningsFor(String patientId) {
    final list = _screenings.where((s) => s.patientId == patientId).toList()..sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  Screening? latestScreening(String patientId) {
    final list = screeningsFor(patientId);
    return list.isEmpty ? null : list.first;
  }

  Screening? screeningByKey(String key) {
    for (final s in _screenings) {
      if (s.key == key) return s;
    }
    return null;
  }

  List<Screening> get pendingReview {
    final list = _screenings.where((s) => !reviews.containsKey(s.key)).toList()
      ..sort((a, b) {
        final byPriority = b.priority.compareTo(a.priority);
        return byPriority != 0 ? byPriority : a.date.compareTo(b.date);
      });
    return list;
  }

  List<ClinicalReview> reviewsFor(String patientId) {
    final keys = screeningsFor(patientId).map((s) => s.key).toSet();
    final list = reviews.values.where((r) => keys.contains(r.screeningKey)).toList()
      ..sort((a, b) => b.reviewedAt.compareTo(a.reviewedAt));
    return list;
  }

  /// Where the patient stands, based on the latest review and open screenings.
  String caseStatus(String patientId) {
    final screenings = screeningsFor(patientId);
    if (screenings.isEmpty) return 'No screenings';
    if (screenings.any((s) => !reviews.containsKey(s.key))) return 'Awaiting review';
    final latest = reviewsFor(patientId);
    return latest.isEmpty ? 'Reviewed' : latest.first.action.short;
  }

  /// Files the family uploaded for this patient, newest first.
  List<FamilyRecord> recordsFor(String patientId) => _records.where((r) => r.patientId == patientId).toList();

  /// Opens an uploaded record in a new browser tab. Throws [ApiException]
  /// when it cannot be opened.
  Future<void> openRecord(FamilyRecord record) {
    return _guard(() async => openFileUrl(await _api.recordUrl(record.id)));
  }

  List<ClinicAppointment> appointmentsFor(String patientId) {
    final list = appointments.where((a) => a.patientId == patientId).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return list;
  }

  List<ClinicAppointment> appointmentsOn(DateTime day) {
    final list = appointments
        .where(
            (a) => a.scheduledAt.year == day.year && a.scheduledAt.month == day.month && a.scheduledAt.day == day.day)
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return list;
  }

  // ---- mutations ------------------------------------------------------------

  /// Saves the review in the backend; the family's app then shows the next
  /// step and gets a notification (never the note). Throws [ApiException]
  /// when it could not be saved.
  Future<void> saveReview({
    required Screening screening,
    required ClinicalFinding finding,
    required RecommendedAction action,
    required String note,
  }) {
    return _guard(() async {
      await _api.saveReview(screening.id, finding, action, note);
      await refresh();
    });
  }

  /// Adds the patient in the backend and returns it. Throws [ApiException]
  /// when it could not be saved.
  Future<Patient?> addPatient({
    required String firstName,
    required String lastName,
    required DateTime dateOfBirth,
    required String sex,
    required String guardianName,
    required String guardianPhone,
    required String guardianEmail,
    required String referralSource,
  }) async {
    int? childId;
    await _guard(() async {
      childId = await _api.addPatient({
        'first_name': firstName,
        'last_name': lastName,
        'date_of_birth': isoDate(dateOfBirth),
        // The backend stores female / male / other, or nothing.
        'sex': const {'Female': 'female', 'Male': 'male', 'Other': 'other'}[sex],
        'guardian_name': guardianName,
        'guardian_phone': guardianPhone,
        'guardian_email': guardianEmail,
        'referral_source': referralSource,
      });
      await refresh();
    });
    return childId == null ? null : patient('$childId');
  }

  /// The family gets a notification and sees the new status in their app.
  void setAppointmentStatus(ClinicAppointment a, VisitStatus status) {
    a.status = status;
    notifyListeners();
    _saveInBackground(() => _api.setAppointmentStatus(a.id, status));
  }

  /// Shows a screening the backend just returned, without waiting for the reload.
  Screening recordLiveResult(Patient p, ScreeningResult r, String fileName) {
    final s = Screening(
      id: r.screeningId,
      patientId: p.id,
      date: DateTime.now(),
      modelName: r.modelName,
      modelVersion: '1.0',
      predictedClass: r.predictedClass,
      autismProbability: r.autismProbability,
      confidence: r.confidence,
      imageReference: fileName,
      routing: r.routing,
      // The backend keeps the image when it is a PNG, JPEG, GIF or WebP; the
      // next refresh says for sure.
      hasImage: true,
    );
    _screenings.removeWhere((x) => x.key == s.key);
    _screenings.add(s);
    notifyListeners();
    return s;
  }
}

/// Makes widgets rebuild when [ClinicData] changes. Pages read data with
/// `ClinicScope.of(context)` so they redraw straight away, even when they are
/// const widgets (a const page is otherwise never rebuilt by its parent).
class ClinicScope extends InheritedNotifier<ClinicData> {
  ClinicScope({super.key, required super.child}) : super(notifier: ClinicData.instance);

  static ClinicData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ClinicScope>()?.notifier ?? ClinicData.instance;
}
