import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'router.dart';

class BranchOpsApp extends ConsumerWidget {
  const BranchOpsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Courier Pro',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    routerConfig: ref.watch(routerProvider),
  );
}
