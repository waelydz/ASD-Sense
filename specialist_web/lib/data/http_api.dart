import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// A failed backend call. [statusCode] is 0 when the server could not be reached.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  /// The session is missing or expired; the user has to sign in again.
  bool get unauthorized => statusCode == 401;
  bool get offline => statusCode == 0;

  @override
  String toString() => message;
}

/// JSON calls to the FastAPI backend with the session token attached.
class HttpApi {
  HttpApi(this.baseUrl);

  String baseUrl;

  /// Session token from /api/clinic/auth/login. Null when signed out.
  String? token;

  Map<String, String> get authHeaders => {if (token != null) 'Authorization': 'Bearer $token'};

  Future<dynamic> get(String path, {Duration timeout = const Duration(seconds: 15)}) =>
      _send('GET', path, null, timeout);
  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body);
  Future<dynamic> put(String path, [Object? body]) => _send('PUT', path, body);
  Future<dynamic> patch(String path, [Object? body]) => _send('PATCH', path, body);
  Future<dynamic> delete(String path) => _send('DELETE', path, null);

  Future<dynamic> _send(String method, String path, Object? body,
      [Duration timeout = const Duration(seconds: 15)]) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'))..headers.addAll(authHeaders);
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    return _run(request, timeout);
  }

  /// Multipart upload of one file in the `file` field, with optional form fields.
  Future<dynamic> upload(String path, Uint8List bytes, String fileName, {Map<String, String> fields = const {}}) {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'))
      ..headers.addAll(authHeaders)
      ..fields.addAll(fields)
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
    return _run(request, const Duration(seconds: 60));
  }

  Future<dynamic> _run(http.BaseRequest request, Duration timeout) async {
    final http.Response response;
    try {
      response = await http.Response.fromStream(await request.send().timeout(timeout));
    } catch (_) {
      throw ApiException(0, 'Could not reach the server at $baseUrl. Check that the backend is running.');
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body.isEmpty ? null : jsonDecode(utf8.decode(response.bodyBytes));
    }
    throw ApiException(response.statusCode, errorMessage(response));
  }

  /// FastAPI puts the reason in `detail`: a string for our own errors, a list
  /// of problems for request validation errors.
  static String errorMessage(http.Response response) {
    try {
      final detail = (jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>)['detail'];
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first as Map<String, dynamic>;
        final field = (first['loc'] as List?)?.last;
        return '${field ?? 'Request'}: ${first['msg']}';
      }
    } catch (_) {
      // not JSON; fall through
    }
    return 'The server returned an error (${response.statusCode}).';
  }
}

/// Opens a file the backend serves at [url] (a one-minute link from
/// POST /records/{id}/link) in the browser or the device's viewer.
Future<void> openFileUrl(String url) async {
  if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
    throw ApiException(0, 'No app on this device could open the file.');
  }
}

/// Keeps the session token on the device (app storage on mobile, localStorage
/// on web) so the user is still signed in on their next visit.
class SessionStore {
  const SessionStore(this.key);
  final String key;

  Future<String?> read() async => (await SharedPreferences.getInstance()).getString(key);

  Future<void> write(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }
}

/// Backend timestamps come in two forms:
/// - `YYYY-MM-DD HH:MM:SS`, UTC without a marker (SQLite CURRENT_TIMESTAMP);
/// - ISO 8601 with an offset, e.g. `2026-11-20T10:00:00+04:00`
///   (Appointments.scheduled_at, as the guardian app sends it).
DateTime parseBackendDate(String? raw) {
  if (raw == null || raw.isEmpty) return DateTime.now();
  final iso = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
  final hasZone = iso.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(iso);
  final parsed = DateTime.tryParse(hasZone ? iso : '${iso}Z');
  return parsed?.toLocal() ?? DateTime.now();
}

/// A calendar date as `YYYY-MM-DD`, for dates of birth.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
