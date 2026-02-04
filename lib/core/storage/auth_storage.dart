import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _keyAccessToken = 'access_token';
const _keyRefreshToken = 'refresh_token';
const _keyUserId = 'user_id';

class AuthStorage {
  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  Future<void> saveTokens({required String accessToken, required String refreshToken, String? userId}) async {
    await _storage.write(key: _keyAccessToken, value: accessToken);
    await _storage.write(key: _keyRefreshToken, value: refreshToken);
    if (userId != null) await _storage.write(key: _keyUserId, value: userId);
  }

  Future<String?> getAccessToken() => _storage.read(key: _keyAccessToken);
  Future<String?> getRefreshToken() => _storage.read(key: _keyRefreshToken);
  Future<String?> getUserId() => _storage.read(key: _keyUserId);

  Future<void> clear() async {
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyRefreshToken);
    await _storage.delete(key: _keyUserId);
  }
}
