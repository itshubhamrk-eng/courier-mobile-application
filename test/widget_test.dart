import 'package:branch_ops/app.dart';
import 'package:branch_ops/core/network/api_response.dart';
import 'package:branch_ops/core/widgets/status_badge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app starts on the UI kit preview', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: BranchOpsApp()));
    expect(find.text('UI kit preview'), findsOneWidget);
  });

  test('status labels follow server values and do not guess unknown ones', () {
    expect(statusStyle('MANIFEST_CREATED').label, 'Loading Sheet Created');
    expect(statusStyle('SOMETHING_NEW').label, 'SOMETHING_NEW');
  });

  test('ApiResponse parses the courier-service envelope', () {
    final res = ApiResponse.fromJson({
      'success': false,
      'message': 'Invalid pincode',
      'errorCode': 'VALIDATION_FAILED',
      'errors': [
        {'field': 'deliveryPincode', 'message': 'not serviceable'},
      ],
      'requestId': 'abc',
    }, (d) => d);
    expect(res.success, isFalse);
    expect(res.errors.single.field, 'deliveryPincode');
  });

  test('PageResponse parses content', () {
    final page = PageResponse.fromJson({
      'content': [
        {'id': '1'},
      ],
      'page': 0,
      'size': 20,
      'totalElements': 1,
      'totalPages': 1,
      'hasNext': false,
    }, (m) => m['id'] as String);
    expect(page.content, ['1']);
  });
}
