import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/ui.dart';
import '../../auth/application/auth_controller.dart';
import '../../masters/data/masters.dart';
import '../../thc/data/thc_repository.dart';
import '../data/drs_repository.dart';
import '../../shell/branch_header.dart';

final incomingSheetsProvider = FutureProvider.autoDispose<List<IncomingSheet>>((ref) {
  final branchId = ref.watch(sessionProvider.select((s) => s?.operatingBranchId));
  if (branchId == null) return const [];
  return ref.watch(drsRepositoryProvider).incoming(branchId);
});

/// Days of DRS runs shown on the Runs tab, ending today.
final drsRangeDaysProvider = NotifierProvider<DrsRangeDays, int>(DrsRangeDays.new);

class DrsRangeDays extends Notifier<int> {
  @override
  int build() => 1;

  void set(int days) => state = days;
}

final drsRunsProvider = FutureProvider.autoDispose<List<DrsRun>>((ref) {
  final branchId = ref.watch(sessionProvider.select((s) => s?.operatingBranchId));
  final days = ref.watch(drsRangeDaysProvider);
  if (branchId == null) return const [];
  final today = DateTime.now();
  return ref
      .watch(drsRepositoryProvider)
      .runs(
        branchId: branchId,
        from: today.subtract(Duration(days: days - 1)),
        to: today,
      );
});

/// Delivery tab: receive incoming THCs, make DRS, follow delivery runs.
class DeliveryPage extends ConsumerWidget {
  const DeliveryPage({super.key, this.initialTab = 0});

  /// 0 = In Scan (receive), 1 = Delivery runs.
  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final canAssign = session?.can(Permissions.deliveryAssign) ?? false;
    return DefaultTabController(
      key: ValueKey(initialTab),
      initialIndex: initialTab,
      length: 2,
      child: Scaffold(
        appBar: sectionBar(
          'Delivery',
          bottom: sectionTabs(const [Tab(text: 'In Scan'), Tab(text: 'Delivery runs')]),
        ),
        floatingActionButton: canAssign
            ? FloatingActionButton.extended(
                onPressed: () async {
                  await context.push('/drs/new');
                  ref.invalidate(drsRunsProvider);
                },
                icon: const Icon(Icons.assignment_outlined),
                label: const Text('New DRS'),
              )
            : null,
        body: const TabBarView(children: [_ReceiveTab(), _RunsTab()]),
      ),
    );
  }
}

class _ReceiveTab extends ConsumerWidget {
  const _ReceiveTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incoming = ref.watch(incomingSheetsProvider);
    final branches = ref.watch(branchNamesProvider).value ?? const <String, Branch>{};
    Future<void> refresh() => ref.refresh(incomingSheetsProvider.future);

    return RefreshIndicator(
      onRefresh: refresh,
      child: switch (incoming) {
        AsyncData(:final value) when value.isEmpty => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [SizedBox(height: 300, child: EmptyView(message: 'No THC on its way to your branch.'))],
        ),
        AsyncData(:final value) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Incoming THCs: tap to receive', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final s in value)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AccentCard(
                  color: AppColors.teal,
                  icon: Icons.move_to_inbox_outlined,
                  title: s.number,
                  trailing: const Icon(Icons.chevron_right, color: AppColors.teal),
                  onTap: () async {
                    await context.push('/receive/${s.id}');
                    ref.invalidate(incomingSheetsProvider);
                  },
                  children: [
                    Text(
                      'From ${branches[s.fromBranchId]?.label ?? '–'}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${s.shipmentCount} shipments · dispatched ${Fmt.dateTime(s.dispatchedAt)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
          ],
        ),
        AsyncError(:final error) => ErrorView(error: error, onRetry: refresh),
        _ => const LoadingView(),
      },
    );
  }
}

class _RunsTab extends ConsumerWidget {
  const _RunsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(drsRunsProvider);
    final days = ref.watch(drsRangeDaysProvider);
    final users = ref.watch(staffUsersProvider).value ?? const <StaffUser>[];
    String partner(String id) => users.where((u) => u.id == id).firstOrNull?.name ?? 'Delivery partner';
    Future<void> refresh() => ref.refresh(drsRunsProvider.future);

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final (d, label) in const [(1, 'Today'), (7, 'Last 7 days'), (30, 'Last 30 days')])
                ChoiceChip(
                  label: Text(label),
                  selected: days == d,
                  onSelected: (_) => ref.read(drsRangeDaysProvider.notifier).set(d),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ...switch (runs) {
            AsyncData(:final value) when value.isEmpty => [
              const SizedBox(height: 240, child: EmptyView(message: 'No delivery runs in this period.')),
            ],
            AsyncData(:final value) => [
              for (final r in value)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AccentCard(
                    color: r.pendingCount == 0 ? AppColors.success : AppColors.orange,
                    icon: Icons.delivery_dining_outlined,
                    title: r.drsNumber ?? 'DRS',
                    trailing: _Progress(done: r.deliveredCount, total: r.shipmentCount),
                    onTap: () => context.push(
                      Uri(
                        path: '/drs/run',
                        queryParameters: {
                          'user': r.deliveryUserId,
                          'branch': r.deliveryBranchId,
                          'date': Fmt.apiDate(r.runDate),
                        },
                      ).toString(),
                    ),
                    children: [
                      Text(
                        '${partner(r.deliveryUserId)} · ${Fmt.date(r.runDate)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _Count('${r.shipmentCount} total', AppColors.indigo),
                          _Count('${r.deliveredCount} delivered', AppColors.success),
                          _Count('${r.pendingCount} pending', AppColors.orange),
                          if (r.failedCount > 0) _Count('${r.failedCount} failed', AppColors.danger),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
            AsyncError(:final error) => [ErrorView(error: error, onRetry: refresh)],
            _ => [
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          },
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 44,
    height: 44,
    child: Stack(
      alignment: Alignment.center,
      children: [
        CircularProgressIndicator(
          value: total == 0 ? 0 : done / total,
          backgroundColor: AppColors.border,
          color: AppColors.success,
          strokeWidth: 4,
        ),
        Text('$done/$total', style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
}

class _Count extends StatelessWidget {
  const _Count(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
}
