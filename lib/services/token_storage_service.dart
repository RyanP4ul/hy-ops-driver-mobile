import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _storage = FlutterSecureStorage();

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: 'access_token', value: accessToken);
    await _storage.write(key: 'refresh_token', value: refreshToken);
  }

  static Future<String?> getAccessToken() {
    return _storage.read(key: 'access_token');
  }

  static Future<String?> getRefreshToken() {
    return _storage.read(key: 'refresh_token');
  }

  static Future<void> saveRefreshToken(String token) =>
      _storage.write(key: 'refresh_token', value: token);

  static Future<void> clearTokens() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }
}
