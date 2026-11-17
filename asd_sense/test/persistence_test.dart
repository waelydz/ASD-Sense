import 'dart:typed_data';
import 'dart:convert';

import 'package:asd_sense/data/app_data.dart';
import 'package:asd_sense/services/api_service.dart';
import 'package:asd_sense/services/session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeSessionStore implements SessionStore {
  String? token;
  final Map<int, String> selections = {};

  @override
  Future<String?> readToken() async => token;
  @override
  Future<void> writeToken(String? value) async {
    token = value;
  }
  @override
  Future<String?> readSelectedChild(int userId) async => selections[userId];
  @override
  Future<void> writeSelectedChild(int userId, String? id) async {
    if (id == null) {
      selections.remove(userId);
    } else {
      selections[userId] = id;
    }
  }
}

http.Response jsonResponse(Object payload, [int status = 200]) =>
    http.Response(jsonEncode(payload), status,
        headers: {'content-type': 'application/json'});

Map<String, dynamic> child(int id, {String name = 'Synthetic Child'}) => {
  'child_id': id,
  'user_id': 99,
  'first_name': name,
  'last_name': null,
  'date_of_birth': '2021-03-04',
  'sex': null,
  'relationship_to_user': null,
  'notes': null,
  'created_at': '2026-01-01 00:00:00',
  'updated_at': '2026-01-01 00:00:00',
};

Map<String, dynamic> get account => {
  'user_id': 99,
  'full_name': 'Synthetic Guardian',
  'email': 'synthetic@example.test',
  'phone': null,
  'role': 'guardian',
};

http.Response? commonResponse(String path) {
  if (path == '/api/account/preferences') return jsonResponse({
    'push_notifications': true, 'email_notifications': false,
  });
  if (path.endsWith('/screenings') || path.endsWith('/medical-records') ||
      path.endsWith('/appointments')) return jsonResponse([]);
  return null;
}

