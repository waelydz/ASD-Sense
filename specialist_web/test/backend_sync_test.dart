// End-to-end check that the guardian app and the clinician portal stay in
// step through the backend. It drives the guardian app's real API client
// (asd_sense ApiService) and the portal's real data class (ClinicData)
// against a running backend.
//
// Needs a backend with the demo clinician account, on a database you can throw
// away (PowerShell):
//
//   cd backend
//   $env:ASD_SENSE_DB_PATH = "$env:TEMP\asd_sense_sync_test.db"
//   $env:ASD_SENSE_RECORDS_DIR = "$env:TEMP\asd_sense_sync_records"
//   $env:ASD_SENSE_SCREENINGS_DIR = "$env:TEMP\asd_sense_sync_screenings"
//   python manage.py seed-demo
//   python -m uvicorn main:app --port 8000
//
//   cd specialist_web
//   flutter test test/backend_sync_test.dart --dart-define=RUN_BACKEND_TESTS=true --dart-define=API_BASE_URL=http://127.0.0.1:8000
//
// Without RUN_BACKEND_TESTS it is skipped, so a plain `flutter test` passes.
//
// The guardian app is a dev dependency (../asd_sense). Each app has its own
// API client and its own exception class: `ApiException` below is the
// portal's, `guardian.ApiException` the app's.

import 'dart:convert';
import 'dart:typed_data';

import 'package:asd_sense/services/api_service.dart' as guardian;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:specialist_web/clinician/api_client.dart';
import 'package:specialist_web/clinician/clinic_data.dart';
import 'package:specialist_web/clinician/models.dart';

const _enabled = bool.fromEnvironment('RUN_BACKEND_TESTS');
const _baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://127.0.0.1:8000');

// A 1x1 PNG.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

