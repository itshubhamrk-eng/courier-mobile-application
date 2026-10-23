/// Mirrors courier-service `ApiResponse<T>` and `PageResponse<T>`.
class ApiResponse<T> {
  const ApiResponse({
    required this.success,
    this.message,
    this.data,
    this.errorCode,
    this.errors = const [],
    this.requestId,
  });

  final bool success;
  final String? message;
  final T? data;
  final String? errorCode;
  final List<FieldError> errors;
  final String? requestId;

  factory ApiResponse.fromJson(Map<String, dynamic> json, T Function(Object? data) parseData) {
    final rawErrors = json['errors'];
    return ApiResponse(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String?,
      data: json['data'] == null ? null : parseData(json['data']),
      errorCode: json['errorCode'] as String?,
      errors: rawErrors is List
          ? rawErrors.whereType<Map<String, dynamic>>().map(FieldError.fromJson).toList()
          : const [],
      requestId: json['requestId'] as String?,
    );
  }
}

class FieldError {
  const FieldError({this.field, this.message});

  final String? field;
  final String? message;

  factory FieldError.fromJson(Map<String, dynamic> json) =>
      FieldError(field: json['field'] as String?, message: json['message'] as String?);
}

class PageResponse<T> {
  const PageResponse({
    required this.content,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
    required this.hasNext,
  });

  final List<T> content;
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;
  final bool hasNext;

  factory PageResponse.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic> item) parseItem) {
    final raw = json['content'];
    return PageResponse(
      content: raw is List ? raw.whereType<Map<String, dynamic>>().map(parseItem).toList() : const [],
      page: json['page'] as int? ?? 0,
      size: json['size'] as int? ?? 0,
      totalElements: json['totalElements'] as int? ?? 0,
      totalPages: json['totalPages'] as int? ?? 0,
      hasNext: json['hasNext'] as bool? ?? false,
    );
  }
}
