import 'dart:async';
import 'dart:typed_data';

import 'package:branch_ops/core/network/api_client.dart';
import 'package:branch_ops/core/network/auth_interceptor.dart';
import 'package:branch_ops/core/storage/secure_store.dart';
import 'package:branch_ops/app.dart';
import 'package:branch_ops/features/auth/application/auth_controller.dart';
import 'package:branch_ops/features/pod/presentation/pod_page.dart';
import 'package:branch_ops/router.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Map<String, dynamic> _shipment({String status = 'OUT_FOR_DELIVERY'}) => {
  'id': 's1',
  'shipmentNumber': 'BK-1',
  'trackingNumber': 'AWB1',
  'status': status,
  'receiverName': 'Ravi Kumar',
  'receiverContact': '9123456780',
  'receiverAddress': 'MG Road',
};

/// Valid 1×1 PNG.
final _pngPixel = Uint8List.fromList(const [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, //
  137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 248, 255, 255, 63, 0, 5, 254, 2, 254, 167, 53, 129, 132, 0, 0, 0, //
  0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

class _Server {
  _Server({
    this.status = 'OUT_FOR_DELIVERY',
    this.existingPod,
    this.uploadTimesOut = false,
    this.deliverTimesOut = false,
    this.failTimesOut = false,
    this.failLands = true,
    List<Map<String, dynamic>>? attempts,
  }) : attempts = attempts ?? [];

  String status;
  Map<String, dynamic>? existingPod;
  final bool uploadTimesOut;
  final bool deliverTimesOut;
  final uploads = <RequestOptions>[];
  final delivers = <RequestOptions>[];
  final bool failTimesOut;

  /// With [failTimesOut]: whether the attempt was recorded before the answer was lost.
  final bool failLands;
  final List<Map<String, dynamic>> attempts;
  final fails = <RequestOptions>[];

  Future<FakeResponse> handle(RequestOptions r) async {
    switch (r.path) {
      case '/api/v1/auth/refresh':
        return (
          status: 200,
          body: ok(loginJson(permissions: ['SHIPMENT_READ', 'DELIVERY_UPLOAD', 'DELIVERY_DELIVER'])),
        );
      case '/api/v1/shipments/s1':
        return (status: 200, body: ok(_shipment(status: status)));
      case '/api/v1/shipments/track/AWB1':
        return (status: 200, body: ok(_shipment(status: status)));
      case '/api/v1/shipments/s1/pod/verification':
        return existingPod == null ? (status: 404, body: errorBody('No POD')) : (status: 200, body: ok(existingPod));
      case '/api/v1/shipments/s1/pod/verify':
        uploads.add(r);
        existingPod = {'id': 'pod-${uploads.length}', 'verificationStatus': 'PENDING'};
        if (uploadTimesOut) throw DioException(requestOptions: r, type: DioExceptionType.receiveTimeout);
        return (status: 200, body: ok(existingPod));
      case '/api/v1/shipment-movement/deliver':
        delivers.add(r);
        status = 'DELIVERED';
        if (deliverTimesOut) throw DioException(requestOptions: r, type: DioExceptionType.receiveTimeout);
        return (status: 200, body: ok(_shipment(status: 'DELIVERED')));
      case '/api/v1/shipments/s1/delivery-attempts':
        return (status: 200, body: ok(attempts));
      case '/api/v1/shipments/s1/history':
        return (status: 200, body: ok(<Object>[]));
      case '/api/v1/shipment-movement/s1/delivery-failed':
        fails.add(r);
        final body = r.data as Map;
        final n = attempts.length + 1;
        final attempt = _attempt(n, body['reason'] as String, remarks: body['remarks'] as String?);
        if (!failTimesOut || failLands) {
          attempts.add(attempt);
          status = n >= 3 ? 'RETURNED' : 'IN_SCAN';
        }
        if (failTimesOut) throw DioException(requestOptions: r, type: DioExceptionType.receiveTimeout);
        return (status: 200, body: ok(attempt));
      default:
        return (status: 200, body: ok(null));
    }
  }
}

Map<String, dynamic> _attempt(int n, String reason, {String? remarks}) => {
  'id': 'att-$n',
  'shipmentId': 's1',
  'attemptNo': n,
  'maxAttempts': 3,
  'reason': reason,
  'remarks': remarks,
  'outcome': n >= 3 ? 'RTO' : 'RETRY',
  'drsNumber': 'DRS-7',
  'attemptedAt': '2026-10-23T10:15:00Z',
};

Future<void> _failWith(WidgetTester tester, String reason, {String? remarks}) async {
  await tester.ensureVisible(find.text('Could not deliver?'));
  await tester.tap(find.text('Could not deliver?'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(reason));
  await tester.pumpAndSettle();
  if (remarks != null) await tester.enterText(find.byType(TextField).last, remarks);
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, _Server server, {String route = '/pod?shipmentId=s1'}) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final adapter = FakeAdapter(server.handle);
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
        // A tiny JPEG stand-in instead of opening the camera.
        podImagePickerProvider.overrideWithValue((_) async => _pngPixel),
      ],
      child: const BranchOpsApp(),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(tester.element(find.byType(BranchOpsApp)));
  unawaited(container.read(routerProvider).push(route));
  await tester.pumpAndSettle();
}

Future<void> _complete(WidgetTester tester) async {
  await tester.tap(find.text('Complete delivery'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Complete'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shipment not out for delivery cannot get a POD', (tester) async {
    await _open(tester, _Server(status: 'IN_SCAN'));
    expect(find.textContaining('POD is only for shipments out for delivery'), findsOneWidget);
  });

  testWidgets('fresh POD: photo, upload with fields, then server closes the delivery', (tester) async {
    final server = _Server();
    await _open(tester, server);

    expect(find.text('Complete delivery'), findsNothing, reason: 'no POD yet');
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload POD'));
    await tester.pumpAndSettle();

    expect(server.uploads, hasLength(1));
    final form = server.uploads.single.data as FormData;
    final fields = Map.fromEntries(form.fields);
    expect(fields['receiverName'], 'Ravi Kumar');
    expect(fields['awbNumber'], 'AWB1');
    expect(form.files.map((f) => f.key), ['photo'], reason: 'no signature drawn');
    expect(find.text('POD uploaded, waiting for company review'), findsOneWidget);

    await _complete(tester);
    expect(server.delivers, hasLength(1));
    expect((server.delivers.single.data as Map)['receiverName'], 'Ravi Kumar');
    expect(find.text('Delivered'), findsOneWidget, reason: 'status badge from the server response');
  });

  testWidgets('existing POD is reused, no second upload', (tester) async {
    final server = _Server(existingPod: {'id': 'pod-0', 'verificationStatus': 'PENDING'});
    await _open(tester, server);

    expect(find.text('POD uploaded, waiting for company review'), findsOneWidget);
    await _complete(tester);
    expect(server.uploads, isEmpty);
    expect(server.delivers, hasLength(1));
  });

  testWidgets('upload answer lost but POD landed: not uploaded twice', (tester) async {
    final server = _Server(uploadTimesOut: true);
    await _open(tester, server);

    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload POD'));
    await tester.pumpAndSettle();

    expect(server.uploads, hasLength(1));
    expect(find.text('Complete delivery'), findsOneWidget);
  });

  testWidgets('rejected POD asks for a new photo', (tester) async {
    final server = _Server(existingPod: {'id': 'pod-0', 'verificationStatus': 'FAIL', 'reviewRemarks': 'Blurry'});
    await _open(tester, server);

    expect(find.textContaining('Previous POD was rejected: Blurry'), findsOneWidget);
    expect(find.text('Complete delivery'), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('deliver answer lost: reads status back, shows delivered once', (tester) async {
    final server = _Server(existingPod: {'id': 'pod-0', 'verificationStatus': 'PASS'}, deliverTimesOut: true);
    await _open(tester, server);

    await _complete(tester);
    expect(server.delivers, hasLength(1));
    expect(find.text('Delivered'), findsOneWidget);
    expect(find.textContaining('confirmed by the server'), findsOneWidget);
  });

  testWidgets('search by AWB from the POD screen', (tester) async {
    await _open(tester, _Server(), route: '/pod');
    await tester.enterText(find.widgetWithText(TextField, 'AWB of the delivered shipment'), 'AWB1');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Take photo'), findsOneWidget);
  });

  group('failed delivery', () {
    testWidgets('OTHER needs remarks; attempt 1 goes back for the next DRS', (tester) async {
      final server = _Server();
      await _open(tester, server);

      await _failWith(tester, 'Other');
      expect(find.text('Add remarks for "Other".'), findsOneWidget);
      expect(server.fails, isEmpty);

      await tester.enterText(find.byType(TextField).last, 'Gate locked');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Record failed delivery?'), findsOneWidget, reason: 'confirm before recording');
      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();

      expect(server.fails, hasLength(1));
      expect(server.fails.single.data, {'reason': 'OTHER', 'remarks': 'Gate locked'});
      expect(find.text('Attempt 1 of 3 recorded'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Proof of Delivery'), findsNothing, reason: 'POD screen closes, nothing left to do');
    });

    testWidgets('cancel at confirm records nothing', (tester) async {
      final server = _Server();
      await _open(tester, server);
      await _failWith(tester, 'Customer refused');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(server.fails, isEmpty);
    });

    testWidgets('third attempt returns the shipment to origin', (tester) async {
      final server = _Server(attempts: [_attempt(1, 'CUSTOMER_UNAVAILABLE'), _attempt(2, 'ADDRESS_NOT_FOUND')]);
      await _open(tester, server);
      await _failWith(tester, 'Customer refused');
      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();

      expect(server.fails.single.data, {'reason': 'CUSTOMER_REFUSED', 'remarks': null});
      expect(find.text('Returned to origin'), findsOneWidget);
      expect(find.textContaining('after 3 failed attempts'), findsOneWidget);
    });

    testWidgets('answer lost and not recorded: says not confirmed, no auto-retry', (tester) async {
      final server = _Server(failTimesOut: true, failLands: false);
      await _open(tester, server);
      await _failWith(tester, 'Payment not ready');
      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();

      expect(server.fails, hasLength(1));
      expect(find.text('Not confirmed'), findsOneWidget);
      expect(find.textContaining('check its delivery attempts before trying again'), findsOneWidget);
    });

    testWidgets('answer lost but recorded: reads attempts back, shows the result once', (tester) async {
      final server = _Server(failTimesOut: true);
      await _open(tester, server);
      await _failWith(tester, 'Customer asked to reschedule');
      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();

      expect(server.fails, hasLength(1));
      expect(find.text('Attempt 1 of 3 recorded'), findsOneWidget);
      expect(find.text('Not confirmed'), findsNothing);
    });
  });

  testWidgets('shipment detail lists delivery attempts from the server', (tester) async {
    final server = _Server(
      status: 'RETURNED',
      attempts: [
        _attempt(1, 'CUSTOMER_UNAVAILABLE'),
        _attempt(2, 'OTHER', remarks: 'Shop closed'),
        _attempt(3, 'CUSTOMER_REFUSED'),
      ],
    );
    await _open(tester, server, route: '/shipments/s1');

    await tester.scrollUntilVisible(find.text('Delivery attempts'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Attempt 1 of 3: Customer not available'), findsOneWidget);
    expect(find.text('Attempt 2 of 3: Other'), findsOneWidget);
    expect(find.textContaining('Shop closed'), findsOneWidget);
    expect(find.text('Attempt 3 of 3: Customer refused'), findsOneWidget);
    expect(find.textContaining('Returned to origin'), findsOneWidget);
  });
}
