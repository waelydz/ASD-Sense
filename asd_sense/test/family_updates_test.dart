// Reviews, notifications and password reset in the guardian app, against a
// fake backend. Synthetic data only.
import 'dart:convert';

import 'package:asd_sense/data/app_data.dart';
import 'package:asd_sense/models/models.dart';
import 'package:asd_sense/services/api_service.dart';
import 'package:asd_sense/services/session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryStore implements SessionStore {
  String? token;
  @override
  Future<String?> readToken() async => token;
  @override
  Future<void> writeToken(String? value) async => token = value;
  @override
  Future<String?> readSelectedChild(int userId) async => null;
  @override
  Future<void> writeSelectedChild(int userId, String? id) async {}
}

http.Response json(Object payload, [int status = 200]) =>
    http.Response(jsonEncode(payload), status, headers: {'content-type': 'application/json'});

/// A backend with one guardian, one child and a review that arrives later.
class FakeBackend {
  bool pushOn = true;
  final notifications = <Map<String, dynamic>>[];
  Map<String, dynamic> screening = {
    'screening_id': 7, 'child_id': 1, 'screening_date': '2026-11-01 10:00:00',
    'model_name': 'Facial_MobileNetV2', 'predicted_class': 'autistic',
    'review_action': null, 'reviewer_name': null, 'reviewed_at': null,
  };
  final requests = <String>[];

  late final client = MockClient((request) async {
    final path = request.url.path;
    requests.add('${request.method} $path');
    switch (path) {
      case '/api/auth/login':
        return json({'access_token': 't', 'user': {'user_id': 1, 'full_name': 'G', 'email': 'g@example.test', 'phone': null, 'role': 'guardian'}});
      case '/api/children':
        return json([{'child_id': 1, 'first_name': 'Sam', 'last_name': null, 'date_of_birth': '2022-01-01'}]);
      case '/api/account/preferences':
        return json({'push_notifications': pushOn, 'email_notifications': false});
      case '/api/children/1/screenings':
        return json([screening]);
      case '/api/children/1/medical-records':
      case '/api/children/1/appointments':
        return json([]);
      case '/api/notifications':
        return json(notifications);
      case '/api/notifications/read':
        for (final n in notifications) {
          n['is_read'] = true;
        }
        return http.Response('', 204);
      case '/api/auth/forgot':
        return json({'ok': true});
      case '/api/auth/reset':
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return body['code'] == '123456' ? json({'ok': true}) : json({'detail': 'invalid'}, 400);
    }
    return json({'detail': 'unexpected $path'}, 404);
  });

  void clinicianReviews() {
    screening = {...screening, 'review_action': 'refer_diagnostic', 'reviewer_name': 'Dr Synthetic',
        'reviewed_at': '2026-11-02 09:00:00'};
    notifications.insert(0, {'notification_id': notifications.length + 1, 'child_id': 1,
        'title': 'Screening reviewed', 'body': "A clinician reviewed Sam's screening.",
        'created_at': '2026-11-02 09:00:00', 'is_read': false});
  }
}

Future<AppData> signedIn(FakeBackend backend) async {
  final data = AppData.testing(api: ApiService(client: backend.client, baseUrl: 'http://test'), store: MemoryStore());
  await data.signIn('g@example.test', 'password-123456', remember: false);
  return data;
}

void main() {
  test('a review that arrives while the app is open: banner, badge and next step', () async {
    final backend = FakeBackend();
    final data = await signedIn(backend);
    final banners = <AppNotification>[];
    data.onNotification = banners.add;

    expect(data.activeScreenings.single.isReviewed, isFalse);
    expect(data.activeScreenings.single.nextStep, 'Waiting for a clinician to review.');
    await data.refreshNotifications(); // first load: nothing new yet
    expect(banners, isEmpty);

    backend.clinicianReviews();
    await data.refreshNotifications();
    expect(banners.map((n) => n.title), ['Screening reviewed']);
    expect(data.unreadNotifications, 1);
    // The screening list was reloaded and shows the outcome, not a note.
    final s = data.activeScreenings.single;
    expect(s.isReviewed, isTrue);
    expect(s.reviewerName, 'Dr Synthetic');
    expect(s.nextStep, startsWith('A full developmental assessment is recommended'));

    await data.markNotificationsRead();
    expect(data.unreadNotifications, 0);
    expect(backend.requests, contains('POST /api/notifications/read'));
  });

  test('no banner when push notifications are off, but the update is still listed', () async {
    final backend = FakeBackend()..pushOn = false;
    final data = await signedIn(backend);
    final banners = <AppNotification>[];
    data.onNotification = banners.add;
    await data.refreshNotifications();
    backend.clinicianReviews();
    await data.refreshNotifications();
    expect(banners, isEmpty);
    expect(data.unreadNotifications, 1);
  });

  test('updates that came in while the app was closed get no banner', () async {
    final backend = FakeBackend()..clinicianReviews();
    final data = await signedIn(backend);
    final banners = <AppNotification>[];
    data.onNotification = banners.add;
    await data.refreshNotifications();
    expect(banners, isEmpty);
    expect(data.unreadNotifications, 1);
  });

  test('password reset: a wrong code gets a clear message', () async {
    final backend = FakeBackend();
    final data = AppData.testing(api: ApiService(client: backend.client, baseUrl: 'http://test'), store: MemoryStore());
    await data.requestPasswordReset(' g@example.test ');
    expect(backend.requests, contains('POST /api/auth/forgot'));
    await expectLater(
      data.resetPassword(email: 'g@example.test', code: '000000', newPassword: 'new-password-123'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('not valid or has expired'))),
    );
    await data.resetPassword(email: 'g@example.test', code: '123456', newPassword: 'new-password-123');
  });

  test('signing out stops the checks and forgets the updates', () async {
    final backend = FakeBackend()..clinicianReviews();
    final data = await signedIn(backend);
    await data.refreshNotifications();
    expect(data.notifications, isNotEmpty);
    await data.signOut();
    expect(data.notifications, isEmpty);
    final before = backend.requests.length;
    await data.refreshNotifications();
    expect(backend.requests.length, before, reason: 'no request without a session');
  });
}
