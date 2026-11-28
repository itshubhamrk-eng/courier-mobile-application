import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';
import '../../auth/application/auth_controller.dart';
import '../../masters/data/masters.dart';

/// Branch type of a Vendor (the web's "Pickup Delivery Partner").
const vendorBranchType = 'PICKUP_DELIVERY_PARTNER';

/// The signed-in user works at a Vendor. Read from the branch directory, like the web
/// (`PartnerContextService`); false while unknown, so the full app shows rather than none.
final isVendorProvider = Provider<bool>((ref) {
  final branchId = ref.watch(sessionProvider.select((s) => s?.operatingBranchId));
  final branches = ref.watch(branchNamesProvider).value;
  return branchId != null && branches?[branchId]?.type == vendorBranchType;
});

class Pickup {
  const Pickup({
    required this.id,
    required this.number,
    required this.status,
    required this.contactName,
    required this.contactMobile,
    required this.address,
    required this.pincode,
    this.city,
    this.expectedParcels = 1,
    this.expectedWeightKg,
    this.preferredDate,
    this.preferredSlot,
    this.remarks,
    this.actualParcels,
    this.actualWeightKg,
    this.shipmentNo,
    this.failReason,
    this.createdAt,
  });

  final String id;
  final String number;
  final String status;
  final String contactName;
  final String contactMobile;
  final String address;
  final String pincode;
  final String? city;
  final int expectedParcels;
  final num? expectedWeightKg;
  final DateTime? preferredDate;
  final String? preferredSlot;
  final String? remarks;
  final int? actualParcels;
  final num? actualWeightKg;
  final String? shipmentNo;
  final String? failReason;
  final DateTime? createdAt;

  /// Still the vendor's to work (the server's `PickupStatus.isOpen` less REQUESTED, which is unassigned).
  bool get isOpen => const {'ASSIGNED', 'ACCEPTED', 'OUT_FOR_PICKUP', 'PICKED_UP'}.contains(status);

  String get fullAddress => [address, city, pincode].nonNulls.where((s) => s.isNotEmpty).join(', ');

  factory Pickup.fromJson(Map<String, dynamic> j) => Pickup(
    id: j['id'] as String,
    number: jStr(j['pickupNo']) ?? '',
    status: jStr(j['status']) ?? '',
    contactName: jStr(j['contactName']) ?? '',
    contactMobile: jStr(j['contactMobile']) ?? '',
    address: jStr(j['addressLine']) ?? '',
    pincode: jStr(j['pincode']) ?? '',
    city: jStr(j['city']),
    expectedParcels: jInt(j['expectedParcels']) ?? 1,
    expectedWeightKg: jNum(j['expectedWeightKg']),
    preferredDate: jTime(j['preferredDate']),
    preferredSlot: jStr(j['preferredSlot']),
    remarks: jStr(j['remarks']),
    actualParcels: jInt(j['actualParcels']),
    actualWeightKg: jNum(j['actualWeightKg']),
    shipmentNo: jStr(j['shipmentNo']),
    failReason: jStr(j['failReason']),
    createdAt: jTime(j['createdDate']),
  );
}

class VendorDashboard {
  const VendorDashboard(this._j);

  final Map<String, dynamic> _j;

  num? _n(String group, String key) => jNum(jMap(_j[group])[key]);

  int get openPickups => (_n('pickups', 'open') ?? 0).toInt();
  int get unaccepted => (_n('pickups', 'unaccepted') ?? 0).toInt();
  int get pickedUpThisMonth => (_n('pickups', 'pickedUpThisMonth') ?? 0).toInt();
  int get atVendor => (_n('deliveries', 'atPartner') ?? 0).toInt();
  int get outForDelivery => (_n('deliveries', 'outForDelivery') ?? 0).toInt();
  int get podPending => (_n('deliveries', 'podPending') ?? 0).toInt();
  int get deliveredThisMonth => (_n('deliveries', 'deliveredThisMonth') ?? 0).toInt();
  num? get earnedThisMonth => _n('earnings', 'earnedThisMonth');
  num? get accrued => _n('earnings', 'accruedAmount');
  num? get outstanding => _n('statements', 'outstandingPayable');
  num? get paidThisMonth => _n('statements', 'paidThisMonth');
}

class Earning {
  const Earning({
    required this.id,
    required this.type,
    required this.reference,
    required this.status,
    this.earnedOn,
    this.chargeableKg,
    this.ratePerKg,
    this.total,
    this.remark,
  });

