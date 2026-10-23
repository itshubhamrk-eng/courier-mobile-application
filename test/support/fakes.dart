import 'dart:convert';
import 'dart:typed_data';

import 'package:branch_ops/core/network/api_client.dart';
import 'package:branch_ops/core/network/auth_interceptor.dart';
import 'package:branch_ops/core/storage/secure_store.dart';
import 'package:branch_ops/features/auth/application/auth_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// In-memory replacement for the device keystore.
class MemoryStore extends SecureStore {
  MemoryStore() : super(const FlutterSecureStorage());

  final values = <String, String>{};

  @override
  Future<String?> readRefreshToken() async => values['refresh'];

  @override
  Future<void> writeRefreshToken(String token) async => values['refresh'] = token;

  @override
  Future<void> clearRefreshToken() async => values.remove('refresh');

  @override
  Future<String?> readCompanyCode() async => values['company'];

  @override
  Future<void> writeCompanyCode(String? code) async =>
      code == null ? values.remove('company') : values['company'] = code;

  @override
  Future<String> deviceId() async => 'test-device';
}

typedef FakeResponse = ({int status, Object? body});
typedef FakeHandler = Future<FakeResponse> Function(RequestOptions request);

/// Answers Dio requests from a function; records every request it sees.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  FakeHandler handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final r = await handler(options);
    return ResponseBody.fromString(
      jsonEncode(r.body),
      r.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> ok(Object? data) => {'success': true, 'data': data};

Map<String, dynamic> errorBody(String message, {String code = 'ERROR'}) => {
  'success': false,
  'message': message,
  'errorCode': code,
};

Map<String, dynamic> loginJson({
  String access = 'access-1',
  String refresh = 'refresh-1',
  int expiresIn = 900,
  String? branchId = 'branch-1',
  List<String> permissions = const ['DASHBOARD_READ', 'SHIPMENT_CREATE', 'SHIPMENT_READ'],
}) => {
  'accessToken': access,
  'refreshToken': refresh,
  'tokenType': 'Bearer',
  'expiresIn': expiresIn,
  'refreshExpiresIn': 604800,
  'userId': 'user-1',
  'companyId': 'company-1',
  'email': 'clerk@example.test',
  'displayName': 'Test Clerk',
  'roles': ['BOOKING_OPERATOR'],
  'permissions': permissions,
  'branchId': branchId,
  'hubId': null,
  'companyName': 'Test Couriers',
};

/// A container wired like the app, with both Dio instances answering from [adapter].
ProviderContainer testContainer({required FakeAdapter adapter, MemoryStore? store}) {
  Dio dio() => Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adapter;
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      secureStoreProvider.overrideWithValue(store ?? MemoryStore()),
      bareDioProvider.overrideWith((ref) => dio()),
      dioProvider.overrideWith((ref) {
        final d = dio();
        d.interceptors.add(AuthInterceptor(d, () => ref.read(tokenSourceProvider)));
        return d;
      }),
      tokenSourceProvider.overrideWith((ref) => ref.watch(authControllerProvider.notifier)),
    ],
  );
  return container;
}

/// Waits until the auth controller leaves [AuthRestoring].
Future<AuthState> settledAuth(ProviderContainer c) async {
  c.read(authControllerProvider);
  for (var i = 0; i < 50; i++) {
    final s = c.read(authControllerProvider);
    if (s is! AuthRestoring) return s;
    await Future<void>.delayed(Duration.zero);
  }
  return c.read(authControllerProvider);
}