/// Waits for the portal's own polling (every few seconds) to pick a change up.
Future<void> _eventually(bool Function() condition, String what) async {
  for (var i = 0; i < 40; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  fail('Not synced within 10 seconds: $what');
}

Matcher _status(int code) => throwsA(isA<guardian.ApiException>().having((e) => e.statusCode, 'status', code));
Matcher _portalStatus(int code) => throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', code));

void main() {
  test('guardian app and clinician portal stay in sync',
      skip: _enabled ? false : 'needs a running backend', timeout: const Timeout(Duration(minutes: 3)), () async {
    SharedPreferences.setMockInitialValues({});
    final app = guardian.ApiService(baseUrl: _baseUrl);
    final clinic = ClinicData.instance;
    final email = 'sync-test-${DateTime.now().microsecondsSinceEpoch}@example.com';
    const password = 'parent-pass-123';

    // --- sign-in: each account only works in its own app ---
    await expectLater(app.login(email, password), _status(401));
    await expectLater(clinic.signIn('clinician@asdsense.com', 'wrong-password-0'), _portalStatus(401));
    final account = await app.register(name: 'Sync Tester', email: email, phone: '050 000 0000', password: password);
    final token = account['access_token'] as String;
    await expectLater(clinic.signIn(email, password), _portalStatus(403));
    await expectLater(app.login('clinician@asdsense.com', 'Clinic#2026demo'), _status(401));
    await clinic.signIn('clinician@asdsense.com', 'Clinic#2026demo');
    expect(clinic.isSignedIn, isTrue);

    // --- guardian adds a child -> it appears in the portal by itself ---
    final child = await app.createChild(token, 'Sync Child', DateTime(2023, 3, 9));
    final childId = '${child['child_id']}';
    await _eventually(() => clinic.patient(childId) != null, 'new child in the portal');
    expect(clinic.patient(childId)!.guardianName, 'Sync Tester');
    expect(clinic.patient(childId)!.guardianEmail, email);

    // --- guardian screens in the app -> the portal's review queue has it ---
    await app.predict(token, childId, modality: 'facial', filename: 'face.png', bytes: _png);
    await _eventually(() => clinic.screeningsFor(childId).length == 1, 'app screening in the portal');

    // --- clinician runs a screening and reviews it ---
    final result = await ApiClient.instance.predict(
        modality: ScreeningModality.gesture, childId: int.parse(childId), bytes: _png, fileName: 'hands.png');
    final screening = clinic.recordLiveResult(clinic.patient(childId)!, result, 'hands.png');
    // The portal can load the screened images, with the clinician's session only.
    await clinic.refresh();
    expect(clinic.screeningsFor(childId).every((s) => s.hasImage), isTrue);
    final imageUrl = Uri.parse(ApiClient.instance.screeningImageUrl(screening.id));
    expect((await http.get(imageUrl, headers: ApiClient.instance.authHeaders)).bodyBytes, _png);
    expect((await http.get(imageUrl)).statusCode, 401);
    expect((await http.get(imageUrl, headers: {'Authorization': 'Bearer $token'})).statusCode, 403);
    await clinic.saveReview(
        screening: screening,
        finding: ClinicalFinding.agree,
        action: RecommendedAction.referDiagnostic,
        note: 'For the clinic only.');
    // The family's own screening is still open.
    expect(clinic.caseStatus(childId), 'Awaiting review');
    final fromApp = clinic.screeningsFor(childId).firstWhere((s) => s.key != screening.key);
    await clinic.saveReview(
        screening: fromApp, finding: ClinicalFinding.agree, action: RecommendedAction.referDiagnostic, note: '');
    expect(clinic.caseStatus(childId), 'Referred');
    // Both screenings are in the family's history with the outcome and the
    // reviewer; the clinical note is not.
    final history = await app.screenings(token, childId);
    expect(history, hasLength(2));
    expect(history.every((s) => s['review_action'] == 'refer_diagnostic'), isTrue);
    expect(history.first['reviewer_name'], isNotEmpty);
    expect(jsonEncode(history), isNot(contains('For the clinic only')));
    final reviewed = await app.notifications(token);
    expect(reviewed.map((n) => n['title']), ['Screening reviewed', 'Screening reviewed']);
    expect(jsonEncode(reviewed), isNot(contains('For the clinic only')));

    // --- guardian adds an appointment -> portal schedule shows it at the same
    //     moment -> clinician confirms -> the app shows it confirmed ---
    final when = DateTime.now().add(const Duration(days: 3)).copyWith(second: 0, millisecond: 0, microsecond: 0);
    await app.addAppointment(token, childId, scheduled: when, location: 'ASD-Sense Demo Clinic');
    await _eventually(() => clinic.appointmentsFor(childId).isNotEmpty, 'appointment in the portal');
    final visit = clinic.appointmentsFor(childId).single;
    expect(visit.location, 'ASD-Sense Demo Clinic');
    expect(visit.scheduledAt.isAtSameMomentAs(when), isTrue, reason: '${visit.scheduledAt} vs $when');
    clinic.setAppointmentStatus(visit, VisitStatus.confirmed);
    Future<String> appStatus() async => (await app.appointments(token, childId)).single['status'] as String;
    for (var i = 0; i < 20 && await appStatus() != 'confirmed'; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect(await appStatus(), 'confirmed');
    expect((await app.notifications(token)).first['title'], 'Appointment confirmed');
    await app.markNotificationsRead(token);
    expect((await app.notifications(token)).every((n) => n['is_read'] == true), isTrue);

    // --- guardian uploads a record -> the clinician can open it ---
    final pdf = Uint8List.fromList(utf8.encode('%PDF-1.4 test'));
    await app.uploadMedicalRecord(token, childId, filename: 'report.pdf', bytes: pdf, recordType: 'document');
    await _eventually(() => clinic.recordsFor(childId).isNotEmpty, 'uploaded record in the portal');
    expect(clinic.recordsFor(childId).single.fileName, 'report.pdf');
    final url = await ApiClient.instance.recordUrl(clinic.recordsFor(childId).single.id);
    expect((await http.get(Uri.parse(url))).body, '%PDF-1.4 test');
    expect((await http.get(Uri.parse(url))).statusCode, 404, reason: 'links are single-use');

    // --- guardian edits their profile; the portal follows ---
    await app.updateGuardian(token, 'Sync Tester Renamed', '050 111 1111');
    await _eventually(() => clinic.patient(childId)!.guardianName == 'Sync Tester Renamed', 'new name in the portal');

    // --- the portal keeps its session across a reload, and ends it on sign-out ---
    expect(await clinic.restoreSession(), isTrue);
    expect(clinic.reviews[screening.key]!.note, 'For the clinic only.');
    expect(clinic.activity.map((a) => a.text), contains("Marked Sync Child's appointment as confirmed"));
    await clinic.signOut();
    expect(await clinic.restoreSession(), isFalse);
    await app.logout(token);
  });
}
