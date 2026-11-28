import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/format.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/result_animation.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/ui.dart';
import '../../auth/application/auth_controller.dart';
import '../../booking/application/booking_draft.dart';
import '../../drs/presentation/drs_widgets.dart';
import '../../shell/branch_header.dart';
import '../data/vendor_repository.dart';

/// The vendor's pickup requests (web: Vendor Management > Pickup Requests). Assigned
/// ones are accepted or rejected, then started, collected (or failed) and booked.
class PickupsPage extends ConsumerWidget {
  const PickupsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pickups = ref.watch(pickupsProvider);
    Future<void> refresh() => ref.refresh(pickupsProvider.future);
    Widget list(bool open) => RefreshIndicator(
      onRefresh: refresh,
      child: switch (pickups) {
        AsyncData(:final value) => () {
          final rows = value.where((p) => p.isOpen == open).toList();
          if (rows.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: 320,
                  child: EmptyView(
                    message: open ? 'No pickups waiting for you.' : 'No finished pickups yet.',
                    icon: Icons.inventory_2_outlined,
                  ),
                ),
              ],
            );
          }
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [for (final p in rows) PickupCard(pickup: p)],
          );
        }(),
        AsyncError(:final error) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 360,
              child: ErrorView(error: error, onRetry: refresh),
            ),
          ],
        ),
        _ => const LoadingView(message: 'Loading pickups…'),
      },
    );
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: sectionBar(
          'Pickup Requests',
          bottom: sectionTabs(const [Tab(text: 'To do'), Tab(text: 'Done')]),
        ),
        body: TabBarView(children: [list(true), list(false)]),
      ),
    );
  }
}

class PickupCard extends ConsumerStatefulWidget {
  const PickupCard({super.key, required this.pickup});

  final Pickup pickup;

  @override
  ConsumerState<PickupCard> createState() => _PickupCardState();
}

class _PickupCardState extends ConsumerState<PickupCard> {
  bool _busy = false;

  Pickup get _p => widget.pickup;

