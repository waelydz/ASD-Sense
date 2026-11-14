import 'dart:async';
import 'dart:convert';

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
        404 => 'Child profile not found.',
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

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
