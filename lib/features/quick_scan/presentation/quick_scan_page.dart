import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/scanner_page.dart';
import '../../../core/widgets/result_animation.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/ui.dart';
import '../../auth/application/auth_controller.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../../drs/data/drs_repository.dart';
import '../../loading_sheet/data/loading_sheet_repository.dart';
import '../../masters/data/masters.dart';
import '../../shipments/data/shipment_models.dart';
import '../../shipments/data/shipment_repository.dart';
import '../../thc/data/thc_repository.dart';
import '../data/package_tally.dart';
import '../data/quick_scan_repository.dart';

enum QuickScanMode {
  inScan('In-scan', 'DISPATCHED', Icons.move_to_inbox_outlined, ResultScene.inScan),
  outScan('Out-scan', 'MANIFEST_CREATED', Icons.outbox_outlined, ResultScene.outScan);

  const QuickScanMode(this.label, this.requiredStatus, this.icon, this.scene);

  final String label;

  /// The only status the server accepts this scan from.
  final String requiredStatus;
  final IconData icon;
  final ResultScene scene;
}

/// Scan one shipment in (or out at a hub) package by package. Scanning a label opens
/// its shipment and counts that package; every package must be scanned, otherwise the
/// operator confirms a short shipment and can add a note.
class QuickScanPage extends ConsumerStatefulWidget {
  const QuickScanPage({super.key, required this.mode});

  final QuickScanMode mode;

  @override
  ConsumerState<QuickScanPage> createState() => _QuickScanPageState();
}

class _QuickScanPageState extends ConsumerState<QuickScanPage> {
  final _input = TextEditingController();
  ShipmentDetail? _shipment;
  LoadingSheet? _sheet;
  PackageTally? _tally;
  bool _loading = false;
  bool _submitting = false;

  /// An out-scan answer was lost, so "already out-scanned" on the next try is our own scan.
  bool _outScanMaybeSent = false;
  _Done? _done;

  /// Shown under the scan box, never as a snack bar: that would cover the submit button.
  ScanFeedback? _feedback;

  QuickScanMode get _mode => widget.mode;
  String? get _branchId => ref.read(sessionProvider)?.operatingBranchId;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _warn(String message) => showFailure(context, ApiException(ApiErrorKind.validation, message));

  // ---------------------------------------------------------------- scanning

