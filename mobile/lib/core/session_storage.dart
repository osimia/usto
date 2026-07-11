import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the refresh token across app restarts, so the user isn't forced
/// to log in again every time they reopen the app. Only the refresh token is
/// stored - restoring a session always exchanges it for a brand-new access
/// token via POST /auth/refresh, so there's nothing else worth keeping at
/// rest.
class SessionStorage {
  SessionStorage() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _refreshTokenKey = 'usto_refresh_token';

  Future<void> saveRefreshToken(String refreshToken) {
    return _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  Future<String?> readRefreshToken() {
    return _storage.read(key: _refreshTokenKey);
  }

  Future<void> clear() {
    return _storage.delete(key: _refreshTokenKey);
  }
}
