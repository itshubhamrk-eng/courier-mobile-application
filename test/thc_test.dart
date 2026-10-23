import 'dart:async';

import 'package:branch_ops/core/network/api_client.dart';
import 'package:branch_ops/features/thc/data/thc_repository.dart';
import 'package:branch_ops/router.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Map<String, dynamic> _sheet({String status = 'CREATED', String from = 'branch-1'}) => {
  'id': 'm1',
  'manifestNumber': 'LS-1',
  'status': status,
  'bookingBranchId': from,
  'deliveryBranchId': 'b2',
  'shipmentCount': 2,
  'totalPackages': 3,
  'totalWeight': 14.5,
  'vehicleId': status == 'CREATED' ? null : 'v1',
  'driverUserId': status == 'CREATED' ? null : 'u1',
};

Map<String, dynamic> _ship(String id, String awb) => {
  'id': id,
  'shipmentNumber': 'BK-$id',
  'trackingNumber': awb,
  'status': 'MANIFEST_CREATED',
};

void main() {
  test('dispatch sends the trip fields and UTC departure time', () async {
    final adapter = FakeAdapter(
      (r) async => (status: 200, body: ok({'manifestId': 'm1', 'manifestNumber': 'LS-1', 'status': 'DISPATCHED'})),
    );
    final repo = ThcRepository(ApiClient(Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adapter));

    final r = await repo.dispatch(
      manifestId: 'm1',
      vehicleId: 'v1',
      driverUserId: 'u1',
      departureTime: DateTime.utc(2026, 10, 24, 9, 30),
      fuelCost: 500,
    );

    final body = adapter.requests.single.data as Map<String, dynamic>;
    expect(adapter.requests.single.path, '/api/v1/shipment-movement/dispatch');
    expect(body['departureTime'], '2026-10-24T09:30:00.000Z');
    expect(body['fuelCost'], 500);
    expect(body['tollAmount'], isNull);
    expect(r.number, 'LS-1', reason: 'THC number is the loading sheet number');
  });

  Future<List<RequestOptions>> run(
    WidgetTester tester, {
    String sheetStatus = 'CREATED',
    bool fromHub = false,
    bool timeout = false,
  }) async {
    final dispatches = <RequestOptions>[];
    final outScans = <RequestOptions>[];
    var dispatched = false;
    final container = await pumpSignedInApp(tester, (r) async {
      switch (r.path) {
        case '/api/v1/branches/directory':
          return (
            status: 200,
            body: ok({
              'content': [
                {'id': 'branch-1', 'branchCode': 'PUN', 'branchName': 'Pune', 'branchType': fromHub ? 'HUB' : 'BRANCH'},
                {'id': 'b2', 'branchCode': 'SAT', 'branchName': 'Satara', 'branchType': 'BRANCH'},
              ],
            }),
          );
        case '/api/v1/manifests/m1':
          return (status: 200, body: ok(_sheet(status: dispatched ? 'DISPATCHED' : sheetStatus)));
        case '/api/v1/manifests/m1/shipments':
          return (status: 200, body: ok([_ship('s1', 'AWB1'), _ship('s2', 'AWB2')]));
        case '/api/v1/vehicles':
          return (
            status: 200,
            body: ok([
              {'id': 'v1', 'vehicleNumber': 'MH12AB1234', 'vehicleType': 'TRUCK'},
            ]),
          );
        case '/api/v1/users':
          return (
            status: 200,
            body: ok({
              'content': [
                {'id': 'u1', 'displayName': 'Driver Dev', 'mobile': '9000000001', 'branchId': 'branch-1'},
              ],
            }),
          );
        case '/api/v1/hub-operations/out-scan':
          outScans.add(r);
          final awb = ((r.data as Map)['trackingNumbers'] as List).single;
          return (
            status: 200,
            body: ok([
              {'reference': awb, 'success': true},
            ]),
          );
        case '/api/v1/shipment-movement/dispatch':
          dispatches.add(r);
          dispatched = true;
          if (timeout) throw DioException(requestOptions: r, type: DioExceptionType.receiveTimeout);
          return (
            status: 200,
            body: ok({
              'manifestId': 'm1',
              'manifestNumber': 'LS-1',
              'status': 'DISPATCHED',
              'vehicleId': 'v1',
              'driverUserId': 'u1',
              'shipmentCount': 2,
            }),
          );
        default:
          return (status: 200, body: ok(null));
      }
    });
    unawaited(container.read(routerProvider).push('/thc?manifestId=m1'));
    await tester.pumpAndSettle();
    if (sheetStatus != 'CREATED') return dispatches;

    if (fromHub) {
      expect(find.text('0 of 2 scanned on this phone'), findsOneWidget);
      for (final awb in ['AWB1', 'AWB2']) {
        await tester.enterText(find.widgetWithText(TextField, 'Scan or type AWB'), awb);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
      }
      expect(find.text('2 of 2 scanned on this phone'), findsOneWidget);
      expect(outScans, hasLength(2));
      expect((outScans.first.data as Map)['hubBranchId'], 'branch-1');
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    } else {
      expect(find.textContaining('Out-scan'), findsNothing);
    }

    await tester.tap(find.text('Vehicle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MH12AB1234 · truck').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick driver'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Driver Dev'));
    await tester.pumpAndSettle();

    // The app bar title says "Generate THC" too; target the button by its icon.
    final button = find.byIcon(Icons.receipt_long_outlined);
    await tester.dragUntilVisible(button, find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();
    return dispatches;
  }

  testWidgets('branch sheet: pick vehicle and driver, generate once, show THC', (tester) async {
    final dispatches = await run(tester);
    expect(dispatches, hasLength(1));
    expect((dispatches.single.data as Map)['vehicleId'], 'v1');
    expect(find.text('THC generated'), findsOneWidget);
    expect(find.text('LS-1'), findsWidgets);
  });

  testWidgets('hub sheet: out-scan each AWB before generating', (tester) async {
    final dispatches = await run(tester, fromHub: true);
    expect(dispatches, hasLength(1));
    expect(find.text('THC generated'), findsOneWidget);
  });

  testWidgets('lost answer: reads the sheet back and shows the THC instead of retrying', (tester) async {
    final dispatches = await run(tester, timeout: true);
    expect(dispatches, hasLength(1));
    expect(find.text('THC generated'), findsOneWidget);
  });

  testWidgets('already dispatched sheet shows its THC, no second form', (tester) async {
    await run(tester, sheetStatus: 'DISPATCHED');
    expect(find.textContaining('already has a THC'), findsOneWidget);
    expect(find.text('Pick driver'), findsNothing);
  });
}