  Future<void> _open(String raw) async {
    final code = raw.trim();
    _input.clear();
    if (code.isEmpty || _loading) return;
    setState(() => _loading = true);
    try {
      final s = await ref.read(shipmentRepositoryProvider).byAwb(code);
      LoadingSheet? sheet;
      if (s.s('manifestId') case final id?) {
        try {
          sheet = await ref.read(loadingSheetRepositoryProvider).byId(id);
        } on ApiException {
          // Only its number and destination are shown; scanning works without it.
        }
      }
      if (!mounted) return;
      final tally = PackageTally(
        trackingNumber: s.trackingNumber,
        shipmentNumber: s.shipmentNumber,
        quantity: s.n('numberOfPackages')?.toInt() ?? 1,
      );
      setState(() {
        _shipment = s;
        _sheet = sheet;
        _tally = tally;
        _outScanMaybeSent = false;
      });
      if (_problem == null) {
        final r = _count(code, typed: false);
        if (!r.ok && tally.quantity > 1) {
          setState(() => _feedback = ScanFeedback('Now scan all ${tally.quantity} package labels.', ok: true));
        }
      }
    } on ApiException catch (e) {
      if (mounted) {
        e.kind == ApiErrorKind.notFound ? _warn('No shipment found for $code.') : showFailure(context, e);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  ScanFeedback _count(String raw, {bool typed = true}) {
    final t = _tally!;
    final ack = t.scan(raw, typed: typed);
    final feedback = switch (ack) {
      ScanAck.added => ScanFeedback(
        '${t.scanned.length} of ${t.quantity} packages scanned',
        ok: true,
        finished: t.complete,
      ),
      ScanAck.duplicate => const ScanFeedback('This package is already scanned'),
      ScanAck.wrongShipment => ScanFeedback('$raw is not a package of ${t.trackingNumber}'),
      ScanAck.needsPackage => const ScanFeedback('That is the shipment code. Scan the label on each package.'),
      ScanAck.outOfRange => ScanFeedback('This shipment has only ${t.quantity} package(s)'),
    };
    setState(() => _feedback = feedback);
    return feedback;
  }

  void _typed(String raw) {
    if (raw.trim().isEmpty || _submitting) return;
    if (_tally == null) {
      _open(raw);
      return;
    }
    _input.clear();
    _count(raw.trim());
  }

  Future<void> _camera() async {
    if (_tally == null) {
      final v = await ScannerPage.scan(context, title: 'Scan label');
      if (v != null && mounted) await _open(v);
      return;
    }
    await ScannerPage.scanMany(context, title: 'Scan packages', onCode: (v) => _count(v, typed: false));
  }

  Future<bool> _confirmDiscard() async {
    if (_tally == null || _tally!.scanned.isEmpty || _done != null) return true;
    return confirmAction(
      context,
      title: 'Discard scans?',
      message: '${_tally!.scanned.length} scanned package(s) have not been submitted.',
      confirmLabel: 'Discard',
    );
  }

  void _reset() => setState(() {
    _shipment = null;
    _sheet = null;
    _tally = null;
    _done = null;
    _feedback = null;
    _outScanMaybeSent = false;
    _input.clear();
  });

  /// Why this shipment cannot be scanned here; null when it can.
  String? get _problem {
    final s = _shipment!;
    if (s.status != _mode.requiredStatus) {
      final now = statusStyle(s.status).label;
      return _mode == QuickScanMode.inScan
          ? 'Cannot in-scan: this shipment is "$now". Only dispatched shipments can be received.'
          : 'Cannot out-scan: this shipment is "$now". It must be on an open loading sheet.';
    }
    if (_mode == QuickScanMode.inScan) {
      final next = s.s('nextLocationId') ?? s.deliveryBranchId;
      if (next != null && next != _branchId) {
        final name = (ref.read(branchNamesProvider).value ?? const {})[next]?.label;
        return 'This shipment is for ${name ?? 'another branch'}, not your branch.';
      }
    } else if (_sheet != null && _sheet!.bookingBranchId != _branchId) {
      return 'Loading sheet ${_sheet!.number} belongs to another branch.';
    }
    return null;
  }

  // ---------------------------------------------------------------- submit

  Future<void> _submit() async {
    final t = _tally!;
    if (_submitting || t.scanned.isEmpty) return;
    String? remarks;
    if (!t.complete) {
      if (_mode == QuickScanMode.outScan && !ref.read(quickScanAccessProvider).raiseException) {
        _warn('Only ${t.scanned.length} of ${t.quantity} packages scanned. Your role cannot record a short out-scan.');
        return;
      }
      final note = await showDialog<String>(
        context: context,
        builder: (_) => _ShortDialog(mode: _mode, tally: t),
      );
      if (note == null || !mounted) return;
      remarks = _shortRemarks(t, note);
    }
    setState(() => _submitting = true);
    try {
      if (_mode == QuickScanMode.inScan) {
        await _inScan(t, remarks);
      } else {
        await _outScan(t, remarks);
      }
      ref.invalidate(dashboardCountsProvider);
    } on ApiException catch (e) {
      if (mounted) showSubmitFailure(context, e, title: '${_mode.label} failed', scene: _mode.scene);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// What is stored against the shipment (server limit 500 characters).
  String _shortRemarks(PackageTally t, String note) {
    final verb = _mode == QuickScanMode.inScan ? 'received' : 'loaded';
    final base = 'Short shipment $verb: ${t.scanned.length} of ${t.quantity}. Missing ${_ranges(t.missing)}.';
    final text = note.isEmpty ? base : '$base Note: $note';
    return text.length <= 500 ? text : text.substring(0, 500);
  }

  Future<void> _inScan(PackageTally t, String? remarks) async {
    final asException = ref.read(quickScanAccessProvider).raiseException;
    BulkResult? result;
    try {
      result = await ref
          .read(drsRepositoryProvider)
          .inScan(
            branchId: _branchId!,
            received: [t.trackingNumber],
            manifestNumber: _sheet?.number,
            // Staff who cannot raise an exception get the server's shortage ticket instead.
            missing: remarks != null && !asException ? t.missingIds : const [],
            remarks: remarks,
          );
    } on ApiException catch (e) {
      if (!e.outcomeUnknown) rethrow;
      // The answer was lost: read the shipment back rather than guessing.
      final now = await ref.read(shipmentRepositoryProvider).byId(_shipment!.id);
      if (now.status == QuickScanMode.inScan.requiredStatus) rethrow;
    }
    final failed = result?.results.where((r) => !r.success).firstOrNull;
    if (failed != null) {
      throw ApiException(ApiErrorKind.validation, failed.message ?? 'The shipment could not be received.');
    }
    await _finish(remarks, asException: asException, ticket: result?.shortageTicket);
  }

  Future<void> _outScan(PackageTally t, String? remarks) async {
    final manifestId = _shipment!.s('manifestId');
    if (manifestId == null) {
      throw const ApiException(ApiErrorKind.validation, 'This shipment is not on a loading sheet.');
    }
    try {
      final outcome =
          (await ref
                  .read(thcRepositoryProvider)
                  .outScan(manifestId: manifestId, hubBranchId: _branchId!, awbs: [t.trackingNumber]))
              .firstOrNull;
      final alreadyOurs = _outScanMaybeSent && (outcome?.message ?? '').startsWith('Already out-scanned');
      if (outcome == null || (!outcome.success && !alreadyOurs)) {
        throw ApiException(ApiErrorKind.validation, outcome?.message ?? 'The shipment could not be out-scanned.');
      }
    } on ApiException catch (e) {
      if (e.outcomeUnknown) _outScanMaybeSent = true;
      rethrow;
    }
    await _finish(remarks, asException: true);
  }

  /// The scan is saved. A short one still needs its exception; if that fails the scan
  /// stands and only the note is offered again.
  Future<void> _finish(String? remarks, {required bool asException, String? ticket}) async {
    final t = _tally!;
    if (mounted) {
      setState(() => _done = _Done(scanned: t.scanned.length, quantity: t.quantity, remarks: remarks, ticket: ticket));
    }
    if (remarks != null && asException) await _saveShort();
  }

  Future<void> _saveShort() async {
    final done = _done!;
    if (done.saving) return;
    setState(() => _done = done.copyWith(saving: true));
    try {
      await ref
          .read(quickScanRepositoryProvider)
          .raiseShort(shipmentId: _shipment!.id, branchId: _branchId!, remarks: done.remarks!);
      if (mounted) setState(() => _done = done.copyWith(saving: false, noteSaved: true));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _done = done.copyWith(
          saving: false,
          noteError: e.outcomeUnknown
              ? 'Could not confirm whether the short note was saved. Check the shipment before saving it again.'
              : 'The scan is saved, but the short note is not: ${e.message}',
        ),
      );
    }
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(quickScanAccessProvider);
    final allowed = _mode == QuickScanMode.inScan ? access.inScan : access.outScan;
    ref.watch(branchNamesProvider);
    return PopScope(
      canPop: !_submitting && (_done != null || (_tally?.scanned.isEmpty ?? true)),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _submitting) return;
        if (await _confirmDiscard() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(flexibleSpace: const AppBarGradient(), title: Text('Quick ${_mode.label}')),
        body: !allowed
            ? EmptyView(message: 'Your role cannot ${_mode.label.toLowerCase()} shipments.', icon: Icons.lock_outline)
            : _done != null
            ? _doneView(_done!)
            : _scanView(),
      ),
    );
  }

  Widget _scanView() {
    final s = _shipment;
    final t = _tally;
    final problem = s == null ? null : _problem;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (problem == null)
                TextField(
                  controller: _input,
                  enabled: !_loading && !_submitting,
                  textInputAction: TextInputAction.done,
                  onSubmitted: _typed,
                  decoration: scanDecoration(
                    t == null ? 'Scan label or enter shipment no / AWB' : 'Scan label or enter package no',
                    busy: _loading,
                    onScan: _camera,
                  ),
                ),
              if (problem == null && t != null)
                if (_feedback case final f?)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        Icon(
                          f.ok ? Icons.check_circle : Icons.error_outline,
                          size: 20,
                          color: f.ok ? AppColors.success : AppColors.danger,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            f.message,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: f.ok ? AppColors.success : AppColors.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: 14),
              if (s == null)
                EmptyView(
                  message: 'Scan the QR code on a package label, or type the shipment number.',
                  icon: Icons.qr_code_scanner,
                )
              else ...[
                _ShipmentCard(shipment: s, sheet: _sheet, mode: _mode),
                if (problem != null)
                  _Notice(text: problem, color: AppColors.danger, icon: Icons.block)
                else
                  _TallyCard(tally: t!, mode: _mode),
                TextButton.icon(
                  onPressed: _submitting
                      ? null
                      : () async {
                          if (await _confirmDiscard() && mounted) _reset();
                        },
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Scan a different shipment'),
                ),
              ],
            ],
          ),
        ),
        if (t != null && problem == null)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  if (!t.complete) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _submitting ? null : _camera,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scan next'),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: t.scanned.isEmpty || _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            )
                          : Icon(_mode.icon),
                      label: Text(_submitting ? 'Saving…' : _mode.label),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _doneView(_Done d) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      HeroCard(
        child: Column(
          children: [
            const SizedBox(height: 18),
            ResultSceneView(_mode.scene, d.short ? ResultKind.warning : ResultKind.success, onDark: true),
            const SizedBox(height: 22),
            Text(
              d.short ? '${_mode.label} done, short' : '${_mode.label} done',
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
            ),
            Text(_shipment!.trackingNumber, style: const TextStyle(color: Colors.white, fontSize: 16)),
            Text('${d.scanned} of ${d.quantity} packages', style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
      if (d.remarks != null)
        SectionCard(
          title: 'Short shipment',
          icon: Icons.report_problem_outlined,
          color: AppColors.warning,
          children: [
            Text(d.remarks!),
            if (d.ticket != null) InfoRow('Shortage ticket', d.ticket),
            if (d.saving) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
            if (d.noteSaved)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Short exception recorded.', style: TextStyle(color: AppColors.success)),
              ),
            if (d.noteError != null) ...[
              const SizedBox(height: 8),
              Text(d.noteError!, style: const TextStyle(color: AppColors.danger)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: d.saving ? null : _saveShort,
                icon: const Icon(Icons.refresh),
                label: const Text('Save note again'),
              ),
            ],
          ],
        ),
      FilledButton.icon(
        onPressed: d.saving ? null : _reset,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Scan next shipment'),
      ),
      const SizedBox(height: 10),
      OutlinedButton(onPressed: d.saving ? null : () => context.go('/home'), child: const Text('Done')),
    ],
  );
}

class _Done {
  const _Done({
    required this.scanned,
    required this.quantity,
    this.remarks,
    this.ticket,
    this.saving = false,
    this.noteSaved = false,
    this.noteError,
  });

  final int scanned;
  final int quantity;
  final String? remarks;
  final String? ticket;
  final bool saving;
  final bool noteSaved;
  final String? noteError;

  bool get short => scanned < quantity;

  _Done copyWith({required bool saving, bool noteSaved = false, String? noteError}) => _Done(
    scanned: scanned,
    quantity: quantity,
    remarks: remarks,
    ticket: ticket,
    saving: saving,
    noteSaved: noteSaved,
    noteError: noteError,
  );
}

/// 9, 10 or 3-6: compact list of package numbers.
String _ranges(List<int> n) {
  final out = <String>[];
  for (var i = 0; i < n.length; i++) {
    final start = n[i];
    while (i + 1 < n.length && n[i + 1] == n[i] + 1) {
      i++;
    }
    out.add(n[i] == start ? '$start' : '$start-${n[i]}');
  }
  return 'package ${out.join(', ')}';
}

class _ShortDialog extends StatefulWidget {
  const _ShortDialog({required this.mode, required this.tally});

  final QuickScanMode mode;
  final PackageTally tally;

  @override
  State<_ShortDialog> createState() => _ShortDialogState();
}

class _ShortDialogState extends State<_ShortDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tally;
    final received = widget.mode == QuickScanMode.inScan;
    return AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 40),
      title: Text(received ? 'Short shipment received' : 'Short shipment out-scan'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${t.scanned.length} of ${t.quantity} packages scanned.',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text('Missing: ${_ranges(t.missing)}', style: const TextStyle(color: AppColors.danger)),
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              maxLength: 300,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(labelText: 'Note', hintText: 'Why is it short?'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Keep scanning')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.warning, minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.pop(context, _note.text.trim()),
          child: Text('${widget.mode.label} short'),
        ),
      ],
    );
  }
}

