import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../../masters/data/masters.dart';
import '../data/dashboard_repository.dart';
import '../../shell/branch_header.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(dashboardCountsProvider);

    Future<void> refresh() {
      ref.invalidate(branchWalletProvider);
      return ref.refresh(dashboardCountsProvider.future);
    }

    return Scaffold(
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
    final branch = (ref.watch(branchNamesProvider).value ?? const {})[session?.operatingBranchId];
    void open(String route) => context.push(route);

    final actions = <_QuickAction>[
      if (can(Permissions.shipmentCreate))
        const _QuickAction('Book Shipment', Icons.add_box_outlined, '/bookings/new', AppColors.primary),
      if (can(Permissions.shipmentRead)) const _QuickAction('Track Shipment', Icons.search, '/track', AppColors.cyan),
      if (can(Permissions.manifestCreate))
        const _QuickAction('Loading Sheet', Icons.playlist_add_outlined, '/loading-sheets/new', AppColors.indigo),
      if (can(Permissions.manifestDispatch))
        const _QuickAction('Generate THC', Icons.local_shipping_outlined, '/thc', AppColors.teal),
      if (can(Permissions.deliveryAssign))
        const _QuickAction('Generate DRS', Icons.assignment_outlined, '/drs/new', AppColors.purple),
      if (can(Permissions.deliveryUpload))
        const _QuickAction('Upload POD', Icons.photo_camera_outlined, '/pod', AppColors.pink),
    ];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _TodayBanner(branch: branch, counts: counts),
        if (counts.failures.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Some figures could not be loaded (${counts.failures.first.message}). Pull down to retry.',
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        if (actions.isNotEmpty) ...[
          const _Heading('Quick actions'),
          _Grid(extent: 96, children: [for (final a in actions) _QuickActionTile(action: a)]),
        ],
        const _Heading('Booking & loading', color: AppColors.primary),
        _Grid(
          children: [
            StatCard(
              label: "Today's bookings",
              value: counts.todayBookings,
              icon: Icons.inventory_2_outlined,
              color: AppColors.primary,
              onTap: () => open('/bookings'),
            ),
            StatCard(
              label: 'Waiting for loading',
              value: counts.pendingLoading,
              icon: Icons.pending_actions_outlined,
              color: AppColors.orange,
              onTap: () => open('/loading-sheets/new'),
            ),
            StatCard(
              label: 'Loading sheets',
              value: counts.loadingSheetsOpen,
              icon: Icons.list_alt_outlined,
              color: AppColors.indigo,
              onTap: () => open('/loading-sheets'),
            ),
          ],
        ),
        const _Heading('On the road', color: AppColors.teal),
        _Grid(
          children: [
            StatCard(
              label: 'Pending dispatch',
              value: counts.pendingDispatch,
              icon: Icons.schedule_send_outlined,
              color: AppColors.amber,
              onTap: () => open('/thc'),
            ),
            StatCard(
              label: 'THC in transit',
              value: counts.thcInTransit,
              icon: Icons.local_shipping_outlined,
              color: AppColors.teal,
              onTap: () => open('/loading-sheets'),
            ),
            StatCard(
              label: 'Waiting for DRS',
              value: counts.pendingDrs,
              icon: Icons.assignment_ind_outlined,
              color: AppColors.purple,
              onTap: () => open('/drs/new'),
            ),
          ],
        ),
        const _Heading('Delivery', color: AppColors.green),
        _Grid(
          children: [
            StatCard(
              label: 'Out for delivery',
              value: counts.outForDelivery,
              icon: Icons.delivery_dining_outlined,
              color: AppColors.cyan,
              onTap: () => open('/delivery'),
            ),
            StatCard(
              label: 'Delivered today',
              value: counts.deliveredToday,
              icon: Icons.task_alt,
              color: AppColors.green,
              onTap: () => open('/delivery'),
            ),
            StatCard(
              label: 'POD to upload',
              value: counts.pendingPod,
              icon: Icons.photo_camera_outlined,
              color: AppColors.pink,
              onTap: () => open('/pod'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Gradient banner: branch, date and the two headline figures.
class _TodayBanner extends StatelessWidget {
  const _TodayBanner({required this.branch, required this.counts});

  final Branch? branch;
  final DashboardCounts counts;

  @override
  Widget build(BuildContext context) {
    Widget figure(int? v, String label) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            v?.toString() ?? '–',
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
          ),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.indigo, AppColors.purple],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront_outlined, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  branch?.label ?? 'Your branch',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                DateFormat('EEE, d MMM').format(DateTime.now()),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              figure(counts.todayBookings, 'booked today'),
              figure(counts.outForDelivery, 'out for delivery'),
              figure(counts.deliveredToday, 'delivered today'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Three-column grid whose cell height grows with the phone's font size.
class _Grid extends StatelessWidget {
  const _Grid({required this.children, this.extent = 118});

  final List<Widget> children;
  final double extent;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    return LayoutBuilder(
      builder: (context, c) => GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: c.maxWidth >= 600 ? 6 : 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          mainAxisExtent: textScale * extent,
        ),
        children: children,
      ),
    );
  }
}

class _QuickAction {
  const _QuickAction(this.label, this.icon, this.route, this.color);

  final String label;
  final IconData icon;
  final String route;
  final Color color;
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({required this.action});

  final _QuickAction action;

  @override
  Widget build(BuildContext context) => Material(
    borderRadius: BorderRadius.circular(14),
    clipBehavior: Clip.antiAlias,
    child: Ink(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [action.color, Color.lerp(action.color, Colors.black, 0.22)!],
        ),
      ),
      child: InkWell(
        onTap: () => context.push(action.route),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(action.icon, color: Colors.white, size: 28),
              const SizedBox(height: 8),
              Flexible(
                child: Text(
                  action.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Row(
      children: [
        if (color != null) ...[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}
