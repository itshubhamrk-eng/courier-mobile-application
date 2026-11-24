import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/network/api_client.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/session.dart';

/// Who may quick-scan: the same rules the server applies to each call.
class QuickScanAccess {
  const QuickScanAccess(this._s);

  final Session? _s;

  bool _can(String p) => _s?.can(p) ?? false;

  bool get inScan =>
      (_s?.roles.any(const {'COMPANY_ADMIN', 'BRANCH_MANAGER', 'OPERATOR'}.contains) ?? false) ||
      _can(Permissions.manifestReceive) ||
      _can(Permissions.hubInScan);

  /// The server allows out-scan to hub staff only.
  bool get outScan => _can(Permissions.hubOutScan);

  bool get raiseException => _can(Permissions.hubExceptionManage);
}

final quickScanAccessProvider = Provider((ref) => QuickScanAccess(ref.watch(sessionProvider)));

class QuickScanRepository {
  QuickScanRepository(this._api);

  final ApiClient _api;

  /// Records a SHORT exception (and its ticket) with the note. Never changes the shipment's status.
  Future<void> raiseShort({required String shipmentId, required String branchId, required String remarks}) => _api.post(
    '/api/v1/hub-operations/exceptions',
    body: {'shipmentId': shipmentId, 'hubBranchId': branchId, 'exceptionType': 'SHORT', 'remarks': remarks},
    parse: (_) {},
  );
}

final quickScanRepositoryProvider = Provider((ref) => QuickScanRepository(ref.watch(apiClientProvider)));
