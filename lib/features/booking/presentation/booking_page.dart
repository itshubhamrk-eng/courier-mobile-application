import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../../masters/data/masters.dart';
import '../application/booking_draft.dart';
import '../data/booking_repository.dart';
import '../../shell/branch_header.dart';

/// Destination and packages first (one step) so charges show early; sender and
/// receiver after that, then a summary to confirm.
const _steps = ['Shipment', 'Charges', 'Parties', 'Summary'];
const _stepShipment = 0, _stepCharges = 1, _stepParties = 2, _stepSummary = 3;

class BookingPage extends ConsumerStatefulWidget {
  const BookingPage({super.key});

  @override
  ConsumerState<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends ConsumerState<BookingPage> {
  final _forms = List.generate(_steps.length, (_) => GlobalKey<FormState>());

  /// Second form on the Shipment step (packages); validated with the destination form.
  final _packagesForm = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  int _step = 0;

  BookingDraft get _draft => ref.read(bookingDraftProvider);
  void _update(BookingDraft Function(BookingDraft d) change) => ref.read(bookingDraftProvider.notifier).update(change);

  /// A controller bound to one draft field: starts from the draft, writes back on every edit.
  TextEditingController _ctl(String key, String initial, void Function(String v) write) =>
      _controllers.putIfAbsent(key, () {
        final c = TextEditingController(text: initial);
        c.addListener(() => write(c.text));
        return c;
      });

  @override
  void initState() {
    super.initState();
    // Pickup pincode defaults to the branch's own pincode.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_draft.pickupPincode.isNotEmpty) return;
      final branchId = ref.read(sessionProvider)?.operatingBranchId;
      final branches = await ref.read(branchNamesProvider.future).catchError((_) => <String, Branch>{});
      final pin = branches[branchId]?.postalCode;
      if (pin != null && mounted && _draft.pickupPincode.isEmpty) _controllers['pickupPincode']?.text = pin;
    });
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _next() {
    final valid = _forms[_step].currentState?.validate() ?? true;
    final packagesValid = _step != _stepShipment || (_packagesForm.currentState?.validate() ?? true);
    if (!valid || !packagesValid) return;
    if (_step == _stepCharges && (_draft.serviceTypeId == null || _draft.paymentModeId == null)) {
      showFailure(context, const ApiException(ApiErrorKind.validation, 'Choose service type and payment mode.'));
      return;
    }
    if (_step == _stepShipment &&
        _draft.destinationAreaId == null &&
        ref.read(_areasProvider(_draft.deliveryPincode)).value?.isNotEmpty == true) {
      showFailure(context, const ApiException(ApiErrorKind.validation, 'Pick the destination area.'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _step++);
  }

  Future<bool> _confirmDiscard() async {
    final ok = await confirmAction(
      context,
      title: 'Leave booking?',
      message: 'What you entered is kept. Continue later from Book Shipment.',
      confirmLabel: 'Leave',
    );
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(bookingDraftProvider);
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step--);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Book Shipment'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () async {
              if (await _confirmDiscard() && context.mounted) context.pop();
            },
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final ok = await confirmAction(
                  context,
                  title: 'Clear form?',
                  message: 'Everything entered for this booking will be removed.',
                  confirmLabel: 'Clear',
                );
                if (!ok || !mounted) return;
                ref.read(bookingDraftProvider.notifier).reset();
                ref.invalidate(branchWalletProvider);
                for (final c in _controllers.values) {
                  c.dispose();
                }
                setState(() {
                  _controllers.clear();
                  _step = 0;
                });
              },
              child: const Text('Clear', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        body: Column(
          children: [
            _StepHeader(step: _step),
            Expanded(
              child: IndexedStack(
                index: _step,
                children: [
                  _scroll(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Section('Destination'),
                        _destinationStep(),
                        const _Section('Packages'),
                        _packagesStep(),
                      ],
                    ),
                  ),
                  _ChargesStep(businessCustomer: _businessCustomerPicker()),
                  _scroll(_partiesStep()),
                  _SummaryStep(onEdit: (s) => setState(() => _step = s)),
                ],
              ),
            ),
            if (_step < _stepSummary)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      if (_step > 0) ...[
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                            onPressed: () => setState(() => _step--),
                            child: const Text('Back'),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        flex: 2,
                        child: FilledButton(onPressed: _next, child: const Text('Next')),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _scroll(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: child);

  // ---------------------------------------------------------------- step 1

  /// On the charges step: a business customer changes the rates (customer zone
  /// pricing) and the default payment mode, and prefills the sender.
  Widget _businessCustomerPicker() => _BusinessCustomerPicker(
    selectedName: _draft.businessCustomerName,
    onPicked: (detail) {
      _update((x) => x.copyWith(businessCustomerId: detail?.id, businessCustomerName: detail?.name));
      if (detail == null) return;
      _controllers['senderName']?.text = detail.name;
      if (detail.mobile != null) _controllers['senderContact']?.text = detail.mobile!;
      final address = detail.pickupAddresses.firstOrNull ?? detail.billingAddress;
      if (address != null) _controllers['senderAddress']?.text = address;
      _applyCustomerPaymentMode(detail.defaultPaymentMode);
    },
  );

  Widget _partiesStep() {
    final d = _draft;
    return Form(
      key: _forms[_stepParties],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Section('Sender (consignor)'),
          _PartyFields(
            prefix: 'sender',
            name: _ctl('senderName', d.senderName, (v) => _update((x) => x.copyWith(senderName: v))),
            contact: _ctl('senderContact', d.senderContact, (v) => _update((x) => x.copyWith(senderContact: v))),
            address: _ctl('senderAddress', d.senderAddress, (v) => _update((x) => x.copyWith(senderAddress: v))),
          ),
          const _Section('Receiver (consignee)'),
          _PartyFields(
            prefix: 'receiver',
            name: _ctl('receiverName', d.receiverName, (v) => _update((x) => x.copyWith(receiverName: v))),
            contact: _ctl('receiverContact', d.receiverContact, (v) => _update((x) => x.copyWith(receiverContact: v))),
            address: _ctl('receiverAddress', d.receiverAddress, (v) => _update((x) => x.copyWith(receiverAddress: v))),
          ),
        ],
      ),
    );
  }

