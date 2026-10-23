import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import 'api_exception.dart';
import 'api_response.dart';
import 'auth_interceptor.dart';

Dio _newDio() {
  final dio = Dio(
    BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 60),
      headers: {'Accept': 'application/json'},
    ),
  );
  if (Env.isDev && kDebugMode) {
    dio.interceptors.add(_SafeLogInterceptor());
  }
  return dio;
}

/// No auth header. Used only for `/auth/login`, `/auth/refresh` and `/auth/logout`.
final bareDioProvider = Provider<Dio>((ref) => _newDio());

/// Every other call: adds the bearer token and refreshes it when needed.
final dioProvider = Provider<Dio>((ref) {
  final dio = _newDio();
  dio.interceptors.insert(0, AuthInterceptor(dio, () => ref.read(tokenSourceProvider)));
  return dio;
});

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref.watch(dioProvider)));

/// Thin wrapper that unwraps `ApiResponse.data` and turns every failure into [ApiException].
class ApiClient {
  ApiClient(this._dio);

  final Dio _dio;

  Future<T> get<T>(String path, {Map<String, dynamic>? query, required T Function(Object? data) parse}) =>
      _send(() => _dio.get<Object?>(path, queryParameters: query), parse);

  Future<T> post<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    required T Function(Object? data) parse,
    Options? options,
    ProgressCallback? onSendProgress,
  }) => _send(
    () =>
        _dio.post<Object?>(path, data: body, queryParameters: query, options: options, onSendProgress: onSendProgress),
    parse,
  );

  Future<T> delete<T>(String path, {required T Function(Object? data) parse}) =>
      _send(() => _dio.delete<Object?>(path), parse);

  Future<T> _send<T>(Future<Response<Object?>> Function() call, T Function(Object? data) parse) async {
    try {
      final res = await call();
      final body = res.data;
      if (body is! Map<String, dynamic>) {
        throw const ApiException(ApiErrorKind.unknown, 'Unexpected response from server.');
      }
      final api = ApiResponse.fromJson(body, parse);
      if (!api.success) {
        throw ApiException(
          ApiErrorKind.validation,
          api.message ?? 'Request failed.',
          statusCode: res.statusCode,
          errorCode: api.errorCode,
          fieldErrors: api.errors,
          requestId: api.requestId,
        );
      }
      return api.data as T;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

/// Logs method, path and status only: never headers or bodies, so tokens,
/// passwords and OTPs stay out of logs.
class _SafeLogInterceptor extends Interceptor {
  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    debugPrint('[api] ${response.requestOptions.method} ${response.requestOptions.path} -> ${response.statusCode}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    debugPrint(
      '[api] ${err.requestOptions.method} ${err.requestOptions.path} -> ${err.response?.statusCode ?? err.type.name}',
    );
    handler.next(err);
  }
}
