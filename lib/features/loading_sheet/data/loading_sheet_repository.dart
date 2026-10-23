import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';
import '../../shipments/data/shipment_models.dart';

/// A loading sheet is a courier-service manifest (`/api/v1/manifests`).
class LoadingSheet {
  const LoadingSheet({
    required this.id,
    required this.number,
    required this.status,
    required this.bookingBranchId,
    this.deliveryBranchId,
    this.deliveryMode,
    this.shipmentCount = 0,
    this.totalPackages = 0,
    this.totalWeight,
    this.createdAt,
    this.dispatchedAt,
    this.vehicleId,
    this.driverUserId,
    this.remarks,
  });

  final String id;
  final String number;

  /// CREATED (open, waiting for THC) → DISPATCHED → COMPLETED.
  final String status;
  final String bookingBranchId;
  final String? deliveryBranchId;
  final String? deliveryMode;
  final int shipmentCount;
  final int totalPackages;
  final num? totalWeight;
  final DateTime? createdAt;
  final DateTime? dispatchedAt;
  final String? vehicleId;
  final String? driverUserId;
  final String? remarks;

  bool get isOpen => status == 'CREATED';

  factory LoadingSheet.fromJson(Map<String, dynamic> j) => LoadingSheet(
    id: j['id'] as String,
    number: j['manifestNumber'] as String? ?? '',
    status: j['status'] as String? ?? '',
    bookingBranchId: j['bookingBranchId'] as String? ?? '',
    deliveryBranchId: jStr(j['deliveryBranchId']),
    deliveryMode: jStr(j['deliveryMode']),
    shipmentCount: jInt(j['shipmentCount']) ?? 0,
    totalPackages: jInt(j['totalPackages']) ?? 0,
    totalWeight: jNum(j['totalWeight']),
    createdAt: jTime(j['createdAt']),
    dispatchedAt: jTime(j['dispatchedAt']),
    vehicleId: jStr(j['vehicleId']),
    driverUserId: jStr(j['driverUserId']),
    remarks: jStr(j['remarks']),
  );
}

/// How the destination is chosen, same three modes as the web Loading Sheet page.
enum LoadingMode {
  /// Send to a hub for sorting (default). Shipments not yet routed to a branch.
  hub,

  /// Send straight to a branch. Shipments not yet routed to a branch.
  branch,

  /// At a hub: send shipments onward to the next stop already set on them.
  nextStop,
}

/// Statuses a shipment can be loaded from (`ShipmentStatus`).
const loadableStatuses = {'BOOKED', 'READY_FOR_MANIFEST'};

final loadingSheetRepositoryProvider = Provider<LoadingSheetRepository>(
  (ref) => LoadingSheetRepository(ref.watch(apiClientProvider)),
);

class LoadingSheetRepository {
  LoadingSheetRepository(this._api);

  final ApiClient _api;

  Future<PageResponse<LoadingSheet>> list({required String branchId, required String status, int page = 0}) => _api.get(
    '/api/v1/manifests',
    query: {
      'bookingBranchId': branchId,
      'status': status,
      'flowType': 'STANDARD',
      'page': page,
      'size': 20,
      'sort': 'createdAt,desc',
    },
    parse: (d) => PageResponse.fromJson(jMap(d), LoadingSheet.fromJson),
  );

  Future<LoadingSheet> byId(String id) =>
      _api.get('/api/v1/manifests/$id', parse: (d) => LoadingSheet.fromJson(jMap(d)));

  Future<List<ShipmentSummary>> shipmentsOf(String id) =>
      _api.get('/api/v1/manifests/$id/shipments', parse: (d) => jList(d).map(ShipmentSummary.fromJson).toList());

  Future<void> removeShipment(String manifestId, String shipmentId) =>
      _api.delete('/api/v1/manifests/$manifestId/shipments/$shipmentId', parse: (_) {});

  /// Shipments at [branchId] that can go on a sheet. For [LoadingMode.nextStop]
  /// pass [nextLocationId] to get only those headed there; for hub / branch mode
  /// only shipments not yet routed to a delivery branch are returned.
  Future<List<ShipmentSummary>> eligible({
    required String branchId,
    required LoadingMode mode,
    String? nextLocationId,
  }) => _api.get(
    '/api/v1/shipments',
    query: {
      'currentLocationId': branchId,
      'status': loadableStatuses.toList(),
      'flowType': 'STANDARD',
      if (mode != LoadingMode.nextStop) 'unassignedDeliveryBranch': true,
      if (mode == LoadingMode.nextStop && nextLocationId != null) 'nextLocationId': nextLocationId,
      'size': 100,
      'sort': 'createdDate,asc',
    },
    parse: (d) => PageResponse.fromJson(jMap(d), ShipmentSummary.fromJson).content,
  );

  /// Not idempotent: never call twice for one selection without checking the
  /// outcome of the first call.
  Future<LoadingSheet> create({
    required String branchId,
    required String destinationId,
    required LoadingMode mode,
    required List<String> shipmentIds,
    String? remarks,
  }) => _api.post(
    '/api/v1/manifests',
    body: {
      'bookingBranchId': branchId,
      'deliveryBranchId': destinationId,
      'deliveryMode': 'BRANCH_DELIVERY',
      'destinationCity': null,
      'shipmentIds': shipmentIds,
      'hubTransfer': mode == LoadingMode.hub,
      'flowType': 'STANDARD',
      if (remarks != null && remarks.trim().isNotEmpty) 'remarks': remarks.trim(),
    },
    parse: (d) => LoadingSheet.fromJson(jMap(d)),
  );
}

/// Why a shipment cannot go on this sheet, or null if it can. A first check on
/// the phone so staff get an answer right after scanning; the server checks again.
String? loadingIneligibility(
  ShipmentSummary s, {
  required String branchId,
  required LoadingMode mode,
  String? destinationId,
}) {
  if (s.manifestId != null && !loadableStatuses.contains(s.status)) return 'Already on a loading sheet.';
  if (!loadableStatuses.contains(s.status)) return 'Status is ${s.status.replaceAll('_', ' ').toLowerCase()}.';
  if (s.currentLocationId != branchId) return 'Not at your branch.';
  if (s.flowType != null && s.flowType != 'STANDARD') return 'Not a standard-flow shipment.';
  switch (mode) {
    case LoadingMode.hub:
    case LoadingMode.branch:
      if (s.nextLocationId != null || s.deliveryBranchId != null) {
        return 'Already routed to a branch. Use Next stop.';
      }
    case LoadingMode.nextStop:
      final next = s.nextLocationId ?? s.deliveryBranchId;
      if (next == null) return 'No next stop set. Use Hub or Branch.';
      if (destinationId != null && next != destinationId) return 'Headed to a different branch.';
  }
  return null;
}