class _ShipmentCard extends ConsumerWidget {
  const _ShipmentCard({required this.shipment, required this.sheet, required this.mode});

  final ShipmentDetail shipment;
  final LoadingSheet? sheet;
  final QuickScanMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = shipment;
    final branches = ref.watch(branchNamesProvider).value ?? const <String, Branch>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HeroCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.trackingNumber,
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                        ),
                        Text('Shipment ${s.shipmentNumber}', style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: StatusBadge(s.status),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              RouteStrip(
                from: s.s('fromCity') ?? branches[s.bookingBranchId]?.label ?? '–',
                to: s.s('toCity') ?? branches[s.deliveryBranchId]?.label ?? '–',
                onDark: true,
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Shipment details',
          icon: Icons.inventory_2_outlined,
          color: AppColors.purple,
          children: [
            InfoRow('Quantity', '${s.n('numberOfPackages')?.toInt() ?? 1} packages'),
            InfoRow('Weight', Fmt.kg(s.n('chargeableWeight'))),
            InfoRow('Sender', s.s('senderName')),
            InfoRow('Receiver', [s.s('receiverName'), s.s('receiverContact')].nonNulls.join(' · ')),
            InfoRow('Delivery branch', branches[s.deliveryBranchId]?.label),
            InfoRow(mode == QuickScanMode.inScan ? 'THC' : 'Loading sheet', sheet?.number),
          ],
        ),
      ],
    );
  }
}

class _TallyCard extends StatelessWidget {
  const _TallyCard({required this.tally, required this.mode});

  final PackageTally tally;
  final QuickScanMode mode;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Packages scanned',
    icon: Icons.qr_code_scanner,
    color: AppColors.indigo,
    trailing: Text(
      '${tally.scanned.length} / ${tally.quantity}',
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: tally.complete ? AppColors.success : AppColors.primary,
      ),
    ),
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: tally.scanned.length / tally.quantity,
          minHeight: 8,
          backgroundColor: AppColors.field,
          color: tally.complete ? AppColors.success : AppColors.primary,
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var n = 1; n <= tally.quantity; n++)
            Container(
              width: 44,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tally.scanned.contains(n) ? AppColors.success : AppColors.field,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$n',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: tally.scanned.contains(n) ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 10),
      Text(
        tally.complete
            ? 'All packages scanned.'
            : 'Scan every package label. If a label cannot be read, type its package number.',
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
    ],
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.color, required this.icon});

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
