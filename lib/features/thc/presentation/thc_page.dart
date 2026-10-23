import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/scanner_page.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_controller.dart';
import '../../loading_sheet/presentation/loading_sheet_detail_page.dart';
import '../../loading_sheet/presentation/loading_sheets_page.dart';
import '../../masters/data/masters.dart';
import '../data/thc_repository.dart';
import 'staff_picker.dart';
import '../../../core/scan_code.dart';
import '../../documents/document_page.dart';
import '../../documents/document_service.dart';

/// Generate THC. Without [manifestId] it first lists the branch's open loading sheets.
class ThcPage extends ConsumerWidget {
  const ThcPage({super.key, this.manifestId});

  final String? manifestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (manifestId != null) return _ThcForm(manifestId: manifestId!);
    final open = ref.watch(loadingSheetsProvider('CREATED'));
    return Scaffold(
      appBar: AppBar(title: const Text('Generate THC')),
      body: switch (open) {
        AsyncData(:final value) when value.isEmpty => const EmptyView(
          message: 'No open loading sheets. Create a loading sheet first.',
        ),
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text('Pick the loading sheet to dispatch', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final s in value)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LoadingSheetTile(sheet: s, onTap: () => context.pushReplacement('/thc?manifestId=${s.id}')),
              ),
          ],
        ),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(loadingSheetsProvider('CREATED')),
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _ThcForm extends ConsumerStatefulWidget {
  const _ThcForm({required this.manifestId});

  final String manifestId;

  @override
  ConsumerState<_ThcForm> createState() => _ThcFormState();
}

class _ThcFormState extends ConsumerState<_ThcForm> {
  final _form = GlobalKey<FormState>();
  final _scan = TextEditingController();
  final _otp = TextEditingController();
  final _amounts = {
    for (final k in ['fuel', 'advance', 'toll', 'other']) k: TextEditingController(),
  };

  String? _vehicleId;
  StaffUser? _driver;
  DateTime _departure = DateTime.now();
  final _outScanned = <String>{};
  bool _scanning = false;

  String? _otpMasked;
  bool _otpVerified = false;
  bool _otpBusy = false;

  bool _submitting = false;
  ThcResult? _result;

  @override
  void dispose() {
    _scan.dispose();
    _otp.dispose();
    for (final c in _amounts.values) {
      c.dispose();
    }
    super.dispose();
  }

  num? _amount(String k) => num.tryParse(_amounts[k]!.text.trim());

  Future<void> _outScan(String raw, SheetWithShipments data) async {
    final awb = raw.trim();
    _scan.clear();
    if (awb.isEmpty || _scanning) return;
    final onSheet = data.shipments
        .where((s) => matchesScan(trackingNumber: s.trackingNumber, shipmentNumber: s.shipmentNumber, raw: awb))
        .firstOrNull;
    if (onSheet == null) {
      showFailure(context, ApiException(ApiErrorKind.validation, '$awb is not on this loading sheet.'));
      return;
    }
    if (_outScanned.contains(onSheet.id)) {
      showSuccess(context, '$awb already scanned.');
      return;
    }
    setState(() => _scanning = true);
    try {
      final hubId = ref.read(sessionProvider)!.operatingBranchId!;
      final results = await ref
          .read(thcRepositoryProvider)
          .outScan(manifestId: widget.manifestId, hubBranchId: hubId, awbs: [onSheet.trackingNumber]);
      final r = results.firstOrNull;
      if (!mounted) return;
      if (r != null && r.success) {
        setState(() => _outScanned.add(onSheet.id));
        showSuccess(context, '$awb scanned out.');
      } else {
        showFailure(context, ApiException(ApiErrorKind.validation, r?.message ?? 'Out-scan failed for $awb.'));
      }
    } on ApiException catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _pickDriver() async {
    final picked = await showModalBottomSheet<StaffUser>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const StaffPickerSheet(),
    );
    if (picked != null && picked.id != _driver?.id) {
      setState(() {
        _driver = picked;
        _otpMasked = null;
        _otpVerified = false;
        _otp.clear();
      });
    }
  }

