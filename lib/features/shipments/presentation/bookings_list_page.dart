import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/scanner_page.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/ui.dart';
import '../../auth/application/auth_controller.dart';
import '../data/shipment_models.dart';
import '../data/shipment_repository.dart';
import '../../shell/branch_header.dart';

/// Shipments booked at the signed-in user's branch, newest first.
class BookingsListPage extends ConsumerStatefulWidget {
  const BookingsListPage({super.key});

  @override
  ConsumerState<BookingsListPage> createState() => _BookingsListPageState();
}

class _BookingsListPageState extends ConsumerState<BookingsListPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  final _items = <ShipmentSummary>[];
  int _page = 0;
  bool _hasNext = true;
  bool _loading = false;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _loadMore();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    _generation++;
    setState(() {
      _items.clear();
      _page = 0;
      _hasNext = true;
      _error = null;
      _loading = false;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasNext) return;
    final branchId = ref.read(sessionProvider)?.operatingBranchId;
    if (branchId == null) return;
    final generation = _generation;
    setState(() => _loading = true);
    try {
      final page = await ref
          .read(shipmentRepositoryProvider)
          .list(bookingBranchId: branchId, search: _search.text.trim(), page: _page);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(page.content);
        _page++;
        _hasNext = page.hasNext;
      });
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e);
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _reload);
  }

  Future<void> _scan() async {
    final value = await ScannerPage.scan(context);
    if (value == null || !mounted) return;
    _search.text = value;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final canBook = ref.watch(sessionProvider)?.can(Permissions.shipmentCreate) ?? false;
    return Scaffold(
      appBar: sectionBar('Shipment Search'),
      floatingActionButton: canBook
          ? FloatingActionButton.extended(
              onPressed: () async {
                await context.push('/bookings/new');
                if (mounted) await _reload();
              },
              icon: const Icon(Icons.add),
              label: const Text('Book'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search AWB, shipment no., name or phone',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(tooltip: 'Scan', icon: const Icon(Icons.qr_code_scanner), onPressed: _scan),
              ),
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_items.isEmpty && _loading) return const LoadingView();
    if (_items.isEmpty && _error != null) return ErrorView(error: _error!, onRetry: _reload);
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 300,
              child: EmptyView(
                message: _search.text.isEmpty ? 'No bookings at your branch yet.' : 'No shipments match your search.',
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        itemCount: _items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          if (i == _items.length) {
            if (_error != null) {
              return TextButton(onPressed: _loadMore, child: const Text('Could not load more. Tap to retry.'));
            }
            return _hasNext
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : const SizedBox.shrink();
          }
          return ShipmentTile(shipment: _items[i]);
        },
      ),
    );
  }
}

class ShipmentTile extends StatelessWidget {
  const ShipmentTile({super.key, required this.shipment, this.onTap, this.trailing});

  final ShipmentSummary shipment;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final s = shipment;
    final color = statusStyle(s.status).color;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap ?? () => context.push('/shipments/${s.id}'),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.trackingNumber,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                          ),
                          StatusBadge(s.status),
                          ?trailing,
                        ],
                      ),
                      const SizedBox(height: 10),
                      RouteStrip(from: s.fromCity ?? '–', to: s.toCity ?? '–'),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 14,
                        runSpacing: 4,
                        children: [
                          if (s.receiverName != null) _Fact(Icons.person_outline, s.receiverName!),
                          if (s.packages != null) _Fact(Icons.inventory_2_outlined, '${s.packages} pkg'),
                          if (s.chargeableWeight != null) _Fact(Icons.scale_outlined, Fmt.kg(s.chargeableWeight)),
                          _Fact(Icons.event_outlined, Fmt.date(s.bookingDate ?? s.createdDate)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: AppColors.textSecondary),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
    ],
  );
}
