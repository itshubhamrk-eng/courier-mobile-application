import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Bottom navigation: Home, Bookings, Loading Sheets, Delivery, More.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: shell,
    bottomNavigationBar: NavigationBar(
      selectedIndex: shell.currentIndex,
      onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
        NavigationDestination(
          icon: Icon(Icons.inventory_2_outlined),
          selectedIcon: Icon(Icons.inventory_2),
          label: 'Bookings',
        ),
        NavigationDestination(
          icon: Icon(Icons.list_alt_outlined),
          selectedIcon: Icon(Icons.list_alt),
          label: 'Loading',
        ),
        NavigationDestination(
          icon: Icon(Icons.delivery_dining_outlined),
          selectedIcon: Icon(Icons.delivery_dining),
          label: 'Delivery',
        ),
        NavigationDestination(icon: Icon(Icons.menu), label: 'More'),
      ],
    ),
  );
}

/// Stand-in for screens that arrive in a later phase.
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({super.key, required this.title, required this.phase, this.showBack = false});

  final String title;
  final int phase;
  final bool showBack;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), automaticallyImplyLeading: showBack),
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
