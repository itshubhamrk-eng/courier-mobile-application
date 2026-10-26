import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/scanner_page.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../../shipments/data/shipment_repository.dart';
import '../../shipments/presentation/shipment_detail_page.dart';
import '../../../core/widgets/ui.dart';

class TrackPage extends ConsumerStatefulWidget {
  const TrackPage({super.key, this.initialAwb});

  final String? initialAwb;

  @override
  ConsumerState<TrackPage> createState() => _TrackPageState();
}

class _TrackPageState extends ConsumerState<TrackPage> {
  final _awb = TextEditingController();
  ShipmentView? _view;
  Object? _error;
  bool _loading = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialAwb != null) {
      _awb.text = widget.initialAwb!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _awb.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final awb = _awb.text.trim();
    if (awb.isEmpty) return;
    FocusScope.of(context).unfocus();
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(shipmentRepositoryProvider);
      final withCharges = ref.read(sessionProvider)?.can(Permissions.shipmentCreate) ?? false;
      final view = await repo.view(await repo.byAwb(awb), withCharges: withCharges);
      if (mounted && request == _request) setState(() => _view = view);
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _view = null;
          _error = e is ApiException && e.kind == ApiErrorKind.notFound
              ? ApiException(ApiErrorKind.notFound, 'No shipment found for AWB $awb.')
              : e;
        });
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _scan() async {
    final value = await ScannerPage.scan(context);
    if (value == null || !mounted) return;
    _awb.text = value;
    await _search();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(flexibleSpace: const AppBarGradient(), title: const Text('Track Shipment')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _awb,
            textInputAction: TextInputAction.search,
            textCapitalization: TextCapitalization.characters,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'AWB or shipment number',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(tooltip: 'Scan', icon: const Icon(Icons.qr_code_scanner), onPressed: _scan),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const LoadingView(message: 'Looking up shipment…')
              : _error != null
              ? ErrorView(error: _error!, onRetry: _search)
              : _view != null
              ? RefreshIndicator(
                  onRefresh: _search,
                  child: ShipmentViewBody(view: _view!),
                )
              : const EmptyView(icon: Icons.qr_code_2, message: 'Type or scan an AWB to see where the shipment is.'),
        ),
      ],
    ),
  );
}
