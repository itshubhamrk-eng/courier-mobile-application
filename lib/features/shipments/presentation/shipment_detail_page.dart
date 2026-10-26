import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/movement_timeline.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/ui.dart';
import '../../auth/application/auth_controller.dart';
import '../../masters/data/masters.dart';
import '../data/shipment_repository.dart';
import '../../documents/document_page.dart';
import '../../documents/document_service.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_exception.dart';
import '../data/shipment_models.dart';

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
        flexibleSpace: const AppBarGradient(),
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
    final canSheets = ref.watch(sessionProvider)?.can(Permissions.manifestRead) ?? false;
    String? option(List<Option> list, String? id) => list.where((o) => o.id == id).firstOrNull?.label;

    final timeline = _timeline(view, branch);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
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
                        const Text('AWB', style: TextStyle(fontSize: 12, color: Colors.white70, letterSpacing: 1)),
                        SelectableText(
                          s.trackingNumber,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                        Text('Shipment ${s.shipmentNumber}', style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                  _HeroStatus(s.status),
                ],
              ),
              const SizedBox(height: 18),
              RouteStrip(
                from: s.s('fromCity') ?? branch(s.bookingBranchId) ?? '–',
                fromSub: s.s('pickupPincode'),
                to: s.s('toCity') ?? branch(s.deliveryBranchId) ?? '–',
                toSub: s.s('deliveryPincode'),
                onDark: true,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _HeroFact(Icons.event_outlined, 'Booked', Fmt.date(s.t('bookingDate'))),
                  _HeroFact(Icons.flag_outlined, 'Expected', Fmt.date(s.t('expectedDeliveryDate'))),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            children: [
              Expanded(
                child: MetricTile(
                  icon: Icons.inventory_2_outlined,
                  value: '${s.n('numberOfPackages') ?? '–'}',
                  label: 'Packages',
                  color: AppColors.indigo,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricTile(
                  icon: Icons.scale_outlined,
                  value: Fmt.kg(s.n('chargeableWeight')),
                  label: 'Chargeable',
                  color: AppColors.teal,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricTile(
                  icon: Icons.currency_rupee,
                  value: Fmt.money(view.charges?.netAmount ?? s.n('netAmount')),
                  label: 'Net amount',
                  color: AppColors.orange,
                ),
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Branches',
          icon: Icons.store_mall_directory_outlined,
          color: AppColors.cyan,
          children: [
            InfoRow('Booked at', branch(s.bookingBranchId)),
            InfoRow('Current location', branch(s.currentLocationId)),
            InfoRow('Delivery branch', branch(s.deliveryBranchId)),
          ],
        ),
        SectionCard(
          title: 'Sender',
          icon: Icons.north_east,
          color: AppColors.indigo,
          children: [
            InfoRow('Name', s.s('senderName')),
            InfoRow('Contact', s.s('senderContact')),
            InfoRow('Address', s.s('senderAddress')),
          ],
        ),
        SectionCard(
          title: 'Receiver',
          icon: Icons.south_west,
          color: AppColors.green,
          children: [
            InfoRow('Name', s.s('receiverName')),
            InfoRow('Contact', s.s('receiverContact')),
            InfoRow('Address', s.s('receiverAddress')),
            InfoRow('Delivery', s.s('deliveryType') == 'OFFICE' ? 'Office collection' : 'Door delivery'),
          ],
        ),
        SectionCard(
          title: 'Package',
          icon: Icons.inventory_2_outlined,
          color: AppColors.purple,
          children: [
            InfoRow('Actual weight', Fmt.kg(s.n('actualWeight'))),
            InfoRow('Volumetric weight', Fmt.kg(s.n('volumetricWeight'))),
            InfoRow('Chargeable weight', Fmt.kg(s.n('chargeableWeight'))),
            InfoRow('Declared value', Fmt.money(s.n('declaredValue'))),
            InfoRow('Service', option(serviceTypes, s.serviceTypeId)),
            InfoRow('Payment', option(paymentModes, s.paymentModeId)),
            for (final i in s.items)
              InfoRow(
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
          SectionCard(
            title: 'Charges',
            icon: Icons.receipt_long_outlined,
            color: AppColors.orange,
            children: [
              for (final l in [...c.lines, ...c.adjustments]) InfoRow(l.label, Fmt.money(l.amount)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: InfoRow('Net amount', Fmt.money(c.netAmount), bold: true),
              ),
            ],
          ),
        if (view.sheets.isNotEmpty || view.deliveryRun?.drsNumber != null)
          SectionCard(
            title: 'Loading sheet, THC and DRS',
            icon: Icons.local_shipping_outlined,
            color: AppColors.teal,
            children: [
              for (final sh in view.sheets)
                _LinkTile(
                  icon: sh.isOpen ? Icons.list_alt_outlined : Icons.local_shipping_outlined,
                  // A dispatched loading sheet is the THC (same number, as on the web).
                  title: '${sh.isOpen ? 'Loading sheet' : 'THC'} ${sh.number}',
                  subtitle: [
                    statusStyle(sh.status).label,
                    '${branch(sh.bookingBranchId) ?? '–'} → ${branch(sh.deliveryBranchId) ?? '–'}',
                    Fmt.dateTime(sh.dispatchedAt ?? sh.createdAt),
                  ].join(' · '),
                  onTap: canSheets ? () => context.push('/loading-sheets/${sh.id}') : null,
                ),
              if (view.deliveryRun case final d? when d.drsNumber != null)
                _LinkTile(
                  icon: Icons.delivery_dining_outlined,
                  title: 'DRS ${d.drsNumber}',
                  subtitle: [
                    ?d.status,
                    'Assigned ${Fmt.dateTime(d.assignedAt)}',
                    if (d.deliveredAt != null) 'Delivered ${Fmt.dateTime(d.deliveredAt)}',
                    if (d.receiverName != null) 'Received by ${d.receiverName}',
                    ?d.remarks,
                  ].join(' · '),
                  onTap: d.deliveryUserId != null && d.deliveryBranchId != null && d.assignedAt != null
                      ? () => context.push(
                          Uri(
                            path: '/drs/run',
                            queryParameters: {
                              'user': d.deliveryUserId!,
                              'branch': d.deliveryBranchId!,
                              'date': Fmt.apiDate(d.assignedAt!.toUtc()),
                            },
                          ).toString(),
                        )
                      : null,
                ),
            ],
          ),
        if (view.files.isNotEmpty)
          SectionCard(
            title: 'Documents',
            icon: Icons.folder_open_outlined,
            color: AppColors.cyan,
            children: [
              for (final f in view.files)
                _LinkTile(
                  icon: f.isImage ? Icons.image_outlined : Icons.description_outlined,
                  title: f.label,
                  subtitle: [?f.remarks, if (f.addedAt != null) Fmt.dateTime(f.addedAt)].join(' · '),
                  onTap: () => openShipmentFile(context, ref, f),
                ),
            ],
          ),
        if (view.pod case final p?)
          SectionCard(
            title: 'Proof of delivery',
            icon: Icons.verified_outlined,
            color: AppColors.green,
            children: [
              InfoRow('Status', [p.entryStatus, p.verificationStatus].nonNulls.join(' · ')),
              InfoRow('Delivery date', Fmt.date(p.deliveryDate)),
              if (p.remark != null) InfoRow('Remark', p.remark),
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
        if (view.attempts.isNotEmpty)
          SectionCard(
            title: 'Delivery attempts',
            icon: Icons.event_repeat,
            color: AppColors.warning,
            children: [
              for (final a in view.attempts)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    a.returnedToOrigin ? Icons.keyboard_return : Icons.event_repeat,
                    color: a.returnedToOrigin ? AppColors.danger : AppColors.warning,
                  ),
                  title: Text(
                    'Attempt ${a.attemptNo} of ${a.maxAttempts}: ${a.reasonLabel}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    [
                      Fmt.dateTime(a.attemptedAt),
                      ?a.drsNumber,
                      if (a.returnedToOrigin) 'Returned to origin' else 'Back for next DRS',
                      ?a.remarks,
                    ].join(' · '),
                  ),
                ),
            ],
          ),
        SectionCard(
          title: 'Movement',
          icon: Icons.timeline,
          color: AppColors.primary,
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

class _HeroStatus extends StatelessWidget {
  const _HeroStatus(this.status);

  final String status;

  @override
  Widget build(BuildContext context) {
    final style = statusStyle(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Text(
        style.label,
        style: TextStyle(color: style.color, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

class _HeroFact extends StatelessWidget {
  const _HeroFact(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Row(
      children: [
        Icon(icon, size: 18, color: Colors.white70),
        const SizedBox(width: 6),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label  ',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                TextSpan(
                  text: value,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.icon, required this.title, required this.subtitle, this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    leading: IconBadge(icon, size: 34),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: subtitle.isEmpty ? null : Text(subtitle),
    trailing: onTap == null ? null : const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

/// Opens a shipment file: images in the app, other files (PDF, ...) in the phone's viewer.
Future<void> openShipmentFile(BuildContext context, WidgetRef ref, ShipmentFile f) async {
  final sameServer = f.url.startsWith('/');
  final url = sameServer ? '${Env.apiBaseUrl}${f.url}' : f.url;
  if (f.isImage) {
    final token = sameServer ? ref.read(sessionProvider)?.accessToken : null;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(flexibleSpace: const AppBarGradient(), title: Text(f.label)),
          backgroundColor: Colors.black,
          body: InteractiveViewer(
            child: Center(
              child: Image.network(
                url,
                headers: token == null ? null : {'Authorization': 'Bearer $token'},
                errorBuilder: (_, _, _) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'This file could not be loaded. It may need to be opened from the web app.',
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    showFailure(context, const ApiException(ApiErrorKind.unknown, 'No app on this phone can open this file.'));
  }
}
