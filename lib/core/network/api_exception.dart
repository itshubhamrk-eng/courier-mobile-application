import 'package:dio/dio.dart';

import 'api_response.dart';

enum ApiErrorKind { network, timeout, unauthorized, forbidden, validation, notFound, server, unknown }

/// One error type for every failed call, with a message safe to show staff.
class ApiException implements Exception {
  const ApiException(
    this.kind,
    this.message, {
    this.statusCode,
    this.errorCode,
    this.fieldErrors = const [],
    this.requestId,
  });

  final ApiErrorKind kind;
  final String message;
  final int? statusCode;
  final String? errorCode;
  final List<FieldError> fieldErrors;
  final String? requestId;

  /// True when the request may or may not have reached the server, so a
  /// non-idempotent call (booking, THC, DRS, deliver) must not be retried blindly.
  bool get outcomeUnknown => kind == ApiErrorKind.timeout;

  factory ApiException.fromDio(DioException e) {
    final status = e.response?.statusCode;
    final body = e.response?.data;
    ApiResponse<Object?>? parsed;
    if (body is Map<String, dynamic>) {
      parsed = ApiResponse.fromJson(body, (d) => d);
    }
    final serverMessage = parsed?.message;

    ApiErrorKind kind;
    String fallback;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        kind = ApiErrorKind.timeout;
        fallback = 'The server took too long to respond.';
      case DioExceptionType.connectionError:
        kind = ApiErrorKind.network;
        fallback = 'No connection. Check your internet and try again.';
      default:
        switch (status) {
          case 400 || 409 || 422:
            kind = ApiErrorKind.validation;
            fallback = 'Please check the details and try again.';
          case 401:
            kind = ApiErrorKind.unauthorized;
            fallback = 'Your session has expired. Please sign in again.';
          case 403:
            kind = ApiErrorKind.forbidden;
            fallback = 'You do not have permission for this action.';
          case 404:
            kind = ApiErrorKind.notFound;
            fallback = 'Not found.';
          case final s? when s >= 500:
            kind = ApiErrorKind.server;
            fallback = 'Server error. Please try again shortly.';
          default:
            kind = ApiErrorKind.unknown;
            fallback = 'Something went wrong.';
        }
    }

    return ApiException(
      kind,
      (serverMessage != null && serverMessage.isNotEmpty) ? serverMessage : fallback,
      statusCode: status,
      errorCode: parsed?.errorCode,
      fieldErrors: parsed?.errors ?? const [],
      requestId: parsed?.requestId,
    );
  }

  @override
  String toString() => 'ApiException($kind, $statusCode, $errorCode, requestId=$requestId)';
}
