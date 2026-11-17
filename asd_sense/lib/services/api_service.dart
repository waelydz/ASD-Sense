import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Errors raised by the API client. Never include patient data or credentials.
class ApiException implements Exception {
  final int? statusCode;
  final String message;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Small JSON client for the existing FastAPI auth and child-profile routes.
///
/// On a physical Android device, pass WIFI_BACKEND_URL via run_app.ps1.
/// ADB reverse is the fallback when Wi-Fi cannot reach the backend.
class ApiService {
  static const _wifiUrl = String.fromEnvironment(
    'WIFI_BACKEND_URL',
    defaultValue: 'http://10.255.131.126:8000',
  );
  static const _usbUrl = 'http://127.0.0.1:8000';

  final http.Client _client;
  final String? _testBaseUrl;
  String? _resolvedBaseUrl;

  ApiService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _testBaseUrl = baseUrl;

  Future<String> _baseUrl() async {
    if (_testBaseUrl != null) return _testBaseUrl!;
    if (_resolvedBaseUrl != null) return _resolvedBaseUrl!;
    try {
      final response = await _client
          .get(Uri.parse('$_wifiUrl/'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        _resolvedBaseUrl = _wifiUrl;
        return _wifiUrl;
      }
    } catch (_) {
      // USB forwarding may still be available.
    }
    _resolvedBaseUrl = _usbUrl;
    return _usbUrl;
  }

  Future<dynamic> _send(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    final base = await _baseUrl();
    final url = Uri.parse('$base$path');
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (token != null) headers['Authorization'] = 'Bearer $token';

    late http.Response response;
    try {
      switch (method) {
        case 'GET':
          response = await _client.get(url, headers: headers)
              .timeout(const Duration(seconds: 12));
          break;
        case 'POST':
          response = await _client.post(url, headers: headers, body: jsonEncode(body))
              .timeout(const Duration(seconds: 12));
          break;
        case 'PUT':
          response = await _client.put(url, headers: headers, body: jsonEncode(body))
              .timeout(const Duration(seconds: 12));
          break;
        case 'PATCH':
          response = await _client.patch(url, headers: headers, body: jsonEncode(body))
              .timeout(const Duration(seconds: 12));
          break;
        case 'DELETE':
          response = await _client.delete(url, headers: headers)
              .timeout(const Duration(seconds: 12));
          break;
        default:
          throw const ApiException('Unsupported HTTP method');
      }
    } on TimeoutException {
      throw const ApiException('The backend did not respond in time.');
    } on http.ClientException {
      throw const ApiException('Could not connect to the backend.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final status = response.statusCode;
      final message = switch (status) {
        401 => 'Session expired or sign-in failed. Please sign in again.',
        403 => 'You do not have permission to access this information.',
        404 => 'Requested item was not found or is inaccessible.',
        413 => 'The file is too large (maximum 10 MB).',
        415 => 'Unsupported file type or contents.',
        409 => 'This action conflicts with existing records or account details.',
        422 => 'Please review the information you entered.',
        _ => 'Server error ($status).',
      };
      throw ApiException(message, statusCode: status);
    }
    if (response.statusCode == 204 || response.body.isEmpty) return null;
    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw const ApiException('The backend returned an invalid response.');
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async =>
      Map<String, dynamic>.from(await _send('POST', '/api/auth/login',
          body: {'email': email, 'password': password}));

  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async =>
      Map<String, dynamic>.from(await _send('POST', '/api/auth/register', body: {
        'full_name': name,
        'email': email,
        'phone': phone.isEmpty ? null : phone,
        'password': password,
      }));

  /// Exchange a Clerk session token (Google sign-in) for an app session.
  Future<Map<String, dynamic>> signInWithClerk(String clerkSessionToken) async =>
      Map<String, dynamic>.from(await _send('POST', '/api/auth/clerk',
          body: {'session_token': clerkSessionToken}));

  Future<Map<String, dynamic>> me(String token) async =>
      Map<String, dynamic>.from(await _send('GET', '/api/auth/me', token: token));

  Future<void> logout(String token) async {
    await _send('POST', '/api/auth/logout', token: token);
  }

  Future<List<Map<String, dynamic>>> listChildren(String token) async {
    final payload = await _send('GET', '/api/children', token: token) as List<dynamic>;
    return payload.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  Future<Map<String, dynamic>> createChild(
      String token, String name, DateTime dob) async =>
      Map<String, dynamic>.from(await _send('POST', '/api/children',
          token: token, body: {
            'first_name': name,
            'date_of_birth': _dateOnly(dob),
          }));

  Future<Map<String, dynamic>> updateChild(
      String token, String id, String? changedName, DateTime dob) async {
    final changes = <String, dynamic>{'date_of_birth': _dateOnly(dob)};
    if (changedName != null) {
      // The current UI has one name field; don't silently retain an old suffix.
      changes['first_name'] = changedName;
      changes['last_name'] = null;
    }
    return Map<String, dynamic>.from(await _send('PATCH', '/api/children/$id',
        token: token, body: changes));
  }

  Future<void> deleteChild(String token, String id) async {
    await _send('DELETE', '/api/children/$id', token: token);
  }


  Future<Map<String, dynamic>> updateGuardian(String token, String fullName, String phone) async =>
      Map<String, dynamic>.from(await _send('PATCH', '/api/account/profile', token: token,
          body: {'full_name': fullName, 'phone': phone.isEmpty ? null : phone}));

  Future<Map<String, dynamic>> preferences(String token) async =>
      Map<String, dynamic>.from(await _send('GET', '/api/account/preferences', token: token));

  Future<Map<String, dynamic>> savePreferences(String token,
      {required bool push, required bool email}) async =>
      Map<String, dynamic>.from(await _send('PUT', '/api/account/preferences', token: token,
          body: {'push_notifications': push, 'email_notifications': email}));

  /// Updates from the clinic (reviews, appointment status), newest first.
  Future<List<Map<String, dynamic>>> notifications(String token) =>
      _getRows(token, '/api/notifications');

  Future<void> markNotificationsRead(String token) async {
    await _send('POST', '/api/notifications/read', token: token);
  }

  /// Emails a 6-digit reset code. Succeeds whether or not the email has an
  /// account, so the app cannot tell (and does not say) which is the case.
  Future<void> forgotPassword(String email) async {
    await _send('POST', '/api/auth/forgot', body: {'email': email});
  }

  Future<void> resetPassword({required String email, required String code,
      required String newPassword}) async {
    try {
      await _send('POST', '/api/auth/reset',
          body: {'email': email, 'code': code, 'new_password': newPassword});
    } on ApiException catch (e) {
      if (e.statusCode == 400) {
        throw const ApiException('That code is not valid or has expired. Request a new one.',
            statusCode: 400);
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> screenings(String token, String childId) =>
      _getRows(token, '/api/children/$childId/screenings');

  Future<List<Map<String, dynamic>>> medicalRecords(String token, String childId) =>
      _getRows(token, '/api/children/$childId/medical-records');

  Future<List<Map<String, dynamic>>> appointments(String token, String childId) =>
      _getRows(token, '/api/children/$childId/appointments');

  Future<List<Map<String, dynamic>>> _getRows(String token, String path) async =>
      (await _send('GET', path, token: token) as List<dynamic>)
          .map((value) => Map<String, dynamic>.from(value as Map)).toList();

  Future<Map<String, dynamic>> addAppointment(String token, String childId,
      {required DateTime scheduled, required String location}) async =>
      Map<String, dynamic>.from(await _send('POST', '/api/children/$childId/appointments',
          token: token, body: {
            'scheduled_at': _withTimezone(scheduled),
            'location': location,
            'appointment_type': 'Personal reminder (not provider-confirmed)',
          }));

  Future<Map<String, dynamic>> rescheduleAppointment(String token, String childId,
      int appointmentId, DateTime scheduled) async =>
      Map<String, dynamic>.from(await _send('PATCH',
          '/api/children/$childId/appointments/$appointmentId',
          token: token, body: {'scheduled_at': _withTimezone(scheduled)}));

  Future<void> cancelAppointment(String token, String childId,
      int appointmentId) async {
    await _send('PATCH', '/api/children/$childId/appointments/$appointmentId',
        token: token, body: {'status': 'cancelled'});
  }

  Future<Map<String, dynamic>> uploadMedicalRecord(String token, String childId,
      {required String filename, required Uint8List bytes, required String recordType}) async {
    final base = await _baseUrl();
    final request = http.MultipartRequest('POST',
        Uri.parse('$base/api/children/$childId/medical-records'))
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['record_type'] = recordType
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 40)));
    if (response.statusCode != 201) {
      throw ApiException('Medical upload failed (${response.statusCode}).',
          statusCode: response.statusCode);
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<Uint8List> downloadMedicalRecord(String token, String childId, int id) async {
    final base = await _baseUrl();
    final response = await _client.get(Uri.parse(
        '$base/api/children/$childId/medical-records/$id/download'),
        headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 40));
    if (response.statusCode != 200) {
      throw ApiException('File download failed (${response.statusCode}).',
          statusCode: response.statusCode);
    }
    return response.bodyBytes;
  }

  Future<void> deleteMedicalRecord(String token, String childId, int id) async {
    await _send('DELETE', '/api/children/$childId/medical-records/$id', token: token);
  }

  Future<Map<String, dynamic>> predict(String token, String childId,
      {required String modality, required String filename, required Uint8List bytes}) async {
    final base = await _baseUrl();
    final request = http.MultipartRequest('POST', Uri.parse('$base/predict/$modality'))
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['child_id'] = childId
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    late http.Response response;
    try {
      response = await http.Response.fromStream(
          await _client.send(request).timeout(const Duration(seconds: 60)));
    } on TimeoutException {
      throw const ApiException('The screening request timed out.');
    } on http.ClientException {
      throw const ApiException('Could not connect to the screening server.');
    }
    if (response.statusCode != 200) {
      throw ApiException('Screening failed (${response.statusCode}). Please check your session and selected child.',
          statusCode: response.statusCode);
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  static String _withTimezone(DateTime d) {
    final local = d.toLocal();
    final offset = local.timeZoneOffset;
    final minutes = offset.inMinutes.abs();
    final sign = offset.isNegative ? '-' : '+';
    final hh = (minutes ~/ 60).toString().padLeft(2, '0');
    final mm = (minutes % 60).toString().padLeft(2, '0');
    return '${local.toIso8601String()}$sign$hh:$mm';
  }

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
