import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore(const FlutterSecureStorage()));

/// Encrypted on-device storage. Only the refresh token is kept across restarts;
/// the access token lives in memory.
class SecureStore {
  SecureStore(this._storage);

  final FlutterSecureStorage _storage;

  static const _refreshToken = 'refresh_token';
  static const _companyCode = 'company_code';
  static const _deviceId = 'device_id';

  Future<String?> readRefreshToken() => _storage.read(key: _refreshToken);

  Future<void> writeRefreshToken(String token) => _storage.write(key: _refreshToken, value: token);

  Future<void> clearRefreshToken() => _storage.delete(key: _refreshToken);

  Future<String?> readCompanyCode() => _storage.read(key: _companyCode);

  Future<void> writeCompanyCode(String? code) => code == null || code.isEmpty
      ? _storage.delete(key: _companyCode)
      : _storage.write(key: _companyCode, value: code);

  /// Stable random ID for this install, shown in the server's device list.
  Future<String> deviceId() async {
    final existing = await _storage.read(key: _deviceId);
    if (existing != null) return existing;
    final random = Random.secure();
    final id = 'android-${List.generate(16, (_) => random.nextInt(16).toRadixString(16)).join()}';
    await _storage.write(key: _deviceId, value: id);
    return id;
  }
}
