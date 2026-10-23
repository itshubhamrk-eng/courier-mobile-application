import 'dart:async';

import 'package:branch_ops/core/network/api_client.dart';
import 'package:branch_ops/core/network/api_exception.dart';
import 'package:branch_ops/features/auth/application/auth_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  group('restore on app start', () {
    test('no saved token signs out', () async {
      final c = testContainer(adapter: FakeAdapter((_) async => (status: 500, body: null)));
      expect(await settledAuth(c), isA<AuthSignedOut>());
    });

    test('saved token is renewed into a full session', () async {
      final store = MemoryStore()..values['refresh'] = 'saved';
      final adapter = FakeAdapter((r) async => (status: 200, body: ok(loginJson(refresh: 'rotated'))));
      final c = testContainer(adapter: adapter, store: store);

      final state = await settledAuth(c);

      expect(state, isA<AuthSignedIn>());
      expect((state as AuthSignedIn).session.operatingBranchId, 'branch-1');
      expect(adapter.requests.single.path, '/api/v1/auth/refresh');
      expect(adapter.requests.single.data, {'refreshToken': 'saved'});
      expect(store.values['refresh'], 'rotated');
    });

    test('rejected token signs out as expired and is forgotten', () async {
      final store = MemoryStore()..values['refresh'] = 'old';
      final c = testContainer(
        adapter: FakeAdapter((_) async => (status: 401, body: errorBody('Session expired'))),
        store: store,
      );

      final state = await settledAuth(c);

      expect(state, isA<AuthSignedOut>());
      expect((state as AuthSignedOut).expired, isTrue);
      expect(store.values.containsKey('refresh'), isFalse);
    });

    test('server unreachable keeps the token and offers retry', () async {
      final store = MemoryStore()..values['refresh'] = 'saved';
      final c = testContainer(
        adapter: FakeAdapter((r) async => throw DioException.connectionError(requestOptions: r, reason: 'offline')),
        store: store,
      );

      final state = await settledAuth(c);

      expect(state, isA<AuthRestoreFailed>());
      expect(store.values['refresh'], 'saved');
    });
  });

  group('login', () {
    test('success stores refresh token and company code, sends no stale data', () async {
      final store = MemoryStore();
      final adapter = FakeAdapter((r) async => (status: 200, body: ok(loginJson())));
      final c = testContainer(adapter: adapter, store: store);
      await settledAuth(c);

      await c
          .read(authControllerProvider.notifier)
          .login(companyCode: ' acme ', emailOrMobile: ' clerk@example.test ', password: 'pw');

      expect(c.read(authControllerProvider), isA<AuthSignedIn>());
      expect(store.values['refresh'], 'refresh-1');
      expect(store.values['company'], 'ACME');
      final body = adapter.requests.last.data as Map<String, dynamic>;
      expect(body['companyCode'], 'ACME');
      expect(body['email'], 'clerk@example.test');
    });

    test('wrong password surfaces the server message', () async {
      final c = testContainer(
        adapter: FakeAdapter((_) async => (status: 401, body: errorBody('Invalid email or password'))),
      );
      await settledAuth(c);

      await expectLater(
        c.read(authControllerProvider.notifier).login(companyCode: 'A', emailOrMobile: 'x', password: 'y'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Invalid email or password')),
      );
      expect(c.read(authControllerProvider), isA<AuthSignedOut>());
    });

    test('account without a branch has no operating branch', () async {
      final c = testContainer(adapter: FakeAdapter((_) async => (status: 200, body: ok(loginJson(branchId: null)))));
      await settledAuth(c);
      await c.read(authControllerProvider.notifier).login(companyCode: 'A', emailOrMobile: 'x', password: 'y');

      expect((c.read(authControllerProvider) as AuthSignedIn).session.operatingBranchId, isNull);
    });
  });

  group('token handling on API calls', () {
    Future<(FakeAdapter, ProviderContainer)> signedIn({int expiresIn = 900}) async {
      final adapter = FakeAdapter((_) async => (status: 200, body: ok(loginJson(expiresIn: expiresIn))));
      final c = testContainer(adapter: adapter);
      await settledAuth(c);
      await c.read(authControllerProvider.notifier).login(companyCode: 'A', emailOrMobile: 'x', password: 'y');
      adapter.requests.clear();
      return (adapter, c);
    }

    test('adds the bearer token', () async {
      final (adapter, c) = await signedIn();
      adapter.handler = (_) async => (status: 200, body: ok({'n': 1}));

      await c.read(apiClientProvider).get('/api/v1/x', parse: (d) => d);

      expect(adapter.requests.single.headers['Authorization'], 'Bearer access-1');
    });

    test('401 refreshes once and replays the request with the new token', () async {
      final (adapter, c) = await signedIn();
      adapter.handler = (r) async {
        if (r.path == '/api/v1/auth/refresh') {
          return (status: 200, body: ok(loginJson(access: 'access-2', refresh: 'refresh-2')));
        }
        return r.headers['Authorization'] == 'Bearer access-2'
            ? (status: 200, body: ok('done'))
            : (status: 401, body: errorBody('expired'));
      };

      final result = await c.read(apiClientProvider).get('/api/v1/x', parse: (d) => d);

      expect(result, 'done');
      expect(adapter.requests.map((r) => r.path), ['/api/v1/x', '/api/v1/auth/refresh', '/api/v1/x']);
    });

    test('concurrent 401s share a single refresh', () async {
      final (adapter, c) = await signedIn();
      var refreshes = 0;
      final gate = Completer<void>();
      adapter.handler = (r) async {
        if (r.path == '/api/v1/auth/refresh') {
          refreshes++;
          await gate.future;
          return (status: 200, body: ok(loginJson(access: 'access-2', refresh: 'refresh-2')));
        }
        return r.headers['Authorization'] == 'Bearer access-2'
            ? (status: 200, body: ok(r.path))
            : (status: 401, body: errorBody('expired'));
      };

      final api = c.read(apiClientProvider);
      final calls = <Future<Object?>>[api.get('/api/v1/a', parse: (d) => d), api.get('/api/v1/b', parse: (d) => d)];
      await Future<void>.delayed(const Duration(milliseconds: 10));
      gate.complete();

      expect(await Future.wait(calls), ['/api/v1/a', '/api/v1/b']);
      expect(refreshes, 1);
    });

    test('refresh rejected ends the session as expired', () async {
      final (adapter, c) = await signedIn();
      adapter.handler = (r) async => r.path == '/api/v1/auth/refresh'
          ? (status: 401, body: errorBody('Refresh token revoked'))
          : (status: 401, body: errorBody('expired'));

      await expectLater(
        c.read(apiClientProvider).get('/api/v1/x', parse: (d) => d),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.unauthorized)),
      );
      final state = c.read(authControllerProvider);
      expect(state, isA<AuthSignedOut>());
      expect((state as AuthSignedOut).expired, isTrue);
    });

    test('token about to expire is refreshed before the request is sent', () async {
      final (adapter, c) = await signedIn(expiresIn: 5);
      adapter.handler = (r) async => r.path == '/api/v1/auth/refresh'
          ? (status: 200, body: ok(loginJson(access: 'access-2', refresh: 'refresh-2')))
          : (status: 200, body: ok('done'));

      await c.read(apiClientProvider).get('/api/v1/x', parse: (d) => d);

      expect(adapter.requests.map((r) => r.path), ['/api/v1/auth/refresh', '/api/v1/x']);
      expect(adapter.requests.last.headers['Authorization'], 'Bearer access-2');
    });

    test('logout clears the token and tells the server', () async {
      final (adapter, c) = await signedIn();
      adapter.handler = (_) async => (status: 200, body: ok(null));

      await c.read(authControllerProvider.notifier).logout();

      expect(c.read(authControllerProvider), isA<AuthSignedOut>());
      expect(adapter.requests.single.path, '/api/v1/auth/logout');
      expect(adapter.requests.single.data, {'refreshToken': 'refresh-1', 'allDevices': false});
    });
  });
}