  /// Same mapping as the web booking screen: CREDIT → TBB, TOPAY → TOPAY/TO_PAY, PAID → PAID.
  Future<void> _applyCustomerPaymentMode(String? customerMode) async {
    final codes = const {
      'CREDIT': ['TBB'],
      'TOPAY': ['TOPAY', 'TO_PAY'],
      'PAID': ['PAID'],
    }[customerMode];
    if (codes == null) return;
    final modes = await ref.read(paymentModesProvider.future).catchError((_) => <Option>[]);
    final match = modes.where((m) => codes.contains(m.code.toUpperCase())).firstOrNull;
    if (match != null) _update((x) => x.copyWith(paymentModeId: match.id));
  }

  // ---------------------------------------------------------------- step 2

  Widget _destinationStep() {
    final d = _draft;
    final pincode = d.deliveryPincode;
    final areas = _isPincode(pincode) ? ref.watch(_areasProvider(pincode)) : null;

    return Form(
      key: _forms[_stepShipment],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _ctl('pickupPincode', d.pickupPincode, (v) => _update((x) => x.copyWith(pickupPincode: v))),
            decoration: const InputDecoration(labelText: 'Pickup pincode', prefixIcon: Icon(Icons.store_outlined)),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            validator: (v) => _isPincode(v ?? '') ? null : 'Enter a 6-digit pincode',
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _ctl(
              'deliveryPincode',
              d.deliveryPincode,
              (v) => _update(
                (x) => x.deliveryPincode == v
                    ? x
                    : x.copyWith(deliveryPincode: v, destinationAreaId: null, destinationAreaLabel: null),
              ),
            ),
            decoration: const InputDecoration(labelText: 'Destination pincode', prefixIcon: Icon(Icons.place_outlined)),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            validator: (v) {
              if (!_isPincode(v ?? '')) return 'Enter a 6-digit pincode';
              if (areas is AsyncData<List<PincodeArea>> && areas.value.isEmpty) {
                return 'This pincode is not serviceable';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          if (areas != null)
            switch (areas) {
              AsyncData(:final value) when value.isEmpty => const Text(
                'No delivery area found for this pincode. Check the pincode or contact your administrator.',
                style: TextStyle(color: AppColors.danger),
              ),
              AsyncData(:final value) => _AreaPicker(
                areas: value,
                selected: d.destinationAreaId,
                onChanged: (a) =>
                    _update((x) => x.copyWith(destinationAreaId: a.areaId, destinationAreaLabel: a.label)),
              ),
              AsyncError(:final error) => ErrorView(
                error: error,
                onRetry: () => ref.invalidate(_areasProvider(pincode)),
              ),
              _ => const LinearProgressIndicator(),
            },
          const _Section('Delivery type'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'DOOR', label: Text('Door delivery'), icon: Icon(Icons.home_outlined)),
              ButtonSegment(value: 'OFFICE', label: Text('Office collect'), icon: Icon(Icons.store_outlined)),
            ],
            selected: {d.deliveryType},
            onSelectionChanged: (s) => _update((x) => x.copyWith(deliveryType: s.first)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- step 3

  Widget _packagesStep() {
    final d = _draft;
    final settings = ref.watch(bookingSettingsProvider).value;
    final needsEway = d.ewayBillNeeded(settings?.ewayBillThreshold);

    return Form(
      key: _packagesForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < d.items.length; i++)
            _ItemCard(
              key: ValueKey('item-$i-${d.items.length}'),
              index: i,
              item: d.items[i],
              canRemove: d.items.length > 1,
              onChanged: (item) => _update((x) => x.copyWith(items: [...x.items]..[i] = item)),
              onRemove: () => _update((x) => x.copyWith(items: [...x.items]..removeAt(i))),
            ),
          OutlinedButton.icon(
            onPressed: () => _update((x) => x.copyWith(items: [...x.items, const ItemDraft()])),
            icon: const Icon(Icons.add),
            label: const Text('Add another item'),
          ),
          const SizedBox(height: 16),
          _NumberField(
            label: 'Number of packages (boxes)',
            initial: d.numberOfPackages,
            hint: '${d.totalQuantity}',
            integer: true,
            onChanged: (v) => _update((x) => x.copyWith(numberOfPackages: v?.toInt())),
          ),
          const SizedBox(height: 14),
          _NumberField(
            label: 'Invoice value (₹)',
            initial: d.invoiceValue,
            onChanged: (v) => _update((x) => x.copyWith(invoiceValue: v)),
          ),
          if (needsEway) ...[
            const _Section('E-Way Bill'),
            Text(
              'Required: invoice value is ₹${settings!.ewayBillThreshold} or more.',
              style: const TextStyle(color: AppColors.warning),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _ctl(
                'ewayInvoiceNumber',
                d.ewayInvoiceNumber,
                (v) => _update((x) => x.copyWith(ewayInvoiceNumber: v)),
              ),
              decoration: const InputDecoration(labelText: 'Invoice number'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Invoice number is required for the E-Way Bill' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _ctl(
                'ewayConsignorGstin',
                d.ewayConsignorGstin,
                (v) => _update((x) => x.copyWith(ewayConsignorGstin: v)),
              ),
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Consignor GSTIN (optional)'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _ctl(
                'ewayConsigneeGstin',
                d.ewayConsigneeGstin,
                (v) => _update((x) => x.copyWith(ewayConsigneeGstin: v)),
              ),
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Consignee GSTIN (optional)'),
            ),
          ],
          const SizedBox(height: 14),
          TextFormField(
            controller: _ctl('remarks', d.remarks, (v) => _update((x) => x.copyWith(remarks: v))),
            decoration: const InputDecoration(labelText: 'Remarks (optional)'),
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  static bool _isPincode(String v) => RegExp(r'^\d{6}$').hasMatch(v.trim());
}

final _areasProvider = FutureProvider.autoDispose.family<List<PincodeArea>, String>(
  (ref, pincode) => ref.watch(mastersRepositoryProvider).pincodeAreas(pincode),
);

// ------------------------------------------------------------------ review

/// One server price check shared by the charges and summary steps. Keyed by the
/// booking body with placeholder sender / receiver (pricing never reads them), so
/// typing names on the parties step does not re-price.
class _PreviewArgs {
  _PreviewArgs(this.draft, this.branchId, this.minimumKg) : key = jsonEncode(previewBody(draft, branchId));

  final BookingDraft draft;
  final String branchId;
  final num? minimumKg;
  final String key;

  @override
  bool operator ==(Object other) => other is _PreviewArgs && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

final _previewProvider = FutureProvider.autoDispose.family<BookingPreview, _PreviewArgs>(
  (ref, a) =>
      ref.watch(bookingRepositoryProvider).preview(a.draft, branchId: a.branchId, minimumChargeableKg: a.minimumKg),
);

_PreviewArgs? _previewArgs(WidgetRef ref, BookingDraft d) {
  final branchId = ref.read(sessionProvider)?.operatingBranchId;
  if (branchId == null || d.serviceTypeId == null || d.paymentModeId == null) return null;
  return _PreviewArgs(d, branchId, ref.watch(bookingSettingsProvider).value?.minimumChargeableKg);
}

/// Step 3: service, payment mode, optional business customer, and the server's charges.
class _ChargesStep extends ConsumerWidget {
  const _ChargesStep({required this.businessCustomer});

  final Widget businessCustomer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(bookingDraftProvider);
    final args = _previewArgs(ref, d);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        businessCustomer,
        const SizedBox(height: 12),
        _OptionDropdown(
          label: 'Service type',
          options: ref.watch(serviceTypesProvider),
          value: d.serviceTypeId,
          onRetry: () => ref.invalidate(serviceTypesProvider),
          onChanged: (v) => ref.read(bookingDraftProvider.notifier).update((x) => x.copyWith(serviceTypeId: v)),
        ),
        const SizedBox(height: 12),
        _OptionDropdown(
          label: 'Payment mode',
          options: ref.watch(paymentModesProvider),
          value: d.paymentModeId,
          onRetry: () => ref.invalidate(paymentModesProvider),
          onChanged: (v) => ref.read(bookingDraftProvider.notifier).update((x) => x.copyWith(paymentModeId: v)),
        ),
        const SizedBox(height: 16),
        if (args == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Choose service type and payment mode to see charges.'),
          )
        else
          _PreviewCard(args: args, draft: d),
        const SizedBox(height: 4),
        const _ExtraCharges(),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Charges from the server for [args] as a bill, with wallet / E-Way Bill warnings.
class _PreviewCard extends ConsumerWidget {
  const _PreviewCard({required this.args, required this.draft, this.onEdit});

  final _PreviewArgs args;
  final BookingDraft draft;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) => switch (ref.watch(_previewProvider(args))) {
    AsyncData(value: final p) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (p.walletSufficient == false)
          _Warning(
            'Branch wallet is short for this booking'
            '${p.walletAvailable != null ? ' (available ${Fmt.money(p.walletAvailable)})' : ''}. '
            'Booking will be refused until the wallet is topped up.',
          ),
        if (p.ewayBillRequired && draft.ewayInvoiceNumber.trim().isEmpty)
          _Warning('An E-Way Bill is required for this invoice value. Add it on the Shipment step.'),
        _Invoice(preview: p, onEdit: onEdit, extrasPending: !p.exact && draft.hasExtraCharges),
      ],
    ),
    AsyncError(:final error) => ErrorView(error: error, onRetry: () => ref.invalidate(_previewProvider(args))),
    _ => const Padding(
      padding: EdgeInsets.all(24),
      child: Center(child: CircularProgressIndicator()),
    ),
  };
}

/// Bill layout: charge lines, then GST / discount / round off, then the net amount.
/// Every figure is the server's; nothing is added up here.
class _Invoice extends StatelessWidget {
  const _Invoice({required this.preview, this.onEdit, this.extrasPending = false});

  final BookingPreview preview;
  final VoidCallback? onEdit;

  /// Extra charges were entered but the estimate endpoints cannot price them.
  final bool extrasPending;

  @override
  Widget build(BuildContext context) {
    final p = preview;
    const amountStyle = TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]);
    Widget row(String label, num amount, {TextStyle? style}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(Fmt.money(amount), style: style ?? amountStyle),
        ],
      ),
    );
    final meta = [
      if (p.destinationCity != null) p.destinationCity!,
      'Chargeable ${Fmt.kg(p.chargeableWeight)}',
      if (p.ratePerKg != null) '${Fmt.money(p.ratePerKg)}/kg',
      if (p.slab != null) 'Slab ${p.slab}',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Charges', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (p.exact ? AppColors.success : AppColors.warning).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    p.exact ? 'Server price' : 'Estimate',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: p.exact ? AppColors.success : AppColors.warning,
                    ),
                  ),
                ),
                if (onEdit != null) TextButton(onPressed: onEdit, child: const Text('Edit')),
              ],
            ),
            Text(meta, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            const Row(
              children: [
                Expanded(
                  child: Text(
                    'DESCRIPTION',
                    style: TextStyle(fontSize: 11, letterSpacing: 0.6, color: AppColors.textSecondary),
                  ),
                ),
                Text('AMOUNT', style: TextStyle(fontSize: 11, letterSpacing: 0.6, color: AppColors.textSecondary)),
              ],
            ),
            const Divider(height: 12),
            for (final l in p.charges.lines) row(l.label, l.amount),
            if (p.charges.adjustments.isNotEmpty) ...[
              const Divider(height: 14),
              for (final l in p.charges.adjustments)
                row(l.label, l.amount, style: const TextStyle(color: AppColors.textSecondary)),
            ],
            const Divider(height: 18, thickness: 1.4, color: AppColors.textPrimary),
            if (p.exact && p.charges.netAmount != null)
              row(
                'Net amount',
                p.charges.netAmount!,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              )
            else
              const Text(
                'Net amount: calculated by the server when you book.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            const SizedBox(height: 8),
            Text(
              extrasPending
                  ? 'Additional charges you entered are added by the server when you book.'
                  : p.exact
                  ? 'Priced by the server exactly as booking will price it.'
                  : 'Estimate from the server\'s current rates; final GST and total are set at booking.',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Extra charges and options, as on the web booking form. Typed amounts are
/// sent after a short pause so the server is not asked on every keystroke.
class _ExtraCharges extends ConsumerWidget {
  const _ExtraCharges();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(bookingDraftProvider);
    final defaultAppointment = ref.watch(bookingSettingsProvider).value?.defaultAppointmentCharge;
    void update(BookingDraft Function(BookingDraft x) f) => ref.read(bookingDraftProvider.notifier).update(f);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Additional charges', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _DebouncedMoney(
                    label: 'Other (₹)',
                    value: d.otherCharges,
                    onChanged: (v) => update((x) => x.copyWith(otherCharges: v)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DebouncedMoney(
                    label: 'ODA (₹)',
                    hint: 'As per rate',
                    value: d.odaChargeOverride,
                    onChanged: (v) => update((x) => x.copyWith(odaChargeOverride: v)),
                  ),
                ),
              ],
            ),
            if (d.deliveryType == 'DOOR') ...[
              const SizedBox(height: 10),
              _DebouncedMoney(
                label: 'Door delivery charge (₹)',
                value: d.doorDeliveryCharge,
                onChanged: (v) => update((x) => x.copyWith(doorDeliveryCharge: v)),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: d.insuranceApplicable,
              onChanged: (v) => update((x) => x.copyWith(insuranceApplicable: v)),
              title: const Text('Insurance / FOV'),
              subtitle: const Text('2% of invoice value, added by the server'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: d.appointmentDelivery,
              onChanged: (v) => update(
                (x) => x.copyWith(
                  appointmentDelivery: v,
                  appointmentDeliveryCharge: v ? (x.appointmentDeliveryCharge ?? defaultAppointment) : null,
                  appointmentDate: v ? x.appointmentDate : null,
                  appointmentTimeSlot: v ? x.appointmentTimeSlot : '',
                ),
              ),
              title: const Text('Appointment delivery'),
            ),
            if (d.appointmentDelivery) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: d.appointmentDate ?? now.add(const Duration(days: 1)),
                          firstDate: now,
                          lastDate: now.add(const Duration(days: 60)),
                        );
                        if (picked != null) update((x) => x.copyWith(appointmentDate: picked));
                      },
                      icon: const Icon(Icons.event),
                      label: Text(d.appointmentDate == null ? 'Pick date' : Fmt.date(d.appointmentDate)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DebouncedMoney(
                      label: 'Charge (₹)',
                      value: d.appointmentDeliveryCharge,
                      onChanged: (v) => update((x) => x.copyWith(appointmentDeliveryCharge: v)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                initialValue: d.appointmentTimeSlot,
                decoration: const InputDecoration(labelText: 'Time slot (e.g. 10 AM – 1 PM)'),
                onChanged: (v) => update((x) => x.copyWith(appointmentTimeSlot: v)),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

/// Money field that reports its value 700 ms after typing stops (each value re-prices).
class _DebouncedMoney extends StatefulWidget {
  const _DebouncedMoney({required this.label, required this.value, required this.onChanged, this.hint});

  final String label;
  final String? hint;
  final num? value;
  final void Function(num? v) onChanged;

  @override
  State<_DebouncedMoney> createState() => _DebouncedMoneyState();
}

class _DebouncedMoneyState extends State<_DebouncedMoney> {
  late final _ctl = TextEditingController(text: widget.value?.toString() ?? '');
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _ctl,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
    decoration: InputDecoration(labelText: widget.label, hintText: widget.hint),
    onChanged: (v) {
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 700), () => widget.onChanged(num.tryParse(v.trim())));
    },
  );
}

/// Step 5: everything entered, the server's charges, then confirm.
class _SummaryStep extends ConsumerStatefulWidget {
  const _SummaryStep({required this.onEdit});

  final void Function(int step) onEdit;

  @override
  ConsumerState<_SummaryStep> createState() => _SummaryStepState();
}

class _SummaryStepState extends ConsumerState<_SummaryStep> {
  /// True while the create request is in flight; blocks a second submit.
  bool _submitting = false;

  Future<void> _book() async {
    final d = ref.read(bookingDraftProvider);
    final branchId = ref.read(sessionProvider)?.operatingBranchId;
    if (branchId == null) return;
    final ok = await confirmAction(
      context,
      title: 'Confirm booking?',
      message:
          '${d.packageCount} package(s) to ${d.destinationAreaLabel ?? d.deliveryPincode}.\n'
          'The server calculates the final amount and generates the AWB.',
      confirmLabel: 'Book',
    );
    if (!ok || !mounted || _submitting) return;
    setState(() => _submitting = true);
    try {
      final shipment = await ref.read(bookingRepositoryProvider).create(d, branchId: branchId);
      ref.read(bookingDraftProvider.notifier).reset();
      ref.invalidate(branchWalletProvider);
      if (mounted) context.pushReplacement('/bookings/done/${shipment.id}');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      if (e.outcomeUnknown) {
        await _unknownOutcome();
      } else {
        showFailure(context, e);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// The request may have reached the server. Booking again could create a
  /// duplicate, so send the user to check first.
  Future<void> _unknownOutcome() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Booking not confirmed'),
      content: const Text(
        'The server did not answer in time. The shipment may or may not have been booked.\n\n'
        'Check the Bookings list before booking again, so the same shipment is not booked twice.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Stay here')),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            context.go('/bookings');
          },
          child: const Text('Open Bookings'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(bookingDraftProvider);
    final args = _previewArgs(ref, d);
    final services = ref.watch(serviceTypesProvider).value ?? const <Option>[];
    final payments = ref.watch(paymentModesProvider).value ?? const <Option>[];
    String? label(List<Option> list, String? id) => list.where((o) => o.id == id).firstOrNull?.label;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SummaryCard(
          title: 'Destination',
          onEdit: () => widget.onEdit(_stepShipment),
          rows: [
            ('From', d.pickupPincode),
            ('To', [d.deliveryPincode, d.destinationAreaLabel].nonNulls.join(' · ')),
            ('Delivery', d.deliveryType == 'OFFICE' ? 'Office collection' : 'Door delivery'),
          ],
        ),
        _SummaryCard(
          title: 'Packages',
          onEdit: () => widget.onEdit(_stepShipment),
          rows: [
            ('Packages', '${d.packageCount} (${d.totalQuantity} pcs)'),
            ('Actual weight', Fmt.kg(d.totalActualWeight)),
            ('Declared value', Fmt.money(d.declaredValue)),
            if (d.invoiceValue != null) ('Invoice value', Fmt.money(d.invoiceValue)),
            if (d.ewayInvoiceNumber.trim().isNotEmpty) ('E-Way Bill invoice', d.ewayInvoiceNumber.trim()),
          ],
        ),
        _SummaryCard(
          title: 'Service and payment',
          onEdit: () => widget.onEdit(_stepCharges),
          rows: [
            if (d.businessCustomerName != null) ('Business customer', d.businessCustomerName!),
            ('Service', label(services, d.serviceTypeId) ?? '–'),
            ('Payment', label(payments, d.paymentModeId) ?? '–'),
            if (d.insuranceApplicable) ('Insurance / FOV', 'Yes'),
            if (d.appointmentDelivery)
              (
                'Appointment',
                [
                  Fmt.date(d.appointmentDate),
                  d.appointmentTimeSlot.trim(),
                ].where((x) => x.isNotEmpty && x != '–').join(' · '),
              ),
          ],
        ),
        _SummaryCard(
          title: 'Sender and receiver',
          onEdit: () => widget.onEdit(_stepParties),
          rows: [
            ('Sender', [d.senderName, d.senderContact].where((s) => s.trim().isNotEmpty).join(' · ')),
            if (d.senderAddress.trim().isNotEmpty) ('', d.senderAddress.trim()),
            ('Receiver', [d.receiverName, d.receiverContact].where((s) => s.trim().isNotEmpty).join(' · ')),
            if (d.receiverAddress.trim().isNotEmpty) ('', d.receiverAddress.trim()),
            if (d.remarks.trim().isNotEmpty) ('Remarks', d.remarks.trim()),
          ],
        ),
        if (args != null) _PreviewCard(args: args, draft: d, onEdit: () => widget.onEdit(_stepCharges)),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _submitting || args == null ? null : _book,
          icon: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : const Icon(Icons.check),
          label: Text(_submitting ? 'Booking…' : 'Confirm booking'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ------------------------------------------------------------------ widgets

class _Warning extends StatelessWidget {
  const _Warning(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.orange.shade50,
    margin: const EdgeInsets.only(bottom: 12),
    child: ListTile(
      leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
      title: Text(text, style: const TextStyle(fontSize: 14)),
    ),
  );
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.surface,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Row(
      children: [
        for (var i = 0; i < _steps.length; i++)
          Expanded(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: i <= step ? AppColors.primary : AppColors.border,
                  child: i < step
                      ? const Icon(Icons.check, size: 15, color: Colors.white)
                      : Text('${i + 1}', style: const TextStyle(fontSize: 12, color: Colors.white)),
                ),
                const SizedBox(height: 4),
                Text(
                  _steps[i],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: i == step ? FontWeight.w700 : FontWeight.w400,
                    color: i == step ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
  );
}

class _PartyFields extends StatelessWidget {
  const _PartyFields({required this.prefix, required this.name, required this.contact, required this.address});

  final String prefix;
  final TextEditingController name;
  final TextEditingController contact;
  final TextEditingController address;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _CustomerSuggestField(controller: name, contact: contact),
      const SizedBox(height: 10),
      TextFormField(
        controller: contact,
        keyboardType: TextInputType.phone,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
        decoration: const InputDecoration(labelText: 'Mobile number', prefixIcon: Icon(Icons.phone_outlined)),
        validator: (v) => RegExp(r'^\d{10}$').hasMatch(v ?? '') ? null : 'Enter a 10-digit mobile number',
      ),
      const SizedBox(height: 10),
      TextFormField(
        controller: address,
        maxLines: 2,
        decoration: const InputDecoration(labelText: 'Address', prefixIcon: Icon(Icons.home_outlined)),
        validator: (v) => (v ?? '').trim().length < 5 ? 'Enter the full address' : null,
      ),
    ],
  );
}

/// Name field that suggests existing customers (by name or mobile) as you type.
class _CustomerSuggestField extends ConsumerStatefulWidget {
  const _CustomerSuggestField({required this.controller, required this.contact});

  final TextEditingController controller;
  final TextEditingController contact;

  @override
  ConsumerState<_CustomerSuggestField> createState() => _CustomerSuggestFieldState();
}

class _CustomerSuggestFieldState extends ConsumerState<_CustomerSuggestField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Autocomplete<CustomerHit>(
    textEditingController: widget.controller,
    focusNode: _focus,
    displayStringForOption: (c) => c.name,
    optionsBuilder: (value) async {
      final q = value.text.trim();
      if (q.length < 2) return const [];
      try {
        return await ref.read(bookingRepositoryProvider).searchCustomers(q);
      } on ApiException {
        return const [];
      }
    },
    onSelected: (c) {
      if (c.mobile != null) widget.contact.text = c.mobile!;
    },
    optionsViewBuilder: (context, onSelected, options) => Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
          child: ListView(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            children: [
              for (final c in options)
                ListTile(
                  dense: true,
                  title: Text(c.name),
                  subtitle: Text([c.mobile, c.code].nonNulls.join(' · ')),
                  onTap: () => onSelected(c),
                ),
            ],
          ),
        ),
      ),
    ),
    fieldViewBuilder: (context, ctl, focus, onSubmit) => TextFormField(
      controller: ctl,
      focusNode: focus,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Icons.person_outline)),
      validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the name' : null,
    ),
  );
}

