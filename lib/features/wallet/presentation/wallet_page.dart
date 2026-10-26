import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/ui.dart';
import '../../masters/data/masters.dart';
import '../application/wallet_state.dart';
import '../data/wallet_models.dart';
import 'wallet_widgets.dart';

/// Branch Wallet: balances, commission, actions and recent activity (web: Branch Wallet).
class WalletPage extends ConsumerWidget {
  const WalletPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(walletAccessProvider);
    final summary = ref.watch(walletSummaryProvider);
    final wallet = ref.watch(walletProvider).value;
    Future<void> refresh() async {
      refreshWallet(ref);
      try {
        await ref.read(walletSummaryProvider.future);
      } catch (_) {
        // Shown by the error view.
      }
    }

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const AppBarGradient(),
        title: const Text('Branch Wallet'),
        actions: [IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: () => refreshWallet(ref))],
      ),
      body: !access.view
          ? const EmptyView(message: 'Your role cannot view the branch wallet.', icon: Icons.lock_outline)
          : RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (access.admin) const _BranchPicker(),
                  switch (summary) {
                    AsyncData(:final value) => _Body(summary: value, wallet: wallet),
                    AsyncError(:final error) => ErrorView(error: error, onRetry: () => refreshWallet(ref)),
                    _ => const Padding(
                      padding: EdgeInsets.all(48),
                      child: LoadingView(message: 'Loading wallet…'),
                    ),
                  },
                ],
              ),
            ),
    );
  }
}

class _BranchPicker extends ConsumerWidget {
  const _BranchPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branches = ref.watch(branchDirectoryProvider).value ?? const [];
    final selected = ref.watch(walletBranchProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        key: ValueKey('wallet-branch-$selected-${branches.length}'),
        initialValue: branches.any((b) => b.id == selected) ? selected : null,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Branch', prefixIcon: Icon(Icons.store_outlined)),
        items: [
          for (final b in branches)
            DropdownMenuItem(
              value: b.id,
              child: Text(b.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => ref.read(walletBranchProvider.notifier).select(v),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.summary, required this.wallet});

  final WalletSummary summary;
  final Wallet? wallet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(walletAccessProvider);
    final recent = ref.watch(recentTxnsProvider);
    final s = summary;

    Future<void> manual(bool credit) async {
      final w = wallet;
      if (w == null) return;
      final t = await showManualMoneySheet(context, credit: credit, wallet: w);
      if (t == null || !context.mounted) return;
      refreshWallet(ref);
      showSuccess(context, credit ? 'Wallet credited.' : 'Wallet debited.');
      await showTxnDetail(context, ref, t, wallet: w);
    }

    final actions = <(String, IconData, Color, VoidCallback)>[
      if (access.recharge) ('Recharge', Icons.add_card, AppColors.green, () => context.push('/wallet/recharge')),
      if (access.requestTopup)
        ('Request top-up', Icons.send_outlined, AppColors.indigo, () => context.push('/wallet/topup/new')),
      ('Transactions', Icons.receipt_long_outlined, AppColors.purple, () => context.push('/wallet/transactions')),
      ('Top-up requests', Icons.fact_check_outlined, AppColors.teal, () => context.push('/wallet/topup-requests')),
      if (access.rechargeReport)
        ('Recharge report', Icons.assessment_outlined, AppColors.orange, () => context.push('/wallet/recharge-report')),
      if (access.manualMoney) ('Credit', Icons.add_circle_outline, AppColors.success, () => manual(true)),
      if (access.manualMoney) ('Debit', Icons.remove_circle_outline, AppColors.danger, () => manual(false)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HeroCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.branchName ?? 'Branch wallet',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  _WhitePill(statusLabel(s.status)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [s.walletNumber, ?s.branchCode].join(' · '),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 18),
              const Text('AVAILABLE BALANCE', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  Fmt.money(s.available),
                  style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800),
                ),
              ),
              const Text('Spendable now', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
        if (actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [for (final (label, icon, color, onTap) in actions) _ActionChip(label, icon, color, onTap)],
            ),
          ),
        _Grid(
          children: [
            BalanceTile(
              label: 'Total balance',
              amount: s.total,
              icon: Icons.savings_outlined,
              color: AppColors.info,
              hint: 'Available + hold',
            ),
            BalanceTile(
              label: 'Hold balance',
              amount: s.hold,
              icon: Icons.lock_outline,
              color: AppColors.warning,
              hint: 'Reserved for pending',
            ),
            BalanceTile(
              label: "Today's credit",
              amount: s.todayCredit,
              icon: Icons.trending_up,
              color: AppColors.success,
            ),
            BalanceTile(
              label: "Today's debit",
              amount: s.todayDebit,
              icon: Icons.trending_down,
              color: AppColors.danger,
            ),
            BalanceTile(
              label: 'Month credit',
              amount: s.monthCredit,
              icon: Icons.calendar_month_outlined,
              color: AppColors.teal,
            ),
            BalanceTile(
              label: 'Month debit',
              amount: s.monthDebit,
              icon: Icons.calendar_month_outlined,
              color: AppColors.pink,
            ),
            BalanceTile(
              label: 'Last recharge',
              amount: s.lastRechargeAmount ?? 0,
              icon: Icons.add_card,
              color: AppColors.primary,
              hint: s.lastRechargeAt == null ? 'No recharge yet' : Fmt.date(s.lastRechargeAt),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Commission',
          icon: Icons.paid_outlined,
          color: AppColors.amber,
          children: [
            InfoRow("Today's credit commission", Fmt.money(s.todayCreditCommission)),
            InfoRow('Booking pending (not yet dispatched)', Fmt.money(s.bookingPendingCommission)),
            InfoRow('Delivery pending (To-Pay / COD)', Fmt.money(s.deliveryPendingCommission)),
          ],
        ),
        SectionTitle(
          'Recent transactions',
          icon: Icons.history,
          color: AppColors.purple,
          trailing: TextButton(onPressed: () => context.push('/wallet/transactions'), child: const Text('View all')),
        ),
        const SizedBox(height: 10),
        switch (recent) {
          AsyncData(:final value) when value.isEmpty => const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No transactions yet.', textAlign: TextAlign.center),
          ),
          AsyncData(:final value) => Column(
            children: [
              for (final t in value)
                TxnTile(
                  txn: t,
                  onTap: () => showTxnDetail(context, ref, t, wallet: wallet),
                ),
            ],
          ),
          AsyncError(:final error) => ErrorView(error: error, onRetry: () => ref.invalidate(recentTxnsProvider)),
          _ => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        },
      ],
    );
  }
}

String statusLabel(String s) => prettyToken(s);

class _WhitePill extends StatelessWidget {
  const _WhitePill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
    child: Text(
      text,
      style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700, fontSize: 12),
    ),
  );
}

class _ActionChip extends StatelessWidget {
  const _ActionChip(this.label, this.icon, this.color, this.onTap);

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: color.withValues(alpha: 0.1),
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Two equal columns that wrap.
class _Grid extends StatelessWidget {
  const _Grid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final w = (c.maxWidth - 10) / 2;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [for (final child in children) SizedBox(width: w, child: child)],
      );
    },
  );
}
