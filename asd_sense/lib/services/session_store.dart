import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persist tokens in platform-provided secure storage, never in SharedPreferences.
abstract class SessionStore {
  Future<String?> readToken();
  Future<void> writeToken(String? token);
  Future<String?> readSelectedChild(int userId);
  Future<void> writeSelectedChild(int userId, String? childId);
}

class SecureSessionStore implements SessionStore {
  final FlutterSecureStorage _storage;

  SecureSessionStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'asd_sense_access_token';
  String _childKey(int userId) => 'asd_sense_active_child_$userId';

  @override
  Future<String?> readToken() => _storage.read(key: _tokenKey);

  @override
  Future<void> writeToken(String? token) async {
    if (token == null) {
      await _storage.delete(key: _tokenKey);
    } else {
      await _storage.write(key: _tokenKey, value: token);
    }
  }

  @override
  Future<String?> readSelectedChild(int userId) =>
      _storage.read(key: _childKey(userId));

  @override
  Future<void> writeSelectedChild(int userId, String? childId) async {
    if (childId == null) {
      await _storage.delete(key: _childKey(userId));
    } else {
      await _storage.write(key: _childKey(userId), value: childId);
    }
  }
}
