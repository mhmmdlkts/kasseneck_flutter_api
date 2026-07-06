/// Ergebnis eines direkten Druckvorgangs (z. B. [KeckPrinterService.printRawBytesWifi]).
///
/// Bewusst schlank: [success] plus optionale [error]-Meldung — kein Werfen,
/// damit Aufrufer den Druckfehler ruhig behandeln können (Retry, UI-Hinweis).
///
/// WICHTIG: [success] == `true` bedeutet **an den Drucker gesendet** (Bytes über
/// den Socket geschrieben und geflusht) — NICHT garantiert *gedruckt*. Roh-TCP
/// an einen Thermodrucker (Port 9100) ist fire-and-forget ohne Anwendungs-ACK;
/// Papierstau/-ende bleibt unbemerkt.
class KeckPrintResult {
  /// `true`, wenn die Bytes an den Drucker gesendet wurden (siehe Klassendoku).
  final bool success;

  /// Fehlermeldung bei [success] == `false`, sonst `null`.
  final String? error;

  const KeckPrintResult._(this.success, this.error);

  /// Erfolgreich gesendet.
  const KeckPrintResult.success() : this._(true, null);

  /// Fehlgeschlagen mit [message].
  const KeckPrintResult.failure(String message) : this._(false, message);

  @override
  String toString() => success ? 'KeckPrintResult.success' : 'KeckPrintResult.failure($error)';
}
