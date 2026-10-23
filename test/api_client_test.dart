import 'package:branch_ops/core/network/api_client.dart';
import 'package:branch_ops/core/network/api_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  ApiClient client(FakeResponse r) =>
      ApiClient(Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = FakeAdapter((_) async => r));

  test('success with null data reaches the parser', () async {
    final result = await client((status: 200, body: ok(null)))
        .get<String?>('/x', parse: (d) => d == null ? 'none' : 'some');
    expect(result, 'none');
  });

  test('unexpected response shape is a clear error, not a crash', () async {
    await expectLater(
      client((status: 200, body: ok('not a map'))).get('/x', parse: (d) => (d! as Map<String, dynamic>)['id']),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Unexpected response from server.')),
    );
  });

  test('success=false with 200 is still an error with the server message', () async {
    await expectLater(
      client((status: 200, body: errorBody('Insufficient wallet balance'))).get('/x', parse: (d) => d),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Insufficient wallet balance')),
    );
  });
}