void main() {
  test('profile creation uses SQLite child ID and survives AppData recreation', () async {
    final store = FakeSessionStore();
    final records = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      final path = request.url.path;
      final common = commonResponse(path);
      if (common != null) return common;
      if (path == '/api/auth/login') {
        return jsonResponse({'access_token': 'synthetic-token', 'user': account});
      }
      if (path == '/api/auth/me') return jsonResponse(account);
      if (path == '/api/children' && request.method == 'GET') {
        expect(request.headers['authorization'], 'Bearer synthetic-token');
        return jsonResponse(records);
      }
      if (path == '/api/children' && request.method == 'POST') {
        expect(request.headers['authorization'], 'Bearer synthetic-token');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['date_of_birth'], '2021-03-04');
        final newRow = child(42, name: body['first_name'] as String);
        records.add(newRow);
        return jsonResponse(newRow, 201);
      }
      return http.Response('Not found', 404);
    });
    final api = ApiService(baseUrl: 'http://localhost:8000', client: client);
    final data = AppData.testing(api: api, store: store);
    await data.signIn('synthetic@example.test', 'temporary-long-password', remember: true);
    await data.addChild('Synthetic Child', DateTime(2021, 3, 4));
    expect(data.activeChildId, '42');
    expect(store.token, 'synthetic-token');

    final afterRestart = AppData.testing(api: api, store: store);
    expect(await afterRestart.restoreSession(), isTrue);
    expect(afterRestart.activeChild?.id, '42');
    expect(afterRestart.children.single.name, 'Synthetic Child');
  });

  test('Google sign-in exchanges the Clerk token for a remembered app session', () async {
    final store = FakeSessionStore();
    final client = MockClient((request) async {
      final common = commonResponse(request.url.path);
      if (common != null) return common;
      if (request.url.path == '/api/auth/clerk') {
        expect(request.method, 'POST');
        expect(request.headers['authorization'], isNull);
        expect(jsonDecode(request.body), {'session_token': 'synthetic-clerk-jwt'});
        return jsonResponse({'access_token': 'synthetic-token', 'user': account});
      }
      if (request.url.path == '/api/children') {
        expect(request.headers['authorization'], 'Bearer synthetic-token');
        return jsonResponse([]);
      }
      return http.Response('Not found', 404);
    });
    final api = ApiService(baseUrl: 'http://localhost:8000', client: client);
    final data = AppData.testing(api: api, store: store);
    await data.signInWithGoogle('synthetic-clerk-jwt');
    expect(store.token, 'synthetic-token');
  });

  test('non-remembered session does not auto-restore on restart', () async {
    final store = FakeSessionStore();
    final client = MockClient((request) async {
      final common = commonResponse(request.url.path);
      if (common != null) return common;
      if (request.url.path == '/api/auth/login') {
        return jsonResponse({'access_token': 'synthetic-token', 'user': account});
      }
      if (request.url.path == '/api/children') return jsonResponse([]);
      return http.Response('Not found', 404);
    });
    final api = ApiService(baseUrl: 'http://localhost:8000', client: client);
    final app = AppData.testing(api: api, store: store);
    await app.signIn('synthetic@example.test', 'temporary-long-password', remember: false);
    expect(store.token, isNull);
    final afterRestart = AppData.testing(api: api, store: store);
    expect(await afterRestart.restoreSession(), isFalse);
  });

  test('ownership rejection never adds another guardian child', () async {
    final store = FakeSessionStore();
    final client = MockClient((request) async {
      final common = commonResponse(request.url.path);
      if (common != null) return common;
      if (request.url.path == '/api/auth/login') {
        return jsonResponse({'access_token': 'synthetic-token', 'user': account});
      }
      if (request.url.path == '/api/children') {
        return jsonResponse([], 403);
      }
      return http.Response('Not found', 404);
    });
    final api = ApiService(baseUrl: 'http://localhost:8000', client: client);
    final data = AppData.testing(api: api, store: store);
    await expectLater(
      data.signIn('synthetic@example.test', 'temporary-long-password', remember: true),
      throwsA(isA<ApiException>()),
    );
    expect(data.children, isEmpty);
    expect(store.token, isNull);
  });

  test('failed deletion preserves local child and remote history', () async {
    final store = FakeSessionStore();
    final client = MockClient((request) async {
      final path = request.url.path;
      final common = commonResponse(path);
      if (common != null) return common;
      if (path == '/api/auth/login') {
        return jsonResponse({'access_token': 'synthetic-token', 'user': account});
      }
      if (path == '/api/children' && request.method == 'GET') {
        return jsonResponse([child(42)]);
      }
      if (path == '/api/children/42' && request.method == 'DELETE') {
        return jsonResponse({'detail': 'Screening history exists'}, 409);
      }
      return http.Response('Not found', 404);
    });
    final data = AppData.testing(
        api: ApiService(baseUrl: 'http://localhost:8000', client: client),
        store: store);
    await data.signIn('synthetic@example.test', 'temporary-long-password', remember: true);
    await expectLater(data.removeChild('42'), throwsA(isA<ApiException>()));
    expect(data.children.single.id, '42');
  });

  test('inference request includes active child and verified bearer token', () async {
    final store = FakeSessionStore();
    var requestChild = '';
    var authenticated = false;
    final client = MockClient((request) async {
      final path = request.url.path;
      final common = commonResponse(path);
      if (common != null) return common;
      if (path == '/api/auth/login') {
        return jsonResponse({'access_token': 'synthetic-token', 'user': account});
      }
      if (path == '/api/children') return jsonResponse([child(42)]);
      if (path == '/predict/facial' && request.method == 'POST') {
        requestChild = latin1.decode(request.bodyBytes);
        authenticated = request.headers['authorization'] == 'Bearer synthetic-token';
        return jsonResponse({
          'screening_id': 55, 'predicted_class': 'inconclusive',
          'model_name': 'Synthetic_Model', 'confidence': 0.5,
          'autism_probability': 0.5,
        });
      }
      return http.Response('not found', 404);
    });
    final data = AppData.testing(
        api: ApiService(client: client, baseUrl: 'http://localhost:8000'), store: store);
    await data.signIn('synthetic@example.test', 'temporary-long-password', remember: true);
    expect(data.activeChildId, '42');
    final result = await data.submitScreening(
      modality: 'facial', filename: 'synthetic.png',
      bytes: Uint8List.fromList([137, 80, 78, 71]),
    );
    expect(result['screening_id'], 55);
    expect(authenticated, isTrue);
    expect(requestChild, contains('name="child_id"'));
    expect(requestChild, contains('42'));
  });

  test('appointment and medical requests target selected database child', () async {
    final calledPaths = <String>[];
    final client = MockClient((request) async {
      calledPaths.add('${request.method} ${request.url.path}');
      if (request.url.path == '/api/children/42/appointments' && request.method == 'POST') {
        expect(request.headers['authorization'], 'Bearer test-token');
        return jsonResponse({'appointment_id': 7}, 201);
      }
      if (request.url.path == '/api/children/42/medical-records' && request.method == 'POST') {
        expect(request.headers['authorization'], 'Bearer test-token');
        return jsonResponse({'record_id': 9}, 201);
      }
      return http.Response('not found', 404);
    });
    final api = ApiService(client: client, baseUrl: 'http://localhost:8000');
    await api.addAppointment('test-token', '42',
        scheduled: DateTime(2031, 5, 4, 15), location: 'Synthetic Provider');
    await api.uploadMedicalRecord('test-token', '42',
        filename: 'synthetic.pdf', bytes: Uint8List.fromList([37,80,68,70]),
        recordType: 'document');
    expect(calledPaths, contains('POST /api/children/42/appointments'));
    expect(calledPaths, contains('POST /api/children/42/medical-records'));
  });

}
