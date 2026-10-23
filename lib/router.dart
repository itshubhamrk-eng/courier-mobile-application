import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/application/auth_controller.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/auth/presentation/startup_pages.dart';
import 'features/dashboard/presentation/dashboard_page.dart';
import 'features/more/more_page.dart';
import 'features/shell/app_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run redirects whenever the auth state changes (login, logout, expiry).
  final authChanges = ValueNotifier<AuthState>(ref.read(authControllerProvider));
  ref.listen(authControllerProvider, (_, next) => authChanges.value = next);
  ref.onDispose(authChanges.dispose);

  final router = GoRouter(
    initialLocation: '/home',
    refreshListenable: authChanges,
    redirect: (context, state) {
      final auth = authChanges.value;
      final at = state.matchedLocation;
      return switch (auth) {
        AuthRestoring() || AuthRestoreFailed() => at == '/startup' ? null : '/startup',
        AuthSignedOut() => at == '/login' ? null : '/login',
        AuthSignedIn(:final session) when session.operatingBranchId == null => at == '/no-branch' ? null : '/no-branch',
        AuthSignedIn() => (at == '/login' || at == '/startup' || at == '/no-branch') ? '/home' : null,
      };
    },
    routes: [
      GoRoute(path: '/startup', builder: (_, _) => const StartupPage()),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/no-branch', builder: (_, _) => const NoBranchPage()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/home', builder: (_, _) => const DashboardPage())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/bookings',
                builder: (_, _) => const ComingSoonPage(title: 'Bookings', phase: 2),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/loading-sheets',
                builder: (_, _) => const ComingSoonPage(title: 'Loading Sheets', phase: 3),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/delivery',
                builder: (_, _) => const ComingSoonPage(title: 'Delivery', phase: 5),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/more', builder: (_, _) => const MorePage())],
          ),
        ],
      ),
      // Quick-action targets, filled in by later phases.
      GoRoute(path: '/bookings/new', builder: (_, _) => const _Later('Book Shipment', 2)),
      GoRoute(path: '/track', builder: (_, _) => const _Later('Track Shipment', 2)),
      GoRoute(path: '/loading-sheets/new', builder: (_, _) => const _Later('New Loading Sheet', 3)),
      GoRoute(path: '/thc', builder: (_, _) => const _Later('Generate THC', 4)),
      GoRoute(path: '/drs/new', builder: (_, _) => const _Later('Generate DRS', 5)),
      GoRoute(path: '/pod', builder: (_, _) => const _Later('Upload POD', 6)),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class _Later extends StatelessWidget {
  const _Later(this.title, this.phase);

  final String title;
  final int phase;

  @override
  Widget build(BuildContext context) => ComingSoonPage(title: title, phase: phase, showBack: true);
}
