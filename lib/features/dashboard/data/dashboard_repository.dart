import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/application/auth_controller.dart';

/// The nine dashboard counts. A null field means its source call failed; the
/// card shows a dash rather than a guessed number.
class DashboardCounts {
  const DashboardCounts({
    this.todayBookings,
    this.pendingLoading,
    this.loadingSheetsOpen,
    this.pendingDispatch,
    this.thcInTransit,
    this.pendingDrs,
    this.outForDelivery,
    this.deliveredToday,
    this.pendingPod,
    this.failures = const [],
  });

  final int? todayBookings;
  final int? pendingLoading;
  final int? loadingSheetsOpen;
  final int? pendingDispatch;
  final int? thcInTransit;
  final int? pendingDrs;
  final int? outForDelivery;
  final int? deliveredToday;
  final int? pendingPod;

  /// Errors from the calls that failed, for the "some figures could not load" banner.
  final List<ApiException> failures;
}

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(ref.watch(apiClientProvider)),
);

final dashboardCountsProvider = FutureProvider.autoDispose<DashboardCounts>((ref) {
  final branchId = ref.watch(sessionProvider.select((s) => s?.operatingBranchId));
  if (branchId == null) throw const ApiException(ApiErrorKind.forbidden, 'No branch is assigned to this account.');
  return ref.watch(dashboardRepositoryProvider).load(branchId);
});

class DashboardRepository {
  DashboardRepository(this._api);

  final ApiClient _api;

  /// Source of each card (see docs/API_MAP.md, section 2):
  /// - `/dashboard/summary` is already scoped to the caller's branch by the server.
  /// - Manifest and shipment summaries are filtered to [branchId] explicitly.
  Future<DashboardCounts> load(String branchId) async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final failures = <ApiException>[];

    Future<T?> attempt<T>(Future<T> call) async {
      try {
        return await call;
      } on ApiException catch (e) {
        failures.add(e);
        return null;
      }
    }

    final results = await Future.wait<Object?>([
      attempt(_api.get('/api/v1/dashboard/summary', parse: _map)),
      attempt(
        _api.get('/api/v1/manifests/summary', query: {'bookingBranchId': branchId, 'status': 'CREATED'}, parse: _map),
      ),
      attempt(
        _api.get(
          '/api/v1/manifests/summary',
          query: {'bookingBranchId': branchId, 'status': 'DISPATCHED'},
          parse: _map,
        ),
      ),
      attempt(
        _api.get(
          '/api/v1/shipments/summary',
          query: {
            'deliveryBranchId': branchId,
            'status': ['IN_SCAN', 'OUT_FOR_DELIVERY'],
          },
          parse: _map,
        ),
      ),
      attempt(
        _api.get(
          '/api/v1/shipments/summary',
          query: {'deliveryBranchId': branchId, 'deliveredDateFrom': today, 'deliveredDateTo': today},
          parse: _map,
        ),
      ),
    ]);

    final summary = results[0] as Map<String, dynamic>?;
    final created = results[1] as Map<String, dynamic>?;
    final dispatched = results[2] as Map<String, dynamic>?;
    final delivery = results[3] as Map<String, dynamic>?;
    final delivered = results[4] as Map<String, dynamic>?;

    final stats = summary?['statistics'] as Map<String, dynamic>?;
    final branch = summary?['branchOverview'] as Map<String, dynamic>?;
    final pod = branch?['podOverview'] as Map<String, dynamic>?;
    final statusCounts = delivery?['statusCounts'] as Map<String, dynamic>?;

    if (failures.length == results.length) throw failures.first;

    return DashboardCounts(
      todayBookings: _int(stats?['todayBookings']),
      pendingLoading: _int(branch?['readyForManifest']),
      loadingSheetsOpen: _int(created?['totalManifests']),
      pendingDispatch: _int(branch?['manifestsAwaitingDispatch']),
      thcInTransit: _int(dispatched?['totalManifests']),
      pendingDrs: statusCounts == null ? null : _int(statusCounts['IN_SCAN']) ?? 0,
      outForDelivery: statusCounts == null ? null : _int(statusCounts['OUT_FOR_DELIVERY']) ?? 0,
      deliveredToday: _int(delivered?['totalCount']),
      pendingPod: _int(pod?['pendingUpload']),
      failures: failures,
    );
  }

  static Map<String, dynamic> _map(Object? d) => d! as Map<String, dynamic>;

  static int? _int(Object? v) => v is num ? v.toInt() : null;
}
