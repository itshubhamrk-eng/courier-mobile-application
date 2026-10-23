import 'package:flutter/material.dart';

import '../network/api_exception.dart';
import '../theme/app_theme.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        if (message != null) ...[
          const SizedBox(height: 12),
          Text(message!, style: const TextStyle(color: AppColors.textSecondary)),
        ],
      ],
    ),
  );
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.message, this.icon = Icons.inbox_outlined, this.action});

  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) =>
      _MessageView(icon: icon, color: AppColors.neutral, message: message, action: action);
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final message = error is ApiException ? (error as ApiException).message : 'Something went wrong.';
    final icon = error is ApiException && (error as ApiException).kind == ApiErrorKind.network
        ? Icons.wifi_off_rounded
        : Icons.error_outline_rounded;
    return _MessageView(
      icon: icon,
      color: AppColors.danger,
      message: message,
      action: onRetry == null
          ? null
          : OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({required this.icon, required this.color, required this.message, this.action});

  final IconData icon;
  final Color color;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: color),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

void showSuccess(BuildContext context, String message) => _snack(context, message, AppColors.success);

void showFailure(BuildContext context, Object error) =>
    _snack(context, error is ApiException ? error.message : 'Something went wrong.', AppColors.danger);

void _snack(BuildContext context, String message, Color color) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating));
}

/// Yes/no dialog for irreversible actions (finalize, generate THC/DRS, deliver).
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(confirmLabel)),
      ],
    ),
  );
  return result ?? false;
}
