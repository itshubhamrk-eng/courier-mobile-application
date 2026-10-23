import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/permissions.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/auth/data/session.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/auth/presentation/startup_pages.dart';
import 'features/booking/presentation/booking_done_page.dart';
import 'features/booking/presentation/booking_page.dart';
import 'features/dashboard/presentation/dashboard_page.dart';
import 'features/loading_sheet/presentation/loading_sheet_detail_page.dart';
import 'features/loading_sheet/presentation/loading_sheets_page.dart';
import 'features/loading_sheet/presentation/new_loading_sheet_page.dart';
import 'features/more/more_page.dart';
import 'features/shell/app_shell.dart';
import 'features/shipments/presentation/bookings_list_page.dart';
import 'features/shipments/presentation/shipment_detail_page.dart';
import 'features/thc/presentation/thc_page.dart';
import 'features/tracking/presentation/track_page.dart';

/// Screens that need a permission. The server checks every call anyway; this
/// keeps users from landing on a screen whose actions would all be refused.
const _routePermissions = {
  '/bookings/new': Permissions.shipmentCreate,
  '/bookings/done': Permissions.shipmentCreate,
  '/bookings': Permissions.shipmentRead,
  '/shipments': Permissions.shipmentRead,
  '/track': Permissions.shipmentRead,
  '/loading-sheets/new': Permissions.manifestCreate,
  '/loading-sheets': Permissions.manifestRead,
  '/thc': Permissions.manifestDispatch,
};

bool _allowed(Session session, String location) {
  for (final e in _routePermissions.entries) {
    if (location == e.key || location.startsWith('${e.key}/')) return session.can(e.value);
  }
  return true;
}

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
        AuthSignedIn(:final session) when !_allowed(session, at) => '/home',
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
            routes: [GoRoute(path: '/bookings', builder: (_, _) => const BookingsListPage())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/loading-sheets', builder: (_, _) => const LoadingSheetsPage())],
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
      GoRoute(path: '/bookings/new', builder: (_, _) => const BookingPage()),
      GoRoute(
        path: '/bookings/done/:id',
        builder: (_, state) => BookingDonePage(shipmentId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/shipments/:id',
        builder: (_, state) => ShipmentDetailPage(shipmentId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/track',
        builder: (_, state) => TrackPage(initialAwb: state.uri.queryParameters['awb']),
      ),
      GoRoute(path: '/loading-sheets/new', builder: (_, _) => const NewLoadingSheetPage()),
      GoRoute(
        path: '/loading-sheets/:id',
        builder: (_, state) => LoadingSheetDetailPage(sheetId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/thc',
        builder: (_, state) => ThcPage(manifestId: state.uri.queryParameters['manifestId']),
      ),
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
