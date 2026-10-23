import 'package:branch_ops/app.dart';
import 'package:branch_ops/core/network/api_response.dart';
import 'package:branch_ops/core/network/auth_interceptor.dart';
import 'package:branch_ops/core/network/api_client.dart';
import 'package:branch_ops/core/storage/secure_store.dart';
import 'package:branch_ops/core/widgets/status_badge.dart';
import 'package:branch_ops/features/auth/application/auth_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  Widget app(FakeAdapter adapter, {MemoryStore? store}) {
    Dio dio() => Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adapter;
    return ProviderScope(
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
      child: const BranchOpsApp(),
    );
  }

  testWidgets('no saved session opens the login screen', (tester) async {
    await tester.pumpWidget(app(FakeAdapter((_) async => (status: 500, body: null))));
    await tester.pumpAndSettle();

    expect(find.text('Sign in with your branch account'), findsOneWidget);
  });

  testWidgets('login validates fields, then shows the server error', (tester) async {
    await tester.pumpWidget(app(FakeAdapter((_) async => (status: 401, body: errorBody('Invalid email or password')))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your company code'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Company code'), 'ACME');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email or mobile number'), 'a@b.test');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'wrong');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid email or password'), findsOneWidget);
  });

  testWidgets('saved session lands on the dashboard with permitted actions only', (tester) async {
    final store = MemoryStore()..values['refresh'] = 'saved';
    final adapter = FakeAdapter((r) async {
      if (r.path == '/api/v1/auth/refresh') return (status: 200, body: ok(loginJson()));
      if (r.path == '/api/v1/dashboard/summary') {
        return (
          status: 200,
          body: ok({
            'statistics': {'todayBookings': 12},
          }),
        );
      }
      return (status: 200, body: ok(<String, dynamic>{}));
    });

    await tester.pumpWidget(app(adapter, store: store));
    await tester.pumpAndSettle();

    expect(find.text('Test Couriers'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Book Shipment'), findsOneWidget);
    expect(find.text('Track Shipment'), findsOneWidget);
    expect(find.text('Generate THC'), findsNothing, reason: 'no MANIFEST_DISPATCH permission');
  });

  testWidgets('dashboard fits a small phone with large text', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final store = MemoryStore()..values['refresh'] = 'saved';
    final adapter = FakeAdapter(
      (r) async => r.path == '/api/v1/auth/refresh'
          ? (
              status: 200,
              body: ok(
                loginJson(
                  permissions: [
                    'SHIPMENT_CREATE',
                    'SHIPMENT_READ',
                    'MANIFEST_CREATE',
                    'MANIFEST_DISPATCH',
                    'DELIVERY_ASSIGN',
                    'DELIVERY_UPLOAD',
                  ],
                ),
              ),
            )
          : (status: 200, body: ok(<String, dynamic>{})),
    );

    await tester.pumpWidget(app(adapter, store: store));
    await tester.pumpAndSettle();

    expect(find.text('Upload POD'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account with no branch is stopped', (tester) async {
    final store = MemoryStore()..values['refresh'] = 'saved';
    await tester.pumpWidget(
      app(FakeAdapter((_) async => (status: 200, body: ok(loginJson(branchId: null)))), store: store),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('not assigned to a branch'), findsOneWidget);
  });

  test('status labels follow server values and do not guess unknown ones', () {
    expect(statusStyle('MANIFEST_CREATED').label, 'Loading Sheet Created');
    expect(statusStyle('SOMETHING_NEW').label, 'SOMETHING_NEW');
  });

  test('ApiResponse parses the courier-service envelope', () {
    final res = ApiResponse.fromJson({
      'success': false,
      'message': 'Invalid pincode',
      'errors': [
        {'field': 'deliveryPincode', 'message': 'not serviceable'},
      ],
    }, (d) => d);
    expect(res.success, isFalse);
    expect(res.errors.single.field, 'deliveryPincode');
  });
}
