class ApiException implements Exception {
  final int statusCode;
  final String message;
  final Object? cause;

  ApiException(this.statusCode, this.message, {this.cause});

  bool get isNetworkError => statusCode == 0;
  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}

class NetworkException extends ApiException {
  NetworkException(String message, {Object? cause})
      : super(0, message, cause: cause);
}