  final String id;
  final String type;
  final String reference;
  final String status;
  final DateTime? earnedOn;
  final num? chargeableKg;
  final num? ratePerKg;
  final num? total;
  final String? remark;

  factory Earning.fromJson(Map<String, dynamic> j) => Earning(
    id: j['id'] as String,
    type: jStr(j['earningType']) ?? '',
    reference: jStr(j['referenceNo']) ?? '',
    status: jStr(j['status']) ?? '',
    earnedOn: jTime(j['earnedOn']),
    chargeableKg: jNum(j['chargeableWeightKg']),
    ratePerKg: jNum(j['ratePerKg']),
    total: jNum(j['totalAmount']),
    remark: jStr(j['remark']),
  );
}

class Statement {
  const Statement({
    required this.id,
    required this.number,
    required this.status,
    this.from,
    this.to,
    this.pickups = 0,
    this.deliveries = 0,
    this.netPayable,
    this.paidOn,
    this.paymentRef,
  });

  final String id;
  final String number;
  final String status;
  final DateTime? from;
  final DateTime? to;
  final int pickups;
  final int deliveries;
  final num? netPayable;
  final DateTime? paidOn;
  final String? paymentRef;

  factory Statement.fromJson(Map<String, dynamic> j) => Statement(
    id: j['id'] as String,
    number: jStr(j['statementNo']) ?? '',
    status: jStr(j['status']) ?? '',
    from: jTime(j['periodFrom']),
    to: jTime(j['periodTo']),
    pickups: jInt(j['pickupCount']) ?? 0,
    deliveries: jInt(j['deliveryCount']) ?? 0,
    netPayable: jNum(j['netPayable']),
    paidOn: jTime(j['paidOn']),
    paymentRef: jStr(j['paymentRef']),
  );
}

/// Pickup requests, vendor dashboard, earnings and statements. The server scopes every
/// read and action to the caller's own vendor branch.
class VendorRepository {
  VendorRepository(this._api);

  final ApiClient _api;
  static const _pickups = '/api/v1/pickups';

  Future<VendorDashboard> dashboard() => _api.get('/api/v1/pdp-dashboard', parse: (d) => VendorDashboard(jMap(d)));

  Future<PageResponse<Pickup>> pickups({int page = 0, int size = 50}) => _api.get(
    _pickups,
    query: {'page': page, 'size': size},
    parse: (d) => PageResponse.fromJson(jMap(d), Pickup.fromJson),
  );

  Future<Pickup> _act(String id, String action, [Object body = const {}]) =>
      _api.patch('$_pickups/$id/$action', body: body, parse: (d) => Pickup.fromJson(jMap(d)));

  Future<Pickup> accept(String id) => _act(id, 'accept');
  Future<Pickup> reject(String id, String reason) => _act(id, 'reject', {'reason': reason});
  Future<Pickup> start(String id) => _act(id, 'start');
  Future<Pickup> fail(String id, String reason) => _act(id, 'fail', {'reason': reason});
  Future<Pickup> collected(String id, {required int parcels, required num weightKg}) =>
      _act(id, 'complete', {'actualParcels': parcels, 'actualWeightKg': weightKg});

  /// Moves a collected pickup to Booked, and accrues the vendor's pickup earning.
  Future<void> linkShipment(String id, {required String shipmentId, String? shipmentNo}) =>
      _api.patch('$_pickups/$id/shipment', body: {'shipmentId': shipmentId, 'shipmentNo': shipmentNo}, parse: (_) {});

  Future<PageResponse<Earning>> earnings({int page = 0}) => _api.get(
    '/api/v1/pdp-earnings',
    query: {'page': page, 'size': 30},
    parse: (d) => PageResponse.fromJson(jMap(d), Earning.fromJson),
  );

  Future<PageResponse<Statement>> statements({int page = 0}) => _api.get(
    '/api/v1/pdp-statements',
    query: {'page': page, 'size': 30},
    parse: (d) => PageResponse.fromJson(jMap(d), Statement.fromJson),
  );
}

final vendorRepositoryProvider = Provider<VendorRepository>((ref) => VendorRepository(ref.watch(apiClientProvider)));

final vendorDashboardProvider = FutureProvider.autoDispose<VendorDashboard>(
  (ref) => ref.watch(vendorRepositoryProvider).dashboard(),
);

final pickupsProvider = FutureProvider.autoDispose<List<Pickup>>(
  (ref) async => (await ref.watch(vendorRepositoryProvider).pickups(size: 100)).content,
);
