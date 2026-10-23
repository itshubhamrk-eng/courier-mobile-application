import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/scanner_page.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../../masters/data/masters.dart';
import '../../shipments/data/shipment_models.dart';
import '../../thc/data/thc_repository.dart';
import '../../thc/presentation/staff_picker.dart';
import '../data/drs_repository.dart';
import 'drs_widgets.dart';
import '../../../core/scan_code.dart';
import '../../documents/document_page.dart';
import '../../documents/document_service.dart';

/// Make a DRS: pick shipments waiting for delivery, assign a delivery partner.
class NewDrsPage extends ConsumerStatefulWidget {
  const NewDrsPage({super.key});

  @override
  ConsumerState<NewDrsPage> createState() => _NewDrsPageState();
}

class _NewDrsPageState extends ConsumerState<NewDrsPage> {
  DrsSource _source = DrsSource.branch;
  Future<List<ShipmentSummary>>? _ready;
  List<ShipmentSummary> _list = const [];
  final _selected = <String>{};
  final _scan = TextEditingController();
  final _fuel = TextEditingController();
  final _charge = TextEditingController();
  StaffUser? _partner;
  String? _vehicleId;
  String? _otpMasked;
  bool _otpVerified = false;
  bool _otpBusy = false;
  final _otp = TextEditingController();
  bool _submitting = false;
  BulkResult? _result;
  List<ShipmentSummary> _submitted = const [];

