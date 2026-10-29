import 'dart:convert';
import 'dart:typed_data';

import 'package:branch_ops/app.dart';
import 'package:branch_ops/core/network/api_client.dart';
import 'package:branch_ops/core/network/auth_interceptor.dart';
import 'package:branch_ops/core/storage/secure_store.dart';
import 'package:branch_ops/features/auth/application/auth_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

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
  List<String> roles = const ['BOOKING_OPERATOR'],
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
  'roles': roles,
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

/// Pumps the whole app signed in (saved refresh token) against [handler] and
/// returns its container. Unhandled paths answer `success` with null data.
Future<ProviderContainer> pumpSignedInApp(
  WidgetTester tester,
  FakeHandler handler, {
  List<String> permissions = const [
    'DASHBOARD_READ',
    'SHIPMENT_CREATE',
    'SHIPMENT_READ',
    'MANIFEST_CREATE',
    'MANIFEST_READ',
    'MANIFEST_DISPATCH',
  ],
  String branchId = 'branch-1',
  List<String> roles = const ['BOOKING_OPERATOR'],
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final adapter = FakeAdapter((r) async {
    if (r.path == '/api/v1/auth/refresh') {
      return (status: 200, body: ok(loginJson(permissions: permissions, branchId: branchId, roles: roles)));
    }
    return handler(r);
  });
  Dio dio() => Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adapter;
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        secureStoreProvider.overrideWithValue(MemoryStore()..values['refresh'] = 'saved'),
        bareDioProvider.overrideWith((ref) => dio()),
        dioProvider.overrideWith((ref) {
          final d = dio();
          d.interceptors.add(AuthInterceptor(d, () => ref.read(tokenSourceProvider)));
          return d;
        }),
        tokenSourceProvider.overrideWith((ref) => ref.watch(authControllerProvider.notifier)),
        ...overrides,
      ],
      child: const BranchOpsApp(),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(BranchOpsApp)));
}
