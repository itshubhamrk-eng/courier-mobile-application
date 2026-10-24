import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/format.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/scanner_page.dart';
import '../../../core/widgets/signature_pad.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../drs/presentation/drs_widgets.dart';
import '../../masters/data/masters.dart';
import '../../shipments/data/shipment_models.dart';
import '../../shipments/data/shipment_repository.dart';
import '../data/pod_repository.dart';
import 'failed_delivery.dart';

/// Picks the camera / gallery image. Overridable in tests.
final podImagePickerProvider = Provider<Future<Uint8List?> Function(ImageSource source)>((ref) {
  return (source) async {
    final file = await ImagePicker().pickImage(source: source, imageQuality: 70, maxWidth: 1600);
    return file?.readAsBytes();
  };
});

/// POD: find the shipment, upload proof, then close the delivery on the server.
class PodPage extends ConsumerStatefulWidget {
  const PodPage({super.key, this.shipmentId});

  final String? shipmentId;

  @override
  ConsumerState<PodPage> createState() => _PodPageState();
}

class _PodPageState extends ConsumerState<PodPage> {
  final _awb = TextEditingController();
  final _receiver = TextEditingController();
  final _remarks = TextEditingController();
  final _signature = SignaturePadController();

  ShipmentDetail? _shipment;
  bool _loading = false;
  Object? _error;

  PodVerification? _pod;
  bool _replacing = false;
  Uint8List? _photo;
  double? _progress;
  bool _uploading = false;

  bool _delivering = false;
  ShipmentDetail? _done;

