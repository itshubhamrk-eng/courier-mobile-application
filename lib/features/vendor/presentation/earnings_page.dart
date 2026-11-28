import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/ui.dart';
import '../data/vendor_repository.dart';

final _earningsProvider = FutureProvider.autoDispose<List<Earning>>(
  (ref) async => (await ref.watch(vendorRepositoryProvider).earnings()).content,
);
final _statementsProvider = FutureProvider.autoDispose<List<Statement>>(
  (ref) async => (await ref.watch(vendorRepositoryProvider).statements()).content,
);

/// What the vendor has earned per pickup and delivery, and its billing statements
/// (web: Vendor Earnings and Vendor Billing). Read only: the company bills and pays.
class VendorEarningsPage extends ConsumerWidget {
  const VendorEarningsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        flexibleSpace: const AppBarGradient(),
        title: const Text('Earnings & Billing'),
        bottom: const TabBar(
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: 'Earnings'),
            Tab(text: 'Statements'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          _List(
            provider: _earningsProvider,
            empty: 'No earnings yet. You earn for each booked pickup and each delivery with an approved POD.',
            tile: (Earning e) => AccentCard(
              color: e.type == 'PICKUP' ? AppColors.indigo : AppColors.teal,
              icon: e.type == 'PICKUP' ? Icons.inventory_2_outlined : Icons.delivery_dining_outlined,
              title: e.reference,
              trailing: Text(
                Fmt.money(e.total),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.success),
              ),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${e.type == 'PICKUP' ? 'Pickup' : 'Delivery'} · ${Fmt.date(e.earnedOn)}',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ),
                    StatusBadge(e.status),
                  ],
                ),
                if (e.chargeableKg != null)
                  Text(
                    '${Fmt.kg(e.chargeableKg)} × ${Fmt.money(e.ratePerKg)}/kg',
                    style: const TextStyle(fontSize: 13),
                  ),
                if (e.status == 'UNRATED')
                  const Text(
                    'No rate card for this yet; the company will price it.',
                    style: TextStyle(fontSize: 12, color: AppColors.warning),
                  ),
              ],
            ),
          ),
          _List(
            provider: _statementsProvider,
            empty: 'No statements yet. The company bills your earnings for each period.',
            tile: (Statement s) => AccentCard(
              color: statusStyle(s.status).color,
              icon: Icons.receipt_long_outlined,
              title: s.number,
              trailing: StatusBadge(s.status),
              children: [
                Text(
                  '${Fmt.date(s.from)} – ${Fmt.date(s.to)}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                Text('${s.pickups} pickup(s), ${s.deliveries} delivery(ies)', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  'Net payable ${Fmt.money(s.netPayable)}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                if (s.paidOn != null)
                  Text(
                    'Paid ${Fmt.date(s.paidOn)}${s.paymentRef == null ? '' : ' · Ref ${s.paymentRef}'}',
                    style: const TextStyle(color: AppColors.success, fontSize: 13),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _List<T> extends ConsumerWidget {
  const _List({required this.provider, required this.empty, required this.tile});

  final ProviderListenable<AsyncValue<List<T>>> provider;
  final String empty;
  final Widget Function(T item) tile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(provider);
    Future<void> refresh() async {
      ref
        ..invalidate(_earningsProvider)
        ..invalidate(_statementsProvider);
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: switch (value) {
        AsyncData(:final value) when value.isEmpty => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 320,
              child: EmptyView(message: empty, icon: Icons.payments_outlined),
            ),
          ],
        ),
        AsyncData(:final value) => ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: value.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) => tile(value[i]),
        ),
        AsyncError(:final error) => ErrorView(error: error, onRetry: refresh),
        _ => const LoadingView(),
      },
    );
  }
}
