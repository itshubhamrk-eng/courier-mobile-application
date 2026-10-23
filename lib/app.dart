import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/preview/ui_kit_preview_page.dart';

class BranchOpsApp extends StatelessWidget {
  const BranchOpsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Branch Operations',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      // Phase 1 replaces this with go_router: login, then the bottom-navigation shell.
      home: const UiKitPreviewPage(),
    );
  }
}
