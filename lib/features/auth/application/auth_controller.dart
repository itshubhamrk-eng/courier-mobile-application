import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/auth_interceptor.dart';
import '../../../core/storage/secure_store.dart';
import '../data/auth_repository.dart';
import '../data/session.dart';

sealed class AuthState {
  const AuthState();
}

/// App start: checking for a saved session.
class AuthRestoring extends AuthState {
  const AuthRestoring();
}

/// A saved session exists but the server could not be reached to renew it.
class AuthRestoreFailed extends AuthState {
  const AuthRestoreFailed(this.error);

  final ApiException error;
}

class AuthSignedOut extends AuthState {
  const AuthSignedOut({this.expired = false});

  /// True when the server ended the session (not a manual logout).
  final bool expired;
}

class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.session);

  final Session session;
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

/// Convenience: the signed-in session, or null.
final sessionProvider = Provider<Session?>((ref) {
  final state = ref.watch(authControllerProvider);
  return state is AuthSignedIn ? state.session : null;
});

class AuthController extends Notifier<AuthState> implements TokenSource {
  Future<Session?>? _refreshing;

  AuthRepository get _repo => ref.read(authRepositoryProvider);
  SecureStore get _store => ref.read(secureStoreProvider);

  @override
  AuthState build() {
    unawaited(Future.microtask(restore));
    return const AuthRestoring();
  }

  Session? get _session => switch (state) {
    AuthSignedIn(:final session) => session,
    _ => null,
  };

  /// Renews the saved refresh token into a full session (branch, permissions).
  Future<void> restore() async {
    state = const AuthRestoring();
    final saved = await _store.readRefreshToken();
    if (saved == null) {
      state = const AuthSignedOut();
      return;
    }
    try {
      await _adopt(await _repo.refresh(saved));
    } on ApiException catch (e) {
      if (_isRejected(e)) {
        await _store.clearRefreshToken();
        state = const AuthSignedOut(expired: true);
      } else {
        state = AuthRestoreFailed(e);
      }
    }
  }

  /// Throws [ApiException] with the server's message on failure.
  Future<void> login({required String? companyCode, required String emailOrMobile, required String password}) async {
    final code = companyCode?.trim().toUpperCase();
    final session = await _repo.login(
      companyCode: code,
      emailOrMobile: emailOrMobile.trim(),
      password: password,
      deviceId: await _store.deviceId(),
    );
    await _store.writeCompanyCode(code);
    await _adopt(session);
  }

  Future<String?> lastCompanyCode() => _store.readCompanyCode();

  Future<void> logout() async {
    final session = _session;
    state = const AuthSignedOut();
    await _store.clearRefreshToken();
    if (session != null) {
      try {
        await _repo.logout(refreshToken: session.refreshToken, accessToken: session.accessToken);
      } on ApiException {
        // Signed out on this device either way; the server session times out.
      }
    }
  }

  @override
  Future<String?> validAccessToken() async {
    final session = _session;
    if (session == null) return null;
    if (!session.accessExpiringSoon) return session.accessToken;
    return (await _refreshOnce())?.accessToken;
  }

  @override
  Future<String?> renewAfterUnauthorized(String rejectedToken) async {
    final session = _session;
    if (session == null) return null;
    // Another request already renewed it.
    if (session.accessToken != rejectedToken) return session.accessToken;
    return (await _refreshOnce())?.accessToken;
  }

  /// One refresh at a time: concurrent callers share the same result, so a
  /// rotated refresh token is never used twice.
  Future<Session?> _refreshOnce() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<Session?> _doRefresh() async {
    final session = _session;
    if (session == null) return null;
    try {
      final fresh = await _repo.refresh(session.refreshToken);
      await _adopt(fresh);
      return fresh;
    } on ApiException catch (e) {
      if (_isRejected(e)) {
        await _store.clearRefreshToken();
        state = const AuthSignedOut(expired: true);
      }
      return null;
    }
  }

  Future<void> _adopt(Session session) async {
    await _store.writeRefreshToken(session.refreshToken);
    state = AuthSignedIn(session);
  }

  static bool _isRejected(ApiException e) =>
      e.kind == ApiErrorKind.unauthorized || e.kind == ApiErrorKind.validation || e.kind == ApiErrorKind.forbidden;
}
