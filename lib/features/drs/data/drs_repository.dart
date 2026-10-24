import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';
import '../../shipments/data/shipment_models.dart';

/// Per-shipment result of a bulk movement call (in-scan, out-for-delivery).
class MovementOutcome {
  const MovementOutcome({required this.reference, required this.success, this.message});

  final String reference;
  final bool success;
  final String? message;

  factory MovementOutcome.fromJson(Map<String, dynamic> j) => MovementOutcome(
    reference: j['reference'] as String? ?? '',
    success: j['success'] == true,
    message: jStr(j['message']),
  );
}

class BulkResult {
  const BulkResult({
    required this.results,
    required this.successCount,
    required this.failureCount,
    this.drsNumber,
    this.shortageTicket,
  });

  final List<MovementOutcome> results;
  final int successCount;
  final int failureCount;
  final String? drsNumber;
  final String? shortageTicket;

  factory BulkResult.fromJson(Map<String, dynamic> j) => BulkResult(
    results: jList(j['results']).map(MovementOutcome.fromJson).toList(),
    successCount: jInt(j['successCount']) ?? 0,
    failureCount: jInt(j['failureCount']) ?? 0,
    drsNumber: jStr(j['drsNumber']),
    shortageTicket: jStr(j['shortageTicketNumber']),
  );
}

class DrsRun {
  const DrsRun({
    required this.deliveryUserId,
    required this.deliveryBranchId,
    required this.runDate,
    this.drsNumber,
    this.shipmentCount = 0,
    this.deliveredCount = 0,
    this.pendingCount = 0,
    this.failedCount = 0,
  });

  final String deliveryUserId;
  final String deliveryBranchId;
  final DateTime runDate;
  final String? drsNumber;
  final int shipmentCount;
  final int deliveredCount;
  final int pendingCount;

  /// Failed attempts on this run; not counted as pending.
  final int failedCount;

  factory DrsRun.fromJson(Map<String, dynamic> j) => DrsRun(
    deliveryUserId: j['deliveryUserId'] as String,
    deliveryBranchId: j['deliveryBranchId'] as String,
    runDate: DateTime.parse(j['runDate'] as String),
    drsNumber: jStr(j['drsNumber']),
    shipmentCount: jInt(j['shipmentCount']) ?? 0,
    deliveredCount: jInt(j['deliveredCount']) ?? 0,
    pendingCount: jInt(j['pendingCount']) ?? 0,
    failedCount: jInt(j['failedCount']) ?? 0,
  );
}

class DrsRow {
  const DrsRow({
    required this.shipmentId,
    required this.trackingNumber,
    required this.status,
    this.shipmentNumber,
    this.receiverName,
    this.receiverAddress,
    this.receiverContact,
    this.paymentModeId,
    this.netAmount,
    this.deliveredAt,
    this.toCity,
  });

  final String shipmentId;
  final String trackingNumber;
  final String status;
  final String? shipmentNumber;
  final String? receiverName;
  final String? receiverAddress;
  final String? receiverContact;
  final String? paymentModeId;
  final num? netAmount;
  final DateTime? deliveredAt;
  final String? toCity;

  factory DrsRow.fromJson(Map<String, dynamic> j) => DrsRow(
    shipmentId: j['shipmentId'] as String,
    trackingNumber: j['trackingNumber'] as String? ?? '',
    status: j['status'] as String? ?? '',
    shipmentNumber: jStr(j['shipmentNumber']),
    receiverName: jStr(j['receiverName']),
    receiverAddress: jStr(j['receiverAddress']),
    receiverContact: jStr(j['receiverContact']),
    paymentModeId: jStr(j['paymentModeId']),
    netAmount: jNum(j['netAmount']),
    deliveredAt: jTime(j['deliveredAt']),
    toCity: jStr(j['toCity']),
  );
}

/// An incoming THC (dispatched loading sheet headed to this branch).
class IncomingSheet {
  const IncomingSheet({
    required this.id,
    required this.number,
    required this.fromBranchId,
    this.dispatchedAt,
    this.shipmentCount = 0,
  });

  final String id;
  final String number;
  final String fromBranchId;
  final DateTime? dispatchedAt;
  final int shipmentCount;

  factory IncomingSheet.fromJson(Map<String, dynamic> j) => IncomingSheet(
    id: j['id'] as String,
    number: j['manifestNumber'] as String? ?? '',
    fromBranchId: j['bookingBranchId'] as String? ?? '',
    dispatchedAt: jTime(j['dispatchedAt']),
    shipmentCount: jInt(j['shipmentCount']) ?? 0,
  );
}

