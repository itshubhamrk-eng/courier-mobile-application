import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/scanner_page.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_controller.dart';
import '../../masters/data/masters.dart';
import '../../shipments/data/shipment_models.dart';
import '../../shipments/data/shipment_repository.dart';
import '../data/loading_sheet_repository.dart';
import '../../../core/scan_code.dart';
import '../../../core/widgets/ui.dart';

class NewLoadingSheetPage extends ConsumerStatefulWidget {
  const NewLoadingSheetPage({super.key});

  @override
  ConsumerState<NewLoadingSheetPage> createState() => _NewLoadingSheetPageState();
}

class _NewLoadingSheetPageState extends ConsumerState<NewLoadingSheetPage> {
  LoadingMode _mode = LoadingMode.hub;
  String? _destinationId;
  final _selected = <String>{};
  final _scan = TextEditingController();
  final _remarks = TextEditingController();

  List<ShipmentSummary> _eligible = const [];

  /// All loadable shipments at this branch (next-stop mode only), to offer destinations.
  List<ShipmentSummary> _routed = const [];
  bool _loading = false;
  Object? _error;
  bool _submitting = false;
  int _generation = 0;

  String get _branchId => ref.read(sessionProvider)!.operatingBranchId!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyDefaultHub());
  }

  @override
  void dispose() {
    _scan.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _applyDefaultHub() async {
    final branches = await ref.read(branchNamesProvider.future).catchError((_) => <String, Branch>{});
    final hubId = branches[_branchId]?.assignedHubId;
    if (!mounted) return;
    if (_mode == LoadingMode.hub && _destinationId == null && hubId != null && branches[hubId]?.isHub == true) {
      await _setDestination(hubId);
    }
  }

  Future<void> _setMode(LoadingMode mode) async {
    setState(() {
      _mode = mode;
      _destinationId = null;
      _selected.clear();
      _eligible = const [];
      _routed = const [];
      _error = null;
    });
    if (mode == LoadingMode.hub) await _applyDefaultHub();
    if (mode == LoadingMode.nextStop) await _loadRouted();
  }

  Future<void> _loadRouted() async {
    final generation = ++_generation;
    setState(() => _loading = true);
    try {
      final all = await ref
          .read(loadingSheetRepositoryProvider)
          .eligible(branchId: _branchId, mode: LoadingMode.nextStop);
      if (mounted && generation == _generation) setState(() => _routed = all);
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e);
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  Future<void> _setDestination(String? id) async {
    final generation = ++_generation;
    setState(() {
      _destinationId = id;
      _selected.clear();
      _eligible = const [];
      _error = null;
      _loading = id != null;
    });
    if (id == null) return;
    try {
      final list = await ref
          .read(loadingSheetRepositoryProvider)
          .eligible(branchId: _branchId, mode: _mode, nextLocationId: _mode == LoadingMode.nextStop ? id : null);
      if (mounted && generation == _generation) setState(() => _eligible = list);
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e);
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  /// Scanned or typed AWB: select it if eligible, otherwise say why not.
  Future<void> _addByAwb(String raw) async {
    final awb = raw.trim();
    if (awb.isEmpty) return;
    _scan.clear();
    final local = _eligible
        .where((s) => matchesScan(trackingNumber: s.trackingNumber, shipmentNumber: s.shipmentNumber, raw: awb))
        .firstOrNull;
    if (local != null) {
      if (_selected.contains(local.id)) {
        showSuccess(context, '$awb is already selected.');
      } else {
        setState(() => _selected.add(local.id));
        showSuccess(context, '$awb added.');
      }
      return;
    }
    try {
      final detail = await ref.read(shipmentRepositoryProvider).byAwb(awb);
      if (!mounted) return;
      final s = ShipmentSummary.fromJson(detail.raw);
      final reason =
          loadingIneligibility(s, branchId: _branchId, mode: _mode, destinationId: _destinationId) ??
          'Not in the eligible list for this destination.';
      showFailure(context, ApiException(ApiErrorKind.validation, '$awb cannot be loaded: $reason'));
    } on ApiException catch (e) {
      if (!mounted) return;
      showFailure(
        context,
        e.kind == ApiErrorKind.notFound ? ApiException(ApiErrorKind.notFound, 'No shipment found for $awb.') : e,
      );
    }
  }

  Future<void> _scanAwb() async {
    final value = await ScannerPage.scan(context);
    if (value != null && mounted) await _addByAwb(value);
  }

  Future<void> _create() async {
    final dest = _destinationId;
    if (dest == null || _selected.isEmpty || _submitting) return;
    final branches = ref.read(branchNamesProvider).value ?? const {};
    final picked = _eligible.where((s) => _selected.contains(s.id)).toList();
    final ok = await confirmAction(
      context,
      title: 'Create loading sheet?',
      message:
          '${picked.length} shipments to ${branches[dest]?.label ?? 'the selected branch'}.\n'
          'They will be reserved for this sheet.',
      confirmLabel: 'Create',
    );
    if (!ok || !mounted) return;
    setState(() => _submitting = true);
    try {
      final sheet = await ref
          .read(loadingSheetRepositoryProvider)
          .create(
            branchId: _branchId,
            destinationId: dest,
            mode: _mode,
            shipmentIds: picked.map((s) => s.id).toList(),
            remarks: _remarks.text,
          );
      if (!mounted) return;
      showSuccess(context, 'Loading sheet ${sheet.number} created.');
      context.pushReplacement('/loading-sheets/${sheet.id}');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      if (e.outcomeUnknown) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Not confirmed'),
            content: const Text(
              'The server did not answer in time. The loading sheet may have been created.\n\n'
              'Check Open loading sheets before trying again.',
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.go('/loading-sheets');
                },
                child: const Text('Open loading sheets'),
              ),
            ],
          ),
        );
      } else {
        showFailure(context, e);
        // Something changed on the server (e.g. another user loaded a shipment): refresh the list.
        await _setDestination(dest);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final branches = ref.watch(branchNamesProvider);
    final map = branches.value ?? const <String, Branch>{};
    final atHub = map[ref.watch(sessionProvider)?.operatingBranchId]?.isHub ?? false;
    final picked = _eligible.where((s) => _selected.contains(s.id)).toList();
    final packages = picked.fold<int>(0, (s, x) => s + (x.packages ?? 0));
    final weight = picked.fold<num>(0, (s, x) => s + (x.chargeableWeight ?? 0));

    final options = switch (_mode) {
      LoadingMode.hub => map.values.where((b) => b.isHub && b.id != _branchId).toList(),
      LoadingMode.branch => map.values.where((b) => b.id != _branchId).toList(),
      LoadingMode.nextStop => {
        for (final s in _routed)
          if ((s.nextLocationId ?? s.deliveryBranchId) case final id? when id != _branchId)
            id: map[id] ?? Branch(id: id, code: '', name: id),
      }.values.toList(),
    }..sort((a, b) => a.label.compareTo(b.label));

    return Scaffold(
      appBar: AppBar(flexibleSpace: const AppBarGradient(), title: const Text('New Loading Sheet')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SegmentedButton<LoadingMode>(
                  segments: [
                    const ButtonSegment(value: LoadingMode.hub, label: Text('To hub')),
                    const ButtonSegment(value: LoadingMode.branch, label: Text('To branch')),
                    if (atHub) const ButtonSegment(value: LoadingMode.nextStop, label: Text('Next stop')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => _setMode(s.first),
                ),
                const SizedBox(height: 14),
                if (branches.hasError)
                  ErrorView(error: branches.error!, onRetry: () => ref.invalidate(branchDirectoryProvider))
                else
                  DropdownButtonFormField<String>(
                    key: ValueKey('dest-$_mode-${options.length}'),
                    initialValue: options.any((o) => o.id == _destinationId) ? _destinationId : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: _mode == LoadingMode.hub ? 'Hub' : 'Destination branch',
                      prefixIcon: const Icon(Icons.local_shipping_outlined),
                    ),
                    items: [
                      for (final b in options)
                        DropdownMenuItem(
                          value: b.id,
                          child: Text(b.label, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _setDestination,
                  ),
                if (_mode == LoadingMode.nextStop && !_loading && _routed.isEmpty && _error == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('No shipments with a next stop are waiting here.'),
                  ),
                if (_destinationId != null) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _scan,
                    textInputAction: TextInputAction.done,
                    onSubmitted: _addByAwb,
                    decoration: InputDecoration(
                      hintText: 'Scan or type AWB to add',
                      prefixIcon: const Icon(Icons.qr_code_scanner),
                      suffixIcon: IconButton(
                        tooltip: 'Scan',
                        icon: const Icon(Icons.camera_alt_outlined),
                        onPressed: _scanAwb,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Eligible shipments (${_eligible.length})',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (_eligible.isNotEmpty)
                        TextButton(
                          onPressed: () => setState(() {
                            if (_selected.length == _eligible.length) {
                              _selected.clear();
                            } else {
                              _selected.addAll(_eligible.map((s) => s.id));
                            }
                          }),
                          child: Text(_selected.length == _eligible.length ? 'Clear all' : 'Select all'),
                        ),
                    ],
                  ),
                ],
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  ErrorView(
                    error: _error!,
                    onRetry: () => _mode == LoadingMode.nextStop && _destinationId == null
                        ? _loadRouted()
                        : _setDestination(_destinationId),
                  )
                else if (_destinationId != null && _eligible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No shipments are waiting to be loaded for this destination.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  for (final s in _eligible)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: CheckboxListTile(
                        value: _selected.contains(s.id),
                        onChanged: (v) => setState(() => v == true ? _selected.add(s.id) : _selected.remove(s.id)),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(s.trackingNumber, style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            StatusBadge(s.status),
                          ],
                        ),
                        subtitle: Text(
                          [
                            '${s.fromCity ?? '–'} → ${s.toCity ?? '–'}',
                            '${s.packages ?? 0} pkg · ${Fmt.kg(s.chargeableWeight)}',
                          ].join('\n'),
                        ),
                        isThreeLine: true,
                      ),
                    ),
                if (_destinationId != null && _eligible.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _remarks,
                    decoration: const InputDecoration(labelText: 'Remarks (optional)'),
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _Total('Shipments', '${picked.length}'),
                      _Total('Packages', '$packages'),
                      _Total('Weight', Fmt.kg(weight)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: picked.isEmpty || _submitting ? null : _create,
                    icon: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Icon(Icons.playlist_add_check),
                    label: Text(_submitting ? 'Creating…' : 'Create loading sheet'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
    ],
  );
}
