/// Ergebnis eines direkten Druckvorgangs (z. B. [KeckPrinterService.printRawBytesWifi]).
///
/// Bewusst schlank: [success] plus optionale [error]-Meldung — kein Werfen,
/// damit Aufrufer den Druckfehler ruhig behandeln können (Retry, UI-Hinweis).
class PrintResult {
  /// `true`, wenn die Bytes an den Drucker gesendet wurden.
  final bool success;

  /// Fehlermeldung bei [success] == `false`, sonst `null`.
  final String? error;

  const PrintResult._(this.success, this.error);

  /// Erfolgreich gesendet.
  const PrintResult.success() : this._(true, null);

  /// Fehlgeschlagen mit [message].
  const PrintResult.failure(String message) : this._(false, message);

  @override
  String toString() => success ? 'PrintResult.success' : 'PrintResult.failure($error)';
}