  @override
  void initState() {
    super.initState();
    if (widget.shipmentId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(byId: widget.shipmentId));
    }
  }

  @override
  void dispose() {
    _awb.dispose();
    _receiver.dispose();
    _remarks.dispose();
    _signature.dispose();
    super.dispose();
  }

  Future<void> _load({String? byId, String? awb}) async {
    setState(() {
      _loading = true;
      _error = null;
      _shipment = null;
      _pod = null;
      _photo = null;
      _replacing = false;
      _signature.clear();
    });
    try {
      final repo = ref.read(shipmentRepositoryProvider);
      final s = byId != null ? await repo.byId(byId) : await repo.byAwb(awb!);
      if (s.status != 'OUT_FOR_DELIVERY') {
        throw ApiException(
          ApiErrorKind.validation,
          '${s.trackingNumber} is ${statusStyle(s.status).label.toLowerCase()}. '
          'POD is only for shipments out for delivery.',
        );
      }
      // An earlier POD (e.g. from a lost answer) is reused instead of uploading a duplicate.
      final pod = await ref.read(podRepositoryProvider).latest(s.id);
      if (!mounted) return;
      _receiver.text = s.s('receiverName') ?? '';
      setState(() {
        _shipment = s;
        _pod = pod;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ApiException && e.kind == ApiErrorKind.notFound
              ? ApiException(ApiErrorKind.notFound, 'No shipment found for ${awb ?? byId}.')
              : e,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick(ImageSource source) async {
    final bytes = await ref.read(podImagePickerProvider)(source);
    if (bytes != null && mounted) setState(() => _photo = bytes);
  }

  Future<void> _upload() async {
    final s = _shipment;
    if (s == null || _photo == null || _uploading) return;
    if (_receiver.text.trim().isEmpty) {
      showFailure(context, const ApiException(ApiErrorKind.validation, 'Enter who received the shipment.'));
      return;
    }
    setState(() {
      _uploading = true;
      _progress = 0;
    });
    try {
      final pod = await ref
          .read(podRepositoryProvider)
          .upload(
            shipment: s,
            photo: _photo!,
            signature: await _signature.toPng(),
            receiverName: _receiver.text.trim(),
            onProgress: (p) {
              if (mounted) setState(() => _progress = p);
            },
          );
      if (!mounted) return;
      setState(() {
        _pod = pod;
        _replacing = false;
      });
      showSuccess(context, 'POD uploaded.');
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.outcomeUnknown) {
        // The upload may have landed: check before offering another try.
        final latest = await ref.read(podRepositoryProvider).latest(s.id).catchError((_) => null);
        if (!mounted) return;
        if (latest != null && latest.usable && latest.id != _pod?.id) {
          setState(() {
            _pod = latest;
            _replacing = false;
          });
          showSuccess(context, 'POD uploaded.');
          return;
        }
      }
      showFailure(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _complete() async {
    final s = _shipment;
    if (s == null || _delivering) return;
    final ok = await confirmAction(
      context,
      title: 'Complete delivery?',
      message: '${s.trackingNumber} delivered to ${_receiver.text.trim()}. The server confirms the status.',
      confirmLabel: 'Complete',
    );
    if (!ok || !mounted) return;
    setState(() => _delivering = true);
    try {
      final result = await ref
          .read(podRepositoryProvider)
          .deliver(shipmentId: s.id, receiverName: _receiver.text.trim(), remarks: _remarks.text);
      if (mounted) setState(() => _done = result);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.outcomeUnknown) {
        final fresh = await ref.read(shipmentRepositoryProvider).byId(s.id).catchError((_) => s);
        if (!mounted) return;
        if (fresh.status == 'DELIVERED') {
          setState(() => _done = fresh);
          return;
        }
      }
      showFailure(context, e);
    } finally {
      if (mounted) setState(() => _delivering = false);
    }
  }

  Future<void> _cannotDeliver() async {
    final s = _shipment;
    if (s == null) return;
    final attempt = await recordFailedDelivery(context, ref, shipmentId: s.id, trackingNumber: s.trackingNumber);
    if (attempt == null || !mounted) return;
    // The shipment is no longer out for delivery: nothing left to do here.
    if (widget.shipmentId != null && context.canPop()) {
      context.pop(true);
    } else {
      setState(() {
        _shipment = null;
        _pod = null;
        _photo = null;
        _awb.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done != null) return _DoneView(shipment: _done!);
    return Scaffold(
      appBar: AppBar(title: const Text('Proof of Delivery')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.shipmentId == null) ...[
            TextField(
              controller: _awb,
              textInputAction: TextInputAction.search,
              textCapitalization: TextCapitalization.characters,
              onSubmitted: (v) => v.trim().isEmpty ? null : _load(awb: v.trim()),
              decoration: InputDecoration(
                hintText: 'AWB of the delivered shipment',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Scan',
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: () async {
                    final v = await ScannerPage.scan(context);
                    if (v != null && mounted) {
                      _awb.text = v;
                      await _load(awb: v);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            ErrorView(
              error: _error!,
              onRetry: widget.shipmentId != null ? () => _load(byId: widget.shipmentId) : null,
            )
          else if (_shipment == null)
            const SizedBox(
              height: 260,
              child: EmptyView(
                icon: Icons.photo_camera_outlined,
                message: 'Find the shipment by AWB or scan its label.',
              ),
            )
          else
            ..._shipmentSection(_shipment!),
        ],
      ),
    );
  }

  List<Widget> _shipmentSection(ShipmentDetail s) {
    final modes = ref.watch(paymentModesProvider).value ?? const <Option>[];
    final collect = collectLabel(s.paymentModeId, s.n('netAmount'), modes);
    final podReady = _pod != null && _pod!.usable && !_replacing;

    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(s.trackingNumber, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  StatusBadge(s.status),
                ],
              ),
              const SizedBox(height: 6),
              Text([s.s('receiverName'), s.s('receiverContact')].nonNulls.join(' · ')),
              if (s.s('receiverAddress') != null) Text(s.s('receiverAddress')!),
              if (collect != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    collect,
                    style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _receiver,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Received by', prefixIcon: Icon(Icons.person_outline)),
      ),
      const SizedBox(height: 16),
      if (podReady)
        _ExistingPod(
          pod: _pod!,
          onReplace: () => setState(() {
            _replacing = true;
            _photo = null;
          }),
        )
      else ...[
        if (_pod != null && !_pod!.usable)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Previous POD was rejected${_pod!.reviewRemarks == null ? '' : ': ${_pod!.reviewRemarks}'}. Upload a new photo.',
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        const Text('Delivery photo', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (_photo != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              _photo!,
              height: 220,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Text('Photo could not be shown. Retake it.'),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _uploading ? null : () => _pick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(_photo == null ? 'Take photo' : 'Retake'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _uploading ? null : () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Gallery'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(
              child: Text('Signature (optional)', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            TextButton(onPressed: _signature.clear, child: const Text('Clear')),
          ],
        ),
        SignaturePad(controller: _signature),
        const SizedBox(height: 16),
        if (_progress != null) ...[
          LinearProgressIndicator(value: _progress),
          const SizedBox(height: 4),
          Text('Uploading ${((_progress ?? 0) * 100).round()}%', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
        ],
        FilledButton.icon(
          onPressed: _photo == null || _uploading ? null : _upload,
          icon: const Icon(Icons.cloud_upload_outlined),
          label: Text(_uploading ? 'Uploading…' : 'Upload POD'),
        ),
        if (_replacing)
          TextButton(onPressed: () => setState(() => _replacing = false), child: const Text('Keep the existing POD')),
      ],
      if (podReady) ...[
        const SizedBox(height: 12),
        TextField(
          controller: _remarks,
          decoration: const InputDecoration(labelText: 'Delivery remarks (optional)'),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _delivering ? null : _complete,
          icon: _delivering
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : const Icon(Icons.task_alt),
          label: Text(_delivering ? 'Completing…' : 'Complete delivery'),
        ),
      ],
      const SizedBox(height: 8),
      if (canRecordFailedDelivery(ref))
        TextButton.icon(
          onPressed: _delivering || _uploading ? null : _cannotDeliver,
          icon: const Icon(Icons.report_problem_outlined, color: AppColors.danger),
          label: const Text('Could not deliver?', style: TextStyle(color: AppColors.danger)),
        ),
    ];
  }
}

class _ExistingPod extends StatelessWidget {
  const _ExistingPod({required this.pod, required this.onReplace});

  final PodVerification pod;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) => Card(
    color: AppColors.primaryLight,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_outlined, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pod.status == 'PASS' ? 'POD approved' : 'POD uploaded, waiting for company review',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (pod.photoUrl != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                pod.photoUrl!,
                height: 160,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Text('Photo stored on server.'),
              ),
            ),
          ],
          if (pod.reasons.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final r in pod.reasons) Text('• $r', style: const TextStyle(fontSize: 12)),
          ],
          TextButton(onPressed: onReplace, child: const Text('Upload a different photo')),
        ],
      ),
    ),
  );
}

class _DoneView extends StatelessWidget {
  const _DoneView({required this.shipment});

  final ShipmentDetail shipment;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Proof of Delivery'), automaticallyImplyLeading: false),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Icon(
          shipment.status == 'DELIVERED' ? Icons.check_circle : Icons.info_outline,
          size: 64,
          color: shipment.status == 'DELIVERED' ? AppColors.success : AppColors.warning,
        ),
        const SizedBox(height: 8),
        Text(
          shipment.trackingNumber,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Center(child: StatusBadge(shipment.status)),
        const SizedBox(height: 6),
        Text(
          'Status confirmed by the server${shipment.t('deliveredAt') == null ? '' : ' at ${Fmt.dateTime(shipment.t('deliveredAt'))}'}.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: () => context.pop(), child: const Text('Done')),
        TextButton(
          onPressed: () => context.pushReplacement('/shipments/${shipment.id}'),
          child: const Text('View shipment'),
        ),
      ],
    ),
  );
}
