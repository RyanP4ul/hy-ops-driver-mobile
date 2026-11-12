import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SessionStore {
  Future<String?> read();
  Future<void> write(String refreshToken);
  Future<void> clear();
}

abstract class SessionIdentityStore {
  Future<String?> readScope();
  Future<void> writeScope(String scope);
}

class SecureSessionStore implements SessionStore, SessionIdentityStore {
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  final String origin;
  SecureSessionStore(this.origin);
  @override
  Future<String?> readScope() async =>
      await _storage.read(key: 'refresh_origin') == origin
      ? _storage.read(key: 'driver_scope')
      : null;
  @override
  Future<void> writeScope(String scope) =>
      _storage.write(key: 'driver_scope', value: scope);
  @override
  Future<String?> read() async {
    if (await _storage.read(key: 'refresh_origin') != origin) return null;
    return _storage.read(key: 'refresh_token');
  }

  @override
  Future<void> write(String token) async {
    await _storage.write(key: 'refresh_origin', value: origin);
    await _storage.write(key: 'refresh_token', value: token);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
    await _storage.delete(key: 'refresh_origin');
    await _storage.delete(key: 'driver_scope');
  }
}