  String get _branchId => ref.read(sessionProvider)!.operatingBranchId!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scan.dispose();
    _fuel.dispose();
    _charge.dispose();
    _otp.dispose();
    super.dispose();
  }

  void _load() {
    _selected.clear();
    _ready = ref.read(drsRepositoryProvider).readyForDelivery(_branchId, _source).then((l) => _list = l);
    setState(() {});
  }

  void _addByAwb(String raw) {
    final awb = raw.trim();
    _scan.clear();
    if (awb.isEmpty) return;
    final s = _list
        .where((x) => matchesScan(trackingNumber: x.trackingNumber, shipmentNumber: x.shipmentNumber, raw: awb))
        .firstOrNull;
    if (s == null) {
      showFailure(
        context,
        ApiException(
          ApiErrorKind.validation,
          '$awb is not waiting for delivery here. Receive it first, or check the AWB.',
        ),
      );
      return;
    }
    setState(() => _selected.add(s.id));
    showSuccess(context, '$awb added.');
  }

  Future<void> _pickPartner() async {
    final u = await showModalBottomSheet<StaffUser>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const StaffPickerSheet(hint: 'Search delivery partner'),
    );
    if (u != null && u.id != _partner?.id) {
      setState(() {
        _partner = u;
        _otpMasked = null;
        _otpVerified = false;
        _otp.clear();
      });
    }
  }

  Future<void> _sendOtp() async {
    if (_partner == null) return;
    setState(() => _otpBusy = true);
    try {
      final r = await ref.read(drsRepositoryProvider).requestOtp(_partner!.id);
      if (!mounted) return;
      setState(() => _otpMasked = r.maskedMobile);
      showSuccess(context, 'OTP sent to ${r.maskedMobile}.');
    } on ApiException catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _otpBusy = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (_partner == null || _otp.text.length != 4) return;
    setState(() => _otpBusy = true);
    try {
      await ref.read(drsRepositoryProvider).verifyOtp(_partner!.id, _otp.text);
      if (mounted) setState(() => _otpVerified = true);
    } on ApiException catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _otpBusy = false);
    }
  }

  Future<void> _create() async {
    if (_partner == null) {
      showFailure(context, const ApiException(ApiErrorKind.validation, 'Pick the delivery partner.'));
      return;
    }
    final picked = _list.where((s) => _selected.contains(s.id)).toList();
    if (picked.isEmpty || _submitting) return;
    final ok = await confirmAction(
      context,
      title: 'Generate DRS?',
      message: '${picked.length} shipments go out for delivery with ${_partner!.name}.',
      confirmLabel: 'Generate',
    );
    if (!ok || !mounted) return;
    setState(() => _submitting = true);
    try {
      final r = await ref
          .read(drsRepositoryProvider)
          .outForDelivery(
            shipmentIds: picked.map((s) => s.id).toList(),
            deliveryUserId: _partner!.id,
            vehicleId: _vehicleId,
            fuelCost: num.tryParse(_fuel.text.trim()),
            deliveryCharge: num.tryParse(_charge.text.trim()),
          );
      if (mounted) {
        setState(() {
          _result = r;
          _submitted = picked;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      showFailure(
        context,
        e.outcomeUnknown
            ? const ApiException(
                ApiErrorKind.timeout,
                'Not confirmed (server timed out). Check Delivery runs before trying again: '
                'shipments already out for delivery cannot be assigned twice.',
              )
            : e,
      );
      _load();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_result != null) return _ResultPage(result: _result!, submitted: _submitted, partner: _partner!);
    final map = ref.watch(branchNamesProvider).value ?? const <String, Branch>{};
    final atHub = map[ref.watch(sessionProvider)?.operatingBranchId]?.isHub ?? false;
    final vehicles = ref.watch(vehiclesProvider).value ?? const <Vehicle>[];
    final modes = ref.watch(paymentModesProvider).value ?? const <Option>[];
    final picked = _list.where((s) => _selected.contains(s.id)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('New DRS')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (atHub) ...[
                  SegmentedButton<DrsSource>(
                    segments: const [
                      ButtonSegment(value: DrsSource.branch, label: Text('Received here')),
                      ButtonSegment(value: DrsSource.hubDirect, label: Text('Hub direct')),
                    ],
                    selected: {_source},
                    onSelectionChanged: (s) {
                      _source = s.first;
                      _load();
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.delivery_dining_outlined, color: AppColors.primary),
                    title: Text(_partner?.name ?? 'Pick delivery partner'),
                    subtitle: _partner?.mobile == null ? null : Text(_partner!.mobile!),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pickPartner,
                  ),
                ),
                if (_partner != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _otpVerified
                        ? const Row(
                            children: [
                              Icon(Icons.verified, color: AppColors.success),
                              SizedBox(width: 8),
                              Text('Partner verified by OTP'),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: _otpMasked == null
                                    ? const Text(
                                        'Partner OTP (optional)',
                                        style: TextStyle(color: AppColors.textSecondary),
                                      )
                                    : TextField(
                                        controller: _otp,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.digitsOnly,
                                          LengthLimitingTextInputFormatter(4),
                                        ],
                                        decoration: InputDecoration(
                                          labelText: 'OTP sent to $_otpMasked',
                                          isDense: true,
                                        ),
                                      ),
                              ),
                              TextButton(
                                onPressed: _otpBusy ? null : _sendOtp,
                                child: Text(_otpMasked == null ? 'Send OTP' : 'Resend'),
                              ),
                              if (_otpMasked != null)
                                FilledButton(onPressed: _otpBusy ? null : _verifyOtp, child: const Text('Verify')),
                            ],
                          ),
                  ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _vehicleId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Vehicle (optional)'),
                  items: [
                    const DropdownMenuItem<String>(child: Text('None')),
                    for (final v in vehicles) DropdownMenuItem(value: v.id, child: Text(v.label)),
                  ],
                  onChanged: (v) => setState(() => _vehicleId = v),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _fuel,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Fuel (₹, optional)'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _charge,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Delivery charge (₹, optional)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _scan,
                  onSubmitted: _addByAwb,
                  decoration: InputDecoration(
                    hintText: 'Scan or type AWB to add',
                    prefixIcon: const Icon(Icons.qr_code_scanner),
                    suffixIcon: IconButton(
                      tooltip: 'Scan',
                      icon: const Icon(Icons.camera_alt_outlined),
                      onPressed: () async {
                        final v = await ScannerPage.scan(context);
                        if (v != null && mounted) _addByAwb(v);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                FutureBuilder<List<ShipmentSummary>>(
                  future: _ready,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _load);
                    final list = snap.data!;
                    if (list.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No shipments are waiting for delivery.', textAlign: TextAlign.center),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Waiting for delivery (${list.length})',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            TextButton(
                              onPressed: () => setState(() {
                                if (_selected.length == list.length) {
                                  _selected.clear();
                                } else {
                                  _selected.addAll(list.map((s) => s.id));
                                }
                              }),
                              child: Text(_selected.length == list.length ? 'Clear all' : 'Select all'),
                            ),
                          ],
                        ),
                        for (final s in list)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: CheckboxListTile(
                              value: _selected.contains(s.id),
                              onChanged: (v) =>
                                  setState(() => v == true ? _selected.add(s.id) : _selected.remove(s.id)),
                              title: Text(s.trackingNumber, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text(
                                [
                                  [s.receiverName, s.receiverContact].nonNulls.join(' · '),
                                  ?collectLabel(s.paymentModeId, s.netAmount, modes),
                                ].join('\n'),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                onPressed: picked.isEmpty || _submitting ? null : _create,
                icon: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Icon(Icons.assignment_turned_in_outlined),
                label: Text(_submitting ? 'Generating…' : 'Generate DRS (${picked.length})'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultPage extends ConsumerWidget {
  const _ResultPage({required this.result, required this.submitted, required this.partner});

  final BulkResult result;
  final List<ShipmentSummary> submitted;
  final StaffUser partner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failed = result.results.where((o) => !o.success).toList();
    final branchId = ref.watch(sessionProvider)?.operatingBranchId;
    return Scaffold(
      appBar: AppBar(title: const Text('DRS generated'), automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(
            failed.isEmpty ? Icons.check_circle : Icons.warning_amber_rounded,
            size: 60,
            color: failed.isEmpty ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(height: 8),
          if (result.drsNumber != null) ...[
            const Text(
              'DRS number',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            SelectableText(
              result.drsNumber!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '${result.successCount} out for delivery with ${partner.name}'
            '${failed.isEmpty ? '' : ' · ${failed.length} not assigned'}',
            textAlign: TextAlign.center,
          ),
          for (final o in failed)
            ListTile(
              leading: const Icon(Icons.error_outline, color: AppColors.danger),
              title: Text(o.reference),
              subtitle: Text(o.message ?? 'Not assigned'),
            ),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => context.pop(), child: const Text('Done')),
          const SizedBox(height: 8),
          if (result.successCount > 0 && branchId != null)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => openDocument(
                context,
                title: 'DRS ${result.drsNumber ?? ''}',
                fileName: 'drs-${result.drsNumber ?? 'today'}.pdf',
                build: () => ref
                    .read(documentServiceProvider)
                    .drs(
                      DrsRun(
                        deliveryUserId: partner.id,
                        deliveryBranchId: branchId,
                        runDate: DateTime.now(),
                        drsNumber: result.drsNumber,
                      ),
                    ),
              ),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Print DRS'),
            ),
        ],
      ),
    );
  }
}
