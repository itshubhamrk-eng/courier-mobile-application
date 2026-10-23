import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';

class Vehicle {
  const Vehicle({required this.id, required this.number, this.type, this.capacityKg});

  final String id;
  final String number;
  final String? type;
  final num? capacityKg;

  String get label => [number, type?.replaceAll('_', ' ').toLowerCase()].nonNulls.join(' · ');

  factory Vehicle.fromJson(Map<String, dynamic> j) => Vehicle(
    id: j['id'] as String,
    number: j['vehicleNumber'] as String? ?? '',
    type: jStr(j['vehicleType']),
    capacityKg: jNum(j['capacityKg']),
  );
}

class StaffUser {
  const StaffUser({required this.id, required this.name, this.mobile, this.designation, this.branchId});

  final String id;
  final String name;
  final String? mobile;
  final String? designation;
  final String? branchId;

  factory StaffUser.fromJson(Map<String, dynamic> j) => StaffUser(
    id: j['id'] as String,
    name: j['displayName'] as String? ?? '',
    mobile: jStr(j['mobile']),
    designation: jStr(j['designation']),
    branchId: jStr(j['branchId']),
  );
}

/// Result of `POST /shipment-movement/dispatch`. The THC number is the
/// loading sheet (manifest) number, as on the web Trip Hire Challan page.
class ThcResult {
  const ThcResult({
    required this.manifestId,
    required this.number,
    required this.status,
    this.vehicleId,
    this.driverUserId,
    this.dispatchedAt,
    this.departureTime,
    this.shipmentCount,
    this.fuelCost,
    this.driverAdvance,
    this.tollAmount,
    this.otherAmount,
  });

  final String manifestId;
  final String number;
  final String status;
  final String? vehicleId;
  final String? driverUserId;
  final DateTime? dispatchedAt;
  final DateTime? departureTime;
  final int? shipmentCount;
  final num? fuelCost;
  final num? driverAdvance;
  final num? tollAmount;
  final num? otherAmount;

  /// Works for both the dispatch response and a dispatched `ManifestResponse`.
  factory ThcResult.fromJson(Map<String, dynamic> j) => ThcResult(
    manifestId: (j['manifestId'] ?? j['id']) as String,
    number: j['manifestNumber'] as String? ?? '',
    status: j['status'] as String? ?? '',
    vehicleId: jStr(j['vehicleId']),
    driverUserId: jStr(j['driverUserId']),
    dispatchedAt: jTime(j['dispatchedAt']),
    departureTime: jTime(j['departureTime']),
    shipmentCount: jInt(j['shipmentCount']),
    fuelCost: jNum(j['fuelCost']),
    driverAdvance: jNum(j['driverAdvance']),
    tollAmount: jNum(j['tollAmount']),
    otherAmount: jNum(j['otherAmount']),
  );
}

class OutScanOutcome {
  const OutScanOutcome({required this.reference, required this.success, this.message});

  final String reference;
  final bool success;
  final String? message;

  factory OutScanOutcome.fromJson(Map<String, dynamic> j) => OutScanOutcome(
    reference: j['reference'] as String? ?? '',
    success: j['success'] == true,
    message: jStr(j['message']),
  );
}

final thcRepositoryProvider = Provider<ThcRepository>((ref) => ThcRepository(ref.watch(apiClientProvider)));

final vehiclesProvider = FutureProvider.autoDispose<List<Vehicle>>(
  (ref) => ref.watch(thcRepositoryProvider).vehicles(),
);

final staffUsersProvider = FutureProvider.autoDispose<List<StaffUser>>(
  (ref) => ref.watch(thcRepositoryProvider).activeUsers(),
);

class ThcRepository {
  ThcRepository(this._api);

  final ApiClient _api;

  Future<List<Vehicle>> vehicles() => _api.get(
    '/api/v1/vehicles',
    query: {'activeOnly': true},
    parse: (d) => jList(d).map(Vehicle.fromJson).toList()..sort((a, b) => a.number.compareTo(b.number)),
  );

  /// Drivers and delivery staff. Needs a manager role or `USER_READ`
  /// (docs/API_GAPS.md G4); a 403 is shown to the user as such.
  Future<List<StaffUser>> activeUsers() => _api.get(
    '/api/v1/users',
    query: {'status': 'ACTIVE', 'size': 100, 'sort': 'firstName,asc'},
    parse: (d) => PageResponse.fromJson(jMap(d), StaffUser.fromJson).content,
  );

  /// Required before dispatch when the sheet starts at a hub.
  Future<List<OutScanOutcome>> outScan({
    required String manifestId,
    required String hubBranchId,
    required List<String> awbs,
  }) => _api.post(
    '/api/v1/hub-operations/out-scan',
    body: {'manifestId': manifestId, 'hubBranchId': hubBranchId, 'trackingNumbers': awbs},
    parse: (d) => jList(d).map(OutScanOutcome.fromJson).toList(),
  );

  /// Optional driver OTP (the web page offers it without requiring it).
  Future<({String maskedMobile, int expiresInMinutes})> requestOtp(String manifestId, String driverUserId) => _api.post(
    '/api/v1/shipment-movement/dispatch-otp/request',
    body: {'manifestId': manifestId, 'driverUserId': driverUserId},
    parse: (d) =>
        (maskedMobile: jStr(jMap(d)['maskedMobile']) ?? '', expiresInMinutes: jInt(jMap(d)['expiresInMinutes']) ?? 5),
  );

  Future<void> verifyOtp(String manifestId, String driverUserId, String otp) => _api.post(
    '/api/v1/shipment-movement/dispatch-otp/verify',
    body: {'manifestId': manifestId, 'driverUserId': driverUserId, 'otp': otp},
    parse: (_) {},
  );

  /// A sheet's THC details, read back from the manifest (for an already
  /// dispatched sheet, or to settle a dispatch whose answer was lost).
  Future<ThcResult> sheetAsThc(String manifestId) =>
      _api.get('/api/v1/manifests/$manifestId', parse: (d) => ThcResult.fromJson(jMap(d)));

  /// Moves the sheet CREATED → DISPATCHED. The server refuses a second dispatch.
  Future<ThcResult> dispatch({
    required String manifestId,
    required String vehicleId,
    required String driverUserId,
    required DateTime departureTime,
    num? fuelCost,
    num? driverAdvance,
    num? tollAmount,
    num? otherAmount,
  }) => _api.post(
    '/api/v1/shipment-movement/dispatch',
    body: {
      'manifestId': manifestId,
      'vehicleId': vehicleId,
      'driverUserId': driverUserId,
      'departureTime': departureTime.toUtc().toIso8601String(),
      'fuelCost': fuelCost,
      'driverAdvance': driverAdvance,
      'tollAmount': tollAmount,
      'otherAmount': otherAmount,
    },
    parse: (d) => ThcResult.fromJson(jMap(d)),
  );
}