  Future<void> _pickDeparture() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _departure,
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now().add(const Duration(days: 7)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_departure));
    if (time == null) return;
    setState(() => _departure = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _sendOtp() async {
    final driver = _driver;
    if (driver == null) return;
    setState(() => _otpBusy = true);
    try {
      final r = await ref.read(thcRepositoryProvider).requestOtp(widget.manifestId, driver.id);
      if (!mounted) return;
      setState(() => _otpMasked = r.maskedMobile);
      showSuccess(context, 'OTP sent to ${r.maskedMobile}, valid ${r.expiresInMinutes} min.');
    } on ApiException catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _otpBusy = false);
    }
  }

  Future<void> _verifyOtp() async {
    final driver = _driver;
    if (driver == null || _otp.text.length != 4) return;
    setState(() => _otpBusy = true);
    try {
      await ref.read(thcRepositoryProvider).verifyOtp(widget.manifestId, driver.id, _otp.text);
      if (!mounted) return;
      setState(() => _otpVerified = true);
      showSuccess(context, 'Driver verified.');
    } on ApiException catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _otpBusy = false);
    }
  }

  Future<void> _generate(SheetWithShipments data, {required bool fromHub}) async {
    if (!_form.currentState!.validate() || _submitting) return;
    if (_driver == null) {
      showFailure(context, const ApiException(ApiErrorKind.validation, 'Pick the driver.'));
      return;
    }
    final missing = fromHub ? data.shipments.where((s) => !_outScanned.contains(s.id)).length : 0;
    final ok = await confirmAction(
      context,
      title: 'Generate THC?',
      message: [
        '${data.sheet.number}: ${data.shipments.length} shipments will be dispatched.',
        if (missing > 0) '$missing not scanned out on this phone; the server will refuse if they were not scanned.',
        'This cannot be undone from the app.',
      ].join('\n\n'),
      confirmLabel: 'Generate',
    );
    if (!ok || !mounted) return;
    setState(() => _submitting = true);
    try {
      final result = await ref
          .read(thcRepositoryProvider)
          .dispatch(
            manifestId: widget.manifestId,
            vehicleId: _vehicleId!,
            driverUserId: _driver!.id,
            departureTime: _departure,
            fuelCost: _amount('fuel'),
            driverAdvance: _amount('advance'),
            tollAmount: _amount('toll'),
            otherAmount: _amount('other'),
          );
      if (!mounted) return;
      setState(() => _result = result);
      ref.invalidate(loadingSheetDetailProvider(widget.manifestId));
      ref.invalidate(loadingSheetsProvider);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.outcomeUnknown) {
        await _settleUnknown();
      } else {
        showFailure(context, e);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// The dispatch answer was lost: read the sheet back. If it is dispatched the THC exists.
  Future<void> _settleUnknown() async {
    try {
      final sheet = await ref.read(thcRepositoryProvider).sheetAsThc(widget.manifestId);
      if (!mounted) return;
      if (sheet.status != 'CREATED') {
        setState(() => _result = sheet);
        showSuccess(context, 'THC ${sheet.number} was generated.');
        return;
      }
      showFailure(
        context,
        const ApiException(ApiErrorKind.timeout, 'THC was not generated (server timed out). You can try again.'),
      );
    } on ApiException {
      if (!mounted) return;
      showFailure(
        context,
        const ApiException(
          ApiErrorKind.timeout,
          'Could not confirm whether the THC was generated. Check the Dispatched tab before trying again.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(loadingSheetDetailProvider(widget.manifestId));
    final branches = ref.watch(branchNamesProvider).value ?? const <String, Branch>{};

    return Scaffold(
      appBar: AppBar(title: const Text('Generate THC')),
      body: switch (data) {
        AsyncData(:final value) when _result != null => _ResultView(result: _result!, sheet: value),
        AsyncData(:final value) when !value.sheet.isOpen => _AlreadyDispatched(manifestId: widget.manifestId),
        AsyncData(:final value) => _formBody(value, fromHub: branches[value.sheet.bookingBranchId]?.isHub ?? false),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(loadingSheetDetailProvider(widget.manifestId)),
        ),
        _ => const LoadingView(),
      },
    );
  }

  Widget _formBody(SheetWithShipments data, {required bool fromHub}) {
    final branches = ref.watch(branchNamesProvider).value ?? const <String, Branch>{};
    final vehicles = ref.watch(vehiclesProvider);
    final sheet = data.sheet;

    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: Text(sheet.number, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                'To ${branches[sheet.deliveryBranchId]?.label ?? '–'}\n'
                '${sheet.shipmentCount} shipments · ${sheet.totalPackages} pkg · ${Fmt.kg(sheet.totalWeight)}',
              ),
              isThreeLine: true,
              trailing: StatusBadge(sheet.status),
            ),
          ),
          if (fromHub) ...[
            const _Heading('Out-scan (required at hub)'),
            Text(
              '${_outScanned.length} of ${data.shipments.length} scanned on this phone',
              style: TextStyle(
                color: _outScanned.length == data.shipments.length ? AppColors.success : AppColors.warning,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _scan,
              onSubmitted: (v) => _outScan(v, data),
              decoration: InputDecoration(
                hintText: 'Scan or type AWB',
                prefixIcon: const Icon(Icons.qr_code_scanner),
                suffixIcon: _scanning
                    ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(
                        tooltip: 'Scan',
                        icon: const Icon(Icons.camera_alt_outlined),
                        onPressed: () async {
                          final v = await ScannerPage.scan(context);
                          if (v != null && mounted) await _outScan(v, data);
                        },
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in data.shipments)
                  Chip(
                    avatar: Icon(
                      _outScanned.contains(s.id) ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 18,
                      color: _outScanned.contains(s.id) ? AppColors.success : AppColors.neutral,
                    ),
                    label: Text(s.trackingNumber),
                  ),
              ],
            ),
          ],
          const _Heading('Vehicle and driver'),
          switch (vehicles) {
            AsyncData(:final value) when value.isEmpty => const Text(
              'No active vehicles. Add one in the web app first.',
              style: TextStyle(color: AppColors.danger),
            ),
            AsyncData(:final value) => DropdownButtonFormField<String>(
              initialValue: _vehicleId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Vehicle', prefixIcon: Icon(Icons.local_shipping_outlined)),
              items: [for (final v in value) DropdownMenuItem(value: v.id, child: Text(v.label))],
              onChanged: (v) => setState(() => _vehicleId = v),
              validator: (v) => v == null ? 'Pick the vehicle' : null,
            ),
            AsyncError(:final error) => ErrorView(error: error, onRetry: () => ref.invalidate(vehiclesProvider)),
            _ => const LinearProgressIndicator(),
          },
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.badge_outlined, color: AppColors.primary),
              title: Text(_driver?.name ?? 'Pick driver'),
              subtitle: _driver == null ? null : Text([_driver!.mobile, _driver!.designation].nonNulls.join(' · ')),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickDriver,
            ),
          ),
          if (_driver != null) _otpRow(),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.schedule, color: AppColors.primary),
              title: const Text('Departure'),
              subtitle: Text(Fmt.dateTime(_departure)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _pickDeparture,
            ),
          ),
          const _Heading('Trip expenses (optional)'),
          Row(
            children: [
              Expanded(
                child: _MoneyField(controller: _amounts['fuel']!, label: 'Fuel (₹)'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MoneyField(controller: _amounts['advance']!, label: 'Driver advance (₹)'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MoneyField(controller: _amounts['toll']!, label: 'Toll (₹)'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MoneyField(controller: _amounts['other']!, label: 'Other (₹)'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _submitting ? null : () => _generate(data, fromHub: fromHub),
            icon: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : const Icon(Icons.receipt_long_outlined),
            label: Text(_submitting ? 'Generating…' : 'Generate THC'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _otpRow() => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: _otpVerified
        ? const Row(
            children: [
              Icon(Icons.verified, color: AppColors.success),
              SizedBox(width: 8),
              Text('Driver verified by OTP'),
            ],
          )
        : Row(
            children: [
              Expanded(
                child: _otpMasked == null
                    ? const Text('Driver OTP (optional)', style: TextStyle(color: AppColors.textSecondary))
                    : TextField(
                        controller: _otp,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                        decoration: InputDecoration(labelText: 'OTP sent to $_otpMasked', isDense: true),
                      ),
              ),
              const SizedBox(width: 8),
              if (_otpMasked == null)
                TextButton(onPressed: _otpBusy ? null : _sendOtp, child: const Text('Send OTP'))
              else ...[
                TextButton(onPressed: _otpBusy ? null : _sendOtp, child: const Text('Resend')),
                FilledButton(onPressed: _otpBusy ? null : _verifyOtp, child: const Text('Verify')),
              ],
            ],
          ),
  );
}

class _ResultView extends ConsumerWidget {
  const _ResultView({required this.result, required this.sheet});

  final ThcResult result;
  final SheetWithShipments sheet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicles = ref.watch(vehiclesProvider).value ?? const [];
    final users = ref.watch(staffUsersProvider).value ?? const [];
    final vehicle = vehicles.where((v) => v.id == result.vehicleId).firstOrNull?.number;
    final driver = users.where((u) => u.id == result.driverUserId).firstOrNull;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.check_circle, color: AppColors.success, size: 64),
        const SizedBox(height: 8),
        const Text(
          'THC generated',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('THC number', style: TextStyle(color: AppColors.textSecondary)),
                SelectableText(result.number, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const Divider(height: 24),
                _kv('Status', result.status),
                _kv('Dispatched', Fmt.dateTime(result.dispatchedAt)),
                _kv('Departure', Fmt.dateTime(result.departureTime)),
                _kv('Shipments', '${result.shipmentCount ?? sheet.shipments.length}'),
                _kv('Vehicle', vehicle ?? '–'),
                _kv('Driver', driver == null ? '–' : [driver.name, driver.mobile].nonNulls.join(' · ')),
                if (result.fuelCost != null) _kv('Fuel', Fmt.money(result.fuelCost)),
                if (result.driverAdvance != null) _kv('Driver advance', Fmt.money(result.driverAdvance)),
                if (result.tollAmount != null) _kv('Toll', Fmt.money(result.tollAmount)),
                if (result.otherAmount != null) _kv('Other', Fmt.money(result.otherAmount)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: () => context.go('/loading-sheets'), child: const Text('Done')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => openDocument(
            context,
            title: 'THC ${result.number}',
            fileName: 'thc-${result.number}.pdf',
            build: () => ref.read(documentServiceProvider).sheet(result.manifestId, asThc: true),
          ),
          icon: const Icon(Icons.print_outlined),
          label: const Text('Print THC'),
        ),
      ],
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(k, style: const TextStyle(color: AppColors.textSecondary)),
        ),
        Expanded(
          child: Text(v, style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
      ],
    ),
  );
}

final _thcOfSheetProvider = FutureProvider.autoDispose.family<ThcResult, String>(
  (ref, id) => ref.watch(thcRepositoryProvider).sheetAsThc(id),
);

/// Opened for a sheet that already has a THC: show it instead of a second form.
class _AlreadyDispatched extends ConsumerWidget {
  const _AlreadyDispatched({required this.manifestId});

  final String manifestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thc = ref.watch(_thcOfSheetProvider(manifestId));
    final detail = ref.watch(loadingSheetDetailProvider(manifestId)).value;
    return switch (thc) {
      AsyncData(:final value) when detail != null => Column(
        children: [
          Container(
            width: double.infinity,
            color: AppColors.primaryLight,
            padding: const EdgeInsets.all(12),
            child: const Text('This loading sheet already has a THC. A second one cannot be generated.'),
          ),
          Expanded(
            child: _ResultView(result: value, sheet: detail),
          ),
        ],
      ),
      AsyncError(:final error) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(_thcOfSheetProvider(manifestId)),
      ),
      _ => const LoadingView(),
    };
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
    decoration: InputDecoration(labelText: label),
    validator: (v) {
      if (v == null || v.trim().isEmpty) return null;
      final n = num.tryParse(v.trim());
      return n == null || n < 0 ? 'Enter 0 or more' : null;
    },
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
  );
}
