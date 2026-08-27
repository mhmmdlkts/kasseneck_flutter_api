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

  /// Der QR-Code des Belegs konnte nicht gesetzt werden — `null`, solange
  /// alles gut ging. Steht **unabhaengig** von [success]: der Bon geht
  /// vollstaendig hinaus und traegt den Aufdruck „!! QR-CODE FEHLT !!", nur
  /// eben ohne den gesetzlich geforderten QR. Der Aufrufer muss davon
  /// erfahren, um nachzudrucken oder den Beleg elektronisch auszugeben.
  ///
  /// Nur bei Belegdruck gesetzt; ein roher Byte-Strom kennt keinen Beleg.
  final String? qrFehler;

  const KeckPrintResult._(this.success, this.error, [this.qrFehler]);

  /// Erfolgreich gesendet. [qrFehler] meldet einen Beleg, dem der QR fehlt.
  const KeckPrintResult.success({String? qrFehler}) : this._(true, null, qrFehler);

  /// Fehlgeschlagen mit [message].
  const KeckPrintResult.failure(String message, {String? qrFehler}) : this._(false, message, qrFehler);

  @override
  String toString() =>
      '${success ? 'KeckPrintResult.success' : 'KeckPrintResult.failure($error)'}'
      '${qrFehler == null ? '' : ' [QR fehlt]'}';
}
