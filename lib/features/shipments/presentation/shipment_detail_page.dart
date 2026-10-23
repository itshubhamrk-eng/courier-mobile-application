import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/movement_timeline.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_controller.dart';
import '../../masters/data/masters.dart';
import '../data/shipment_repository.dart';
import '../../documents/document_page.dart';
import '../../documents/document_service.dart';

class ShipmentDetailPage extends ConsumerWidget {
  const ShipmentDetailPage({super.key, required this.shipmentId});

  final String shipmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final withCharges = ref.watch(sessionProvider)?.can(Permissions.shipmentCreate) ?? false;
    final key = (id: shipmentId, withCharges: withCharges);
    final view = ref.watch(shipmentViewByIdProvider(key));
    Future<void> refresh() => ref.refresh(shipmentViewByIdProvider(key).future);

    final canPod = ref.watch(sessionProvider)?.can(Permissions.deliveryUpload) ?? false;
    final outForDelivery = view.value?.shipment.status == 'OUT_FOR_DELIVERY';
    return Scaffold(
      appBar: AppBar(
        title: Text(view.value?.shipment.trackingNumber ?? 'Shipment'),
        actions: [
          if (view.value case final v?)
            PopupMenuButton<String>(
              tooltip: 'Print',
              icon: const Icon(Icons.print_outlined),
              onSelected: (doc) => doc == 'label'
                  ? openDocument(
                      context,
                      title: 'Labels ${v.shipment.trackingNumber}',
                      fileName: 'label-${v.shipment.trackingNumber}.pdf',
                      build: () => ref.read(documentServiceProvider).label(shipmentId),
                    )
                  : openDocument(
                      context,
                      title: 'POD ${v.shipment.trackingNumber}',
                      fileName: 'pod-${v.shipment.trackingNumber}.pdf',
                      build: () => ref.read(documentServiceProvider).pod(shipmentId),
                    ),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'label', child: Text('Shipment labels')),
                if (v.shipment.status == 'DELIVERED')
                  const PopupMenuItem(value: 'pod', child: Text('Proof of delivery')),
              ],
            ),
        ],
      ),
      floatingActionButton: canPod && outForDelivery
          ? FloatingActionButton.extended(
              onPressed: () async {
                await context.push('/pod?shipmentId=$shipmentId');
                ref.invalidate(shipmentViewByIdProvider(key));
              },
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('POD'),
            )
          : null,
      body: switch (view) {
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: refresh,
          child: ShipmentViewBody(view: value),
        ),
        AsyncError(:final error) => ErrorView(error: error, onRetry: refresh),
        _ => const LoadingView(),
      },
    );
  }
}

/// Shipment details, charges, POD and movement timeline. Shared by the
/// detail screen and Track Shipment.
class ShipmentViewBody extends ConsumerWidget {
  const ShipmentViewBody({super.key, required this.view});

  final ShipmentView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = view.shipment;
    final branches = ref.watch(branchNamesProvider).value ?? const {};
    final paymentModes = ref.watch(paymentModesProvider).value ?? const [];
    final serviceTypes = ref.watch(serviceTypesProvider).value ?? const [];
    String? branch(String? id) => id == null ? null : branches[id]?.label;
    String? option(List<Option> list, String? id) => list.where((o) => o.id == id).firstOrNull?.label;