class _BusinessCustomerPicker extends ConsumerWidget {
  const _BusinessCustomerPicker({required this.selectedName, required this.onPicked});

  final String? selectedName;
  final void Function(CustomerDetail? detail) onPicked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> pick() async {
      final hit = await showModalBottomSheet<CustomerHit>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const _CustomerSearchSheet(),
      );
      if (hit == null || !context.mounted) return;
      try {
        onPicked(await ref.read(bookingRepositoryProvider).customer(hit.id));
      } on ApiException catch (e) {
        if (context.mounted) showFailure(context, e);
      }
    }

    return Card(
      child: ListTile(
        leading: const Icon(Icons.business_center_outlined, color: AppColors.primary),
        title: Text(selectedName ?? 'Business customer (optional)'),
        subtitle: Text(selectedName == null ? 'Pick to use their address and pricing' : 'Business booking'),
        trailing: selectedName == null
            ? const Icon(Icons.chevron_right)
            : IconButton(tooltip: 'Remove', icon: const Icon(Icons.close), onPressed: () => onPicked(null)),
        onTap: pick,
      ),
    );
  }
}

class _CustomerSearchSheet extends ConsumerStatefulWidget {
  const _CustomerSearchSheet();

  @override
  ConsumerState<_CustomerSearchSheet> createState() => _CustomerSearchSheetState();
}

