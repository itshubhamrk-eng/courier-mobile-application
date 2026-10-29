import 'dart:async';

import 'package:branch_ops/core/network/api_client.dart';
import 'package:branch_ops/features/wallet/application/wallet_state.dart';
import 'package:branch_ops/features/wallet/data/wallet_models.dart';
import 'package:branch_ops/features/wallet/data/wallet_repository.dart';
import 'package:branch_ops/router.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _manager = ['BRANCH_MANAGER'];
const _walletPerms = ['DASHBOARD_READ', 'SHIPMENT_READ', 'WALLET_READ', 'WALLET_RECHARGE'];

final _wallet = {
  'id': 'w-1',
  'walletNumber': 'WAL-PUN-001',
  'branchId': 'branch-1',
  'branchName': 'Pune Shivajinagar',
  'status': 'ACTIVE',
  'availableBalance': 1200,
  'holdBalance': 100,
  'totalBalance': 1300,
  'currency': 'INR',
};

final _order = {
  'walletId': 'w-1',
  'walletNumber': 'WAL-PUN-001',
  'branchId': 'branch-1',
  'gateway': 'RAZORPAY',
  'orderId': 'order_123',
  'amountMinor': 50000,
  'currency': 'INR',
  'publicKey': 'rzp_test_key',
  'receipt': 'rcpt-1',
};

final _settled = {
  'id': 't-1',
  'transactionNo': 'WTX-0001',
  'transactionType': 'CR',
  'subTransactionType': 'WRC',
  'subTransactionTypeLabel': 'Wallet Recharge',
  'amount': 500,
  'balanceBefore': 1200,
  'balanceAfter': 1700,
  'paymentReference': 'pay_abc',
  'createdAt': '2026-10-26T10:00:00Z',
};

/// Stands in for Razorpay: returns [result] and records the order it was given.
class FakeCheckout implements PaymentCheckout {
  FakeCheckout(this.result);

  final CheckoutResult result;
  final orders = <RechargeOrder>[];

  @override
  Future<CheckoutResult> pay(
    RechargeOrder order, {
    required String name,
    required String description,
    String? email,
    String? contact,
  }) async {
    orders.add(order);
    return result;
  }
}

const _paid = CheckoutPaid(orderId: 'order_123', paymentId: 'pay_abc', signature: 'sig');

