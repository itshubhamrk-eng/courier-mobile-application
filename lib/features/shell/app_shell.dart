import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_drawer.dart';
import 'branch_header.dart';
import '../vendor/data/vendor_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';

/// Main screens: branch header on top, side menu on the left (like the web app),
/// bottom bar for the four most used areas.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  // Shell branch indexes (router.dart): home, bookings, manifests, delivery, pickups.
  static const _branchTabs = [0, 1, 2, 3];

  /// A vendor does not create or finalize manifests: its third tab is its pickups.
  static const _vendorTabs = [0, 1, 4, 3];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendor = ref.watch(isVendorProvider);
    final tabs = vendor ? _vendorTabs : _branchTabs;
    final selected = tabs.indexOf(shell.currentIndex);
    return Scaffold(
      appBar: const BranchHeader(),
      drawer: const AppDrawer(),
      drawerScrimColor: AppColors.scrim,
      body: shell,
      bottomNavigationBar: NavigationBar(
        // A screen outside the bar (e.g. Manifests opened from a link) leaves no tab lit.
        selectedIndex: selected < 0 ? 0 : selected,
        indicatorColor: selected < 0 ? Colors.transparent : null,
        onDestinationSelected: (i) => shell.goBranch(tabs[i], initialLocation: tabs[i] == shell.currentIndex),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          const NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Bookings',
          ),
          if (vendor)
            const NavigationDestination(
              icon: Icon(Icons.local_shipping_outlined),
              selectedIcon: Icon(Icons.local_shipping),
              label: 'Pickups',
            )
          else
            const NavigationDestination(
              icon: Icon(Icons.list_alt_outlined),
              selectedIcon: Icon(Icons.list_alt),
              label: 'Manifests',
            ),
          const NavigationDestination(
            icon: Icon(Icons.delivery_dining_outlined),
            selectedIcon: Icon(Icons.delivery_dining),
            label: 'Delivery',
          ),
        ],
      ),
    );
  }
}

/// Stand-in for screens that arrive in a later phase.
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({super.key, required this.title, required this.phase, this.showBack = false});

  final String title;
  final int phase;
  final bool showBack;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(flexibleSpace: const AppBarGradient(), title: Text(title), automaticallyImplyLeading: showBack),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.construction_outlined, size: 48, color: Colors.black38),
            const SizedBox(height: 12),
            Text('$title arrives in Phase $phase.', textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}
