// Renders every app screen with sample data to PNGs for design review.
//
//   flutter test test_screenshots --update-goldens
//
// Output: test_screenshots/screens/*.png (390×844 pt phone, 2× pixels).
// All names, numbers and AWBs below are made-up sample data.
import 'dart:async';
import 'dart:io';

import 'package:branch_ops/app.dart';
import 'package:branch_ops/core/network/api_client.dart';
import 'package:branch_ops/core/network/auth_interceptor.dart';
import 'package:branch_ops/core/storage/secure_store.dart';
import 'package:branch_ops/features/auth/application/auth_controller.dart';
import 'package:branch_ops/features/booking/application/booking_draft.dart';
import 'package:branch_ops/router.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/fakes.dart';

const _fonts = '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts';

Future<void> _loadFonts() async {
  Future<ByteData> f(String name) async => ByteData.view((await File('$_fonts/$name').readAsBytes()).buffer);
  final roboto = FontLoader('Roboto')
    ..addFont(f('Roboto-Regular.ttf'))
    ..addFont(f('Roboto-Medium.ttf'))
    ..addFont(f('Roboto-Bold.ttf'))
    ..addFont(f('Roboto-Black.ttf'));
  await roboto.load();
  await (FontLoader('MaterialIcons')..addFont(f('MaterialIcons-Regular.otf'))).load();
}

const _branches = [
  {
    'id': 'b-pune',
    'branchCode': 'PUN',
    'branchName': 'Pune Shivajinagar',
    'city': 'Pune',
    'postalCode': '411005',
    'branchType': 'BRANCH',
    'assignedHubId': 'h-pune',
  },
  {'id': 'h-pune', 'branchCode': 'PHUB', 'branchName': 'Pune Central Hub', 'city': 'Pune', 'branchType': 'HUB'},
  {'id': 'b-satara', 'branchCode': 'SAT', 'branchName': 'Satara Bus Stand', 'city': 'Satara', 'branchType': 'BRANCH'},
  {
    'id': 'b-kolhapur',
    'branchCode': 'KOP',
    'branchName': 'Kolhapur Rajarampuri',
    'city': 'Kolhapur',
    'branchType': 'BRANCH',
  },
];

Map<String, dynamic> _ship(
  String id,
  String awb,
  String status,
  String to,
  String receiver, {
  int pkg = 1,
  num kg = 5,
  String pay = 'paid',
  num net = 180,
}) => {
  'id': id,
  'shipmentNumber': 'PUN-26-${id.substring(1)}',
  'trackingNumber': awb,
  'status': status,
  'bookingDate': '2026-10-23',
  'createdDate': '2026-10-23T06:30:00Z',
  'fromCity': 'Pune',
  'toCity': to,
  'senderName': 'Shree Ganesh Traders',
  'senderContact': '9822012345',
  'receiverName': receiver,
  'receiverContact': '9890011122',
  'receiverAddress': 'Shop 4, Main Road, $to',
  'numberOfPackages': pkg,
  'chargeableWeight': kg,
  'netAmount': net,
  'paymentModeId': pay,
  'currentLocationId': 'b-pune',
};

final _shipments = [
  _ship('s1041', 'AL10041', 'BOOKED', 'Satara', 'Sai Medicals', pkg: 2, kg: 12.5, net: 420),
  _ship('s1042', 'AL10042', 'BOOKED', 'Kolhapur', 'Patil Hardware', kg: 4, pay: 'topay', net: 210),
  _ship('s1039', 'AL10039', 'DISPATCHED', 'Satara', 'Om Textiles', pkg: 3, kg: 18, net: 640),
  _ship('s1035', 'AL10035', 'OUT_FOR_DELIVERY', 'Pune', 'Kulkarni Clinic', kg: 2, pay: 'cod', net: 1250),
  _ship('s1030', 'AL10030', 'DELIVERED', 'Kolhapur', 'Jadhav Agro', pkg: 2, kg: 9, net: 380),
];

