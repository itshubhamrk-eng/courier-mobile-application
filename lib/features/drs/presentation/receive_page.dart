import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/scanner_page.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../../loading_sheet/presentation/loading_sheet_detail_page.dart';
import '../../masters/data/masters.dart';
import '../data/drs_repository.dart';
import '../../../core/scan_code.dart';
import '../../../core/widgets/ui.dart';

/// Receive an incoming THC: scan or tick what arrived; the rest is reported missing.
class ReceivePage extends ConsumerStatefulWidget {
  const ReceivePage({super.key, required this.manifestId});

  final String manifestId;

  @override
  ConsumerState<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends ConsumerState<ReceivePage> {
  final _received = <String>{};
  final _scan = TextEditingController();
  final _remarks = TextEditingController();
  bool _submitting = false;
  BulkResult? _result;

  @override
  void dispose() {
    _scan.dispose();
    _remarks.dispose();
    super.dispose();
  }

  void _mark(String raw, SheetWithShipments data) {
    final awb = raw.trim();
    _scan.clear();
    if (awb.isEmpty) return;
    final s = data.shipments
        .where((x) => matchesScan(trackingNumber: x.trackingNumber, shipmentNumber: x.shipmentNumber, raw: awb))
        .firstOrNull;
    if (s == null) {
      showFailure(context, ApiException(ApiErrorKind.validation, '$awb is not on THC ${data.sheet.number}.'));
      return;
    }
    setState(() => _received.add(s.trackingNumber));
    showSuccess(context, '$awb received.');
  }

  Future<void> _confirm(SheetWithShipments data) async {
    if (_received.isEmpty || _submitting) return;
    final missing = data.shipments.map((s) => s.trackingNumber).where((t) => !_received.contains(t)).toList();
    final ok = await confirmAction(
      context,
      title: 'Confirm receipt?',
      message: [
        '${_received.length} of ${data.shipments.length} shipments received.',
        if (missing.isNotEmpty) '${missing.length} will be reported missing and a shortage ticket raised.',
      ].join('\n\n'),
      confirmLabel: 'Confirm',
    );
    if (!ok || !mounted) return;
    setState(() => _submitting = true);
    try {
      final result = await ref
          .read(drsRepositoryProvider)
          .inScan(
            branchId: ref.read(sessionProvider)!.operatingBranchId!,
            received: _received.toList(),
            manifestNumber: data.sheet.number,
            missing: missing,
            remarks: _remarks.text,
          );
      if (mounted) setState(() => _result = result);
    } on ApiException catch (e) {
      if (!mounted) return;
      // In-scan of an already received shipment is refused per shipment by the
      // server, so retrying after a lost answer cannot double-receive.
      showFailure(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(loadingSheetDetailProvider(widget.manifestId));
    final branches = ref.watch(branchNamesProvider).value ?? const <String, Branch>{};
    return Scaffold(
      appBar: AppBar(flexibleSpace: const AppBarGradient(), title: Text(data.value?.sheet.number ?? 'Receive')),
      body: switch (data) {
        AsyncData() when _result != null => _ResultView(result: _result!),
        AsyncData(:final value) => Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  HeroCard(
                    colors: const [AppColors.teal, AppColors.cyan],
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'INCOMING FROM',
                          style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1),
                        ),
                        Text(
                          branches[value.sheet.bookingBranchId]?.label ?? '–',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Text(
                              '${_received.length} / ${value.shipments.length}',
                              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(width: 8),
                            const Text('received', style: TextStyle(color: Colors.white70)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: value.shipments.isEmpty ? 0 : _received.length / value.shipments.length,
                            minHeight: 8,
                            backgroundColor: Colors.white24,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextField(
                    controller: _scan,
                    onSubmitted: (v) => _mark(v, value),
                    decoration: scanDecoration(
                      'Scan or type AWB received',
                      onScan: () async {
                        final v = await ScannerPage.scan(context);
                        if (v != null && mounted) _mark(v, value);
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SectionTitle(
                          '${_received.length} of ${value.shipments.length} received',
                          icon: Icons.move_to_inbox_outlined,
                          color: AppColors.teal,
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          if (_received.length == value.shipments.length) {
                            _received.clear();
                          } else {
                            _received.addAll(value.shipments.map((s) => s.trackingNumber));
                          }
                        }),
                        child: Text(_received.length == value.shipments.length ? 'Clear all' : 'All arrived'),
                      ),
                    ],
                  ),
                  for (final s in value.shipments)
                    PickTile(
                      selected: _received.contains(s.trackingNumber),
                      onChanged: (v) =>
                          setState(() => v ? _received.add(s.trackingNumber) : _received.remove(s.trackingNumber)),
                      title: s.trackingNumber,
                      color: AppColors.teal,
                      lines: [
                        Text(
                          [s.receiverName, s.toCity].nonNulls.join(' · '),
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _remarks,
                    decoration: const InputDecoration(labelText: 'Remarks (optional)'),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _received.isEmpty || _submitting ? null : () => _confirm(value),
                  icon: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : const Icon(Icons.inventory_outlined),
                  label: Text(_submitting ? 'Saving…' : 'Confirm receipt'),
                ),
              ),
            ),
          ],
        ),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(loadingSheetDetailProvider(widget.manifestId)),
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.result});

  final BulkResult result;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Icon(
        result.failureCount == 0 ? Icons.check_circle : Icons.warning_amber_rounded,
        size: 56,
        color: result.failureCount == 0 ? AppColors.success : AppColors.warning,
      ),
      const SizedBox(height: 8),
      Text(
        '${result.successCount} received${result.failureCount > 0 ? ', ${result.failureCount} failed' : ''}',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      if (result.shortageTicket != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Shortage ticket ${result.shortageTicket} raised for the missing shipments.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.danger),
          ),
        ),
      const SizedBox(height: 12),
      for (final o in result.results.where((o) => !o.success))
        ListTile(
          leading: const Icon(Icons.error_outline, color: AppColors.danger),
          title: Text(o.reference),
          subtitle: Text(o.message ?? 'Failed'),
        ),
      const SizedBox(height: 12),
      FilledButton(onPressed: () => context.pop(), child: const Text('Done')),
    ],
  );
}
