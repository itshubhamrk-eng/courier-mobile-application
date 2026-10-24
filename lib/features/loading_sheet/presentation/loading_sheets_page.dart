import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_controller.dart';
import '../../masters/data/masters.dart';
import '../data/loading_sheet_repository.dart';
import '../../shell/branch_header.dart';

final loadingSheetsProvider = FutureProvider.autoDispose.family<List<LoadingSheet>, String>((ref, status) async {
  final branchId = ref.watch(sessionProvider.select((s) => s?.operatingBranchId));
  if (branchId == null) return const [];
  final page = await ref.watch(loadingSheetRepositoryProvider).list(branchId: branchId, status: status);
  return page.content;
});

/// Loading tab: open sheets (waiting for THC), dispatched and completed.
class LoadingSheetsPage extends ConsumerWidget {
  const LoadingSheetsPage({super.key});

  static const _tabs = [('CREATED', 'Open'), ('DISPATCHED', 'Dispatched'), ('COMPLETED', 'Completed')];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canCreate = ref.watch(sessionProvider)?.can(Permissions.manifestCreate) ?? false;
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: sectionBar('Loading Sheets', bottom: sectionTabs([for (final (_, label) in _tabs) Tab(text: label)])),
        floatingActionButton: canCreate
            ? FloatingActionButton.extended(
                onPressed: () async {
                  await context.push('/loading-sheets/new');
                  ref.invalidate(loadingSheetsProvider);
                },
                icon: const Icon(Icons.add),
                label: const Text('New sheet'),
              )
            : null,
        body: TabBarView(children: [for (final (status, _) in _tabs) _SheetList(status: status)]),
      ),
    );
  }
}

class _SheetList extends ConsumerWidget {
  const _SheetList({required this.status});

  final String status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sheets = ref.watch(loadingSheetsProvider(status));
    Future<void> refresh() => ref.refresh(loadingSheetsProvider(status).future);

    return switch (sheets) {
      AsyncData(:final value) when value.isEmpty => RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 300,
              child: EmptyView(message: status == 'CREATED' ? 'No open loading sheets.' : 'Nothing here yet.'),
            ),
          ],
        ),
      ),
      AsyncData(:final value) => RefreshIndicator(
        onRefresh: refresh,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          itemCount: value.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) => LoadingSheetTile(sheet: value[i]),
        ),
      ),
      AsyncError(:final error) => ErrorView(error: error, onRetry: refresh),
      _ => const LoadingView(),
    };
  }
}

class LoadingSheetTile extends ConsumerWidget {
  const LoadingSheetTile({super.key, required this.sheet, this.onTap});

  final LoadingSheet sheet;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branches = ref.watch(branchNamesProvider).value ?? const {};
    final to = branches[sheet.deliveryBranchId]?.label ?? '–';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap ?? () => context.push('/loading-sheets/${sheet.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(sheet.number, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  StatusBadge(sheet.status),
                ],
              ),
              const SizedBox(height: 4),
              Text('To $to', style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              Text(
                '${sheet.shipmentCount} shipments · ${sheet.totalPackages} pkg · ${Fmt.kg(sheet.totalWeight)}'
                ' · ${Fmt.dateTime(sheet.createdAt)}',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
