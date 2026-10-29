import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/data/session.dart';
import '../data/wallet_models.dart';
import '../data/wallet_repository.dart';

/// Who may do what: the same role and permission rules as the web app's
/// wallet screens (roles any-of, then permissions any-of).
class WalletAccess {
  const WalletAccess(this._s);

  final Session? _s;

  bool _role(Set<String> roles) => _s != null && _s.roles.any(roles.contains);
  bool _perm(String p) => _s?.can(p) ?? false;

  bool get admin => _role(const {'COMPANY_ADMIN'});
  bool get view =>
      _role(const {'SUPER_ADMIN', 'COMPANY_ADMIN', 'BRANCH_MANAGER', 'FINANCE_USER'}) && _perm('WALLET_READ');
  bool get recharge => _role(const {'COMPANY_ADMIN', 'BRANCH_MANAGER', 'FINANCE_USER'}) && _perm('WALLET_RECHARGE');
  bool get requestTopup => _role(const {'BRANCH_MANAGER'});
  bool get manualMoney => admin;
  bool get rechargeReport => _role(const {'COMPANY_ADMIN', 'FINANCE_USER', 'BRANCH_MANAGER'});
}

final walletAccessProvider = Provider((ref) => WalletAccess(ref.watch(sessionProvider)));

/// Which branch's wallet is open. A company admin may pick any branch (defaults to the
/// branch they operate from); everyone else always sees their own (null = own).
class WalletBranch extends Notifier<String?> {
  @override
  String? build() {
    final s = ref.watch(sessionProvider);
    return ref.watch(walletAccessProvider).admin ? s?.operatingBranchId : null;
  }

  void select(String? branchId) => state = branchId;
}

final walletBranchProvider = NotifierProvider<WalletBranch, String?>(WalletBranch.new);

final walletProvider = FutureProvider.autoDispose<Wallet>(
  (ref) => ref.watch(walletRepositoryProvider).wallet(ref.watch(walletBranchProvider)),
);

final walletSummaryProvider = FutureProvider.autoDispose<WalletSummary>(
  (ref) => ref.watch(walletRepositoryProvider).summary(ref.watch(walletBranchProvider)),
);

final recentTxnsProvider = FutureProvider.autoDispose<List<WalletTxn>>(
  (ref) async =>
      (await ref.watch(walletRepositoryProvider).transactions(branchId: ref.watch(walletBranchProvider), size: 5))
          .content,
);

// ------------------------------------------------------------------ checkout

/// What the payment sheet ended with.
sealed class CheckoutResult {
  const CheckoutResult();
}

class CheckoutPaid extends CheckoutResult {
  const CheckoutPaid({required this.orderId, required this.paymentId, required this.signature});

  final String orderId;
  final String paymentId;
  final String signature;
}

class CheckoutCancelled extends CheckoutResult {
  const CheckoutCancelled();
}

class CheckoutFailed extends CheckoutResult {
  const CheckoutFailed(this.message);

  final String message;
}

/// The customer chose an external wallet app; Razorpay reports the outcome to the
/// server, not to us.
class CheckoutExternalWallet extends CheckoutResult {
  const CheckoutExternalWallet(this.wallet);

  final String? wallet;
}

/// Opens the gateway's payment sheet for a server-issued order.
abstract class PaymentCheckout {
  Future<CheckoutResult> pay(
    RechargeOrder order, {
    required String name,
    required String description,
    String? email,
    String? contact,
  });
}

/// Razorpay Standard Checkout (native SDK). Key, order id and amount all come from the
/// server's order; nothing is chosen on the phone.
class RazorpayCheckout implements PaymentCheckout {
  @override
  Future<CheckoutResult> pay(
    RechargeOrder order, {
    required String name,
    required String description,
    String? email,
    String? contact,
  }) {
    final done = Completer<CheckoutResult>();
    final razorpay = Razorpay();
    void finish(CheckoutResult r) {
      if (!done.isCompleted) done.complete(r);
      razorpay.clear();
    }

    razorpay
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
        if (r.paymentId == null || r.signature == null) {
          finish(const CheckoutFailed('The payment app did not return a payment reference.'));
        } else {
          finish(CheckoutPaid(orderId: r.orderId ?? order.orderId, paymentId: r.paymentId!, signature: r.signature!));
        }
      })
      ..on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
        finish(r.code == Razorpay.PAYMENT_CANCELLED ? const CheckoutCancelled() : CheckoutFailed(_failureMessage(r)));
      })
      ..on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) => finish(CheckoutExternalWallet(r.walletName)));

    try {
      razorpay.open({
        'key': order.publicKey,
        'order_id': order.orderId,
        'amount': order.amountMinor,
        'currency': order.currency,
        'name': name,
        'description': description,
        'prefill': {'email': ?email, 'contact': ?contact},
        'theme': {'color': '#3949AB'},
        'retry': {'enabled': true, 'max_count': 2},
      });
    } catch (e) {
      finish(const CheckoutFailed('Could not open the payment screen.'));
    }
    return done.future;
  }

  static String _failureMessage(PaymentFailureResponse r) {
    final m = r.message;
    if (m != null && m.isNotEmpty && !m.trimLeft().startsWith('{')) return m;
    final desc = (r.error?['error'] as Map?)?['description'];
    if (desc is String && desc.isNotEmpty) return desc;
    return switch (r.code) {
      Razorpay.NETWORK_ERROR => 'Network error during payment. Check your connection and try again.',
      Razorpay.TLS_ERROR => 'This device does not support a secure payment connection.',
      _ => 'Payment failed.',
    };
  }
}

final paymentCheckoutProvider = Provider<PaymentCheckout>((ref) => RazorpayCheckout());
