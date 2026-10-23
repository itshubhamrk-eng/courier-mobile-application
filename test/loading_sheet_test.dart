import 'dart:async';

import 'package:branch_ops/core/network/api_client.dart';
import 'package:branch_ops/features/loading_sheet/data/loading_sheet_repository.dart';
import 'package:branch_ops/features/shipments/data/shipment_models.dart';
import 'package:branch_ops/router.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

ShipmentSummary _s({
  String status = 'BOOKED',
  String? at = 'branch-1',
  String? next,
  String? delivery,
  String? manifestId,
}) => ShipmentSummary(
  id: 'x',
  shipmentNumber: 'S',
  trackingNumber: 'A',
  status: status,
  currentLocationId: at,
  nextLocationId: next,
  deliveryBranchId: delivery,
  manifestId: manifestId,
);

Map<String, dynamic> _shipmentJson(String id, String awb, {int pkg = 1, num weight = 5}) => {
  'id': id,
  'shipmentNumber': 'BK-$id',
  'trackingNumber': awb,
  'status': 'BOOKED',
  'currentLocationId': 'branch-1',
  'numberOfPackages': pkg,
  'chargeableWeight': weight,
  'fromCity': 'Pune',
  'toCity': 'Satara',
};

void main() {
  group('eligibility check after scan', () {
    const b = 'branch-1';
    test('unrouted booked shipment at this branch can go to a hub', () {
      expect(loadingIneligibility(_s(), branchId: b, mode: LoadingMode.hub), isNull);
    });
    test('already on a sheet', () {
      expect(
        loadingIneligibility(
          _s(status: 'MANIFEST_CREATED', manifestId: 'm1'),
          branchId: b,
          mode: LoadingMode.hub,
        ),
        'Already on a loading sheet.',
      );
    });
    test('at another branch', () {
      expect(
        loadingIneligibility(
          _s(at: 'other'),
          branchId: b,
          mode: LoadingMode.branch,
        ),
        'Not at your branch.',
      );
    });
    test('routed shipment must use next stop, and match it', () {
      expect(
        loadingIneligibility(
          _s(next: 'b9'),
          branchId: b,
          mode: LoadingMode.hub,
        ),
        contains('Next stop'),
      );
      expect(
        loadingIneligibility(
          _s(next: 'b9'),
          branchId: b,
          mode: LoadingMode.nextStop,
          destinationId: 'b9',
        ),
        isNull,
      );
      expect(
        loadingIneligibility(
          _s(next: 'b9'),
          branchId: b,
          mode: LoadingMode.nextStop,
          destinationId: 'b7',
        ),
        'Headed to a different branch.',
      );
    });
  });

  group('requests', () {
    late FakeAdapter adapter;
    late LoadingSheetRepository repo;
    setUp(() {
      adapter = FakeAdapter(
        (r) async => (
          status: 200,
          body: ok(
            r.method == 'POST' ? {'id': 'm1', 'manifestNumber': 'LS-1', 'status': 'CREATED'} : {'content': <Object>[]},
          ),
        ),
      );
      repo = LoadingSheetRepository(
        ApiClient(Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adapter),
      );
    });

    test('hub and branch modes ask only for unrouted shipments at this branch', () async {
      await repo.eligible(branchId: 'branch-1', mode: LoadingMode.hub);
      final q = adapter.requests.single.queryParameters;
      expect(q['currentLocationId'], 'branch-1');
      expect(q['unassignedDeliveryBranch'], true);
      expect(q['status'], ['BOOKED', 'READY_FOR_MANIFEST']);
    });

    test('next-stop mode filters by the next location', () async {
      await repo.eligible(branchId: 'hub-1', mode: LoadingMode.nextStop, nextLocationId: 'b9');
      final q = adapter.requests.single.queryParameters;
      expect(q['nextLocationId'], 'b9');
      expect(q.containsKey('unassignedDeliveryBranch'), isFalse);
    });

    test('create marks hub transfers', () async {
      await repo.create(branchId: 'branch-1', destinationId: 'hub-1', mode: LoadingMode.hub, shipmentIds: ['s1']);
      final body = adapter.requests.single.data as Map<String, dynamic>;
      expect(body['hubTransfer'], true);
      expect(body['deliveryMode'], 'BRANCH_DELIVERY');
      expect(body['shipmentIds'], ['s1']);
    });
  });

  testWidgets('new sheet: assigned hub preselected, scan adds, totals, create once', (tester) async {
    final creates = <RequestOptions>[];
    final container = await pumpSignedInApp(tester, (r) async {
      switch (r.path) {
        case '/api/v1/branches/directory':
          return (
            status: 200,
            body: ok({
              'content': [
                {
                  'id': 'branch-1',
                  'branchCode': 'PUN',
                  'branchName': 'Pune',
                  'branchType': 'BRANCH',
                  'assignedHubId': 'hub-1',
                },
                {'id': 'hub-1', 'branchCode': 'HUB', 'branchName': 'Central Hub', 'branchType': 'HUB'},
              ],
            }),
          );
        case '/api/v1/shipments':
          return (
            status: 200,
            body: ok({
              'content': [
                _shipmentJson('s1', 'AWB1', pkg: 2, weight: 10),
                _shipmentJson('s2', 'AWB2', pkg: 1, weight: 4.5),
              ],
            }),
          );
        case '/api/v1/shipments/track/AWB9':
          return (status: 200, body: ok({..._shipmentJson('s9', 'AWB9'), 'currentLocationId': 'elsewhere'}));
        case '/api/v1/manifests' when r.method == 'POST':
          creates.add(r);
          return (
            status: 201,
            body: ok({'id': 'm1', 'manifestNumber': 'LS-1', 'status': 'CREATED', 'shipmentCount': 2}),
          );
        case '/api/v1/manifests/m1':
          return (
            status: 200,
            body: ok({'id': 'm1', 'manifestNumber': 'LS-1', 'status': 'CREATED', 'shipmentCount': 2}),
          );
        case '/api/v1/manifests/m1/shipments':
          return (status: 200, body: ok([_shipmentJson('s1', 'AWB1'), _shipmentJson('s2', 'AWB2')]));
        default:
          return (status: 200, body: ok(null));
      }
    });
    unawaited(container.read(routerProvider).push('/loading-sheets/new'));
    await tester.pumpAndSettle();

    expect(find.text('Central Hub'), findsOneWidget, reason: 'assigned hub preselected');
    expect(find.text('Eligible shipments (2)'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Scan or type AWB to add'), 'AWB2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('AWB2 added.'), findsOneWidget);
    expect(find.text('4.5 kg'), findsWidgets);

    await tester.enterText(find.widgetWithText(TextField, 'Scan or type AWB to add'), 'AWB9');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('AWB9 cannot be loaded: Not at your branch.'), findsOneWidget);

    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(find.text('14.5 kg'), findsOneWidget, reason: 'total weight of both');

    // Let the message snackbar (it floats over the action bar) time out first.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create loading sheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(creates, hasLength(1));
    expect((creates.single.data as Map)['shipmentIds'], ['s1', 's2']);
    expect(find.text('LS-1'), findsWidgets, reason: 'opens the new sheet');
    expect(find.text('Generate THC'), findsOneWidget);
  });
}
