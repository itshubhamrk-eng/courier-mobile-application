import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../masters/data/masters.dart';
import '../../thc/data/thc_repository.dart';
import '../data/drs_repository.dart';
import 'drs_widgets.dart';

typedef DrsRunKey = ({String user, String branch, String date});

final drsRunDetailProvider = FutureProvider.autoDispose.family<({String? drsNumber, List<DrsRow> rows}), DrsRunKey>(
  (ref, k) => ref
      .watch(drsRepositoryProvider)
      .runDetail(DrsRun(deliveryUserId: k.user, deliveryBranchId: k.branch, runDate: DateTime.parse(k.date))),
);

/// One delivery partner's run for one day: every shipment with its server status.
class DrsRunPage extends ConsumerWidget {
  const DrsRunPage({super.key, required this.runKey});

  final DrsRunKey runKey;

  static const _filters = [
    ('ALL', 'All'),
    ('OUT_FOR_DELIVERY', 'Pending'),
    ('DELIVERED', 'Delivered'),
    ('OTHER', 'Not delivered'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(drsRunDetailProvider(runKey));
    final modes = ref.watch(paymentModesProvider).value ?? const <Option>[];
    final users = ref.watch(staffUsersProvider).value ?? const <StaffUser>[];
    final partner = users.where((u) => u.id == runKey.user).firstOrNull;
    Future<void> refresh() => ref.refresh(drsRunDetailProvider(runKey).future);

    bool matches(String filter, DrsRow r) => switch (filter) {
      'ALL' => true,
      'OUT_FOR_DELIVERY' || 'DELIVERED' => r.status == filter,
      _ => r.status != 'OUT_FOR_DELIVERY' && r.status != 'DELIVERED',
    };

    return DefaultTabController(
      length: _filters.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(detail.value?.drsNumber ?? 'Delivery run'),
          bottom: TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              for (final (f, label) in _filters)
                Tab(text: '$label (${detail.value?.rows.where((r) => matches(f, r)).length ?? 0})'),
            ],
          ),
        ),
        body: switch (detail) {
          AsyncData(:final value) => Column(
            children: [
              Container(
                width: double.infinity,
                color: AppColors.surface,
                padding: const EdgeInsets.all(12),
                child: Text(
                  [
                    partner?.name ?? 'Delivery partner',
                    ?partner?.mobile,
                    Fmt.date(DateTime.parse(runKey.date)),
                  ].join(' · '),
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    for (final (f, _) in _filters)
                      RefreshIndicator(
                        onRefresh: refresh,
                        child: () {
                          final rows = value.rows.where((r) => matches(f, r)).toList();
                          if (rows.isEmpty) {
                            return ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [SizedBox(height: 260, child: EmptyView(message: 'Nothing here.'))],
                            );
                          }
                          return ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            itemCount: rows.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (_, i) => _RowCard(row: rows[i], modes: modes),
                          );
                        }(),
                      ),
                  ],
                ),
              ),
            ],
          ),
          AsyncError(:final error) => ErrorView(error: error, onRetry: refresh),
          _ => const LoadingView(),
        },
      ),
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({required this.row, required this.modes});

  final DrsRow row;
  final List<Option> modes;

  @override
  Widget build(BuildContext context) {
    final collect = collectLabel(row.paymentModeId, row.netAmount, modes);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/shipments/${row.shipmentId}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(row.trackingNumber, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  StatusBadge(row.status),
                ],
              ),
              const SizedBox(height: 6),
              if (row.receiverName != null)
                Text(row.receiverName!, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (row.receiverAddress != null) Text(row.receiverAddress!),
              if (collect != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    collect,
                    style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700),
                  ),
                ),
              if (row.deliveredAt != null)
                Text('Delivered ${Fmt.dateTime(row.deliveredAt)}', style: const TextStyle(color: AppColors.success)),
              const SizedBox(height: 4),
              // Wrap, not Row: phone number + Navigate do not fit side by side on small phones.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                children: [
                  if (row.receiverContact != null)
                    TextButton.icon(
                      onPressed: () => callNumber(row.receiverContact!),
                      icon: const Icon(Icons.call_outlined),
                      label: Text(row.receiverContact!),
                    ),
                  if (row.receiverAddress != null)
                    TextButton.icon(
                      onPressed: () => openInMaps([row.receiverAddress, row.toCity].nonNulls.join(', ')),
                      icon: const Icon(Icons.directions_outlined),
                      label: const Text('Navigate'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