Map<String, dynamic> _detail(String status) => {
  ..._ship('s1035', 'AL10035', status, 'Pune', 'Kulkarni Clinic', kg: 2, pay: 'cod', net: 1250),
  'senderAddress': '12 Laxmi Road, Pune',
  'pickupPincode': '411005',
  'deliveryPincode': '411038',
  'bookingBranchId': 'b-pune',
  'deliveryBranchId': 'b-pune',
  'expectedDeliveryDate': '2026-10-25',
  'actualWeight': 1.6,
  'volumetricWeight': 2,
  'declaredValue': 4500,
  'serviceTypeId': 'svc-std',
  'deliveryType': 'DOOR',
  'items': [
    {'itemName': 'Medicine carton', 'quantity': 1, 'weight': 1.6, 'lengthCm': 25, 'widthCm': 20, 'heightCm': 20},
  ],
};

class _Server {
  _Server({this.signedIn = true, this.expired = false});

  final bool signedIn;
  final bool expired;
  Map<String, dynamic>? pod;

  Future<FakeResponse> handle(RequestOptions r) async {
    final q = r.queryParameters;
    switch (r.path) {
      case '/api/v1/auth/refresh':
        if (expired) return (status: 401, body: errorBody('Session expired'));
        return (
          status: 200,
          body: ok({
            ...loginJson(
              branchId: 'b-pune',
              permissions: const [
                'DASHBOARD_READ',
                'SHIPMENT_CREATE',
                'SHIPMENT_READ',
                'MANIFEST_CREATE',
                'MANIFEST_READ',
                'MANIFEST_DISPATCH',
                'DELIVERY_ASSIGN',
                'DELIVERY_UPLOAD',
                'DELIVERY_READ',
              ],
            ),
            'displayName': 'Priya Deshmukh',
            'email': 'priya.d@amazinglogistics.example',
            'companyName': 'Amazing Logistics',
          }),
        );
      case '/api/v1/branches/directory':
        return (status: 200, body: ok({'content': _branches}));
      case '/api/v1/dashboard/summary':
        return (
          status: 200,
          body: ok({
            'statistics': {'todayBookings': 38, 'delivered': 21},
            'branchOverview': {
              'readyForManifest': 14,
              'manifestsAwaitingDispatch': 3,
              'podOverview': {'pendingUpload': 5},
            },
          }),
        );
      case '/api/v1/manifests/summary':
        return (status: 200, body: ok({'totalManifests': q['status'] == 'CREATED' ? 3 : 6}));
      case '/api/v1/shipments/summary':
        return q.containsKey('deliveredDateFrom')
            ? (status: 200, body: ok({'totalCount': 17}))
            : (
                status: 200,
                body: ok({
                  'statusCounts': {'IN_SCAN': 9, 'OUT_FOR_DELIVERY': 12},
                }),
              );
      case '/api/v1/master/service-types':
        return (
          status: 200,
          body: ok({
            'content': [
              {'id': 'svc-std', 'code': 'STD', 'name': 'Standard'},
              {'id': 'svc-exp', 'code': 'EXP', 'name': 'Express'},
            ],
          }),
        );
      case '/api/v1/master/payment-modes':
        return (
          status: 200,
          body: ok({
            'content': [
              {'id': 'paid', 'code': 'PAID', 'name': 'Paid', 'collectAtBooking': true},
              {'id': 'topay', 'code': 'TOPAY', 'name': 'To Pay', 'collectAtDelivery': true},
              {
                'id': 'cod',
                'code': 'COD',
                'name': 'Cash on Delivery',
                'collectAtDelivery': true,
                'cashOnDelivery': true,
              },
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
              {'id': 'pin-1', 'code': q['search']},
            ],
          }),
        );
      case '/api/v1/global-masters/pincodes/pin-1/areas':
        return (
          status: 200,
          body: ok([
            {'areaId': 'a1', 'areaName': 'Satara City', 'cityName': 'Satara', 'primary': true},
            {'areaId': 'a2', 'areaName': 'Karanje', 'cityName': 'Satara', 'odaApplicable': true},
          ]),
        );
      case '/api/v1/shipments/preview':
        return (
          status: 200,
          body: ok({
            'actualWeight': 10,
            'volumetricWeight': 14.4,
            'chargeableWeight': 14.4,
            'destinationCityName': 'Satara',
            'weightSlabLabel': '10–25 kg',
            'ratePerKg': 22,
            'ewayBillRequired': false,
            'charges': {
              'freight': 316.8,
              'fuelCharge': 31.68,
              'handlingCharge': 20,
              'gstAmount': 66.41,
              'roundOff': 0.11,
              'netAmount': 435,
            },
          }),
        );
      case '/api/v1/shipments' when r.method == 'GET':
        if (q['status'] == 'IN_SCAN') {
          return (
            status: 200,
            body: ok({
              'content': [
                _ship('s1050', 'AL10050', 'IN_SCAN', 'Pune', 'Kulkarni Clinic', pay: 'cod', net: 1250),
                _ship('s1051', 'AL10051', 'IN_SCAN', 'Pune', 'Joshi Electricals', pay: 'topay', net: 340),
                _ship('s1052', 'AL10052', 'IN_SCAN', 'Pune', 'Mehta Stores'),
              ],
            }),
          );
        }
        if (q['unassignedDeliveryBranch'] == true) {
          return (status: 200, body: ok({'content': _shipments.where((s) => s['status'] == 'BOOKED').toList()}));
        }
        return (status: 200, body: ok({'content': _shipments, 'hasNext': false}));
      case '/api/v1/shipments/s1035' || '/api/v1/shipments/track/AL10035':
        return (status: 200, body: ok(_detail(pod == null ? 'OUT_FOR_DELIVERY' : 'OUT_FOR_DELIVERY')));
      case '/api/v1/shipments/s1035/history':
        return (
          status: 200,
          body: ok([
            {
              'status': 'BOOKED',
              'changedAt': '2026-10-22T05:10:00Z',
              'branchId': 'b-pune',
              'remarks': 'Booked at counter',
            },
            {
              'status': 'MANIFEST_CREATED',
              'changedAt': '2026-10-22T09:40:00Z',
              'branchId': 'b-pune',
              'remarks': 'Loading sheet LS-PUN-0218',
            },
            {
              'status': 'DISPATCHED',
              'changedAt': '2026-10-22T13:05:00Z',
              'branchId': 'b-pune',
              'remarks': 'THC LS-PUN-0218, MH12 RT 4471',
            },
            {'status': 'IN_SCAN', 'changedAt': '2026-10-23T04:20:00Z', 'branchId': 'h-pune'},
            {
              'status': 'OUT_FOR_DELIVERY',
              'changedAt': '2026-10-23T06:45:00Z',
              'branchId': 'h-pune',
              'remarks': 'DRS-PUN-0091',
            },
          ]),
        );
      case '/api/v1/hub-operations/exceptions':
        return (
          status: 200,
          body: ok({
            'content': [
              {
                'exceptionType': 'ON_HOLD',
                'status': 'RESOLVED',
                'raisedAt': '2026-10-23T04:30:00Z',
                'hubBranchId': 'h-pune',
                'remarks': 'Address unclear',
                'resolvedAt': '2026-10-23T05:50:00Z',
                'resolutionRemarks': 'Customer confirmed by phone',
              },
            ],
          }),
        );
      case '/api/v1/shipments/s1035/charges' || '/api/v1/shipments/new1/charges':
        return (
          status: 200,
          body: ok({
            'freight': 900,
            'fuelCharge': 90,
            'handlingCharge': 50,
            'gstAmount': 187.2,
            'roundOff': 0.8,
            'netAmount': 1250,
          }),
        );
      case '/api/v1/shipments/s1035/delivery-run':
        return (
          status: 200,
          body: ok({'drsNumber': 'DRS-PUN-0091', 'status': 'ASSIGNED', 'assignedAt': '2026-10-23T06:45:00Z'}),
        );
      case '/api/v1/shipments/s1035/pod/verification':
        return pod == null ? (status: 404, body: errorBody('none')) : (status: 200, body: ok(pod));
      case '/api/v1/shipments/new1':
        return (
          status: 200,
          body: ok({..._ship('new1', 'AL10058', 'BOOKED', 'Satara', 'Sai Medicals'), 'shipmentNumber': 'PUN-26-1058'}),
        );
      case '/api/v1/shipments/new1/history':
        return (status: 200, body: ok(<Object>[]));
      case '/api/v1/manifests':
        final status = q['status'];
        Map<String, dynamic> sheet(String id, String no, String st, String to, int n, int pkg, num kg) => {
          'id': id,
          'manifestNumber': no,
          'status': st,
          'bookingBranchId': status == 'DISPATCHED' && q.containsKey('deliveryBranchId') ? 'b-kolhapur' : 'b-pune',
          'deliveryBranchId': to,
          'shipmentCount': n,
          'totalPackages': pkg,
          'totalWeight': kg,
          'createdAt': '2026-10-23T08:15:00Z',
          'dispatchedAt': st == 'CREATED' ? null : '2026-10-23T11:00:00Z',
        };
        if (status == 'DISPATCHED' && q.containsKey('deliveryBranchId')) {
          return (
            status: 200,
            body: ok({
              'content': [sheet('m-in', 'LS-KOP-0144', 'DISPATCHED', 'b-pune', 6, 9, 41.5)],
            }),
          );
        }
        return (
          status: 200,
          body: ok({
            'content': [
              if (status == 'CREATED') ...[
                sheet('m1', 'LS-PUN-0221', 'CREATED', 'h-pune', 14, 22, 96.4),
                sheet('m2', 'LS-PUN-0220', 'CREATED', 'b-satara', 5, 7, 31),
              ] else
                sheet('m3', 'LS-PUN-0218', status as String, 'b-kolhapur', 11, 16, 72.5),
            ],
          }),
        );
      case '/api/v1/manifests/m1' || '/api/v1/manifests/m-in':
        final incoming = r.path.endsWith('m-in');
        return (
          status: 200,
          body: ok({
            'id': incoming ? 'm-in' : 'm1',
            'manifestNumber': incoming ? 'LS-KOP-0144' : 'LS-PUN-0221',
            'status': incoming ? 'DISPATCHED' : 'CREATED',
            'bookingBranchId': incoming ? 'b-kolhapur' : 'b-pune',
            'deliveryBranchId': incoming ? 'b-pune' : 'h-pune',
            'shipmentCount': 3,
            'totalPackages': 5,
            'totalWeight': 26.5,
            'createdAt': '2026-10-23T08:15:00Z',
          }),
        );
      case '/api/v1/manifests/m1/shipments' || '/api/v1/manifests/m-in/shipments':
        return (
          status: 200,
          body: ok([
            _ship('s1041', 'AL10041', 'MANIFEST_CREATED', 'Satara', 'Sai Medicals', pkg: 2, kg: 12.5),
            _ship('s1042', 'AL10042', 'MANIFEST_CREATED', 'Kolhapur', 'Patil Hardware', kg: 4),
            _ship('s1043', 'AL10043', 'MANIFEST_CREATED', 'Satara', 'Om Textiles', pkg: 2, kg: 10),
          ]),
        );
      case '/api/v1/vehicles':
        return (
          status: 200,
          body: ok([
            {'id': 'v1', 'vehicleNumber': 'MH12 RT 4471', 'vehicleType': 'TEMPO'},
            {'id': 'v2', 'vehicleNumber': 'MH12 QW 2290', 'vehicleType': 'TRUCK'},
          ]),
        );
      case '/api/v1/users':
        return (
          status: 200,
          body: ok({
            'content': [
              {
                'id': 'u1',
                'displayName': 'Rahul Pawar',
                'mobile': '9881100221',
                'designation': 'Driver',
                'branchId': 'b-pune',
              },
              {
                'id': 'u2',
                'displayName': 'Sameer Shaikh',
                'mobile': '9881100334',
                'designation': 'Delivery partner',
                'branchId': 'b-pune',
              },
            ],
          }),
        );
      case '/api/v1/shipment-movement/drs':
        return (
          status: 200,
          body: ok([
            {
              'deliveryUserId': 'u2',
              'deliveryBranchId': 'b-pune',
              'runDate': '2026-10-23',
              'drsNumber': 'DRS-PUN-0091',
              'shipmentCount': 12,
              'deliveredCount': 7,
              'pendingCount': 5,
            },
            {
              'deliveryUserId': 'u1',
              'deliveryBranchId': 'b-pune',
              'runDate': '2026-10-23',
              'drsNumber': 'DRS-PUN-0090',
              'shipmentCount': 8,
              'deliveredCount': 8,
              'pendingCount': 0,
            },
          ]),
        );
      case '/api/v1/shipment-movement/drs/detail':
        return (
          status: 200,
          body: ok({
            'drsNumber': 'DRS-PUN-0091',
            'shipments': [
              {
                'shipmentId': 's1035',
                'trackingNumber': 'AL10035',
                'status': 'OUT_FOR_DELIVERY',
                'receiverName': 'Kulkarni Clinic',
                'receiverAddress': '22 FC Road, Deccan',
                'receiverContact': '9890011122',
                'paymentModeId': 'cod',
                'netAmount': 1250,
                'toCity': 'Pune',
              },
              {
                'shipmentId': 's1036',
                'trackingNumber': 'AL10036',
                'status': 'OUT_FOR_DELIVERY',
                'receiverName': 'Joshi Electricals',
                'receiverAddress': '7 Tilak Road',
                'receiverContact': '9890033344',
                'paymentModeId': 'topay',
                'netAmount': 340,
                'toCity': 'Pune',
              },
              {
                'shipmentId': 's1030',
                'trackingNumber': 'AL10030',
                'status': 'DELIVERED',
                'receiverName': 'Jadhav Agro',
                'receiverAddress': 'Market Yard',
                'deliveredAt': '2026-10-23T09:12:00Z',
                'toCity': 'Pune',
              },
            ],
          }),
        );
      default:
        return (status: 200, body: ok(null));
    }
  }
}

