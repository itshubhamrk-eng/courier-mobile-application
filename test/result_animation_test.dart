import 'package:branch_ops/core/network/api_exception.dart';
import 'package:branch_ops/core/widgets/result_animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  late BuildContext page;

  Future<void> pump(WidgetTester t) => t.pumpWidget(
    MaterialApp.router(
      routerConfig: GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: Builder(
                builder: (c) {
                  page = c;
                  return const Text('page');
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );

  testWidgets('success plays and closes by itself', (t) async {
    await pump(t);
    showSubmitSuccess(page, 'Saved.', title: 'Done');
    await t.pumpAndSettle();
    expect(find.text('Saved.'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();
    expect(find.text('Saved.'), findsNothing);
  });

  testWidgets('failure shows the server message and stays until OK', (t) async {
    await pump(t);
    showSubmitFailure(page, const ApiException(ApiErrorKind.validation, 'Wallet is low.'));
    await t.pump(const Duration(seconds: 10));
    await t.pumpAndSettle();
    expect(find.text('Wallet is low.'), findsOneWidget);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(find.text('Wallet is low.'), findsNothing);
  });

  testWidgets('a new result replaces the old one; back closes the card, not the page', (t) async {
    await pump(t);
    showSubmitFailure(page, const ApiException(ApiErrorKind.validation, 'First'));
    await t.pumpAndSettle();
    showSubmitFailure(page, const ApiException(ApiErrorKind.validation, 'Second'));
    await t.pumpAndSettle();
    expect(find.text('First'), findsNothing);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Second'), findsNothing);
    expect(find.text('page'), findsOneWidget);
  });

  test('bulk outcome', () {
    expect(ResultKind.ofCounts(ok: 2, failed: 0), ResultKind.success);
    expect(ResultKind.ofCounts(ok: 1, failed: 1), ResultKind.warning);
    expect(ResultKind.ofCounts(ok: 0, failed: 2), ResultKind.failure);
  });
}
