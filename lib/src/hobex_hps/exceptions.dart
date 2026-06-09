/// Base class for all errors thrown by this package.
///
/// Note: a **declined** payment is *not* an exception — it is returned as a
/// [TransactionResponse] with `isApproved == false`. Exceptions represent
/// transport failures or non-success HTTP status codes.
class HpsException implements Exception {
  const HpsException(this.message);

  final String message;

  @override
  String toString() => 'HpsException: $message';
}

/// Thrown when the HPS responds with a non-2xx HTTP status code.
///
/// Common cases:
/// * `400` — missing/invalid parameter, or transaction already
///   cancelled/captured.
/// * `403` — the requested feature is not activated for this account.
/// * `404` — transaction not found, or endpoint not implemented.
/// * `503` — terminal not operable.
class HpsHttpException extends HpsException {
  HpsHttpException(this.statusCode, super.message, {this.body});

  /// The HTTP status code returned by the HPS.
  final int statusCode;

  /// The raw response body, if any.
  final String? body;

  @override
  String toString() => 'HpsHttpException($statusCode): $message';
}

/// Thrown when the HPS could not be reached at all (socket error, timeout,
/// connection refused, …).
class HpsConnectionException extends HpsException {
  HpsConnectionException(this.cause)
    : super('Could not reach the hobex HPS: $cause');

  /// The underlying error (e.g. `SocketException`, `TimeoutException`).
  final Object cause;
}
