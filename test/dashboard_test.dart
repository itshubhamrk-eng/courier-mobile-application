import 'package:branch_ops/core/network/api_client.dart';
import 'package:branch_ops/core/network/api_exception.dart';
import 'package:branch_ops/features/dashboard/data/dashboard_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  DashboardRepository repo(FakeAdapter adapter) =>
      DashboardRepository(ApiClient(Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adapter));

  Future<FakeResponse> server(RequestOptions r) async {
    final q = r.queryParameters;
    return switch (r.path) {
      '/api/v1/dashboard/summary' => (
        status: 200,
        body: ok({
          'statistics': {'todayBookings': 12},
          'branchOverview': {
            'readyForManifest': 7,
            'manifestsAwaitingDispatch': 2,
            'podOverview': {'pendingUpload': 4},
          },
        }),
      ),
      '/api/v1/manifests/summary' => (status: 200, body: ok({'totalManifests': q['status'] == 'CREATED' ? 3 : 5})),
      '/api/v1/shipments/summary' when q.containsKey('deliveredDateFrom') => (status: 200, body: ok({'totalCount': 9})),
      '/api/v1/shipments/summary' => (
        status: 200,
        body: ok({
          'statusCounts': {'IN_SCAN': 6},
        }),
      ),
      _ => (status: 404, body: errorBody('no route')),
    };
  }

  test('maps every card from its documented source, filtered to the branch', () async {
    final adapter = FakeAdapter(server);
    final counts = await repo(adapter).load('branch-1');

    expect(counts.todayBookings, 12);
    expect(counts.pendingLoading, 7);
    expect(counts.loadingSheetsOpen, 3);
    expect(counts.pendingDispatch, 2);
    expect(counts.thcInTransit, 5);
    expect(counts.pendingDrs, 6);
    expect(counts.outForDelivery, 0, reason: 'status absent from counts means none');
    expect(counts.deliveredToday, 9);
    expect(counts.pendingPod, 4);
    expect(counts.failures, isEmpty);

    final branchScoped = adapter.requests.where((r) => r.path != '/api/v1/dashboard/summary');
    expect(
      branchScoped.every(
        (r) =>
            r.queryParameters['bookingBranchId'] == 'branch-1' || r.queryParameters['deliveryBranchId'] == 'branch-1',
      ),
      isTrue,
    );
  });

  test('a failed source leaves its cards empty instead of guessing', () async {
    final counts = await repo(
      FakeAdapter(
        (r) async => r.path == '/api/v1/manifests/summary' ? (status: 500, body: errorBody('boom')) : server(r),
      ),
    ).load('branch-1');

    expect(counts.loadingSheetsOpen, isNull);
    expect(counts.thcInTransit, isNull);
    expect(counts.todayBookings, 12);
    expect(counts.failures, hasLength(2));
  });

  test('every source failing is an error', () async {
    await expectLater(
      repo(FakeAdapter((_) async => (status: 403, body: errorBody('Forbidden')))).load('branch-1'),
      throwsA(isA<ApiException>()),
    );
  });
}