void main() {
  setUpAll(_loadFonts);

  Future<ProviderContainer> boot(WidgetTester tester, _Server server, {double height = 844}) async {
    tester.view.physicalSize = Size(780, height * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final adapter = FakeAdapter(server.handle);
    Dio dio() => Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adapter;
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          secureStoreProvider.overrideWithValue(
            MemoryStore()..values.addAll({if (server.signedIn) 'refresh': 'saved', 'company': 'AMAZING_LOGISTICS'}),
          ),
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
    return ProviderScope.containerOf(tester.element(find.byType(BranchOpsApp)));
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(seconds: 5)); // let snackbars clear
    await tester.pumpAndSettle();
    await expectLater(find.byType(BranchOpsApp), matchesGoldenFile('screens/$name.png'));
  }

  Future<void> go(WidgetTester tester, ProviderContainer c, String route) async {
    unawaited(c.read(routerProvider).push(route));
    await tester.pumpAndSettle();
  }

  testWidgets('01 login', (t) async {
    await boot(t, _Server(signedIn: false));
    await shot(t, '01_login');
  });

  testWidgets('02 session expired', (t) async {
    await boot(t, _Server(expired: true));
    await shot(t, '02_session_expired');
  });

  testWidgets('03 dashboard', (t) async {
    await boot(t, _Server(), height: 1180);
    await shot(t, '03_dashboard');
  });

  testWidgets('04 bookings list', (t) async {
    final c = await boot(t, _Server());
    c.read(routerProvider).go('/bookings');
    await t.pumpAndSettle();
    await shot(t, '04_bookings_list');
  });

  const draft = BookingDraft(
    senderName: 'Shree Ganesh Traders',
    senderContact: '9822012345',
    senderAddress: '12 Laxmi Road, Pune',
    receiverName: 'Sai Medicals',
    receiverContact: '9890011122',
    receiverAddress: 'Shop 4, Powai Naka, Satara',
    pickupPincode: '411005',
    deliveryPincode: '415001',
    items: [
      ItemDraft(
        name: 'Medicine cartons',
        quantity: 2,
        weight: 12.5,
        length: 40,
        width: 30,
        height: 30,
        declaredValue: 8500,
      ),
    ],
    invoiceValue: 8500,
    serviceTypeId: 'svc-std',
    paymentModeId: 'paid',
  );

  for (final (step, name) in [
    (0, '05_booking_parties'),
    (1, '06_booking_destination'),
    (2, '07_booking_packages'),
    (3, '08_booking_review'),
  ]) {
    testWidgets(name, (t) async {
      final c = await boot(t, _Server(), height: step == 3 ? 1250 : 1000);
      c.read(bookingDraftProvider.notifier).update((_) => draft);
      await go(t, c, '/bookings/new');
      for (var i = 0; i < step; i++) {
        await t.tap(find.text('Next'));
        await t.pumpAndSettle();
      }
      await shot(t, name);
    });
  }

  testWidgets('09 booked', (t) async {
    final c = await boot(t, _Server());
    await go(t, c, '/bookings/done/new1');
    await shot(t, '09_booking_done');
  });

  testWidgets('10 shipment detail', (t) async {
    final c = await boot(t, _Server(), height: 2300);
    await go(t, c, '/shipments/s1035');
    await shot(t, '10_shipment_detail');
  });

  testWidgets('11 track', (t) async {
    final c = await boot(t, _Server(), height: 1400);
    await go(t, c, '/track?awb=AL10035');
    await shot(t, '11_track_shipment');
  });

  testWidgets('12 loading sheets', (t) async {
    final c = await boot(t, _Server());
    c.read(routerProvider).go('/loading-sheets');
    await t.pumpAndSettle();
    await shot(t, '12_loading_sheets');
  });

  testWidgets('13 new loading sheet', (t) async {
    final c = await boot(t, _Server());
    await go(t, c, '/loading-sheets/new');
    await t.tap(find.text('Select all'));
    await t.pumpAndSettle();
    await shot(t, '13_new_loading_sheet');
  });

  testWidgets('14 loading sheet detail', (t) async {
    final c = await boot(t, _Server(), height: 1000);
    await go(t, c, '/loading-sheets/m1');
    await shot(t, '14_loading_sheet_detail');
  });

  testWidgets('15 THC', (t) async {
    final c = await boot(t, _Server(), height: 1250);
    await go(t, c, '/thc?manifestId=m1');
    await t.tap(find.text('Vehicle'));
    await t.pumpAndSettle();
    await t.tap(find.text('MH12 RT 4471 · tempo').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Pick driver'));
    await t.pumpAndSettle();
    await t.tap(find.text('Rahul Pawar'));
    await t.pumpAndSettle();
    await shot(t, '15_generate_thc');
  });

  testWidgets('16 delivery receive', (t) async {
    final c = await boot(t, _Server());
    c.read(routerProvider).go('/delivery');
    await t.pumpAndSettle();
    await shot(t, '16_delivery_receive');
  });

  testWidgets('17 receive THC', (t) async {
    final c = await boot(t, _Server());
    await go(t, c, '/receive/m-in');
    await t.tap(find.text('AL10041'));
    await t.tap(find.text('AL10043'));
    await t.pumpAndSettle();
    await shot(t, '17_receive_thc');
  });

  testWidgets('18 delivery runs', (t) async {
    final c = await boot(t, _Server());
    c.read(routerProvider).go('/delivery');
    await t.pumpAndSettle();
    await t.tap(find.text('Delivery runs'));
    await t.pumpAndSettle();
    await shot(t, '18_delivery_runs');
  });

  testWidgets('19 new DRS', (t) async {
    final c = await boot(t, _Server(), height: 1100);
    await go(t, c, '/drs/new');
    await t.tap(find.text('Pick delivery partner'));
    await t.pumpAndSettle();
    await t.tap(find.text('Sameer Shaikh'));
    await t.pumpAndSettle();
    await t.tap(find.text('Select all'));
    await t.pumpAndSettle();
    await shot(t, '19_new_drs');
  });

  testWidgets('20 DRS run', (t) async {
    final c = await boot(t, _Server());
    await go(t, c, '/drs/run?user=u2&branch=b-pune&date=2026-10-23');
    await shot(t, '20_drs_run');
  });

  testWidgets('21 POD capture', (t) async {
    final c = await boot(t, _Server(), height: 1100);
    await go(t, c, '/pod?shipmentId=s1035');
    await shot(t, '21_pod_capture');
  });

  testWidgets('22 POD ready', (t) async {
    final c = await boot(
      t,
      _Server()
        ..pod = {
          'id': 'p1',
          'verificationStatus': 'PENDING',
          'verificationReasons': ['Receiver name matches', 'AWB visible on label'],
        },
      height: 1000,
    );
    await go(t, c, '/pod?shipmentId=s1035');
    await shot(t, '22_pod_complete_delivery');
  });

  testWidgets('23 more', (t) async {
    final c = await boot(t, _Server());
    c.read(routerProvider).go('/more');
    await t.pumpAndSettle();
    await shot(t, '23_more');
  });
}
