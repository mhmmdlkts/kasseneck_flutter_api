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
  final String? qrError;

  /// Der QR steht auf dem Papier, aber nicht auf dem eingestellten Weg --
  /// `null`, solange nichts abgewichen ist. Entweder war das Symbol fuer den
  /// nativen Befehl zu breit und ging als Bild hinaus, oder es passte nur
  /// unter der Mindest-Modulgroesse.
  ///
  /// Getrennt von [qrError], weil die Handlung eine andere ist: hier ist der
  /// Beleg vollstaendig, aber der eingestellte Druckweg taugt fuer dieses
  /// Geraet nicht -- die Kasse kann es dem Chef sagen und ihn dauerhaft
  /// umstellen.
  final String? qrFallback;

  const KeckPrintResult._(this.success, this.error, [this.qrError, this.qrFallback]);

  /// Erfolgreich gesendet. [qrError] meldet einen Beleg, dem der QR fehlt,
  /// [qrFallback] einen, dessen QR auf anderem Weg entstehen musste.
  const KeckPrintResult.success({String? qrError, String? qrFallback})
      : this._(true, null, qrError, qrFallback);

  /// Fehlgeschlagen mit [message].
  const KeckPrintResult.failure(String message, {String? qrError, String? qrFallback})
      : this._(false, message, qrError, qrFallback);

  @override
  String toString() =>
      '${success ? 'KeckPrintResult.success' : 'KeckPrintResult.failure($error)'}'
      '${qrError == null ? '' : ' [QR fehlt]'}'
      '${qrFallback == null ? '' : ' [QR ausgewichen]'}';
}
