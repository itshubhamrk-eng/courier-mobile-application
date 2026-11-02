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
import '../wallet/application/wallet_state.dart';

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

/// Left side menu: a floating crimson panel 12px off the screen edges, like the web
/// portal's sidebar. Brand on top, the menu (scrolls inside the panel), and the
/// signed-in user, wallet and Sign out pinned at the bottom.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final branch = (ref.watch(branchNamesProvider).value ?? const {})[session?.operatingBranchId];
    final wallet = ref.watch(branchWalletProvider).value;
    final location = GoRouterState.of(context).matchedLocation;
    bool can(String? p) => p == null || (session?.can(p) ?? false);
    final walletAccess = ref.watch(walletAccessProvider);
    final screen = MediaQuery.sizeOf(context).width;
    final panelWidth = (screen * 0.84).clamp(0.0, 288.0);

    void go(String route, {bool tab = false}) {
      Navigator.of(context).pop();
      tab ? context.go(route) : context.push(route);
    }

    final finance = [
      ('Branch Wallet', Icons.account_balance_wallet_outlined, '/wallet'),
      if (walletAccess.recharge) ('Recharge Wallet', Icons.add_card, '/wallet/recharge'),
      ('Wallet Transactions', Icons.receipt_long_outlined, '/wallet/transactions'),
      ('Top-up Requests', Icons.fact_check_outlined, '/wallet/topup-requests'),
      if (walletAccess.rechargeReport) ('Recharge Report', Icons.assessment_outlined, '/wallet/recharge-report'),
    ];

    return Drawer(
      width: panelWidth + 12,
      backgroundColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppColors.sidebarGradient,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [BoxShadow(color: AppColors.sidebarShadow, blurRadius: 40, offset: Offset(0, 10))],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 20, 14, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Brand(name: session?.companyName ?? 'Courier Pro', logoUrl: session?.companyLogo),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        _Pill(
                          title: 'Dashboard',
                          icon: Icons.dashboard_outlined,
                          active: location == '/home',
                          onTap: () => go('/home', tab: true),
                        ),
                        const _Heading('Operations'),
                        for (final item in _operations.where((i) => can(i.permission)))
                          _Pill(
                            title: item.title,
                            icon: item.icon,
                            active: item.tab && location == item.route && item.title != 'In Scan',
                            onTap: () => go(item.route, tab: item.tab),
                          ),
                        if (walletAccess.view) ...[
                          const _Heading('Finance'),
                          for (final (title, icon, route) in finance)
                            _Pill(title: title, icon: icon, active: location == route, onTap: () => go(route)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _UserCard(
                    name: session?.displayName ?? '',
                    role: session?.roles.map(_roleLabel).firstOrNull,
                    branch: branch?.label,
                    email: session?.email,
                    wallet: wallet == null ? null : Fmt.money(wallet.available),
                  ),
                  const SizedBox(height: 6),
                  _Pill(
                    title: 'Sign out',
                    icon: Icons.logout,
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Company logo on a white square (10px corners), or initials on a white circle.
class _Brand extends StatelessWidget {
  const _Brand({required this.name, this.logoUrl});

  final String name;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Row(
      children: [
        if (logoUrl != null && logoUrl!.isNotEmpty)
          Container(
            width: 38,
            height: 38,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: AppColors.sidebarPillBg, borderRadius: BorderRadius.circular(10)),
            child: CompanyLogo(name: name, url: logoUrl, size: 32),
          )
        else
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.sidebarPillBg, shape: BoxShape.circle),
            child: Text(
              _initials(name),
              style: const TextStyle(color: AppColors.sidebarPillFg, fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.sidebarText, fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: AppColors.sidebarText,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 11.5 * 0.12,
      ),
    ),
  );
}

/// One menu item: a full-width pill. The active item is the only solid white pill.
class _Pill extends StatefulWidget {
  const _Pill({required this.title, required this.icon, required this.onTap, this.active = false});

  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final fg = widget.active ? AppColors.sidebarPillFg : AppColors.sidebarText;
    final pill = StadiumBorder();
    return Padding(
      padding: EdgeInsets.zero,
      child: DecoratedBox(
        // Visible keyboard focus: 2px indigo ring, 2px outside the pill.
        decoration: ShapeDecoration(
          shape: StadiumBorder(side: BorderSide(color: _focused ? AppColors.focusRing : Colors.transparent, width: 2)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              boxShadow: widget.active
                  ? const [BoxShadow(color: AppColors.sidebarPillShadow, blurRadius: 14, offset: Offset(0, 4))]
                  : null,
            ),
            child: Material(
              color: widget.active ? AppColors.sidebarPillBg : Colors.transparent,
              shape: pill,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                customBorder: pill,
                onTap: widget.onTap,
                onFocusChange: (f) => setState(() => _focused = f),
                hoverColor: widget.active ? null : AppColors.sidebarPressed,
                highlightColor: widget.active ? null : AppColors.sidebarPressed,
                splashColor: widget.active ? null : AppColors.sidebarPressed,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Icon(widget.icon, size: 20, color: fg),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Signed-in user, branch and wallet, pinned above Sign out.
class _UserCard extends StatelessWidget {
  const _UserCard({required this.name, this.role, this.branch, this.email, this.wallet});

  final String name;
  final String? role;
  final String? branch;
  final String? email;
  final String? wallet;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AppColors.sidebarInset, borderRadius: BorderRadius.circular(20)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.sidebarPillBg, shape: BoxShape.circle),
              child: Text(
                _initials(name),
                style: const TextStyle(color: AppColors.sidebarPillFg, fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.sidebarText, fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  if (role != null)
                    Text(
                      role!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.sidebarText, fontSize: 12),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (branch != null) _Line(Icons.store_outlined, branch!),
        if (email != null && email!.isNotEmpty) _Line(Icons.mail_outline, email!),
        if (wallet != null) _Line(Icons.account_balance_wallet_outlined, 'Wallet $wallet', bold: true),
      ],
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.text, {this.bold = false});

  final IconData icon;
  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        Icon(icon, size: 16, color: AppColors.sidebarText),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.sidebarText,
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
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
