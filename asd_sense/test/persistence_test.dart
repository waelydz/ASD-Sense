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

void main() {
  test('profile creation uses SQLite child ID and survives AppData recreation', () async {
    final store = FakeSessionStore();
    final records = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      final path = request.url.path;
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

  test('non-remembered session does not auto-restore on restart', () async {
    final store = FakeSessionStore();
    final client = MockClient((request) async {
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
}
