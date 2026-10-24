import 'dart:async';

import 'package:branch_ops/core/network/api_client.dart';
import 'package:branch_ops/features/drs/data/drs_repository.dart';
import 'package:branch_ops/features/drs/presentation/drs_widgets.dart';
import 'package:branch_ops/features/masters/data/masters.dart';
import 'package:branch_ops/router.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _perms = [
  'DASHBOARD_READ',
  'SHIPMENT_READ',
  'MANIFEST_READ',
  'MANIFEST_RECEIVE',
  'DELIVERY_ASSIGN',
  'DELIVERY_READ',
];

final _paymentModes = ok({
  'content': [
    {'id': 'paid', 'code': 'PAID', 'name': 'Paid'},
    {'id': 'cod', 'code': 'COD', 'name': 'Cash on delivery', 'cashOnDelivery': true, 'collectAtDelivery': true},
    {'id': 'topay', 'code': 'TOPAY', 'name': 'To pay', 'collectAtDelivery': true},
  ],
});

void main() {
  test('collect label follows the payment mode flags', () {
    const modes = [
      Option(id: 'paid', code: 'PAID', name: 'Paid'),
      Option(id: 'cod', code: 'COD', name: 'COD', flags: {'cashOnDelivery': true, 'collectAtDelivery': true}),
      Option(id: 'topay', code: 'TOPAY', name: 'To pay', flags: {'collectAtDelivery': true}),
    ];
    expect(collectLabel('paid', 100, modes), isNull);
    expect(collectLabel('cod', 250, modes), 'Collect ₹250.00 (COD)');
    expect(collectLabel('topay', 99.5, modes), 'Collect ₹99.50 (To-Pay)');
    expect(collectLabel('unknown', 1, modes), isNull);
  });

  group('requests', () {
    late FakeAdapter adapter;
    late DrsRepository repo;
    setUp(() {
      adapter = FakeAdapter((_) async => (status: 200, body: ok({'content': <Object>[], 'results': <Object>[]})));
      repo = DrsRepository(ApiClient(Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adapter));
    });

    test('branch DRS lists received shipments for this delivery branch', () async {
      await repo.readyForDelivery('b1', DrsSource.branch);
      final q = adapter.requests.single.queryParameters;
      expect(q['deliveryBranchId'], 'b1');
      expect(q['status'], 'IN_SCAN');
    });

    test('hub direct lists unrouted shipments at the hub', () async {
      await repo.readyForDelivery('hub', DrsSource.hubDirect);
      final q = adapter.requests.single.queryParameters;
      expect(q['currentLocationId'], 'hub');
      expect(q['unassignedDeliveryBranch'], true);
      expect(q['status'], 'READY_FOR_MANIFEST');
    });
  });

  testWidgets('receive: scan one of two, the other is reported missing', (tester) async {
    RequestOptions? inScan;
    final container = await pumpSignedInApp(tester, permissions: _perms, (r) async {
      return switch (r.path) {
        '/api/v1/manifests/m1' => (
          status: 200,
          body: ok({'id': 'm1', 'manifestNumber': 'THC-1', 'status': 'DISPATCHED', 'bookingBranchId': 'b0'}),
        ),
        '/api/v1/manifests/m1/shipments' => (
          status: 200,
          body: ok([
            {'id': 's1', 'shipmentNumber': 'B1', 'trackingNumber': 'AWB1', 'status': 'DISPATCHED'},
            {'id': 's2', 'shipmentNumber': 'B2', 'trackingNumber': 'AWB2', 'status': 'DISPATCHED'},
          ]),
        ),
        '/api/v1/shipment-movement/in-scan' => () {
          inScan = r;
          return (
            status: 200,
            body: ok({
              'results': [
                {'reference': 'AWB1', 'success': true},
              ],
              'successCount': 1,
              'failureCount': 0,
              'shortageTicketNumber': 'TKT-9',
            }),
          );
        }(),
        _ => (status: 200, body: ok(null)),
      };
    });
    unawaited(container.read(routerProvider).push('/receive/m1'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Scan or type AWB received'), 'AWB1');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 received'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm receipt'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 will be reported missing'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    final body = inScan!.data as Map<String, dynamic>;
    expect(body['trackingNumbers'], ['AWB1']);
    expect(body['missingTrackingNumbers'], ['AWB2']);
    expect(body['manifestNumber'], 'THC-1');
    expect(find.textContaining('TKT-9'), findsOneWidget);
  });

  testWidgets('new DRS: partner, select all, generate, refused shipment listed', (tester) async {
    final calls = <RequestOptions>[];
    final container = await pumpSignedInApp(tester, permissions: _perms, (r) async {
      return switch (r.path) {
        '/api/v1/shipments' => (
          status: 200,
          body: ok({
            'content': [
              {
                'id': 's1',
                'shipmentNumber': 'B1',
                'trackingNumber': 'AWB1',
                'status': 'IN_SCAN',
                'receiverName': 'Ravi',
                'paymentModeId': 'cod',
                'netAmount': 250,
              },
              {
                'id': 's2',
                'shipmentNumber': 'B2',
                'trackingNumber': 'AWB2',
                'status': 'IN_SCAN',
                'receiverName': 'Asha',
              },
            ],
          }),
        ),
        '/api/v1/master/payment-modes' => (status: 200, body: _paymentModes),
        '/api/v1/users' => (
          status: 200,
          body: ok({
            'content': [
              {'id': 'u9', 'displayName': 'Partner Pat', 'mobile': '9000000009'},
            ],
          }),
        ),
        '/api/v1/vehicles' => (status: 200, body: ok(<Object>[])),
        '/api/v1/shipment-movement/out-for-delivery' => () {
          calls.add(r);
          return (
            status: 200,
            body: ok({
              'drsNumber': 'DRS-77',
              'successCount': 1,
              'failureCount': 1,
              'results': [
                {'reference': 'B1', 'success': true},
                {'reference': 'B2', 'success': false, 'message': 'Not at this branch'},
              ],
            }),
          );
        }(),
        _ => (status: 200, body: ok(null)),
      };
    });
    unawaited(container.read(routerProvider).push('/drs/new'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Collect ₹250.00 (COD)'), findsOneWidget);
    await tester.tap(find.text('Pick delivery partner'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Partner Pat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate DRS (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();

    expect(calls, hasLength(1));
    final body = calls.single.data as Map<String, dynamic>;
    expect(body['deliveryUserId'], 'u9');
    expect(body['shipmentIds'], ['s1', 's2']);
    expect(find.text('DRS-77'), findsOneWidget);
    expect(find.text('Not at this branch'), findsOneWidget);
  });

  testWidgets('run view: status tabs and COD amount from the server rows', (tester) async {
    final container = await pumpSignedInApp(tester, permissions: _perms, (r) async {
      return switch (r.path) {
        '/api/v1/shipment-movement/drs/detail' => (
          status: 200,
          body: ok({
            'drsNumber': 'DRS-77',
            'shipments': [
              {
                'shipmentId': 's1',
                'trackingNumber': 'AWB1',
                'status': 'OUT_FOR_DELIVERY',
                'receiverName': 'Ravi',
                'receiverAddress': 'MG Road',
                'receiverContact': '9123456780',
                'paymentModeId': 'cod',
                'netAmount': 250,
              },
              {'shipmentId': 's2', 'trackingNumber': 'AWB2', 'status': 'DELIVERED', 'receiverName': 'Asha'},
              {'shipmentId': 's3', 'trackingNumber': 'AWB3', 'status': 'IN_SCAN', 'receiverName': 'Kiran'},
            ],
          }),
        ),
        '/api/v1/master/payment-modes' => (status: 200, body: _paymentModes),
        _ => (status: 200, body: ok(null)),
      };
    });
    unawaited(container.read(routerProvider).push('/drs/run?user=u9&branch=branch-1&date=2026-10-23'));
    await tester.pumpAndSettle();

    expect(find.text('DRS-77'), findsOneWidget);
    expect(find.text('Pending (1)'), findsOneWidget);
    expect(find.text('Delivered (1)'), findsOneWidget);
    expect(find.text('Not delivered (1)'), findsOneWidget);
    expect(find.text('Collect ₹250.00 (COD)'), findsOneWidget);
    expect(find.text('Navigate'), findsOneWidget);
    expect(find.text('Could not deliver'), findsNothing, reason: 'needs DELIVERY_DELIVER or DELIVERY_UPLOAD');
  });

  test('run summary reads failedCount', () {
    final run = DrsRun.fromJson({
      'deliveryUserId': 'u9',
      'deliveryBranchId': 'b1',
      'runDate': '2026-10-23',
      'shipmentCount': 5,
      'deliveredCount': 2,
      'pendingCount': 1,
      'failedCount': 2,
    });
    expect(run.failedCount, 2);
    expect(DrsRun.fromJson({'deliveryUserId': 'u', 'deliveryBranchId': 'b', 'runDate': '2026-10-23'}).failedCount, 0);
  });

  testWidgets('run view: failed delivery from an out-for-delivery row, then reloads', (tester) async {
    var status = 'OUT_FOR_DELIVERY';
    final fails = <RequestOptions>[];
    final container = await pumpSignedInApp(tester, permissions: [..._perms, 'DELIVERY_DELIVER'], (r) async {
      return switch (r.path) {
        '/api/v1/shipment-movement/drs/detail' => (
          status: 200,
          body: ok({
            'drsNumber': 'DRS-77',
            'shipments': [
              {'shipmentId': 's1', 'trackingNumber': 'AWB1', 'status': status, 'receiverName': 'Ravi'},
              {'shipmentId': 's2', 'trackingNumber': 'AWB2', 'status': 'DELIVERED', 'receiverName': 'Asha'},
            ],
          }),
        ),
        '/api/v1/shipments/s1/delivery-attempts' => (status: 200, body: ok(<Object>[])),
        '/api/v1/shipment-movement/s1/delivery-failed' => () {
          fails.add(r);
          status = 'IN_SCAN';
          return (
            status: 200,
            body: ok({'attemptNo': 1, 'maxAttempts': 3, 'reason': 'ADDRESS_NOT_FOUND', 'outcome': 'RETRY'}),
          );
        }(),
        '/api/v1/master/payment-modes' => (status: 200, body: _paymentModes),
        _ => (status: 200, body: ok(null)),
      };
    });
    unawaited(container.read(routerProvider).push('/drs/run?user=u9&branch=branch-1&date=2026-10-23'));
    await tester.pumpAndSettle();

    expect(find.text('Could not deliver'), findsOneWidget, reason: 'only on the out-for-delivery row');
    await tester.tap(find.text('Could not deliver'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Address not found'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();

    expect(fails.single.data, {'reason': 'ADDRESS_NOT_FOUND', 'remarks': null});
    expect(find.text('Attempt 1 of 3 recorded'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Pending (0)'), findsOneWidget, reason: 'run reloaded from the server');
    expect(find.text('Could not deliver'), findsNothing);
  });
}
