import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/state_views.dart';
import '../application/auth_controller.dart';

/// Shown while a saved session is renewed, or when the server cannot be reached to renew it.
class StartupPage extends ConsumerWidget {
  const StartupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);
    return Scaffold(
      body: SafeArea(
        child: switch (state) {
          AuthRestoreFailed(:final error) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ErrorView(error: error, onRetry: () => ref.read(authControllerProvider.notifier).restore()),
              TextButton(
                onPressed: () => ref.read(authControllerProvider.notifier).logout(),
                child: const Text('Sign in with another account'),
              ),
            ],
          ),
          _ => const LoadingView(message: 'Signing you in…'),
        },
      ),
    );
  }
}

/// Signed in, but the account is not staffed at a branch or hub.
class NoBranchPage extends ConsumerWidget {
  const NoBranchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: SafeArea(
      child: EmptyView(
        icon: Icons.store_mall_directory_outlined,
        message:
            'This account is not assigned to a branch.\n'
            'Ask your administrator to assign one, then sign in again.',
        action: FilledButton(
          onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          child: const Text('Sign out'),
        ),
      ),
    ),
  );
}
