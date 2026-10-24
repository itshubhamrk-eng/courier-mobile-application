import 'package:branch_ops/core/network/api_client.dart';
import 'package:branch_ops/core/scan_code.dart';
import 'package:branch_ops/core/network/api_exception.dart';
import 'package:branch_ops/features/shipments/data/shipment_models.dart';
import 'package:branch_ops/features/shipments/data/shipment_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  ShipmentRepository repo(FakeAdapter a) =>
      ShipmentRepository(ApiClient(Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = a));

  test('AWB lookup is URL-encoded and unknown AWB is a not-found error', () async {
    final adapter = FakeAdapter((_) async => (status: 404, body: errorBody('Shipment not found')));

    await expectLater(
      repo(adapter).byAwb(' AB/12 '),
      throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.notFound)),
    );
    expect(adapter.requests.first.uri.path, '/api/v1/shipments/track/AB%2F12');
  });

  test('view loads history newest first and tolerates missing optional sections', () async {
    final adapter = FakeAdapter((r) async {
      return switch (r.path) {
        '/api/v1/shipments/s1/history' => (
          status: 200,
          body: ok([
            {'status': 'BOOKED', 'changedAt': '2026-10-20T08:00:00Z', 'branchId': 'b1'},
            {'status': 'DISPATCHED', 'changedAt': '2026-10-21T08:00:00Z', 'branchId': 'b1'},
          ]),
        ),
        '/api/v1/hub-operations/exceptions' => (
          status: 200,
          body: ok({
            'content': [
              {'exceptionType': 'ON_HOLD', 'status': 'OPEN', 'raisedAt': '2026-10-22T08:00:00Z'},
            ],
          }),
        ),
        '/api/v1/shipments/s1/charges' => (status: 403, body: errorBody('Forbidden')),
        '/api/v1/shipments/s1/delivery-run' => (status: 200, body: ok(null)),
        _ => (status: 500, body: errorBody('unexpected ${r.path}')),
      };
    });
    const shipment = ShipmentDetail(
      id: 's1',
      shipmentNumber: 'BK1',
      trackingNumber: 'AWB1',
      status: 'DISPATCHED',
      raw: {},
    );

    final view = await repo(adapter).view(shipment, withCharges: true);

    expect(view.history.map((h) => h.status), ['DISPATCHED', 'BOOKED']);
    expect(view.exceptions.single.type, 'ON_HOLD');
    expect(view.charges, isNull, reason: 'no permission is not an error for the screen');
    expect(view.deliveryRun, isNull);
    expect(
      adapter.requests.any((r) => r.path.endsWith('/pod/verification')),
      isFalse,
      reason: 'POD only for delivered shipments',
    );
  });

  test('charges keep server lines and net amount, discount shown negative', () {
    final c = Charges.fromJson({
      'freight': 400,
      'fuelCharge': 0,
      'gstAmount': 72,
      'discountAmount': 10,
      'applicableChargeLines': [
        {'chargeName': 'Hamali', 'amount': 30},
      ],
      'netAmount': 492,
    });

    expect(c.lines.map((l) => (l.label, l.amount)), [('Freight', 400), ('Hamali', 30), ('GST', 72), ('Discount', -10)]);
    expect(c.netAmount, 492);
  });

  test('label package id resolves to its AWB', () async {
    expect(scanCandidates('AL10041-002'), ['AL10041-002', 'AL10041']);
    expect(scanCandidates('AL10041'), ['AL10041']);
    expect(matchesScan(trackingNumber: 'AL10041', shipmentNumber: 'X', raw: 'al10041-001'), isTrue);

    final adapter = FakeAdapter(
      (r) async => r.path.endsWith('/AL10041')
          ? (
              status: 200,
              body: ok({'id': 's1', 'trackingNumber': 'AL10041', 'shipmentNumber': 'B1', 'status': 'BOOKED'}),
            )
          : (status: 404, body: errorBody('not found')),
    );
    final s = await repo(adapter).byAwb('AL10041-003');
    expect(s.trackingNumber, 'AL10041');
    expect(adapter.requests.map((r) => r.path.split('/').last), ['AL10041-003', 'AL10041']);
  });

  test('QR with a shipment number is found through the shipment search', () async {
    final adapter = FakeAdapter((r) async {
      if (r.path.startsWith('/api/v1/shipments/track/')) return (status: 404, body: errorBody('not found'));
      if (r.path == '/api/v1/shipments') {
        return (
          status: 200,
          body: ok({
            'content': [
              {'id': 's-other', 'shipmentNumber': 'PUN-26-10411', 'trackingNumber': 'AL9', 'status': 'BOOKED'},
              {'id': 's7', 'shipmentNumber': 'PUN-26-1041', 'trackingNumber': 'AL10041', 'status': 'BOOKED'},
            ],
          }),
        );
      }
      if (r.path == '/api/v1/shipments/s7') {
        return (
          status: 200,
          body: ok({'id': 's7', 'shipmentNumber': 'PUN-26-1041', 'trackingNumber': 'AL10041', 'status': 'BOOKED'}),
        );
      }
      return (status: 500, body: errorBody('unexpected ${r.path}'));
    });

    final s = await repo(adapter).byAwb('pun-26-1041');

    expect(s.trackingNumber, 'AL10041', reason: 'exact shipment number match, not the similar one');
    expect(adapter.requests.firstWhere((r) => r.path == '/api/v1/shipments').queryParameters['search'], 'pun-26-1041');
  });

  test('unknown value is still not found after the search', () async {
    final adapter = FakeAdapter(
      (r) async => r.path == '/api/v1/shipments'
          ? (status: 200, body: ok({'content': <Object>[]}))
          : (status: 404, body: errorBody('Shipment not found')),
    );
    await expectLater(
      repo(adapter).byAwb('NOPE-1'),
      throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.notFound)),
    );
  });

  test('tracking link in a QR resolves to its number', () {
    expect(scanCandidates('https://courier.skra.in/track/AL10041'), ['AL10041']);
    expect(scanCandidates('https://courier.skra.in/track/AL10041-002'), ['AL10041-002', 'AL10041']);
  });

  test('view collects documents and every loading sheet / THC the shipment was on', () async {
    final adapter = FakeAdapter((r) async {
      return switch (r.path) {
        '/api/v1/shipments/s1/history' => (
          status: 200,
          body: ok([
            {'status': 'MANIFEST_CREATED', 'changedAt': '2026-10-20T08:00:00Z', 'manifestId': 'm1'},
            {'status': 'DISPATCHED', 'changedAt': '2026-10-20T10:00:00Z', 'manifestId': 'm1'},
            {'status': 'MANIFEST_CREATED', 'changedAt': '2026-10-21T08:00:00Z', 'manifestId': 'm2'},
          ]),
        ),
        '/api/v1/manifests/m1' => (
          status: 200,
          body: ok({'id': 'm1', 'manifestNumber': 'LS-1', 'status': 'COMPLETED', 'createdAt': '2026-10-20T08:00:00Z'}),
        ),
        '/api/v1/manifests/m2' => (
          status: 200,
          body: ok({'id': 'm2', 'manifestNumber': 'LS-2', 'status': 'CREATED', 'createdAt': '2026-10-21T08:00:00Z'}),
        ),
        '/api/v1/shipments/s1/documents' => (
          status: 200,
          body: ok([
            {'documentType': 'INVOICE', 'documentName': null, 'documentUrl': 'https://files.test/inv.pdf'},
          ]),
        ),
        _ => (status: 200, body: ok(null)),
      };
    });
    const shipment = ShipmentDetail(
      id: 's1',
      shipmentNumber: 'B1',
      trackingNumber: 'AWB1',
      status: 'MANIFEST_CREATED',
      raw: {
        'manifestId': 'm2',
        'shipmentImageUrl': 'https://files.test/photo.jpg',
        'ewayBill': {'ewayBillNumber': '1811', 'documentUrl': 'https://files.test/eway.pdf'},
      },
    );

    final view = await repo(adapter).view(shipment, withCharges: false);

    expect(view.sheets.map((s) => s.number), ['LS-2', 'LS-1'], reason: 'newest first, each once');
    expect(view.sheets.last.isOpen, isFalse, reason: 'dispatched sheet is shown as the THC');
    expect(view.files.map((f) => f.label), ['Invoice', 'E-Way Bill 1811', 'Shipment photo']);
    expect(view.files.last.isImage, isTrue);
    expect(adapter.requests.where((r) => r.path == '/api/v1/manifests/m2'), hasLength(1));
  });
}
