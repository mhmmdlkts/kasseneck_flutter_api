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
/// * `409` — ein anderer Vorgang laeuft noch, siehe [terminalBusyStatusCode].
/// * `503` — terminal not operable.
class HpsHttpException extends HpsException {
  HpsHttpException(this.statusCode, super.message, {this.body});

  /// The HTTP status code returned by the HPS.
  final int statusCode;

  /// The raw response body, if any.
  final String? body;

  /// HTTP `409` ("Terminal is busy", `text/plain`): das Terminal serialisiert
  /// und weist eine zweite Anfrage ab, waehrend eine erste noch laeuft.
  ///
  /// Am 27.08.2026 an einem hobex-HPS gemessen (TID 3600335, HPS 1.10.0,
  /// Firmware 7.3.6): laeuft bereits ein Vorgang und wird ein zweiter
  /// gestartet, kommt `409` nach 87 Millisekunden. Der ABGEWIESENE Vorgang
  /// hinterlaesst KEINE Spur -- die Statusabfrage auf seine Kennung liefert
  /// `9027` (zweimal geprueft), es wurde nichts angelegt und kein
  /// Kartenfluss gestartet.
  ///
  /// Das ist ein HTTP-Status, KEIN `responseCode` -- er gehoert bewusst
  /// nicht in [TransactionResponse]s Positivliste
  /// ([TransactionResponse.isConclusive]), sondern wird auf einer anderen
  /// Ebene ausgewertet, siehe `HpsPayments`. Und die positive Aussage
  /// ("nichts angelegt") gilt AUSDRUECKLICH nur fuer die ERZEUGENDE Anfrage
  /// (Zahlung, Gutschrift, der direkte Aufhebungs-Request) -- ein `409` auf
  /// einen [HpsClient.abort]-Versuch oder auf eine Statusabfrage waehrend
  /// der Klaerung sagt nur, dass DIESE Anfrage nicht durchkam, nichts ueber
  /// den Vorgang, den sie klaeren sollte.
  static const int terminalBusyStatusCode = 409;

  /// `true`, wenn dies der gemessene "Terminal beschaeftigt"-Fall ist
  /// ([terminalBusyStatusCode]).
  bool get isTerminalBusy => statusCode == terminalBusyStatusCode;

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
