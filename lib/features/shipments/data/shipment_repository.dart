import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import 'shipment_models.dart';
import '../../../core/scan_code.dart';

final shipmentRepositoryProvider = Provider<ShipmentRepository>(
  (ref) => ShipmentRepository(ref.watch(apiClientProvider)),
);

/// Everything the detail / tracking screen shows, loaded together.
class ShipmentView {
  const ShipmentView({
    required this.shipment,
    required this.history,
    this.exceptions = const [],
    this.charges,
    this.deliveryRun,
    this.pod,
  });

  final ShipmentDetail shipment;

  /// Newest first.
  final List<StatusEvent> history;
  final List<ShipmentExceptionEvent> exceptions;

  /// Null when the user may not see charges or the call failed.
  final Charges? charges;
  final DeliveryRun? deliveryRun;
  final PodInfo? pod;
}

class ShipmentRepository {
  ShipmentRepository(this._api);

  final ApiClient _api;

  Future<PageResponse<ShipmentSummary>> list({
    required String bookingBranchId,
    String? search,
    Set<String>? statuses,
    int page = 0,
  }) => _api.get(
    '/api/v1/shipments',
    query: {
      'bookingBranchId': bookingBranchId,
      if (search != null && search.isNotEmpty) 'search': search,
      if (statuses != null && statuses.isNotEmpty) 'status': statuses.toList(),
      'page': page,
      'size': 20,
      'sort': 'createdDate,desc',
    },
    parse: (d) => PageResponse.fromJson(jMap(d), ShipmentSummary.fromJson),
  );

  Future<ShipmentDetail> byId(String id) =>
      _api.get('/api/v1/shipments/$id', parse: (d) => ShipmentDetail.fromJson(jMap(d)));

  /// AWB (tracking number) lookup; the server also matches shipment numbers.
  /// A scanned label package id (`<AWB>-001`) falls back to its AWB.
  Future<ShipmentDetail> byAwb(String awb) async {
    final candidates = scanCandidates(awb);
    for (var i = 0; i < candidates.length; i++) {
      try {
        return await _api.get(
          '/api/v1/shipments/track/${Uri.encodeComponent(candidates[i])}',
          parse: (d) => ShipmentDetail.fromJson(jMap(d)),
        );
      } on ApiException catch (e) {
        if (e.kind != ApiErrorKind.notFound || i == candidates.length - 1) rethrow;
      }
    }
    throw StateError('unreachable');
  }

  Future<List<StatusEvent>> history(String id) => _api.get(
    '/api/v1/shipments/$id/history',
    parse: (d) => jList(d).map(StatusEvent.fromJson).toList()..sort((a, b) => b.at.compareTo(a.at)),
  );

  Future<Charges> charges(String id) =>
      _api.get('/api/v1/shipments/$id/charges', parse: (d) => Charges.fromJson(jMap(d)));

  Future<DeliveryRun?> deliveryRun(String id) =>
      _api.get('/api/v1/shipments/$id/delivery-run', parse: (d) => d == null ? null : DeliveryRun.fromJson(jMap(d)));

  Future<PodInfo?> pod(String id) =>
      _api.get('/api/v1/shipments/$id/pod/verification', parse: (d) => d == null ? null : PodInfo.fromJson(jMap(d)));

  Future<List<ShipmentExceptionEvent>> exceptions(String id) => _api.get(
    '/api/v1/hub-operations/exceptions',
    query: {'shipmentId': id, 'size': 50},
    parse: (d) => jList(jMap(d)['content']).map(ShipmentExceptionEvent.fromJson).toList(),
  );

  /// Shipment plus history (required) and the optional sections, each of which
  /// may be missing (no permission, nothing yet) without failing the screen.
  Future<ShipmentView> view(ShipmentDetail shipment, {required bool withCharges}) async {
    Future<T?> optional<T>(Future<T?> call) async {
      try {
        return await call;
      } on ApiException {
        return null;
      }
    }

    final id = shipment.id;
    final delivered = shipment.status == 'DELIVERED';
    final results = await Future.wait(<Future<Object?>>[
      history(id),
      optional(exceptions(id)),
      withCharges ? optional(charges(id)) : Future.value(),
      optional(deliveryRun(id)),
      delivered ? optional(pod(id)) : Future.value(),
    ]);
    return ShipmentView(
      shipment: shipment,
      history: results[0]! as List<StatusEvent>,
      exceptions: (results[1] as List<ShipmentExceptionEvent>?) ?? const [],
      charges: results[2] as Charges?,
      deliveryRun: results[3] as DeliveryRun?,
      pod: results[4] as PodInfo?,
    );
  }
}

/// Shipment screen data by id.
final shipmentViewByIdProvider = FutureProvider.autoDispose.family<ShipmentView, ({String id, bool withCharges})>((
  ref,
  arg,
) async {
  final repo = ref.watch(shipmentRepositoryProvider);
  return repo.view(await repo.byId(arg.id), withCharges: arg.withCharges);
});
