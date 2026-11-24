import 'dart:async';

import 'package:branch_ops/features/quick_scan/data/package_tally.dart';
import 'package:branch_ops/router.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Map<String, dynamic> _shipment({String status = 'DISPATCHED', String next = 'branch-1', int qty = 10}) => {
  'id': 's1',
  'shipmentNumber': 'PUN-26-1035',
  'trackingNumber': 'AWB100',
  'status': status,
  'numberOfPackages': qty,
  'nextLocationId': next,
  'deliveryBranchId': next,
  'manifestId': 'm1',
  'receiverName': 'Sai Medicals',
  'fromCity': 'Kolhapur',
  'toCity': 'Pune',
};

const _branchPerms = ['DASHBOARD_READ', 'SHIPMENT_READ', 'MANIFEST_READ', 'MANIFEST_RECEIVE'];
const _hubPerms = [..._branchPerms, 'HUB_IN_SCAN', 'HUB_OUT_SCAN', 'HUB_EXCEPTION_MANAGE'];

void main() {
  group('package tally', () {
    PackageTally tally(int qty) => PackageTally(trackingNumber: 'AWB100', shipmentNumber: 'PUN-26-103', quantity: qty);

    test('each label counts once; shipment codes and other shipments do not count', () {
      final t = tally(3);
      expect(t.scan('AWB100-001'), ScanAck.added);
      expect(t.scan('awb100-001'), ScanAck.duplicate);
      expect(t.scan('AWB100-004'), ScanAck.outOfRange);
      expect(t.scan('AWB100-000'), ScanAck.outOfRange);
      expect(t.scan('AWB100'), ScanAck.needsPackage);
      expect(t.scan('PUN-26-103'), ScanAck.needsPackage, reason: 'looks like a package id but is the shipment number');
      expect(t.scan('AWB999-002'), ScanAck.wrongShipment);
      expect(t.scan('2'), ScanAck.wrongShipment, reason: 'a bare number only counts when typed');
      expect(t.scan('2', typed: true), ScanAck.added);
      expect(t.missingIds, ['AWB100-003']);
      expect(t.scan('https://x.test/track/AWB100-003'), ScanAck.added);
      expect(t.complete, isTrue);
    });

    test('a single package counts from any code of the shipment', () {
      expect(tally(1).scan('AWB100'), ScanAck.added);
      expect(tally(1).scan('PUN-26-103'), ScanAck.added);
      expect(tally(0).quantity, 1);
    });
  });

  group('screen', () {
    late List<RequestOptions> inScans;
    late List<RequestOptions> outScans;
    late List<RequestOptions> exceptions;

    FakeHandler server(
      Map<String, dynamic> shipment, {
      Map<String, dynamic> inResult = const {
        'results': [
          {'reference': 'AWB100', 'success': true},
        ],
        'successCount': 1,
        'failureCount': 0,
      },
      List<Map<String, dynamic>> outResult = const [
        {'reference': 'AWB100', 'success': true},
      ],
      int exceptionStatus = 200,
    }) {
      inScans = [];
      outScans = [];
      exceptions = [];
      return (r) async {
        if (r.path.startsWith('/api/v1/shipments/track/')) return (status: 200, body: ok(shipment));
        switch (r.path) {
          case '/api/v1/manifests/m1':
            return (
              status: 200,
              body: ok({'id': 'm1', 'manifestNumber': 'LS-1', 'status': 'CREATED', 'bookingBranchId': 'branch-1'}),
            );
          case '/api/v1/shipment-movement/in-scan':
            inScans.add(r);
            return (status: 200, body: ok(inResult));
          case '/api/v1/hub-operations/out-scan':
            outScans.add(r);
            return (status: 200, body: ok(outResult));
          case '/api/v1/hub-operations/exceptions':
            exceptions.add(r);
            return exceptionStatus == 200
                ? (status: 200, body: ok({'id': 'e1'}))
                : (status: exceptionStatus, body: errorBody('Not now'));
          default:
            return (status: 200, body: ok(null));
        }
      };
    }

    Future<void> open(WidgetTester t, FakeHandler h, String route, {List<String> perms = _branchPerms}) async {
      final c = await pumpSignedInApp(t, h, permissions: perms);
      unawaited(c.read(routerProvider).push(route));
      await t.pumpAndSettle();
    }

    Future<void> type(WidgetTester t, String v) async {
      await t.enterText(find.byType(TextField).first, v);
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
    }

    Future<void> scanUpTo(WidgetTester t, int n) async {
      for (var i = 1; i <= n; i++) {
        await type(t, 'AWB100-${i.toString().padLeft(3, '0')}');
      }
    }

    Future<void> submit(WidgetTester t, String label) async {
      await t.tap(find.widgetWithText(FilledButton, label).last);
      await t.pumpAndSettle();
    }

    for (final (who, perms, out) in [('branch', _branchPerms, findsNothing), ('hub', _hubPerms, findsOneWidget)]) {
      testWidgets('dashboard quick actions for $who staff', (t) async {
        await pumpSignedInApp(t, (r) async => (status: 200, body: ok(<String, dynamic>{})), permissions: perms);
        expect(find.text('Quick In-scan'), findsOneWidget);
        expect(find.text('Quick Out-scan'), out, reason: 'the server allows out-scan to hub staff only');
      });
    }

    testWidgets('scanning a label opens the shipment, counts it; all scanned in-scans without a popup', (t) async {
      await open(t, server(_shipment(qty: 2)), '/quick-scan/in');
      await type(t, 'AWB100-001');
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text('2 packages'), findsOneWidget);
      await type(t, 'AWB100-002');
      await submit(t, 'In-scan');

      expect(find.text('Short shipment received'), findsNothing);
      expect(inScans, hasLength(1));
      final body = inScans.single.data as Map;
      expect(body['receivingBranchId'], 'branch-1');
      expect(body['trackingNumbers'], ['AWB100']);
      expect(body['manifestNumber'], 'LS-1');
      expect(body['missingTrackingNumbers'], isEmpty);
      expect(body.containsKey('remarks'), isFalse);
      expect(find.text('In-scan done'), findsOneWidget);
    });

    testWidgets('8 of 10: popup, note, and the shortage goes with the in-scan for branch staff', (t) async {
      await open(
        t,
        server(
          _shipment(),
          inResult: {
            'results': [
              {'reference': 'AWB100', 'success': true},
            ],
            'successCount': 1,
            'failureCount': 0,
            'shortageTicketNumber': 'TKT-9',
          },
        ),
        '/quick-scan/in',
      );
      await scanUpTo(t, 8);
      await submit(t, 'In-scan');
      expect(find.text('Short shipment received'), findsOneWidget);
      expect(find.text('8 of 10 packages scanned.'), findsOneWidget);
      expect(find.text('Missing: package 9-10'), findsOneWidget);
      expect(inScans, isEmpty, reason: 'nothing saved before confirming');

      await t.tap(find.text('Keep scanning'));
      await t.pumpAndSettle();
      expect(inScans, isEmpty);

      await submit(t, 'In-scan');
      await t.enterText(find.byType(TextField).last, 'Torn bag');
      await submit(t, 'In-scan short');

      final body = inScans.single.data as Map;
      expect(body['missingTrackingNumbers'], ['AWB100-009', 'AWB100-010']);
      expect(body['remarks'], 'Short shipment received: 8 of 10. Missing package 9-10. Note: Torn bag');
      expect(exceptions, isEmpty, reason: 'no permission: the ticket covers it');
      expect(find.text('In-scan done, short'), findsOneWidget);
      expect(find.text('TKT-9'), findsOneWidget);
    });

    testWidgets('hub staff: short in-scan records one SHORT exception, not a second ticket', (t) async {
      await open(t, server(_shipment()), '/quick-scan/in', perms: _hubPerms);
      await scanUpTo(t, 3);
      await submit(t, 'In-scan');
      await submit(t, 'In-scan short');

      expect((inScans.single.data as Map)['missingTrackingNumbers'], isEmpty);
      final body = exceptions.single.data as Map;
      expect(body['exceptionType'], 'SHORT');
      expect(body['shipmentId'], 's1');
      expect(body['remarks'], 'Short shipment received: 3 of 10. Missing package 4-10.');
      expect(find.text('Short exception recorded.'), findsOneWidget);
    });

    testWidgets('short out-scan: popup, out-scan, exception; a failed note is retried without a second out-scan', (
      t,
    ) async {
      await open(
        t,
        server(_shipment(status: 'MANIFEST_CREATED', next: 'branch-2'), exceptionStatus: 500),
        '/quick-scan/out',
        perms: _hubPerms,
      );
      await scanUpTo(t, 8);
      await submit(t, 'Out-scan');
      expect(find.text('Short shipment out-scan'), findsOneWidget);
      await submit(t, 'Out-scan short');

      final body = outScans.single.data as Map;
      expect(body['manifestId'], 'm1');
      expect(body['hubBranchId'], 'branch-1');
      expect(body['trackingNumbers'], ['AWB100']);
      expect(exceptions, hasLength(1));
      expect(find.textContaining('The scan is saved, but the short note is not'), findsOneWidget);
      await t.ensureVisible(find.text('Save note again'));
      await t.tap(find.text('Save note again'));
      await t.pumpAndSettle();
      expect(exceptions, hasLength(2));
      expect(outScans, hasLength(1));
    });

    testWidgets('a short out-scan needs the exception permission', (t) async {
      await open(
        t,
        server(_shipment(status: 'MANIFEST_CREATED')),
        '/quick-scan/out',
        perms: const [..._branchPerms, 'HUB_OUT_SCAN'],
      );
      await scanUpTo(t, 2);
      await submit(t, 'Out-scan');
      expect(outScans, isEmpty);
      expect(find.textContaining('cannot record a short out-scan'), findsOneWidget);
    });

    testWidgets('server refusal is shown and the scans are kept', (t) async {
      await open(
        t,
        server(
          _shipment(qty: 1),
          inResult: {
            'results': [
              {'reference': 'AWB100', 'success': false, 'message': 'Receiving branch does not match.'},
            ],
            'successCount': 0,
            'failureCount': 1,
          },
        ),
        '/quick-scan/in',
      );
      await type(t, 'AWB100');
      await submit(t, 'In-scan');
      expect(find.text('Receiving branch does not match.'), findsOneWidget);
      expect(find.text('In-scan failed'), findsOneWidget);
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(find.text('1 / 1'), findsOneWidget);
    });

    testWidgets('already received or another branch: explained and no scanning', (t) async {
      await open(t, server(_shipment(status: 'IN_SCAN')), '/quick-scan/in');
      await type(t, 'PUN-26-1035');
      expect(find.textContaining('Only dispatched shipments can be received'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'In-scan'), findsNothing);
    });

    testWidgets('shipment for another branch cannot be in-scanned', (t) async {
      await open(t, server(_shipment(next: 'branch-9')), '/quick-scan/in');
      await type(t, 'AWB100-001');
      expect(find.textContaining('not your branch'), findsOneWidget);
    });
  });
}
