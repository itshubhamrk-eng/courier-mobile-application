import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../data/dashboard_repository.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final counts = ref.watch(dashboardCountsProvider);

    Future<void> refresh() => ref.refresh(dashboardCountsProvider.future);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session?.companyName ?? 'Branch Operations', style: const TextStyle(fontSize: 18)),
            Text(
              'Hi, ${session?.displayName ?? ''}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: Colors.white70),
            ),
          ],
        ),
        actions: [IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: refresh)],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: switch (counts) {
          AsyncData(:final value) => _Body(counts: value),
          AsyncError(:final error) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: 420,
                child: ErrorView(error: error, onRetry: refresh),
              ),
            ],
          ),
          _ => const LoadingView(message: 'Loading branch figures…'),
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.counts});

  final DashboardCounts counts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    bool can(String p) => session?.can(p) ?? false;
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);

    final cards = <Widget>[
      StatCard(label: "Today's bookings", value: counts.todayBookings, icon: Icons.inventory_2_outlined),
      StatCard(
        label: 'Waiting for loading sheet',
        value: counts.pendingLoading,
        icon: Icons.pending_actions_outlined,
        color: AppColors.warning,
      ),
      StatCard(label: 'Loading sheets created', value: counts.loadingSheetsOpen, icon: Icons.list_alt_outlined),
      StatCard(
        label: 'Pending dispatch',
        value: counts.pendingDispatch,
        icon: Icons.schedule_send_outlined,
        color: AppColors.warning,
      ),
      StatCard(label: 'THC in transit', value: counts.thcInTransit, icon: Icons.local_shipping_outlined),
      StatCard(
        label: 'Waiting for DRS',
        value: counts.pendingDrs,
        icon: Icons.assignment_ind_outlined,
        color: AppColors.warning,
      ),
      StatCard(
        label: 'Out for delivery',
        value: counts.outForDelivery,
        icon: Icons.delivery_dining_outlined,
        color: AppColors.info,
      ),
      StatCard(label: 'Delivered today', value: counts.deliveredToday, icon: Icons.task_alt, color: AppColors.success),
      StatCard(
        label: 'POD to upload',
        value: counts.pendingPod,
        icon: Icons.photo_camera_outlined,
        color: AppColors.danger,
      ),
    ];

    final actions = <_QuickAction>[
      if (can(Permissions.shipmentCreate)) const _QuickAction('Book Shipment', Icons.add_box_outlined, '/bookings/new'),
      if (can(Permissions.shipmentRead)) const _QuickAction('Track Shipment', Icons.search, '/track'),
      if (can(Permissions.manifestCreate))
        const _QuickAction('Loading Sheet', Icons.playlist_add_outlined, '/loading-sheets/new'),
      if (can(Permissions.manifestDispatch)) const _QuickAction('Generate THC', Icons.local_shipping_outlined, '/thc'),
      if (can(Permissions.deliveryAssign)) const _QuickAction('Generate DRS', Icons.assignment_outlined, '/drs/new'),
      if (can(Permissions.deliveryUpload)) const _QuickAction('Upload POD', Icons.photo_camera_outlined, '/pod'),
    ];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        if (counts.failures.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Some figures could not be loaded (${counts.failures.first.message}). Pull down to retry.',
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        if (actions.isNotEmpty) ...[
          const _Heading('Quick actions'),
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: textScale * 104,
            ),
            children: [for (final a in actions) _QuickActionTile(action: a)],
          ),
          const SizedBox(height: 20),
        ],
        const _Heading('Today at your branch'),
        LayoutBuilder(
          builder: (context, c) => GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: c.maxWidth >= 600 ? 4 : 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              // Fixed height that grows with the phone's font size, so labels never clip.
              mainAxisExtent: textScale * 124,
            ),
            children: cards,
          ),
        ),
      ],
    );
  }
}

class _QuickAction {
  const _QuickAction(this.label, this.icon, this.route);

  final String label;
  final IconData icon;
  final String route;
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({required this.action});

  final _QuickAction action;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => context.push(action.route),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: AppColors.primaryLight,
              child: Icon(action.icon, color: AppColors.primary),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: Text(
                action.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
  );
}