/// Which shipments a DRS can be made from, as on the web Out For Delivery page.
enum DrsSource {
  /// Received (IN_SCAN) shipments whose delivery branch is this branch.
  branch,

  /// At a hub: shipments not routed to a branch, delivered straight from the hub.
  hubDirect,
}

final drsRepositoryProvider = Provider<DrsRepository>((ref) => DrsRepository(ref.watch(apiClientProvider)));

class DrsRepository {
  DrsRepository(this._api);

  final ApiClient _api;

  // ---------------------------------------------------------------- receive

  Future<List<IncomingSheet>> incoming(String branchId) => _api.get(
    '/api/v1/manifests',
    query: {
      'status': 'DISPATCHED',
      'deliveryBranchId': branchId,
      'flowType': 'STANDARD',
      'size': 50,
      'sort': 'dispatchedAt,desc',
    },
    parse: (d) => PageResponse.fromJson(jMap(d), IncomingSheet.fromJson).content,
  );

  /// Marks shipments received at [branchId]. Shipments of [manifestNumber]
  /// left out are sent as missing so the server can raise a shortage ticket.
  Future<BulkResult> inScan({
    required String branchId,
    required List<String> received,
    String? manifestNumber,
    List<String> missing = const [],
    String? remarks,
  }) => _api.post(
    '/api/v1/shipment-movement/in-scan',
    body: {
      'receivingBranchId': branchId,
      'trackingNumbers': received,
      'manifestNumber': manifestNumber,
      'missingTrackingNumbers': missing,
      if (remarks != null && remarks.trim().isNotEmpty) 'remarks': remarks.trim(),
    },
    parse: (d) => BulkResult.fromJson(jMap(d)),
  );

  // ---------------------------------------------------------------- DRS

  Future<List<ShipmentSummary>> readyForDelivery(String branchId, DrsSource source) => _api.get(
    '/api/v1/shipments',
    query: switch (source) {
      DrsSource.branch => {'deliveryBranchId': branchId, 'status': 'IN_SCAN'},
      DrsSource.hubDirect => {
        'currentLocationId': branchId,
        'unassignedDeliveryBranch': true,
        'status': 'READY_FOR_MANIFEST',
      },
    }..addAll({'size': 100, 'sort': 'createdDate,asc'}),
    parse: (d) => PageResponse.fromJson(jMap(d), ShipmentSummary.fromJson).content,
  );

  Future<({String maskedMobile, int expiresInMinutes})> requestOtp(String deliveryUserId) => _api.post(
    '/api/v1/shipment-movement/delivery-otp/request',
    body: {'deliveryUserId': deliveryUserId},
    parse: (d) =>
        (maskedMobile: jStr(jMap(d)['maskedMobile']) ?? '', expiresInMinutes: jInt(jMap(d)['expiresInMinutes']) ?? 5),
  );

  Future<void> verifyOtp(String deliveryUserId, String otp) => _api.post(
    '/api/v1/shipment-movement/delivery-otp/verify',
    body: {'deliveryUserId': deliveryUserId, 'otp': otp},
    parse: (_) {},
  );

  /// Creates the DRS. Not idempotent; per-shipment outcomes come back.
  Future<BulkResult> outForDelivery({
    required List<String> shipmentIds,
    required String deliveryUserId,
    String? vehicleId,
    num? fuelCost,
    num? deliveryCharge,
  }) => _api.post(
    '/api/v1/shipment-movement/out-for-delivery',
    body: {
      'shipmentIds': shipmentIds,
      'deliveryUserId': deliveryUserId,
      'vehicleId': vehicleId,
      'fuelCost': fuelCost,
      'deliveryCharge': deliveryCharge,
    },
    parse: (d) => BulkResult.fromJson(jMap(d)),
  );

  Future<List<DrsRun>> runs({required String branchId, required DateTime from, required DateTime to}) => _api.get(
    '/api/v1/shipment-movement/drs',
    query: {'from': Fmt.apiDate(from), 'to': Fmt.apiDate(to), 'deliveryBranchId': branchId},
    parse: (d) => jList(d).map(DrsRun.fromJson).toList()..sort((a, b) => b.runDate.compareTo(a.runDate)),
  );

  Future<({String? drsNumber, List<DrsRow> rows})> runDetail(DrsRun run) => _api.get(
    '/api/v1/shipment-movement/drs/detail',
    query: {
      'deliveryUserId': run.deliveryUserId,
      'deliveryBranchId': run.deliveryBranchId,
      'runDate': Fmt.apiDate(run.runDate),
    },
    parse: (d) =>
        (drsNumber: jStr(jMap(d)['drsNumber']), rows: jList(jMap(d)['shipments']).map(DrsRow.fromJson).toList()),
  );
}