    final timeline = _timeline(view, branch);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _Card(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('AWB', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      SelectableText(
                        s.trackingNumber,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                      Text('Shipment ${s.shipmentNumber}', style: const TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                StatusBadge(s.status),
              ],
            ),
            const Divider(height: 24),
            _Row('From', [s.s('fromCity'), s.s('pickupPincode')].nonNulls.join(' · ')),
            _Row('To', [s.s('toCity'), s.s('deliveryPincode')].nonNulls.join(' · ')),
            _Row('Booked at', branch(s.bookingBranchId)),
            _Row('Current location', branch(s.currentLocationId)),
            _Row('Delivery branch', branch(s.deliveryBranchId)),
            _Row('Booking date', Fmt.date(s.t('bookingDate'))),
            _Row('Expected delivery', Fmt.date(s.t('expectedDeliveryDate'))),
          ],
        ),
        _Card(
          title: 'Sender',
          children: [
            _Row('Name', s.s('senderName')),
            _Row('Contact', s.s('senderContact')),
            _Row('Address', s.s('senderAddress')),
          ],
        ),
        _Card(
          title: 'Receiver',
          children: [
            _Row('Name', s.s('receiverName')),
            _Row('Contact', s.s('receiverContact')),
            _Row('Address', s.s('receiverAddress')),
            _Row('Delivery', s.s('deliveryType') == 'OFFICE' ? 'Office collection' : 'Door delivery'),
          ],
        ),
        _Card(
          title: 'Package',
          children: [
            _Row('Packages', s.n('numberOfPackages')?.toString()),
            _Row('Actual weight', Fmt.kg(s.n('actualWeight'))),
            _Row('Volumetric weight', Fmt.kg(s.n('volumetricWeight'))),
            _Row('Chargeable weight', Fmt.kg(s.n('chargeableWeight'))),
            _Row('Declared value', Fmt.money(s.n('declaredValue'))),
            _Row('Service', option(serviceTypes, s.serviceTypeId)),
            _Row('Payment', option(paymentModes, s.paymentModeId)),
            for (final i in s.items)
              _Row(
                i.name ?? 'Item',
                [
                  '${i.quantity ?? 1} pc',
                  Fmt.kg(i.weight),
                  if (i.length != null) '${i.length}×${i.width}×${i.height} cm',
                ].join(' · '),
              ),
          ],
        ),
        if (view.charges case final c?)
          _Card(
            title: 'Charges',
            children: [
              for (final l in c.lines) _Row(l.label, Fmt.money(l.amount)),
              const Divider(),
              _Row('Net amount', Fmt.money(c.netAmount), bold: true),
            ],
          ),
        if (view.deliveryRun case final d?)
          _Card(
            title: 'Delivery run',
            children: [
              _Row('DRS', d.drsNumber),
              _Row('Status', d.status),
              _Row('Assigned', Fmt.dateTime(d.assignedAt)),
              if (d.deliveredAt != null) _Row('Delivered', Fmt.dateTime(d.deliveredAt)),
              if (d.receiverName != null) _Row('Received by', d.receiverName),
              if (d.remarks != null) _Row('Remarks', d.remarks),
            ],
          ),
        if (view.pod case final p?)
          _Card(
            title: 'Proof of delivery',
            children: [
              _Row('Status', [p.entryStatus, p.verificationStatus].nonNulls.join(' · ')),
              _Row('Delivery date', Fmt.date(p.deliveryDate)),
              if (p.remark != null) _Row('Remark', p.remark),
              if (p.photoUrl != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      p.photoUrl!,
                      height: 200,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Text('POD image could not be loaded.'),
                    ),
                  ),
                ),
            ],
          ),
        _Card(
          title: 'Movement',
          children: [
            if (timeline.isEmpty) const Text('No movement recorded yet.') else MovementTimeline(entries: timeline),
          ],
        ),
      ],
    );
  }

  /// Status history and hub exceptions, merged newest first. Only recorded events.
  static List<TimelineEntry> _timeline(ShipmentView v, String? Function(String?) branch) {
    final entries = [
      for (final h in v.history)
        TimelineEntry(status: h.status, at: h.at, location: branch(h.branchId), remarks: h.remarks),
      for (final e in v.exceptions) ...[
        TimelineEntry(status: e.type, at: e.raisedAt, location: branch(e.hubBranchId), remarks: e.remarks),
        if (e.resolvedAt != null)
          TimelineEntry(
            status: 'RESOLVED',
            at: e.resolvedAt!,
            location: branch(e.hubBranchId),
            remarks: [e.type.replaceAll('_', ' ').toLowerCase(), e.resolution].nonNulls.join(': '),
          ),
      ],
    ]..sort((a, b) => b.at.compareTo(a.at));
    return entries;
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children, this.title});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(title!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 8),
            ],
            ...children,
          ],
        ),
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.bold = false});

  final String label;
  final String? value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final v = value;
    if (v == null || v.isEmpty || v == '–') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
