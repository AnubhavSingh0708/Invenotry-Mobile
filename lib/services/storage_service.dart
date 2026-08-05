import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static const _storage = FlutterSecureStorage();

  static const _kServerUrl = 'server_url';
  static const _kUsername = 'username';
  static const _kUserId = 'user_id';
  static const _kAuthKey = 'auth_key';
  static const _kIsAdmin = 'is_admin';

  static Future<void> saveSession({
    required String serverUrl,
    required String username,
    required String userId,
    required String authKey,
    required bool isAdmin,
  }) async {
    await _storage.write(key: _kServerUrl, value: serverUrl);
    await _storage.write(key: _kUsername, value: username);
    await _storage.write(key: _kUserId, value: userId);
    await _storage.write(key: _kAuthKey, value: authKey);
    await _storage.write(key: _kIsAdmin, value: isAdmin.toString());
  }

  static Future<Map<String, String?>> getSession() async {
    return {
      'serverUrl': await _storage.read(key: _kServerUrl),
      'username': await _storage.read(key: _kUsername),
      'userId': await _storage.read(key: _kUserId),
      'authKey': await _storage.read(key: _kAuthKey),
      'isAdmin': await _storage.read(key: _kIsAdmin),
    };
  }

  static Future<void> clearSession() async {
    await _storage.deleteAll();
  }
}