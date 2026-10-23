import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import 'session.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(ApiClient(ref.watch(bareDioProvider))));

/// Calls `/api/v1/auth/**`. Uses the bare Dio (no auth interceptor) so a failed
/// refresh can never trigger another refresh.
class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  Future<Session> login({
    required String? companyCode,
    required String emailOrMobile,
    required String password,
    required String deviceId,
  }) => _api.post(
    '/api/v1/auth/login',
    body: {
      if (companyCode != null && companyCode.isNotEmpty) 'companyCode': companyCode,
      'email': emailOrMobile,
      'password': password,
      'rememberMe': true,
      'deviceId': deviceId,
      'deviceName': 'Branch Operations (Android)',
    },
    parse: (d) => Session.fromLoginResponse(d! as Map<String, dynamic>),
  );

  /// Refresh tokens rotate: the returned session carries a new refresh token
  /// and the old one stops working.
  Future<Session> refresh(String refreshToken) => _api.post(
    '/api/v1/auth/refresh',
    body: {'refreshToken': refreshToken},
    parse: (d) => Session.fromLoginResponse(d! as Map<String, dynamic>),
  );

  Future<void> logout({required String refreshToken, String? accessToken}) => _api.post(
    '/api/v1/auth/logout',
    body: {'refreshToken': refreshToken, 'allDevices': false},
    options: accessToken == null ? null : Options(headers: {'Authorization': 'Bearer $accessToken'}),
    parse: (_) {},
  );
}
