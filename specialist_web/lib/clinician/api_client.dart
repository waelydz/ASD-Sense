import 'dart:typed_data';

import '../data/http_api.dart';
import 'models.dart';

export '../data/http_api.dart' show ApiException;

/// The clinician portal's calls to the FastAPI backend: the /api/clinic/...
/// routes in backend/clinic_api.py (and /api/clinic/predict in main.py).
/// Guardian accounts are refused there, as clinician accounts are by the
/// guardian app's /api/... routes.
///
/// Set the address at build time:
///   flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const String baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000');

  final HttpApi http = HttpApi(baseUrl);

  /// GET /  - which models the backend has loaded. Needs no sign-in.
  Future<BackendStatus> status() async {
    try {
      final data = await http.get('/', timeout: const Duration(seconds: 6)) as Map<String, dynamic>;
      return BackendStatus(
        online: true,
        gestureMobileNet: data['gesture_mobilenet_loaded'] == true,
        gestureVit: data['gesture_vit_loaded'] == true,
        facialMobileNet: data['facial_mobilenet_loaded'] == true,
        facialVit: data['facial_vit_loaded'] == true,
        checkedAt: DateTime.now(),
      );
    } on ApiException catch (e) {
      return BackendStatus(
        online: false,
        error: e.offline ? 'Not reachable' : 'HTTP ${e.statusCode}',
        checkedAt: DateTime.now(),
      );
    }
  }

  /// POST /api/clinic/auth/login. Returns `{access_token, expires_in, user}`;
  /// guardian accounts are refused (403).
  Future<Map<String, dynamic>> login(String email, String password) async =>
      await http.post('/api/clinic/auth/login', {'email': email, 'password': password}) as Map<String, dynamic>;

  Future<void> logout() => http.post('/api/clinic/auth/logout');

  /// GET /api/clinic/state - patients, screenings, reviews, appointments, activity.
  Future<Map<String, dynamic>> state() async => await http.get('/api/clinic/state') as Map<String, dynamic>;

  /// GET /api/clinic/sync/revision - goes up whenever anything changes, on either side.
  Future<int> revision() async =>
      (await http.get('/api/clinic/sync/revision', timeout: const Duration(seconds: 6))
          as Map<String, dynamic>)['revision'] as int;

  Future<void> updateProfile(Map<String, dynamic> changes) => http.patch('/api/clinic/me', changes);

  Future<void> changePassword(String current, String next) =>
      http.post('/api/clinic/me/password', {'current_password': current, 'new_password': next});

  /// POST /api/clinic/patients. Returns the new child_id.
  Future<int> addPatient(Map<String, dynamic> patient) async =>
      (await http.post('/api/clinic/patients', patient) as Map<String, dynamic>)['child_id'] as int;

  Future<void> saveReview(int screeningId, ClinicalFinding finding, RecommendedAction action, String note) =>
      http.put('/api/clinic/screenings/$screeningId/review',
          {'finding': finding.apiValue, 'action': action.apiValue, 'note': note});

  /// Where the review dialog loads a screened image from. The request must
  /// carry [authHeaders].
  String screeningImageUrl(int screeningId) => '$baseUrl/api/clinic/screenings/$screeningId/image';
  Map<String, String> get authHeaders => http.authHeaders;

  /// POST /api/clinic/records/{id}/link. Returns a one-minute, single-use URL
  /// for opening the file in a new tab.
  Future<String> recordUrl(int recordId) async =>
      '$baseUrl${(await http.post('/api/clinic/records/$recordId/link') as Map<String, dynamic>)['path']}';

  Future<void> reopenReview(int screeningId) => http.delete('/api/clinic/screenings/$screeningId/review');

  Future<void> setAppointmentStatus(int appointmentId, VisitStatus status) =>
      http.patch('/api/clinic/appointments/$appointmentId', {'status': status.apiValue});

  /// POST /api/clinic/predict/gesture or .../facial. The backend logs the
  /// result to Screening_Records itself and keeps the image for review.
  Future<ScreeningResult> predict({
    required ScreeningModality modality,
    required int childId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final d = await http.upload(modality.endpoint, bytes, fileName, fields: {'child_id': '$childId'})
        as Map<String, dynamic>;
    return ScreeningResult(
      screeningId: d['screening_id'] as int,
      modelName: d['model_name'] as String,
      routing: d['routing'] as String,
      predictedClass: d['predicted_class'] as String,
      autismProbability: (d['autism_probability'] as num).toDouble(),
      confidence: (d['confidence'] as num).toDouble(),
    );
  }
}