void main() {
  group('recharge', () {
    late List<RequestOptions> orders;
    late List<RequestOptions> settles;

    FakeHandler server({FakeResponse? order, Future<FakeResponse> Function()? settle}) {
      orders = [];
      settles = [];
      return (r) async {
        switch (r.path) {
          case '/api/v1/branch-wallet':
            return (status: 200, body: ok(_wallet));
          case '/api/v1/branch-wallet/recharge/order':
            orders.add(r);
            return order ?? (status: 200, body: ok(_order));
          case '/api/v1/branch-wallet/recharge':
            settles.add(r);
            return settle == null ? (status: 200, body: ok(_settled)) : await settle();
          default:
            return (status: 200, body: ok(null));
        }
      };
    }

    Future<FakeCheckout> openAndPay(WidgetTester tester, FakeHandler handler, CheckoutResult result) async {
      final checkout = FakeCheckout(result);
      final c = await pumpSignedInApp(
        tester,
        handler,
        roles: _manager,
        permissions: _walletPerms,
        overrides: [paymentCheckoutProvider.overrideWithValue(checkout)],
      );
      unawaited(c.read(routerProvider).push('/wallet/recharge'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '500');
      await tester.pump();
      await tester.ensureVisible(find.text('Pay ₹500.00'));
      await tester.tap(find.text('Pay ₹500.00'));
      await tester.pumpAndSettle();
      return checkout;
    }

    testWidgets('opens a server order, pays it, settles it once and shows the receipt option', (tester) async {
      final checkout = await openAndPay(tester, server(), _paid);

      expect(orders, hasLength(1));
      expect((orders.single.data as Map)['amount'], 500);
      expect(checkout.orders.single.publicKey, 'rzp_test_key', reason: 'key comes from the server order');
      expect(checkout.orders.single.amountMinor, 50000);
      expect(settles, hasLength(1));
      final body = settles.single.data as Map;
      expect(body['gatewayOrderId'], 'order_123');
      expect(body['paymentReference'], 'pay_abc');
      expect(body['signature'], 'sig');
      expect(find.text('Recharge successful'), findsOneWidget);
      expect(find.text('WTX-0001'), findsOneWidget);
      expect(find.text('Receipt'), findsOneWidget);
    });

    testWidgets('cancelled checkout settles nothing and offers to try again', (tester) async {
      await openAndPay(tester, server(), const CheckoutCancelled());

      expect(settles, isEmpty);
      expect(find.text('Recharge not completed'), findsOneWidget);
      expect(find.text('Payment was cancelled.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('failed payment shows the gateway message and the refund note', (tester) async {
      await openAndPay(tester, server(), const CheckoutFailed('Card declined by bank'));

      expect(settles, isEmpty);
      expect(find.textContaining('Card declined by bank'), findsOneWidget);
      expect(find.textContaining('refunded by Razorpay'), findsOneWidget);
    });

    testWidgets('no gateway configured: shows the server message and never opens checkout', (tester) async {
      final checkout = await openAndPay(
        tester,
        server(order: (status: 422, body: errorBody('Online recharge is not configured for this company.'))),
        _paid,
      );

      expect(checkout.orders, isEmpty);
      expect(find.text('Online recharge is not configured for this company.'), findsOneWidget);
    });

    testWidgets(
      'paid but the server cannot be reached: retries, then says it will be credited, never asks to pay again',
      (tester) async {
        final handler = server(
          settle: () async => throw DioException(
            requestOptions: RequestOptions(path: '/api/v1/branch-wallet/recharge'),
            type: DioExceptionType.connectionError,
          ),
        );
        await openAndPay(tester, handler, _paid);
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        expect(settles, hasLength(3), reason: 'idempotent settle is retried');
        expect(find.text('Confirming payment'), findsOneWidget);
        expect(find.textContaining('Do not pay again'), findsOneWidget);
        expect(find.text('Check again'), findsOneWidget);
        expect(find.text('Recharge report'), findsOneWidget);
      },
    );

    testWidgets('role without WALLET_RECHARGE cannot open the recharge form', (tester) async {
      final c = await pumpSignedInApp(tester, server(), roles: _manager, permissions: const ['WALLET_READ']);
      unawaited(c.read(routerProvider).push('/wallet/recharge'));
      await tester.pumpAndSettle();

      expect(find.text('Your role cannot recharge the wallet.'), findsOneWidget);
      expect(orders, isEmpty);
    });
  });

  group('repository', () {
    test('transaction filters become the server query parameters', () async {
      late RequestOptions seen;
      final adapter = FakeAdapter((r) async {
        seen = r;
        return (status: 200, body: ok({'content': [], 'page': 0, 'size': 20, 'totalElements': 0}));
      });
      final repo = WalletRepository(
        ApiClient(Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adapter),
      );

      await repo.transactions(
        branchId: 'b-2',
        filter: TxnFilter(
          search: ' WTX ',
          from: DateTime(2026, 10, 1),
          to: DateTime(2026, 10, 26),
          types: const {'CR'},
          subTypes: const {'WRC', 'MCR'},
          reference: 'UTR9',
        ),
        page: 2,
      );

      final q = seen.queryParameters;
      expect(seen.path, '/api/v1/branch-wallet/transactions');
      expect(q['branchId'], 'b-2');
      expect(q['search'], 'WTX');
      expect(q['fromDate'], '2026-10-01');
      expect(q['toDate'], '2026-10-26');
      expect(q['transactionType'], ['CR']);
      expect(q['subTransactionType'], containsAll(['WRC', 'MCR']));
      expect(q['referenceId'], 'UTR9');
      expect(q['page'], 2);
      expect(q['sort'], 'createdAt,desc');
    });

    test('settle sends only the gateway fields, so the server credits what the gateway says', () async {
      late RequestOptions seen;
      final adapter = FakeAdapter((r) async {
        seen = r;
        return (status: 200, body: ok(_settled));
      });
      final repo = WalletRepository(
        ApiClient(Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adapter),
      );

      final t = await repo.completeRecharge(orderId: 'o', paymentId: 'p', signature: 's');

      expect(seen.data, {'branchId': null, 'gatewayOrderId': 'o', 'paymentReference': 'p', 'signature': 's'});
      expect(t.isCredit, isTrue);
      expect(t.reason, 'Wallet Recharge');
    });
  });
}
