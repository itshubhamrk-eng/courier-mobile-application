import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/permissions.dart';
import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/state_views.dart';
import '../auth/application/auth_controller.dart';
import '../masters/data/masters.dart';
import 'branch_header.dart';

class _Item {
  const _Item(this.title, this.icon, this.route, {this.permission, this.tab = false});

  final String title;
  final IconData icon;
  final String route;
  final String? permission;

  /// A bottom-bar tab: switched to with go(), not pushed.
  final bool tab;
}

/// Same items, names and order as the web app's Operations menu, filtered by permission.
const _operations = [
  _Item('Shipment Booking', Icons.add_box_outlined, '/bookings/new', permission: Permissions.shipmentCreate),
  _Item('Shipment Search', Icons.search, '/bookings', permission: Permissions.shipmentRead, tab: true),
  _Item('Track Shipment', Icons.my_location, '/track', permission: Permissions.shipmentRead),
  _Item('Loading Sheet', Icons.qr_code_scanner, '/loading-sheets', permission: Permissions.manifestRead, tab: true),
  _Item('Trip Hire Challan (THC)', Icons.outbound_outlined, '/thc', permission: Permissions.manifestDispatch),
  _Item('In Scan', Icons.move_to_inbox_outlined, '/delivery', permission: Permissions.manifestRead, tab: true),
  _Item('Generate DRS', Icons.directions_run, '/drs/new', permission: Permissions.deliveryAssign),
  _Item('Delivery', Icons.delivery_dining_outlined, '/delivery?tab=runs', tab: true),
  _Item('Upload POD', Icons.photo_camera_outlined, '/pod', permission: Permissions.deliveryUpload),
];

/// Left side menu, like the web app's sidebar.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final branch = (ref.watch(branchNamesProvider).value ?? const {})[session?.operatingBranchId];
    final wallet = ref.watch(branchWalletProvider).value;
    final location = GoRouterState.of(context).matchedLocation;
    bool can(String? p) => p == null || (session?.can(p) ?? false);

    void open(_Item item) {
      Navigator.of(context).pop();
      item.tab ? context.go(item.route) : context.push(item.route);
    }

    return Drawer(
      backgroundColor: AppColors.surface,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 16, 16, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.indigo],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CompanyLogo(name: session?.companyName ?? '', url: session?.companyLogo, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        session?.companyName ?? 'Courier Pro',
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  session?.displayName ?? '',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                Text(
                  [branch?.label, session?.email].nonNulls.join(' · '),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (wallet != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Wallet ${Fmt.money(wallet.available)}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _tile(
                  context,
                  'Dashboard',
                  Icons.dashboard_outlined,
                  selected: location == '/home',
                  onTap: () {
                    Navigator.of(context).pop();
                    context.go('/home');
                  },
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 14, 16, 6),
                  child: Text(
                    'OPERATIONS',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                for (final item in _operations.where((i) => can(i.permission)))
                  _tile(
                    context,
                    item.title,
                    item.icon,
                    selected: item.tab && location == item.route && item.title != 'In Scan',
                    onTap: () => open(item),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: _tile(
              context,
              'Sign out',
              Icons.logout,
              color: AppColors.danger,
              onTap: () async {
                final ok = await confirmAction(
                  context,
                  title: 'Sign out?',
                  message: 'You will need your password to sign in again.',
                  confirmLabel: 'Sign out',
                );
                if (ok) await ref.read(authControllerProvider.notifier).logout();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    String title,
    IconData icon, {
    required VoidCallback onTap,
    bool selected = false,
    Color? color,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: AppColors.primaryLight,
      selectedColor: AppColors.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: Icon(icon, color: color ?? (selected ? AppColors.primary : AppColors.textSecondary)),
      title: Text(
        title,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
      ),
      onTap: onTap,
    ),
  );
}
