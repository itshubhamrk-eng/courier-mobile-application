import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/ui.dart';
import '../../auth/application/auth_controller.dart';
import '../../masters/data/masters.dart';
import '../../quick_scan/data/quick_scan_repository.dart';
import '../../shell/branch_header.dart';
import '../../wallet/application/wallet_state.dart';
import '../data/vendor_repository.dart';

/// Home for a vendor login (web: Vendor Management > Dashboard): its own pickups,
/// deliveries and earnings, and only the work a vendor does.
class VendorDashboardPage extends ConsumerWidget {
  const VendorDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(vendorDashboardProvider);
    Future<void> refresh() {
      ref
        ..invalidate(branchWalletProvider)
        ..invalidate(pickupsProvider);
      return ref.refresh(vendorDashboardProvider.future);
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: refresh,
        child: switch (data) {
          AsyncData(:final value) => _Body(d: value),
          AsyncError(:final error) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: 420,
                child: ErrorView(error: error, onRetry: refresh),
              ),
            ],
          ),
          _ => const LoadingView(message: 'Loading your figures…'),
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.d});

  final VendorDashboard d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    bool can(String p) => session?.can(p) ?? false;
    final branch = (ref.watch(branchNamesProvider).value ?? const {})[session?.operatingBranchId];
    final scan = ref.watch(quickScanAccessProvider);
    final wallet = ref.watch(walletAccessProvider);
    final waiting = (ref.watch(pickupsProvider).value ?? const <Pickup>[])
        .where((p) => p.status == 'ASSIGNED')
        .toList();

    final actions = [
      ('Pickups', Icons.inventory_2_outlined, '/pickups', AppColors.primary, true),
      if (can(Permissions.shipmentCreate))
        ('Book Shipment', Icons.add_box_outlined, '/bookings/new', AppColors.indigo, false),
      if (scan.inScan) ('Quick In Scan', Icons.move_to_inbox_outlined, '/quick-scan/in', AppColors.green, false),
      if (can(Permissions.deliveryAssign)) ('Generate DRS', Icons.directions_run, '/drs/new', AppColors.orange, false),
      if (can(Permissions.deliveryUpload)) ('Upload POD', Icons.photo_camera_outlined, '/pod', AppColors.pink, false),
      if (can(Permissions.shipmentRead)) ('Track Shipment', Icons.search, '/track', AppColors.cyan, false),
      ('Earnings', Icons.payments_outlined, '/vendor/earnings', AppColors.teal, false),
      if (wallet.view) ('Wallet', Icons.account_balance_wallet_outlined, '/wallet', AppColors.purple, false),
    ];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), gradient: brandGradient),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.handshake_outlined, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      branch?.label ?? 'Your vendor branch',
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
              const Text('EARNED THIS MONTH', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1)),
              Text(
                Fmt.money(d.earnedThisMonth ?? 0),
                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Payable ${Fmt.money(d.outstanding ?? 0)} · Paid this month ${Fmt.money(d.paidThisMonth ?? 0)}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: MetricTile(value: '${d.openPickups}', label: 'Open pickups', icon: Icons.inventory_2_outlined),
            ),
            Expanded(
              child: MetricTile(
                value: '${d.atVendor}',
                label: 'To deliver',
                icon: Icons.move_to_inbox_outlined,
                color: AppColors.indigo,
              ),
            ),
            Expanded(
              child: MetricTile(
                value: '${d.podPending}',
                label: 'POD pending',
                icon: Icons.photo_camera_outlined,
                color: AppColors.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: MetricTile(
                value: '${d.outForDelivery}',
                label: 'Out for delivery',
                icon: Icons.delivery_dining_outlined,
                color: AppColors.cyan,
              ),
            ),
            Expanded(
              child: MetricTile(
                value: '${d.deliveredThisMonth}',
                label: 'Delivered*',
                icon: Icons.task_alt,
                color: AppColors.success,
              ),
            ),
            Expanded(
              child: MetricTile(
                value: '${d.pickedUpThisMonth}',
                label: 'Picked up*',
                icon: Icons.local_shipping_outlined,
                color: AppColors.teal,
              ),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('* this month', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ),
        const SizedBox(height: 14),
        const Text('Quick actions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.15,
          children: [
            for (final (label, icon, route, color, tab) in actions)
              Material(
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [color, Color.lerp(color, Colors.black, 0.22)!],
                    ),
                  ),
                  child: InkWell(
                    onTap: () => tab ? context.go(route) : context.push(route),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, color: Colors.white, size: 28),
                        const SizedBox(height: 8),
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (waiting.isNotEmpty) ...[
          const SizedBox(height: 20),
          InkWell(
            onTap: () => context.go('/pickups'),
            child: InfoBanner(
              icon: Icons.notifications_active_outlined,
              color: AppColors.warning,
              text: '${waiting.length} new pickup(s) waiting for you to accept. Tap to open.',
            ),
          ),
        ],
      ],
    );
  }
}
