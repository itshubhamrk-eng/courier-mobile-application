import 'dart:async';

import 'package:branch_ops/app.dart';
import 'package:branch_ops/core/network/api_client.dart';
import 'package:branch_ops/core/network/auth_interceptor.dart';
import 'package:branch_ops/core/storage/secure_store.dart';
import 'package:branch_ops/features/auth/application/auth_controller.dart';
import 'package:branch_ops/features/booking/application/booking_draft.dart';
import 'package:branch_ops/features/booking/data/booking_repository.dart';
import 'package:branch_ops/router.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _ready = BookingDraft(
  senderName: 'Asha Traders',
  senderContact: '9876543210',
  senderAddress: '12 Market Road, Pune',
  receiverName: 'Ravi Kumar',
  receiverContact: '9123456780',
  receiverAddress: '4 Station Road, Satara',
  pickupPincode: '411001',
  deliveryPincode: '415001',
  items: [ItemDraft(name: 'Carton', quantity: 2, weight: 10, length: 40, width: 30, height: 30, declaredValue: 1500)],
  serviceTypeId: 'svc-1',
  paymentModeId: 'pay-1',
);

void main() {
  group('server preview mapping', () {
    test('maps weights, charge lines, net amount and warnings as sent', () {
      final p = BookingPreview.fromJson({
        'actualWeight': 10,
        'volumetricWeight': 14.4,
        'chargeableWeight': 14.4,
        'destinationCityName': 'Satara',
        'weightSlabLabel': '10-20 kg',
        'ratePerKg': 30,
        'ewayBillRequired': true,
        'walletSufficient': false,
        'walletAvailable': 100,
        'charges': {
          'freight': 432,
          'fuelCharge': 20,
          'applicableChargeLines': [
            {'chargeName': 'Hamali', 'amount': 15},
          ],
          'gstAmount': 84.06,
          'roundOff': -0.06,
          'netAmount': 551,
        },
      });
      expect(p.chargeableWeight, 14.4);
      expect(p.slab, '10-20 kg');
      expect(p.charges.lines.map((l) => l.label), ['Freight', 'Fuel', 'Hamali']);
      expect(p.charges.adjustments.map((l) => l.label), ['GST', 'Round off']);
      expect(p.charges.netAmount, 551, reason: 'net amount from the server, never summed in the app');
      expect(p.ewayBillRequired, isTrue);
      expect(p.walletSufficient, isFalse);
      expect(p.walletAvailable, 100);
    });

    test('walletSufficient stays null when the mode does not collect at booking', () {
      final p = BookingPreview.fromJson({
        'charges': {'netAmount': 1},
      });
      expect(p.walletSufficient, isNull);
      expect(p.ewayBillRequired, isFalse);
    });
  });

  group('create request', () {
    test('carries the inputs only, never a price or AWB', () {
      final body = _ready.toCreateRequest('branch-1');

      expect(body['bookingBranchId'], 'branch-1');
      expect(body['numberOfPackages'], 2, reason: 'defaults to item quantity total');
      expect(body['declaredValue'], 1500);
      expect(body['deliveryType'], 'DOOR');
      expect((body['items'] as List).single['quantity'], 2);
      for (final k in ['netAmount', 'freight', 'trackingNumber', 'chargeableWeight']) {
        expect(body.containsKey(k), isFalse, reason: '$k must come from the server');
      }
      expect(body.containsKey('ewayBill'), isFalse);
    });

    test('extra charges are sent for the server to price; door charge only for door delivery', () {
      final d = _ready.copyWith(
        otherCharges: 50,
        odaChargeOverride: 120,
        doorDeliveryCharge: 40,
        insuranceApplicable: true,
        appointmentDelivery: true,
        appointmentDate: DateTime(2026, 10, 30),
        appointmentTimeSlot: ' 10 AM - 1 PM ',
        appointmentDeliveryCharge: 75,
      );
      final body = d.toCreateRequest('b');
      expect(body['otherCharges'], 50);
      expect(body['odaCharge'], 120);
      expect(body['doorDeliveryCharge'], 40);
      expect(body['insuranceApplicable'], true);
      expect(body['appointmentDate'], '2026-10-30');
      expect(body['appointmentTimeSlot'], '10 AM - 1 PM');
      expect(body['appointmentDeliveryCharge'], 75);
      expect(d.copyWith(deliveryType: 'OFFICE').toCreateRequest('b')['doorDeliveryCharge'], isNull);
      expect(d.copyWith(appointmentDelivery: false).toCreateRequest('b')['appointmentDeliveryCharge'], isNull);
      expect(d.hasExtraCharges, isTrue);
      expect(_ready.hasExtraCharges, isFalse);
    });

    test('two or more packages: count is the total quantity and invoice value the sum of declared values', () {
      final d = _ready.copyWith(
        numberOfPackages: 9,
        invoiceValue: 1,
        items: [
          const ItemDraft(quantity: 2, weight: 4, declaredValue: 1500),
          const ItemDraft(quantity: 3, weight: 6, declaredValue: 2500),
        ],
      );
      final body = d.toCreateRequest('b');
      expect(d.multiPackage, isTrue);
      expect(body['numberOfPackages'], 5, reason: 'typed count ignored');
      expect(body['invoiceValue'], 4000, reason: 'typed invoice value ignored');
      expect(d.ewayBillNeeded(4000), isTrue);
      expect(_ready.copyWith(invoiceValue: 700).toCreateRequest('b')['invoiceValue'], 700, reason: 'one package: typed');
    });

    test('adds the E-Way Bill block once an invoice number is entered', () {
      final body = _ready.copyWith(invoiceValue: 60000, ewayInvoiceNumber: 'INV-9').toCreateRequest('b');
      expect((body['ewayBill'] as Map)['invoiceNumber'], 'INV-9');
      expect(_ready.copyWith(invoiceValue: 60000).ewayBillNeeded(50000), isTrue);
      expect(_ready.copyWith(invoiceValue: 100).ewayBillNeeded(50000), isFalse);
    });
  });

  group('booking screen', () {
    late List<RequestOptions> creates;
    late List<RequestOptions> previews;

    Future<FakeResponse> server(RequestOptions r, {required bool timeoutOnCreate, bool oldServer = false}) async {
      switch (r.path) {
        case '/api/v1/auth/refresh':
          return (status: 200, body: ok(loginJson()));
        case '/api/v1/branches/directory':
          return (status: 200, body: ok({'content': <Object>[]}));
        case '/api/v1/master/service-types':
          return (
            status: 200,
            body: ok({
              'content': [
                {'id': 'svc-1', 'code': 'STD', 'name': 'Standard'},
              ],
            }),
          );
        case '/api/v1/master/payment-modes':
          return (
            status: 200,
            body: ok({
              'content': [
                {'id': 'pay-1', 'code': 'PAID', 'name': 'Paid'},
              ],
            }),
          );
        case '/api/v1/company-settings':
          return (
            status: 200,
            body: ok({
              'shipment': {'defaultChargeableWeightKg': 1},
              'ewayBill': {'ewayBillMandatoryValue': 50000},
            }),
          );
        case '/api/v1/global-masters/pincodes':
          return (
            status: 200,
            body: ok({
              'content': [
                {'id': 'pin-1', 'code': '415001'},
              ],
            }),
          );
        case '/api/v1/global-masters/pincodes/pin-1/areas':
          return (
            status: 200,
            body: ok([
              {'areaId': 'area-1', 'areaName': 'Satara City', 'cityName': 'Satara', 'primary': true},
            ]),
          );
        case '/api/v1/district-level-freight/calculate':
          return (
            status: 200,
            body: ok({'destinationCityName': 'Satara', 'totalFreight': 420, 'odaApplicable': false}),
          );
        case '/api/v1/pricing/calculate':
          return (
            status: 200,
            body: ok({
              'chargeableWeight': 14.4,
              'chargeBreakup': {'freight': 400, 'fuelCharge': 20, 'netAmount': 500},
            }),
          );
        case '/api/v1/shipments/preview':
          previews.add(r);
          if (oldServer) {
            // Backend before V135: no preview endpoint; POST is refused on /shipments/{id}.
            return (status: 405, body: errorBody('Method POST is not supported for this endpoint'));
          }
          return (
            status: 200,
            body: ok({
              'destinationCityName': 'Satara',
              'chargeableWeight': 14.4,
              'ewayBillRequired': false,
              'walletSufficient': null,
              'charges': {'freight': 400, 'fuelCharge': 20, 'odaCharge': 120, 'gstAmount': 30, 'netAmount': 500},
            }),
          );
        case '/api/v1/shipments' when r.method == 'POST':
          creates.add(r);
          if (timeoutOnCreate) throw DioException(requestOptions: r, type: DioExceptionType.receiveTimeout);
          return (
            status: 201,
            body: ok({'id': 'shp-1', 'shipmentNumber': 'BK-1', 'trackingNumber': 'AWB123', 'status': 'BOOKED'}),
          );
        case '/api/v1/shipments/shp-1':
          return (
            status: 200,
            body: ok({'id': 'shp-1', 'shipmentNumber': 'BK-1', 'trackingNumber': 'AWB123', 'status': 'BOOKED'}),
          );
        case '/api/v1/shipments/shp-1/charges':
          return (status: 200, body: ok({'freight': 420, 'netAmount': 531.5}));
        case '/api/v1/shipments/shp-1/history':
          return (status: 200, body: ok(<Object>[]));
        default:
          return (status: 200, body: ok(null));
      }
    }

    Future<ProviderContainer> openBooking(
      WidgetTester tester, {
      required bool timeoutOnCreate,
      bool oldServer = false,
    }) async {
      creates = [];
      previews = [];
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final adapter = FakeAdapter((r) => server(r, timeoutOnCreate: timeoutOnCreate, oldServer: oldServer));
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
          ],
          child: const BranchOpsApp(),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(tester.element(find.byType(BranchOpsApp)));
      container.read(bookingDraftProvider.notifier).update((_) => _ready);
      unawaited(container.read(routerProvider).push('/bookings/new'));
      await tester.pumpAndSettle();
      return container;
    }

    /// Shipment (destination + packages) → Charges → Parties → Summary.
    Future<void> goToReview(WidgetTester tester) async {
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      // The summary is long: scroll so the charges card and Confirm are built.
      await tester.dragUntilVisible(
        find.text('Confirm booking'),
        find.byType(ListView).hitTestable().first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('walks the steps, shows server preview, books once and shows the server AWB', (tester) async {
      final container = await openBooking(tester, timeoutOnCreate: false);
      await goToReview(tester);

      expect(find.text('Server price'), findsOneWidget);
      expect(find.textContaining('Satara · Chargeable'), findsOneWidget);
      expect(find.text('Net amount'), findsOneWidget);
      expect(find.text('₹500.00'), findsOneWidget);
      expect(previews, isNotEmpty);
      expect((previews.first.data as Map)['bookingBranchId'], isNotNull, reason: 'preview sends the booking body');
      expect((previews.first.data as Map)['senderName'], 'Preview', reason: 'charges come before parties');
      expect(find.textContaining('wallet is short'), findsNothing);

      await tester.ensureVisible(find.text('Confirm booking'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm booking'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Book'));
      await tester.pumpAndSettle();

      expect(creates, hasLength(1));
      final body = creates.single.data as Map<String, dynamic>;
      expect(body['destinationAreaId'], 'area-1', reason: 'primary area picked by default');
      expect(find.text('AWB123'), findsOneWidget);
      expect(find.textContaining('₹531.50'), findsOneWidget);
      expect(container.read(bookingDraftProvider).senderName, isEmpty, reason: 'draft cleared after booking');
    });

    testWidgets('server without the preview endpoint: estimate from the old previews, booking still works', (
      tester,
    ) async {
      await openBooking(tester, timeoutOnCreate: false, oldServer: true);
      await goToReview(tester);

      expect(find.text('Estimate'), findsOneWidget);
      expect(find.text('₹420.00'), findsOneWidget, reason: 'freight from District Level Freight');
      expect(find.text('Net amount'), findsNothing, reason: 'no client-side total');
      await tester.ensureVisible(find.text('Confirm booking'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm booking'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Book'));
      await tester.pumpAndSettle();

      expect(creates, hasLength(1));
      expect(find.text('AWB123'), findsOneWidget);
    });

    testWidgets('timeout on booking warns about duplicates, keeps the draft, does not retry', (tester) async {
      final container = await openBooking(tester, timeoutOnCreate: true);
      await goToReview(tester);

      await tester.ensureVisible(find.text('Confirm booking'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm booking'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Book'));
      await tester.pumpAndSettle();

      expect(find.text('Booking not confirmed'), findsOneWidget);
      expect(creates, hasLength(1));
      expect(container.read(bookingDraftProvider).senderName, 'Asha Traders');
    });

    testWidgets('charges show on step 2, before sender and receiver; typing names does not re-price', (tester) async {
      final container = await openBooking(tester, timeoutOnCreate: false);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Server price'), findsOneWidget);
      expect(find.text('₹500.00'), findsOneWidget);
      final before = previews.length;

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      container.read(bookingDraftProvider.notifier).update((d) => d.copyWith(receiverName: 'Someone Else'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.text('Confirm booking'),
        find.byType(ListView).hitTestable().first,
        const Offset(0, -300),
      );

      expect(find.text('Confirm booking'), findsOneWidget);
      expect(previews.length, before, reason: 'summary reuses the charges step price check');
    });

    testWidgets('service type and payment mode are selected by default', (tester) async {
      final container = await openBooking(tester, timeoutOnCreate: false);
      container.read(bookingDraftProvider.notifier).update((d) => d.copyWith(serviceTypeId: null, paymentModeId: null));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      final d = container.read(bookingDraftProvider);
      expect(d.serviceTypeId, 'svc-1');
      expect(d.paymentModeId, 'pay-1', reason: 'PAID mode preferred');
      expect(find.text('Standard (STD)'), findsOneWidget);
      expect(find.text('Paid (PAID)'), findsOneWidget);
      expect(find.text('Server price'), findsOneWidget, reason: 'charges load without picking anything');
    });

    testWidgets('ODA applied by the server shows in the ODA box and can be changed; GST in the bill', (tester) async {
      final container = await openBooking(tester, timeoutOnCreate: false);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      final oda = find.widgetWithText(TextField, 'ODA (₹)');
      expect(tester.widget<TextField>(oda).controller!.text, '120', reason: 'server ODA prefilled');
      expect(find.text('GST'), findsOneWidget);
      expect(find.text('₹30.00'), findsOneWidget);
      expect(container.read(bookingDraftProvider).odaChargeOverride, isNull, reason: 'not an override until edited');

      await tester.enterText(oda, '80');
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(container.read(bookingDraftProvider).odaChargeOverride, 80);
      expect((previews.last.data as Map)['odaCharge'], 80, reason: 'edited ODA is sent for the server to price');
    });

    testWidgets('missing fields stop the first step', (tester) async {
      final container = await openBooking(tester, timeoutOnCreate: false);
      container.read(bookingDraftProvider.notifier).reset();
      container.read(routerProvider).pop();
      await tester.pumpAndSettle();
      unawaited(container.read(routerProvider).push('/bookings/new'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a 6-digit pincode'), findsWidgets, reason: 'destination is the first step');
      expect(find.text('Choose service type and payment mode to see charges.'), findsNothing);
    });
  });
}
