import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the interceptor needs from the auth layer. Implemented by the auth
/// controller and overridden in tests.
abstract interface class TokenSource {
  /// Current access token, refreshed first if it is about to expire.
  /// Null when nobody is signed in.
  Future<String?> validAccessToken();

  /// Called after a 401. Returns a token to retry with, or null when the
  /// session could not be renewed (the auth layer then signs the user out).
  Future<String?> renewAfterUnauthorized(String rejectedToken);
}

final tokenSourceProvider = Provider<TokenSource>(
  (ref) => throw UnimplementedError('tokenSourceProvider is overridden by the auth controller'),
);

class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._dio, this._tokens);

  final Dio _dio;
  final TokenSource Function() _tokens;

  static const _retriedKey = 'auth_retried';

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _tokens().validAccessToken();
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final request = err.requestOptions;
    final sent = request.headers['Authorization'];
    // A 401 means the server rejected the token before doing any work, so one
    // replay is safe even for bookings. Multipart bodies cannot be re-sent;
    // their callers retry themselves.
    if (err.response?.statusCode != 401 || request.extra[_retriedKey] == true || sent is! String) {
      return handler.next(err);
    }
    if (request.data is FormData) return handler.next(err);

    final token = await _tokens().renewAfterUnauthorized(sent.replaceFirst('Bearer ', ''));
    if (token == null) return handler.next(err);

    request.headers['Authorization'] = 'Bearer $token';
    request.extra[_retriedKey] = true;
    try {
      handler.resolve(await _dio.fetch<dynamic>(request));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}