class _CustomerSearchSheetState extends ConsumerState<_CustomerSearchSheet> {
  Timer? _debounce;
  Future<List<CustomerHit>>? _results;

  void _search(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _results = ref.read(bookingRepositoryProvider).searchCustomers(q.trim(), businessOnly: true));
    });
  }

  @override
  void initState() {
    super.initState();
    _results = ref.read(bookingRepositoryProvider).searchCustomers('', businessOnly: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              autofocus: true,
              onChanged: _search,
              decoration: const InputDecoration(hintText: 'Search business customer', prefixIcon: Icon(Icons.search)),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<CustomerHit>>(
              future: _results,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) return const LoadingView();
                if (snap.hasError) return ErrorView(error: snap.error!);
                final list = snap.data ?? const [];
                if (list.isEmpty) return const EmptyView(message: 'No business customers found.');
                return ListView(
                  children: [
                    for (final c in list)
                      ListTile(
                        title: Text(c.name),
                        subtitle: Text([c.code, c.mobile].nonNulls.join(' · ')),
                        onTap: () => Navigator.pop(context, c),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _AreaPicker extends StatelessWidget {
  const _AreaPicker({required this.areas, required this.selected, required this.onChanged});

  final List<PincodeArea> areas;
  final String? selected;
  final void Function(PincodeArea area) onChanged;

  @override
  Widget build(BuildContext context) {
    // The primary area is the default, as on the web booking screen.
    final current = selected ?? areas.where((a) => a.primary).firstOrNull?.areaId;
    if (selected == null && current != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onChanged(areas.firstWhere((a) => a.areaId == current)));
    }
    return DropdownButtonFormField<String>(
      initialValue: current,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Destination area', prefixIcon: Icon(Icons.map_outlined)),
      items: [
        for (final a in areas)
          DropdownMenuItem(
            value: a.areaId,
            child: Text(a.oda ? '${a.label} (ODA)' : a.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (id) => onChanged(areas.firstWhere((a) => a.areaId == id)),
      validator: (v) => v == null ? 'Pick the destination area' : null,
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    super.key,
    required this.index,
    required this.item,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final ItemDraft item;
  final bool canRemove;
  final void Function(ItemDraft item) onChanged;
  final VoidCallback onRemove;

  ItemDraft _with({
    String? name,
    int? qty,
    Object? weight = _k,
    Object? l = _k,
    Object? w = _k,
    Object? h = _k,
    Object? value = _k,
  }) => ItemDraft(
    name: name ?? item.name,
    quantity: qty ?? item.quantity,
    weight: weight == _k ? item.weight : weight as num?,
    length: l == _k ? item.length : l as num?,
    width: w == _k ? item.width : w as num?,
    height: h == _k ? item.height : h as num?,
    declaredValue: value == _k ? item.declaredValue : value as num?,
  );

  static const _k = Object();

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Text('Item ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              if (canRemove)
                IconButton(tooltip: 'Remove item', icon: const Icon(Icons.delete_outline), onPressed: onRemove),
            ],
          ),
          TextFormField(
            initialValue: item.name,
            decoration: const InputDecoration(labelText: 'Description'),
            onChanged: (v) => onChanged(_with(name: v)),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  label: 'Quantity',
                  initial: item.quantity,
                  integer: true,
                  required: true,
                  onChanged: (v) => onChanged(_with(qty: (v ?? 1).toInt())),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _NumberField(
                  label: 'Total weight (kg)',
                  initial: item.weight,
                  required: true,
                  onChanged: (v) => onChanged(_with(weight: v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  label: 'L (cm)',
                  initial: item.length,
                  onChanged: (v) => onChanged(_with(l: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberField(
                  label: 'W (cm)',
                  initial: item.width,
                  onChanged: (v) => onChanged(_with(w: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberField(
                  label: 'H (cm)',
                  initial: item.height,
                  onChanged: (v) => onChanged(_with(h: v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _NumberField(
            label: 'Declared value (₹)',
            initial: item.declaredValue,
            required: true,
            onChanged: (v) => onChanged(_with(value: v)),
          ),
        ],
      ),
    ),
  );
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.onChanged,
    this.initial,
    this.hint,
    this.integer = false,
    this.required = false,
  });

  final String label;
  final num? initial;
  final String? hint;
  final bool integer;
  final bool required;
  final void Function(num? v) onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
    initialValue: initial?.toString() ?? '',
    keyboardType: TextInputType.numberWithOptions(decimal: !integer),
    inputFormatters: [FilteringTextInputFormatter.allow(integer ? RegExp(r'\d') : RegExp(r'[\d.]'))],
    decoration: InputDecoration(labelText: label, hintText: hint),
    onChanged: (v) => onChanged(num.tryParse(v)),
    validator: (v) {
      final n = num.tryParse(v ?? '');
      if (n == null) return required ? 'Required' : null;
      if (n <= 0) return 'Must be more than 0';
      return null;
    },
  );
}

class _OptionDropdown extends StatelessWidget {
  const _OptionDropdown({
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.onRetry,
  });

  final String label;
  final AsyncValue<List<Option>> options;
  final String? value;
  final void Function(String? id) onChanged;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => switch (options) {
    AsyncData(value: final list) => DropdownButtonFormField<String>(
      initialValue: list.any((o) => o.id == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [for (final o in list) DropdownMenuItem(value: o.id, child: Text(o.label))],
      onChanged: onChanged,
    ),
    AsyncError(:final error) => ErrorView(error: error, onRetry: onRetry),
    _ => const LinearProgressIndicator(),
  };
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.rows, this.onEdit});

  final String title;
  final List<(String, String)> rows;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              if (onEdit != null) TextButton(onPressed: onEdit, child: const Text('Edit')),
            ],
          ),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(label, style: const TextStyle(color: AppColors.textSecondary)),
                  ),
                  Expanded(
                    child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