  Future<void> _run(Future<Pickup> Function(VendorRepository r) action, String done, String failTitle) async {
    setState(() => _busy = true);
    try {
      final p = await action(ref.read(vendorRepositoryProvider));
      if (!mounted) return;
      showSubmitSuccess(context, '${p.number}: ${statusStyle(p.status).label}.', title: done);
      ref
        ..invalidate(pickupsProvider)
        ..invalidate(vendorDashboardProvider);
    } on ApiException catch (e) {
      if (mounted) showSubmitFailure(context, e, title: failTitle);
      ref.invalidate(pickupsProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final reason = await _askReason(context, 'Reject pickup?', 'Why can you not take it?', 'Reject');
    if (reason != null) await _run((r) => r.reject(_p.id, reason), 'Pickup rejected', 'Not rejected');
  }

  Future<void> _fail() async {
    final reason = await _askReason(
      context,
      'Pickup failed?',
      'What happened? e.g. customer not available',
      'Mark failed',
    );
    if (reason != null) await _run((r) => r.fail(_p.id, reason), 'Marked failed', 'Not saved');
  }

  Future<void> _collected() async {
    final v = await showDialog<({int parcels, num weight})>(
      context: context,
      builder: (_) => _CollectedDialog(pickup: _p),
    );
    if (v != null) {
      await _run((r) => r.collected(_p.id, parcels: v.parcels, weightKg: v.weight), 'Goods collected', 'Not saved');
    }
  }

  /// Opens booking with the pickup's details filled; booking links the shipment back.
  void _book() {
    ref
        .read(bookingDraftProvider.notifier)
        .update(
          (_) => BookingDraft(
            pickupId: _p.id,
            pickupNo: _p.number,
            senderName: _p.contactName,
            senderContact: _p.contactMobile
                .replaceAll(RegExp(r'\D'), '')
                .replaceFirst(RegExp(r'^(91|0)(?=\d{10}$)'), ''),
            senderAddress: [_p.address, _p.city].nonNulls.where((s) => s.isNotEmpty).join(', '),
            pickupPincode: _p.pincode,
            items: [ItemDraft(quantity: _p.actualParcels ?? _p.expectedParcels, weight: _p.actualWeightKg)],
          ),
        );
    context.push('/bookings/new');
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final canBook = ref.watch(sessionProvider)?.can(Permissions.shipmentCreate) ?? false;
    Widget action(String label, IconData icon, VoidCallback onTap, {bool primary = true, Color? color}) => Expanded(
      child: primary
          ? FilledButton.icon(
              style: color == null ? null : FilledButton.styleFrom(backgroundColor: color),
              onPressed: _busy ? null : onTap,
              icon: Icon(icon, size: 18),
              label: Text(label),
            )
          : OutlinedButton.icon(
              style: color == null
                  ? null
                  : OutlinedButton.styleFrom(
                      foregroundColor: color,
                      side: BorderSide(color: color),
                    ),
              onPressed: _busy ? null : onTap,
              icon: Icon(icon, size: 18),
              label: Text(label),
            ),
    );
    final actions = switch (p.status) {
      'ASSIGNED' => [
        action('Reject', Icons.close, _reject, primary: false, color: AppColors.danger),
        action('Accept', Icons.check, () => _run((r) => r.accept(p.id), 'Pickup accepted', 'Not accepted')),
      ],
      'ACCEPTED' => [
        action('Start pickup', Icons.two_wheeler, () => _run((r) => r.start(p.id), 'On the way', 'Not started')),
      ],
      'OUT_FOR_PICKUP' => [
        action('Failed', Icons.report_problem_outlined, _fail, primary: false, color: AppColors.danger),
        action('Collected', Icons.inventory_2_outlined, _collected),
      ],
      'PICKED_UP' when canBook => [action('Book shipment', Icons.add_box_outlined, _book)],
      _ => <Widget>[],
    };
    return AccentCard(
      color: statusStyle(p.status).color,
      icon: Icons.inventory_2_outlined,
      title: p.number,
      trailing: StatusBadge(p.status),
      children: [
        Text(p.contactName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 4),
        _Line(Icons.place_outlined, p.fullAddress, onTap: p.isOpen ? () => openInMaps(p.fullAddress) : null),
        _Line(Icons.phone_outlined, p.contactMobile, onTap: p.isOpen ? () => callNumber(p.contactMobile) : null),
        _Line(
          Icons.scale_outlined,
          p.actualParcels != null
              ? 'Collected ${p.actualParcels} parcel(s), ${Fmt.kg(p.actualWeightKg)}'
              : 'Expected ${p.expectedParcels} parcel(s)${p.expectedWeightKg == null ? '' : ', ${Fmt.kg(p.expectedWeightKg)}'}',
        ),
        if (p.preferredDate != null || p.preferredSlot != null)
          _Line(
            Icons.event_outlined,
            [if (p.preferredDate != null) Fmt.date(p.preferredDate), ?p.preferredSlot].join(' · '),
          ),
        if (p.remarks != null) _Line(Icons.notes, p.remarks!),
        if (p.shipmentNo != null) _Line(Icons.receipt_long_outlined, 'Booked as ${p.shipmentNo}'),
        if (p.failReason != null && p.status == 'FAILED')
          _Line(Icons.info_outline, p.failReason!, color: AppColors.danger),
        if (actions.isNotEmpty) ...[const SizedBox(height: 10), Row(spacing: 10, children: actions)],
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.text, {this.onTap, this.color});

  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? (onTap == null ? AppColors.textSecondary : AppColors.primary);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: c),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text, style: TextStyle(fontSize: 13, color: color ?? AppColors.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _askReason(BuildContext context, String title, String hint, String confirm) => showDialog<String>(
  context: context,
  builder: (_) => _ReasonDialog(title: title, hint: hint, confirm: confirm),
);

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, required this.hint, required this.confirm});

  final String title;
  final String hint;
  final String confirm;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _reason,
      autofocus: true,
      maxLength: 255,
      maxLines: 2,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(labelText: 'Reason', hintText: widget.hint),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
        onPressed: _reason.text.trim().isEmpty ? null : () => Navigator.pop(context, _reason.text.trim()),
        child: Text(widget.confirm),
      ),
    ],
  );
}

class _CollectedDialog extends StatefulWidget {
  const _CollectedDialog({required this.pickup});

  final Pickup pickup;

  @override
  State<_CollectedDialog> createState() => _CollectedDialogState();
}

class _CollectedDialogState extends State<_CollectedDialog> {
  final _form = GlobalKey<FormState>();
  late final _parcels = TextEditingController(text: '${widget.pickup.expectedParcels}');
  late final _weight = TextEditingController(text: widget.pickup.expectedWeightKg?.toString() ?? '');

  @override
  void dispose() {
    _parcels.dispose();
    _weight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Goods collected'),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _parcels,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Parcels collected'),
            validator: (v) => (int.tryParse(v ?? '') ?? 0) >= 1 ? null : 'At least 1',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _weight,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
            decoration: const InputDecoration(labelText: 'Total weight (kg)'),
            validator: (v) => (num.tryParse(v ?? '') ?? 0) > 0 ? null : 'Enter the weight',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          Navigator.pop(context, (parcels: int.parse(_parcels.text), weight: num.parse(_weight.text)));
        },
        child: const Text('Save'),
      ),
    ],
  );
}
