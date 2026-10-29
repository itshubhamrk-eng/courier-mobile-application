import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/ui.dart';
import '../../auth/application/auth_controller.dart';
import '../application/wallet_state.dart';
import '../data/wallet_models.dart';
import '../data/wallet_repository.dart';
import 'wallet_widgets.dart';

const _quick = [500, 1000, 2000, 5000, 10000];

enum _Phase { form, opening, paying, verifying, success, confirming, failed }

/// Recharge the branch wallet through Razorpay, same flow as the web:
/// 1. the server opens a gateway order for the amount (nothing credited),
/// 2. Razorpay checkout takes the payment,
/// 3. the server verifies the signature and credits what the gateway says was paid.
///
/// Step 3 is idempotent, so it is retried on network trouble. If it still cannot be
/// confirmed, the server's 2-minute check (and Razorpay's webhook) credits the wallet
/// anyway; the user is told so and pointed at the recharge report, never asked to pay again.
class WalletRechargePage extends ConsumerStatefulWidget {
  const WalletRechargePage({super.key});

  @override
  ConsumerState<WalletRechargePage> createState() => _WalletRechargePageState();
}

class _WalletRechargePageState extends ConsumerState<WalletRechargePage> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _remarks = TextEditingController();
  _Phase _phase = _Phase.form;
  String? _message;
  WalletTxn? _settled;
  CheckoutPaid? _paid;

  bool get _busy => _phase == _Phase.opening || _phase == _Phase.paying || _phase == _Phase.verifying;

  @override
  void dispose() {
    _amount.dispose();
    _remarks.dispose();
    super.dispose();
  }

  void _add(int n) {
    final next = (num.tryParse(_amount.text) ?? 0) + n;
    if (next > 999999) return;
    setState(() => _amount.text = next.toInt().toString());
  }

  Future<void> _pay(Wallet wallet) async {
    if (_busy || !_form.currentState!.validate()) return;
    final amount = num.parse(_amount.text);
    final branchId = ref.read(walletBranchProvider);
    final repo = ref.read(walletRepositoryProvider);
    final session = ref.read(sessionProvider);

    setState(() => _phase = _Phase.opening);
    final RechargeOrder order;
    try {
      order = await repo.openRechargeOrder(
        branchId: branchId,
        amount: amount,
        remarks: _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
      );
    } on ApiException catch (e) {
      // e.g. 422 "no payment gateway configured", wallet suspended, amount limits.
      return _fail(e.message.isEmpty ? 'Could not start the recharge.' : e.message);
    }
    if (order.publicKey.isEmpty || order.orderId.isEmpty) {
      return _fail('The payment gateway is not set up for this company. Ask your administrator.');
    }
    if (!mounted) return;

    setState(() => _phase = _Phase.paying);
    final result = await ref
        .read(paymentCheckoutProvider)
        .pay(
          order,
          name: session?.companyName ?? 'Courier Pro',
          description: 'Wallet recharge · ${order.walletNumber}',
          email: session?.email,
        );
    if (!mounted) return;

    switch (result) {
      case CheckoutCancelled():
        _fail('Payment was cancelled.');
      case CheckoutFailed(:final message):
        _fail(
          '$message\nIf money was deducted, it will be credited automatically after the gateway confirms it, '
          'or refunded by Razorpay.',
        );
      case CheckoutExternalWallet(:final wallet):
        setState(() {
          _phase = _Phase.confirming;
          _message =
              'Payment continues in ${wallet ?? 'the wallet app'}. Once it is confirmed the wallet is credited '
              'automatically. Check the Recharge report for its status.';
        });
      case CheckoutPaid():
        _paid = result;
        await _verify();
    }
  }

  /// Settles a paid order. Retries network failures (safe: idempotent on payment id).
  Future<void> _verify() async {
    final paid = _paid;
    if (paid == null) return;
    setState(() => _phase = _Phase.verifying);
    final repo = ref.read(walletRepositoryProvider);
    final branchId = ref.read(walletBranchProvider);
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final t = await repo.completeRecharge(
          branchId: branchId,
          orderId: paid.orderId,
          paymentId: paid.paymentId,
          signature: paid.signature,
        );
        if (!mounted) return;
        refreshWallet(ref);
        setState(() {
          _settled = t;
          _phase = _Phase.success;
        });
        showSuccess(context, 'Wallet recharged.');
        return;
      } on ApiException catch (e) {
        final retryable =
            e.kind == ApiErrorKind.network || e.kind == ApiErrorKind.timeout || e.kind == ApiErrorKind.server;
        if (!retryable) {
          // The server refused it (e.g. signature mismatch). Its own check still runs
          // against the gateway, so a genuine payment is not lost.
          return _confirming(
            '${e.message}\nYour payment reference is ${paid.paymentId}. If the amount was deducted, the wallet '
            'is credited automatically once the gateway confirms it.',
          );
        }
        if (attempt < 2) await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
    if (mounted) {
      _confirming(
        'Payment received by Razorpay (${paid.paymentId}), but we could not reach the server to confirm it. '
        'Your wallet will be credited automatically within a few minutes. Do not pay again.',
      );
    }
  }

  void _confirming(String message) => setState(() {
    _phase = _Phase.confirming;
    _message = message;
  });

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.failed;
      _message = message;
    });
  }

  void _reset() => setState(() {
    _phase = _Phase.form;
    _message = null;
    _settled = null;
    _paid = null;
    _amount.clear();
    _remarks.clear();
  });

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(walletAccessProvider);
    final wallet = ref.watch(walletProvider);
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) showSuccess(context, 'Please wait, the payment is being processed.');
      },
      child: Scaffold(
        appBar: AppBar(flexibleSpace: const AppBarGradient(), title: const Text('Recharge Wallet')),
        body: !access.recharge
            ? const EmptyView(message: 'Your role cannot recharge the wallet.', icon: Icons.lock_outline)
            : switch (wallet) {
                AsyncData(:final value) => _content(value),
                AsyncError(:final error) => ErrorView(error: error, onRetry: () => ref.invalidate(walletProvider)),
                _ => const LoadingView(message: 'Loading wallet…'),
              },
      ),
    );
  }

  Widget _content(Wallet w) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      HeroCard(
        colors: const [AppColors.green, AppColors.teal],
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    w.branchName ?? 'Branch wallet',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                  Text(w.walletNumber, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 12),
                  const Text('AVAILABLE', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1)),
                  Text(
                    Fmt.money(w.available),
                    style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _HeroMini('Total', Fmt.money(w.total)),
                const SizedBox(height: 6),
                _HeroMini('Hold', Fmt.money(w.hold)),
              ],
            ),
          ],
        ),
      ),
      _Steps(phase: _phase),
      const SizedBox(height: 14),
      switch (_phase) {
        _Phase.success => _successCard(w),
        _Phase.failed => _resultCard(
          icon: Icons.error_outline,
          color: AppColors.danger,
          title: 'Recharge not completed',
          message: _message ?? '',
          actions: [
            FilledButton.icon(onPressed: _reset, icon: const Icon(Icons.refresh), label: const Text('Try again')),
          ],
        ),
        _Phase.confirming => _resultCard(
          icon: Icons.hourglass_top,
          color: AppColors.warning,
          title: 'Confirming payment',
          message: _message ?? '',
          actions: [
            if (_paid != null)
              FilledButton.icon(onPressed: _verify, icon: const Icon(Icons.sync), label: const Text('Check again')),
            OutlinedButton.icon(
              onPressed: () => context.pushReplacement('/wallet/recharge-report'),
              icon: const Icon(Icons.assessment_outlined),
              label: const Text('Recharge report'),
            ),
          ],
        ),
        _ => _formCard(w),
      },
    ],
  );

  Widget _formCard(Wallet w) => SectionCard(
    title: 'Amount',
    icon: Icons.currency_rupee,
    color: AppColors.green,
    children: [
      Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AmountField(controller: _amount, onChanged: (_) => setState(() {})),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final q in _quick)
                  ActionChip(
                    label: Text('+ ${Fmt.money(q).replaceAll('.00', '')}'),
                    labelStyle: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w700),
                    backgroundColor: AppColors.green.withValues(alpha: 0.1),
                    onPressed: _busy ? null : () => _add(q),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _remarks,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'Remarks (optional)'),
            ),
            const SizedBox(height: 4),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.green),
              onPressed: _busy ? null : () => _pay(w),
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Icon(Icons.lock_outline),
              label: Text(switch (_phase) {
                _Phase.opening => 'Starting payment…',
                _Phase.paying => 'Waiting for payment…',
                _Phase.verifying => 'Confirming payment…',
                _ => 'Pay ${Fmt.money(num.tryParse(_amount.text) ?? 0)}',
              }),
            ),
            const SizedBox(height: 8),
            const Text(
              'Secured by Razorpay. UPI, cards, net banking and wallets are accepted.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _successCard(Wallet w) {
    final t = _settled!;
    return SectionCard(
      title: 'Recharge successful',
      icon: Icons.check_circle_outline,
      color: AppColors.success,
      children: [
        Center(
          child: Text(
            '+${Fmt.money(t.amount)}',
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.success),
          ),
        ),
        const SizedBox(height: 8),
        InfoRow('Transaction no', t.transactionNo),
        InfoRow('Payment reference', t.paymentReference),
        InfoRow('Balance after', Fmt.money(t.balanceAfter)),
        InfoRow('Date & time', Fmt.dateTime(t.createdAt)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => openReceipt(context, ref, t, wallet: w),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Receipt'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.add_card),
                label: const Text('New recharge'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _resultCard({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
    required List<Widget> actions,
  }) => SectionCard(
    title: title,
    icon: icon,
    color: color,
    children: [
      Text(message, style: const TextStyle(height: 1.4)),
      const SizedBox(height: 14),
      for (final a in actions) Padding(padding: const EdgeInsets.only(bottom: 8), child: a),
    ],
  );
}

class _HeroMini extends StatelessWidget {
  const _HeroMini(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      Text(
        value,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    ],
  );
}

/// Enter amount → authorise payment → wallet credited.
class _Steps extends StatelessWidget {
  const _Steps({required this.phase});

  final _Phase phase;

  @override
  Widget build(BuildContext context) {
    final current = switch (phase) {
      _Phase.form || _Phase.failed => 0,
      _Phase.opening || _Phase.paying => 1,
      _Phase.verifying || _Phase.confirming => 2,
      _Phase.success => 3,
    };
    const labels = ['Enter amount', 'Authorise payment', 'Wallet credited'];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: i < current
                      ? AppColors.success
                      : (i == current ? AppColors.indigo : AppColors.field),
                  child: i < current
                      ? const Icon(Icons.check, size: 15, color: Colors.white)
                      : Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: i == current ? Colors.white : AppColors.textSecondary,
                          ),
                        ),
                ),
                const SizedBox(height: 4),
                Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
                    color: i <= current ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
