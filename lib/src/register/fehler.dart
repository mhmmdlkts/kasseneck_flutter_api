/// Die Fehler der Kassen-Aufrufe — geteilt von Kopplung, Sitzung und allem,
/// was danach über den [RegisterTransport] läuft.
///
/// Sie stehen in einer eigenen Datei, weil sonst jede neue Aufrufgruppe
/// entweder `pairing.dart` importieren müsste (obwohl sie mit Kopplung nichts
/// zu tun hat) oder sich eigene Fehler ausdächte — und die Kasse dann zwei
/// Arten hätte, dieselbe abgelaufene Sitzung zu melden.
library;

/// Der Aufrufer hat etwas nicht mitgegeben, oder die Antwort trug nicht, was
/// der Aufruf zusagt. Die Meldung nennt immer nur das **Feld**, nie seinen
/// Wert — sonst stünde ein Gerätegeheimnis im Protokoll.
class KasseneckValidationError implements Exception {
  const KasseneckValidationError(this.functionName, this.reason, this.kind);

  final String functionName;
  final String reason;

  /// `request` = der Aufruf war unvollständig, `response` = die Antwort.
  final String kind;

  @override
  String toString() => 'KasseneckValidationError($functionName, $kind): $reason';
}

/// Fachlicher Fehler des Backends (PIN falsch, Kasse belegt, Gerät gesperrt …).
class KasseneckApiError implements Exception {
  const KasseneckApiError(this.functionName, this.message);

  final String functionName;
  final String message;

  @override
  String toString() => 'KasseneckApiError($functionName): $message';
}

/// Die Antwort war keine brauchbare Hülle `{status, data}` oder der HTTP-Weg
/// scheiterte. Trägt bewusst **nichts** aus dem Rumpf: dort könnten Werte
/// stehen, die wir gerade nicht ins Protokoll lassen wollen.
class KasseneckHttpError implements Exception {
  const KasseneckHttpError(this.functionName, this.statusCode, this.reason);

  final String functionName;
  final int statusCode;
  final String reason;

  @override
  String toString() => 'KasseneckHttpError($functionName): HTTP $statusCode ($reason)';
}
