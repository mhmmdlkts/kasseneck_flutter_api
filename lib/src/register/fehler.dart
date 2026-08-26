/// Die Fehler der Kassen-Aufrufe — geteilt von Kopplung, Sitzung und allem,
/// was danach über den [RegisterTransport] läuft, sowie vom Einlesen eines
/// Belegs (der auf beiden Wegen dasselbe Modell füllt).
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

/// Ein Beleg kam an, ließ sich aber nicht lesen — ein Pflichtfeld fehlt oder
/// hat den falschen Typ.
///
/// **Der Beleg existiert an dieser Stelle bereits.** Er ist signiert, steht in
/// der Signaturkette und im DEP; unbrauchbar ist nur die Antwort darüber. Ein
/// roher `TypeError` wäre hier der schlimmste Fall: für den Aufrufer nicht von
/// „Verkauf fehlgeschlagen" zu unterscheiden, und mit der verworfenen Antwort
/// ginge die [receiptId] verloren — dann bliebe nichts, womit sich der Beleg
/// nachholen ließe, und der naheliegende zweite Versuch wäre ein zweiter
/// Umsatz in der Signaturkette.
///
/// Deshalb trägt dieser Fehler die Kennung mit, sooft sie in der Antwort
/// stand. Sie ist der Faden zum Beleg: `KasseneckApi.getReceipt(receiptId)`
/// bzw. `RegisterReceiptClient.holen(receiptId)` holt ihn nach.
class KasseneckReceiptFormatError implements Exception {
  const KasseneckReceiptFormatError(this.field, {this.receiptId, this.causeType});

  /// Das Feld, das fehlt oder den falschen Typ hat — nie sein Wert.
  final String field;

  /// Die Belegkennung, **sofern** sie in der Antwort stand. `null` heißt: der
  /// Beleg ist von hier aus nicht mehr auffindbar.
  final String? receiptId;

  /// Die **Art** der zugrunde liegenden Ausnahme (`TypeError`,
  /// `FormatException` …), wenn das Einlesen an einer anderen Stelle scheiterte.
  ///
  /// Nur der Typname, nie die Meldung: eine `FormatException` trägt ihre
  /// Eingabe im Text, und Antwortinhalte gehören nicht ins Protokoll — dieselbe
  /// Regel, die [KasseneckHttpError] befolgt.
  final String? causeType;

  @override
  String toString() => 'KasseneckReceiptFormatError('
      '${receiptId ?? 'ohne receiptId'}): '
      'Feld "$field" fehlt oder hat den falschen Typ'
      '${causeType == null ? '' : ' ($causeType)'}';
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
