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

/// `POST /shipments/preview`: priced by the same code as booking, nothing saved.
/// Shown as sent; the app adds nothing up itself.
class BookingPreview {
  const BookingPreview({
    required this.charges,
    this.actualWeight,
    this.volumetricWeight,
    this.chargeableWeight,
    this.destinationCity,
    this.slab,
    this.ratePerKg,
    this.ewayBillRequired = false,
    this.walletSufficient,
    this.walletAvailable,
  });

  final Charges charges;
  final num? actualWeight;
  final num? volumetricWeight;
  final num? chargeableWeight;
  final String? destinationCity;
  final String? slab;
  final num? ratePerKg;

  /// An E-Way Bill must be entered before booking.
  final bool ewayBillRequired;

  /// Null unless the payment mode collects at booking.
  final bool? walletSufficient;
  final num? walletAvailable;

  factory BookingPreview.fromJson(Map<String, dynamic> j) => BookingPreview(
    charges: Charges.fromJson(jMap(j['charges'])),
    actualWeight: jNum(j['actualWeight']),
    volumetricWeight: jNum(j['volumetricWeight']),
    chargeableWeight: jNum(j['chargeableWeight']),
    destinationCity: jStr(j['destinationCityName']),
    slab: jStr(j['weightSlabLabel']),
    ratePerKg: jNum(j['ratePerKg']),
    ewayBillRequired: j['ewayBillRequired'] == true,
    walletSufficient: j['walletSufficient'] as bool?,
    walletAvailable: jNum(j['walletAvailable']),
  );
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

  /// Read-only on the server (saves nothing), so safe to repeat.
  Future<BookingPreview> preview(BookingDraft draft, {required String branchId}) => _api.post(
    '/api/v1/shipments/preview',
    body: draft.toCreateRequest(branchId),
    parse: (d) => BookingPreview.fromJson(jMap(d)),
  );

  /// Not idempotent on the server: never call twice for one draft without
  /// checking the outcome of the first call.
  Future<ShipmentDetail> create(BookingDraft draft, {required String branchId}) => _api.post(
    '/api/v1/shipments',
    body: draft.toCreateRequest(branchId),
    parse: (d) => ShipmentDetail.fromJson(jMap(d)),
  );
}
