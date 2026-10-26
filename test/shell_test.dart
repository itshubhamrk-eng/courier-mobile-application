import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  Future<FakeResponse> server(RequestOptions r) async => switch (r.path) {
    '/api/v1/branches/directory' => (
      status: 200,
      body: ok({
        'content': [
          {'id': 'branch-1', 'branchCode': 'PUN', 'branchName': 'Pune Shivajinagar', 'city': 'Pune'},
        ],
      }),
    ),
    '/api/v1/branch-wallet' => (status: 200, body: ok({'availableBalance': 12500.5, 'holdBalance': 0})),
    _ => (status: 200, body: ok(null)),
  };

  testWidgets('header shows company, branch and wallet balance', (tester) async {
    await pumpSignedInApp(tester, server);

    expect(find.text('Test Couriers'), findsWidgets);
    expect(find.text('Pune Shivajinagar, Pune'), findsWidgets);
    expect(find.text('₹12,500.50'), findsOneWidget);
    expect(find.text('More'), findsNothing, reason: 'More moved to the side menu');
  });

  testWidgets('side menu lists only permitted operations and signs out', (tester) async {
    await pumpSignedInApp(tester, server, permissions: const ['DASHBOARD_READ', 'SHIPMENT_READ']);

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();

    expect(find.text('Shipment Search'), findsWidgets);
    expect(find.text('Track Shipment'), findsOneWidget);
    expect(find.text('Shipment Booking'), findsNothing, reason: 'no SHIPMENT_CREATE');
    expect(find.text('Trip Hire Challan (THC)'), findsNothing);
    expect(find.text('Wallet balance'), findsOneWidget);
    expect(find.text('₹12,500.50'), findsWidgets);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with your branch account'), findsOneWidget);
  });

  testWidgets('wallet that cannot be read is hidden, header still works', (tester) async {
    await pumpSignedInApp(
      tester,
      (r) async => r.path == '/api/v1/branch-wallet' ? (status: 404, body: errorBody('No wallet')) : server(r),
    );
    expect(find.byIcon(Icons.account_balance_wallet_outlined), findsNothing);
    expect(find.text('Test Couriers'), findsWidgets);
  });
}
