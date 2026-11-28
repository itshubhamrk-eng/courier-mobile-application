import 'dart:async';

import 'package:branch_ops/router.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _perms = [
  'DASHBOARD_READ',
  'SHIPMENT_READ',
  'SHIPMENT_CREATE',
  'MANIFEST_READ',
  'MANIFEST_CREATE',
  'MANIFEST_DISPATCH',
  'MANIFEST_RECEIVE',
  'DELIVERY_ASSIGN',
];

Map<String, dynamic> _pickup(String id, String status, {int? parcels}) => {
  'id': id,
  'pickupNo': 'PU-$id',
  'status': status,
  'contactName': 'Patil Agro',
  'contactMobile': '+91 98220 11111',
  'addressLine': 'Plot 7, MIDC',
  'city': 'Kolhapur',
  'pincode': '416001',
  'expectedParcels': 2,
  'expectedWeightKg': 12,
  'actualParcels': ?parcels,
  if (parcels != null) 'actualWeightKg': 11.5,
};

void main() {
  late List<RequestOptions> actions;

  FakeHandler server({String type = 'PICKUP_DELIVERY_PARTNER'}) {
    actions = [];
    return (r) async {
      if (r.path.startsWith('/api/v1/pickups/') && r.method == 'PATCH') {
        actions.add(r);
        return (status: 200, body: ok(_pickup('1', 'ACCEPTED')));
      }
      return switch (r.path) {
        '/api/v1/branches/directory' => (
          status: 200,
          body: ok({
            'content': [
              {'id': 'branch-1', 'branchCode': 'V-KOP', 'branchName': 'Kolhapur Vendor', 'branchType': type},
            ],
          }),
        ),
        '/api/v1/pdp-dashboard' => (
          status: 200,
          body: ok({
            'pickups': {'open': 3, 'pickedUpThisMonth': 9},
            'deliveries': {'atPartner': 4, 'outForDelivery': 2, 'podPending': 1, 'deliveredThisMonth': 21},
            'earnings': {'earnedThisMonth': 2450},
            'statements': {'outstandingPayable': 1800, 'paidThisMonth': 600},
          }),
        ),
        '/api/v1/pickups' => (
          status: 200,
          body: ok({
            'content': [_pickup('1', 'ASSIGNED'), _pickup('2', 'OUT_FOR_PICKUP'), _pickup('3', 'BOOKED', parcels: 2)],
          }),
        ),
        _ => (status: 200, body: ok(null)),
      };
    };
  }

  testWidgets('vendor login: own dashboard, Pickups tab, no manifest creation or finalization', (t) async {
    await pumpSignedInApp(t, server(), roles: const ['BRANCH_MANAGER'], permissions: _perms);

    expect(find.text('₹2,450.00'), findsOneWidget, reason: 'earned this month');
    expect(find.text('Open pickups'), findsOneWidget);
    expect(find.textContaining('1 new pickup(s) waiting'), findsOneWidget);
    expect(find.text('Pickups'), findsWidgets);
    expect(find.text('Manifests'), findsNothing);

    await t.tap(find.byTooltip('Menu'));
    await t.pumpAndSettle();
    expect(find.text('Pickup Requests'), findsOneWidget);
    expect(find.text('Earnings & Billing'), findsOneWidget);
    expect(find.text('Manifest Creation'), findsNothing);
    expect(find.text('Manifest Finalization'), findsNothing);
    expect(find.text('Manifest In Scan'), findsOneWidget, reason: 'vendors receive manifests sent to them');
    expect(find.text('Generate DRS'), findsWidgets);
  });

  testWidgets('branch login is unchanged', (t) async {
    await pumpSignedInApp(
      t,
      server(type: 'BRANCH'),
      roles: const ['BRANCH_MANAGER'],
      permissions: _perms,
    );
    expect(find.text('Manifests'), findsOneWidget);
    expect(find.text('Pickups'), findsNothing);
  });

  testWidgets('pickups: accept, reject needs a reason, collected sends parcels and weight', (t) async {
    final c = await pumpSignedInApp(t, server(), roles: const ['BRANCH_MANAGER'], permissions: _perms);
    unawaited(c.read(routerProvider).push('/pickups'));
    await t.pumpAndSettle();

    expect(find.text('PU-1'), findsOneWidget);
    expect(find.text('PU-3'), findsNothing, reason: 'booked ones are under Done');

    await t.tap(find.text('Accept'));
    await t.pumpAndSettle();
    expect(actions.single.path, '/api/v1/pickups/1/accept');
    expect(find.text('Pickup accepted'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();

    await t.tap(find.text('Reject'));
    await t.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, 'Reject');
    expect(t.widget<FilledButton>(confirm).onPressed, isNull, reason: 'no reason yet');
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();

    await t.tap(find.text('Collected'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextFormField, 'Total weight (kg)'), '11.5');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(actions.last.path, '/api/v1/pickups/2/complete');
    expect(actions.last.data, {'actualParcels': 2, 'actualWeightKg': 11.5});
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();

    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(
      find.text(
        'Booked as'
        ' PU-3',
      ),
      findsNothing,
    );
    expect(find.text('PU-3'), findsOneWidget);
  });
}
