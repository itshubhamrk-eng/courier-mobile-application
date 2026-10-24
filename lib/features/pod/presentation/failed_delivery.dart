import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../../shipments/data/shipment_models.dart';
import '../../shipments/data/shipment_repository.dart';
import '../data/pod_repository.dart';

/// Same writers as POD.
bool canRecordFailedDelivery(WidgetRef ref) {
  final s = ref.watch(sessionProvider);
  return s != null && (s.can(Permissions.deliveryDeliver) || s.can(Permissions.deliveryUpload));
}

/// Asks why the delivery failed, confirms, then records it on the server.
/// Returns the recorded attempt, or null when cancelled, refused or not confirmed.
Future<DeliveryAttempt?> recordFailedDelivery(
  BuildContext context,
  WidgetRef ref, {
  required String shipmentId,
  required String trackingNumber,
}) async {
  final input = await showDialog<({FailureReason reason, String remarks})>(
    context: context,
    builder: (_) => const _FailedDeliveryForm(),
  );
  if (input == null || !context.mounted) return null;
  final ok = await confirmAction(
    context,
    title: 'Record failed delivery?',
    message:
        '$trackingNumber: ${input.reason.label}.\n'
        'The server counts this attempt. After the last allowed attempt the shipment is returned to origin.',
    confirmLabel: 'Record',
  );
  if (!ok || !context.mounted) return null;

  final repo = ref.read(podRepositoryProvider);
  final existing = await ref
      .read(shipmentRepositoryProvider)
      .deliveryAttempts(shipmentId)
      .catchError((_) => const <DeliveryAttempt>[]);
  try {
    final attempt = await repo.deliveryFailed(shipmentId: shipmentId, reason: input.reason, remarks: input.remarks);
    if (context.mounted) await _showResult(context, trackingNumber, attempt);
    return attempt;
  } on ApiException catch (e) {
    if (!context.mounted) return null;
    if (e.outcomeUnknown) {
      // The attempt may have been recorded. Look before offering another try.
      final now = await ref
          .read(shipmentRepositoryProvider)
          .deliveryAttempts(shipmentId)
          .catchError((_) => const <DeliveryAttempt>[]);
      if (!context.mounted) return null;
      if (now.length > existing.length) {
        await _showResult(context, trackingNumber, now.last);
        return now.last;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Not confirmed'),
          content: const Text(
            'The server did not answer in time. The failed attempt may or may not have been recorded.\n\n'
            'Open the shipment and check its delivery attempts before trying again, '
            'so the same attempt is not counted twice.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
      return null;
    }
    showFailure(context, e);
    return null;
  }
}

Future<void> _showResult(BuildContext context, String trackingNumber, DeliveryAttempt a) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    icon: Icon(
      a.returnedToOrigin ? Icons.keyboard_return : Icons.event_repeat,
      color: a.returnedToOrigin ? AppColors.danger : AppColors.warning,
      size: 40,
    ),
    title: Text(a.returnedToOrigin ? 'Returned to origin' : 'Attempt ${a.attemptNo} of ${a.maxAttempts} recorded'),
    content: Text(
      a.returnedToOrigin
          ? '$trackingNumber was returned to origin after ${a.attemptNo} failed attempts.'
          : '$trackingNumber is back at the branch for the next DRS (${a.reasonLabel}).',
    ),
    actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
  ),
);

class _FailedDeliveryForm extends StatefulWidget {
  const _FailedDeliveryForm();

  @override
  State<_FailedDeliveryForm> createState() => _FailedDeliveryFormState();
}

class _FailedDeliveryFormState extends State<_FailedDeliveryForm> {
  FailureReason? _reason;
  final _remarks = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _reason;
    if (reason == null) {
      setState(() => _error = 'Choose why the delivery failed.');
      return;
    }
    if (reason == FailureReason.other && _remarks.text.trim().isEmpty) {
      setState(() => _error = 'Add remarks for "Other".');
      return;
    }
    Navigator.pop(context, (reason: reason, remarks: _remarks.text.trim()));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Could not deliver?'),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RadioGroup<FailureReason>(
          groupValue: _reason,
          onChanged: (v) => setState(() {
            _reason = v;
            _error = null;
          }),
          child: Column(
            children: [
              for (final r in FailureReason.values)
                RadioListTile<FailureReason>(
                  value: r,
                  title: Text(r.label),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
        TextField(
          controller: _remarks,
          maxLength: 400,
          maxLines: 2,
          onChanged: (_) => _error == null ? null : setState(() => _error = null),
          decoration: InputDecoration(
            labelText: _reason == FailureReason.other ? 'Remarks (required)' : 'Remarks (optional)',
          ),
        ),
        if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.danger)),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _submit, child: const Text('Continue')),
    ],
  );
}
