import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/network/auth_interceptor.dart';
import 'features/auth/application/auth_controller.dart';

void main() {
  runApp(
    ProviderScope(
      // Failed requests are retried by the user (Retry / pull to refresh), never silently.
      retry: (_, _) => null,
      overrides: [tokenSourceProvider.overrideWith((ref) => ref.watch(authControllerProvider.notifier))],
      child: const BranchOpsApp(),
    ),
  );
}
