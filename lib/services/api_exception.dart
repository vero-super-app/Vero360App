
class ApiException implements Exception {
  /// Message that is safe to show to the user.
  final String message;

  /// Optional HTTP status code (for logging / decisions in code).
  final int? statusCode;

  /// Optional backend validation / error text (for logs only).
  final String? backendMessage;

  const ApiException({
    required this.message,
    this.statusCode,
    this.backendMessage,
  });

  @override
  String toString() => message; // 👈 important: no URL, no body, just message
}
