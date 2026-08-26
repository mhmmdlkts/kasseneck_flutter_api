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
  const KasseneckHttpError(this.functionName, this.statusCode, this.reason, {this.causeType});

  /// Die Frist ist abgelaufen. Die Anfrage war **draußen**; der Zeitablauf
  /// beendet nur das Warten, nicht die Arbeit des Servers. Über einem
  /// verändernden Aufruf heißt das: der Beleg kann längst signiert und in der
  /// Kette sein.
  static const String zeitablauf = 'timeout';

  /// Der Transport ist gescheitert — Verbindung nicht zustande gekommen,
  /// abgebrochen, DNS, TLS.
  ///
  /// **Das ist keine Aussage, dass nichts passiert ist.** `package:http`
  /// trennt „Verbindung wurde nie hergestellt" nicht von „Verbindung riss,
  /// nachdem die Anfrage draußen war" — beides kommt als `ClientException`
  /// bzw. `SocketException` an. Wer daraus „der Beleg existiert sicher nicht"
  /// liest, macht denselben Fehler wie am 24.08. am Terminal: aus Nichtwissen
  /// eine Behauptung. Für einen verändernden Aufruf gilt deshalb auch hier:
  /// nachsehen, nicht wiederholen.
  static const String netz = 'network';

  final String functionName;
  final int statusCode;

  /// Warum es scheiterte: [zeitablauf], [netz], `'not-json'`,
  /// `'missing-status'`, `'data-not-object'`.
  ///
  /// Die Unterscheidung [zeitablauf] gegen [netz] wird **erhalten**, nicht
  /// verworfen: sie ist die einzige Handhabe, die der Aufrufer hat. Welche
  /// Folge er daraus zieht, entscheidet er — dieses Paket entscheidet sie
  /// nicht für ihn, weil keiner der beiden Fälle beweist, dass nichts
  /// passiert ist (siehe [netz]).
  final String reason;

  /// Die **Art** der zugrunde liegenden Ausnahme (`TimeoutException`,
  /// `SocketException`, `ClientException` …), sofern es eine gab.
  ///
  /// Nur der Typname, nie die Meldung — die kann Werte aus dem Rumpf tragen.
  /// Nach dem 24.08. war fehlendes Protokoll ausdrücklich das Problem; ein
  /// restlos verworfener Ursprungsfehler lässt sich hinterher nicht mehr
  /// rekonstruieren.
  final String? causeType;

  @override
  String toString() => 'KasseneckHttpError($functionName): HTTP $statusCode ($reason)'
      '${causeType == null ? '' : ' [$causeType]'}';
}
