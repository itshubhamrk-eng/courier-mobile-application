import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/permissions.dart';
import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/ui.dart';
import '../auth/application/auth_controller.dart';
import '../masters/data/masters.dart';
import 'branch_header.dart';

class _Item {
  const _Item(this.title, this.icon, this.route, {this.permission, this.tab = false, this.color = AppColors.primary});

  final String title;
  final IconData icon;
  final String route;
  final String? permission;
  final Color color;

  /// A bottom-bar tab: switched to with go(), not pushed.
  final bool tab;
}

/// Same items, names and order as the web app's Operations menu, filtered by permission.
const _operations = [
  _Item(
    'Shipment Booking',
    Icons.add_box_outlined,
    '/bookings/new',
    permission: Permissions.shipmentCreate,
    color: AppColors.primary,
  ),
  _Item(
    'Shipment Search',
    Icons.search,
    '/bookings',
    permission: Permissions.shipmentRead,
    tab: true,
    color: AppColors.indigo,
  ),
  _Item('Track Shipment', Icons.my_location, '/track', permission: Permissions.shipmentRead, color: AppColors.cyan),
  _Item(
    'Loading Sheet',
    Icons.qr_code_scanner,
    '/loading-sheets',
    permission: Permissions.manifestRead,
    tab: true,
    color: AppColors.purple,
  ),
  _Item(
    'Trip Hire Challan (THC)',
    Icons.outbound_outlined,
    '/thc',
    permission: Permissions.manifestDispatch,
    color: AppColors.teal,
  ),
  _Item(
    'In Scan',
    Icons.move_to_inbox_outlined,
    '/delivery',
    permission: Permissions.manifestRead,
    tab: true,
    color: AppColors.green,
  ),
  _Item(
    'Generate DRS',
    Icons.directions_run,
    '/drs/new',
    permission: Permissions.deliveryAssign,
    color: AppColors.orange,
  ),
  _Item('Delivery', Icons.delivery_dining_outlined, '/delivery?tab=runs', tab: true, color: AppColors.amber),
  _Item(
    'Upload POD',
    Icons.photo_camera_outlined,
    '/pod',
    permission: Permissions.deliveryUpload,
    color: AppColors.pink,
  ),
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
            padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 14, 16, 16),
            decoration: const BoxDecoration(gradient: brandGradient),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CompanyLogo(name: session?.companyName ?? '', url: session?.companyLogo, size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        session?.companyName ?? 'Courier Pro',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white54, width: 3),
                      ),
                      child: Text(
                        _initials(session?.displayName ?? ''),
                        style: const TextStyle(color: AppColors.indigo, fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session?.displayName ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                          if (session != null && session.roles.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                for (final r in session.roles.take(2))
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white24,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      _roleLabel(r),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (branch?.label case final b?) _HeaderLine(Icons.store_outlined, b),
                if (session?.email case final e? when e.isNotEmpty) _HeaderLine(Icons.mail_outline, e),
                if (wallet != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        const IconBadge(Icons.account_balance_wallet_outlined, color: AppColors.green, size: 34),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text('Wallet balance', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        ),
                        Text(
                          Fmt.money(wallet.available),
                          style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                      ],
                    ),
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
                  badge: AppColors.indigo,
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
                    badge: item.color,
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
    Color? badge,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: AppColors.primaryLight,
      selectedColor: AppColors.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: badge != null
          ? IconBadge(icon, color: badge, size: 34)
          : Icon(icon, color: color ?? (selected ? AppColors.primary : AppColors.textSecondary)),
      title: Text(
        title,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
      ),
      onTap: onTap,
    ),
  );
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
}

/// BRANCH_MANAGER -> Branch Manager.
String _roleLabel(String role) =>
    role.split('_').where((w) => w.isNotEmpty).map((w) => w[0] + w.substring(1).toLowerCase()).join(' ');

class _HeaderLine extends StatelessWidget {
  const _HeaderLine(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        Icon(icon, size: 16, color: Colors.white70),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}
