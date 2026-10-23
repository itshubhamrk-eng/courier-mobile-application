import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/format.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_controller.dart';
import '../../masters/data/masters.dart';
import '../../shipments/data/shipment_models.dart';
import '../../shipments/presentation/bookings_list_page.dart';
import '../data/loading_sheet_repository.dart';
import '../../documents/document_page.dart';
import '../../documents/document_service.dart';

typedef SheetWithShipments = ({LoadingSheet sheet, List<ShipmentSummary> shipments});

final loadingSheetDetailProvider = FutureProvider.autoDispose.family<SheetWithShipments, String>((ref, id) async {
  final repo = ref.watch(loadingSheetRepositoryProvider);
  final results = await Future.wait([repo.byId(id), repo.shipmentsOf(id)]);
  return (sheet: results[0] as LoadingSheet, shipments: results[1] as List<ShipmentSummary>);
});

class LoadingSheetDetailPage extends ConsumerWidget {
  const LoadingSheetDetailPage({super.key, required this.sheetId});

  final String sheetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(loadingSheetDetailProvider(sheetId));
    final session = ref.watch(sessionProvider);
    final branches = ref.watch(branchNamesProvider).value ?? const {};
    Future<void> refresh() => ref.refresh(loadingSheetDetailProvider(sheetId).future);

    return Scaffold(
      appBar: AppBar(
        title: Text(data.value?.sheet.number ?? 'Loading Sheet'),
        actions: [
          if (data.value case final v?)
            PopupMenuButton<bool>(
              tooltip: 'Print',
              icon: const Icon(Icons.print_outlined),
              onSelected: (asThc) => openDocument(
                context,
                title: '${asThc ? 'THC' : 'Loading sheet'} ${v.sheet.number}',
                fileName: '${asThc ? 'thc' : 'loading-sheet'}-${v.sheet.number}.pdf',
                build: () => ref.read(documentServiceProvider).sheet(sheetId, asThc: asThc),
              ),
              itemBuilder: (_) => [
                const PopupMenuItem(value: false, child: Text('Loading sheet')),
                if (!v.sheet.isOpen) const PopupMenuItem(value: true, child: Text('THC')),
              ],
            ),
        ],
      ),
      body: switch (data) {
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              value.sheet.number,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                          ),
                          StatusBadge(value.sheet.status),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('From ${branches[value.sheet.bookingBranchId]?.label ?? '–'}'),
                      Text('To ${branches[value.sheet.deliveryBranchId]?.label ?? '–'}'),
                      Text('Created ${Fmt.dateTime(value.sheet.createdAt)}'),
                      if (value.sheet.dispatchedAt != null)
                        Text('Dispatched ${Fmt.dateTime(value.sheet.dispatchedAt)}'),
                      if (value.sheet.remarks != null) Text('Remarks: ${value.sheet.remarks}'),
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _Stat('Shipments', '${value.sheet.shipmentCount}'),
                          _Stat('Packages', '${value.sheet.totalPackages}'),
                          _Stat('Weight', Fmt.kg(value.sheet.totalWeight)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (value.sheet.isOpen && (session?.can(Permissions.manifestDispatch) ?? false)) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => context.push('/thc?manifestId=${value.sheet.id}'),
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: const Text('Generate THC'),
                ),
              ],
              const SizedBox(height: 16),
              Text('Shipments (${value.shipments.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final s in value.shipments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ShipmentTile(
                    shipment: s,
                    trailing: value.sheet.isOpen && (session?.can(Permissions.manifestCreate) ?? false)
                        ? IconButton(
                            tooltip: 'Remove from sheet',
                            icon: const Icon(Icons.remove_circle_outline, color: AppColors.danger),
                            onPressed: () => _remove(context, ref, value, s),
                          )
                        : null,
                  ),
                ),
            ],
          ),
        ),
        AsyncError(:final error) => ErrorView(error: error, onRetry: refresh),
        _ => const LoadingView(),
      },
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, SheetWithShipments value, ShipmentSummary s) async {
    final last = value.shipments.length == 1;
    final ok = await confirmAction(
      context,
      title: 'Remove ${s.trackingNumber}?',
      message: last
          ? 'This is the last shipment on the sheet. It goes back to the waiting list.'
          : 'The shipment goes back to the waiting list.',
      confirmLabel: 'Remove',
    );
    if (!ok) return;
    try {
      await ref.read(loadingSheetRepositoryProvider).removeShipment(value.sheet.id, s.id);
      if (context.mounted) showSuccess(context, '${s.trackingNumber} removed.');
    } on ApiException catch (e) {
      if (context.mounted) showFailure(context, e);
    }
    ref.invalidate(loadingSheetDetailProvider(sheetId));
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
    ],
  );
}
