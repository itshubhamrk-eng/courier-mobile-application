import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';
import '../../shipments/data/shipment_models.dart';
import '../application/booking_draft.dart';

class CustomerHit {
  const CustomerHit({required this.id, required this.code, required this.name, this.mobile, this.type});

  final String id;
  final String code;
  final String name;
  final String? mobile;
  final String? type;

  factory CustomerHit.fromJson(Map<String, dynamic> j) => CustomerHit(
    id: j['id'] as String,
    code: j['customerCode'] as String? ?? '',
    name: j['displayName'] as String? ?? '',
    mobile: jStr(j['mobile']),
    type: jStr(j['customerType']),
  );
}

/// A business customer's details used to prefill the sender.
class CustomerDetail {
  const CustomerDetail({
    required this.id,
    required this.name,
    this.mobile,
    this.defaultPaymentMode,
    this.pickupAddresses = const [],
    this.billingAddress,
  });

  final String id;
  final String name;
  final String? mobile;
  final String? defaultPaymentMode;
  final List<String> pickupAddresses;
  final String? billingAddress;

  factory CustomerDetail.fromJson(Map<String, dynamic> j) {
    String line(Map<String, dynamic> a) =>
        [a['addressLine1'], a['addressLine2'], a['landmark']].whereType<String>().where((s) => s.isNotEmpty).join(', ');
    final addresses =
        jList(j['addresses'])
            .where((a) => a['status'] == 'ACTIVE' && (a['addressUsage'] == null || a['addressUsage'] != 'DELIVERY'))
            .toList()
          ..sort((a, b) => (b['isDefaultPickup'] == true ? 1 : 0) - (a['isDefaultPickup'] == true ? 1 : 0));
    final billing = [
      j['billingAddressLine1'],
      j['billingAddressLine2'],
      j['billingCity'],
      j['billingState'],
      j['billingPincode'],
    ].whereType<String>().where((s) => s.isNotEmpty).join(', ');
    return CustomerDetail(
      id: j['id'] as String,
      name: j['displayName'] as String? ?? '',
      mobile: jStr(j['mobile']),
      defaultPaymentMode: jStr(j['defaultPaymentMode']),
      pickupAddresses: addresses.map(line).where((s) => s.isNotEmpty).toList(),
      billingAddress: billing.isEmpty ? null : billing,
    );
  }
}

/// Server previews. Neither is trusted at booking: the server reprices on create.
class BookingPreview {
  const BookingPreview({required this.freight, required this.charges, required this.chargeableWeight});

  /// `/district-level-freight/calculate`.
  final Map<String, dynamic> freight;

  /// `/pricing/calculate` `chargeBreakup` (fuel, handling, insurance, applicable charges, GST...).
  final Charges charges;
  final num? chargeableWeight;

  String? get destinationCity => jStr(freight['destinationCityName']);
  String? get slab => jStr(freight['weightSlabLabel']) ?? jStr(freight['customerZoneName']);
  num? get ratePerKg => jNum(freight['ratePerKg']);
  num? get baseFreight => jNum(freight['baseFreight']);
  num? get odaCharge => freight['odaApplicable'] == true ? jNum(freight['odaCharge']) : null;
  num? get totalFreight => jNum(freight['totalFreight']);
  num? get customerExtraCharges => jNum(freight['customerExtraCharges']);
}

final bookingRepositoryProvider = Provider<BookingRepository>((ref) => BookingRepository(ref.watch(apiClientProvider)));

class BookingRepository {
  BookingRepository(this._api);

  final ApiClient _api;

  Future<List<CustomerHit>> searchCustomers(String query, {bool businessOnly = false}) => _api.get(
    '/api/v1/customers',
    query: {
      'search': query,
      'status': 'ACTIVE',
      if (businessOnly) 'customerType': 'BUSINESS',
      'size': 8,
      'sort': 'customerCode,asc',
    },
    parse: (d) => PageResponse.fromJson(jMap(d), CustomerHit.fromJson).content,
  );

  Future<CustomerDetail> customer(String id) =>
      _api.get('/api/v1/customers/$id', parse: (d) => CustomerDetail.fromJson(jMap(d)));

  Future<BookingPreview> preview(BookingDraft draft, {required String branchId, required num chargeableWeight}) async {
    final results = await Future.wait([
      _api.post(
        '/api/v1/district-level-freight/calculate',
        body: {
          'bookingBranchId': branchId,
          'destinationPincode': draft.deliveryPincode,
          'destinationAreaId': draft.destinationAreaId,
          'chargeableWeight': chargeableWeight,
          'businessCustomerId': draft.businessCustomerId,
          'declaredValue': draft.declaredValue,
        },
        parse: jMap,
      ),
      _api.post(
        '/api/v1/pricing/calculate',
        body: {
          'bookingBranchId': branchId,
          'pickupPincode': draft.pickupPincode,
          'deliveryPincode': draft.deliveryPincode,
          'serviceTypeId': draft.serviceTypeId,
          'paymentModeId': draft.paymentModeId,
          // Same inputs the web booking screen sends: chargeable as actualWeight so the
          // engine does not re-derive volumetric from blended totals.
          'actualWeight': chargeableWeight,
          'totalActualWeight': draft.totalActualWeight,
          'declaredValue': draft.declaredValue,
          'numberOfPackages': draft.packageCount,
        },
        parse: jMap,
      ),
    ]);
    return BookingPreview(
      freight: results[0],
      charges: Charges.fromJson(jMap(results[1]['chargeBreakup'])),
      chargeableWeight: jNum(results[1]['chargeableWeight']),
    );
  }

  /// Not idempotent on the server: never call twice for one draft without
  /// checking the outcome of the first call.
  Future<ShipmentDetail> create(BookingDraft draft, {required String branchId}) => _api.post(
    '/api/v1/shipments',
    body: draft.toCreateRequest(branchId),
    parse: (d) => ShipmentDetail.fromJson(jMap(d)),
  );
}
