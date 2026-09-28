/// Die Fehler der Kassen-Aufrufe — geteilt von Kopplung, Sitzung und allem,
/// was danach ueber den [RegisterTransport] laeuft, sowie vom Einlesen eines
/// Belegs (der auf beiden Wegen dasselbe Modell fuellt).
///
/// Sie stehen in einer eigenen Datei, weil sonst jede neue Aufrufgruppe
/// entweder `pairing.dart` importieren muesste (obwohl sie mit Kopplung nichts
/// zu tun hat) oder sich eigene Fehler ausdaechte — und die Kasse dann zwei
/// Arten haette, dieselbe abgelaufene Sitzung zu melden.
library;

/// Der Aufrufer hat etwas nicht mitgegeben, oder die Antwort trug nicht, was
/// der Aufruf zusagt. Die Meldung nennt immer nur das **Feld**, nie seinen
/// Wert — sonst stuende ein Geraetegeheimnis im Protokoll.
class KasseneckValidationError implements Exception {
  const KasseneckValidationError(this.functionName, this.reason, this.kind, {this.receiptId});

  final String functionName;
  final String reason;

  /// `request` = der Aufruf war unvollstaendig, `response` = die Antwort.
  final String kind;

  /// Die Belegkennung, **sofern** der Vorgang schon einen Beleg erzeugt hatte
  /// und die Antwort ihn mitbrachte.
  ///
  /// Betrifft die veraendernden Aufrufe: bei `cancelReceipt` ist der gesetzlich
  /// vorgeschriebene Storno-Beleg zu diesem Zeitpunkt bereits signiert und in
  /// der Kette. Ohne die Kennung bliebe dem Aufrufer nichts zum Nachholen —
  /// derselbe Faden wie in [KasseneckReceiptFormatError].
  final String? receiptId;

  @override
  String toString() => 'KasseneckValidationError($functionName, $kind): $reason'
      '${receiptId == null ? '' : ' [receiptId: $receiptId]'}';
}

/// Ausgang eines gescheiterten Aufrufs. [rejected]: nichts geschehen.
/// [unknown]: der Vorgang kann ausgefuehrt sein (ein Beleg signiert, ein
/// Storno gebucht); **nie wiederholen**, sondern das Ergebnis nachlesen.
enum ErrorOutcome { unknown, rejected }

/// Codes, deren Ausgang unklar ist. `response_translation_failed` nur, wenn
/// der Rand nicht ausdruecklich `handled: false` meldet (Handler lief und
/// lehnte ab); `handled: true` oder `null` heisst ausgefuehrt bzw. unbekannt.
const Set<String> _ausgangUnklarCodes = {
  'dialect_mismatch',
  'receipt_outcome_unknown',
  'cancellation_outcome_unknown',
  'response_unreadable',
};

ErrorOutcome _ausgangAusCode(String? code, Map<String, dynamic> details) {
  if (code == null) return ErrorOutcome.rejected;
  if (_ausgangUnklarCodes.contains(code)) return ErrorOutcome.unknown;
  if (code == 'response_translation_failed' && details['handled'] != false) return ErrorOutcome.unknown;
  return ErrorOutcome.rejected;
}

/// Codes, die das Paket selbst vergibt, nicht der Server: `route_missing`
/// (HTML statt Backend, der Aufruf kam nie an) und `response_unreadable`
/// (ein signierender Aufruf meldete Erfolg, die Antwort ist aber unlesbar).
/// `dialect_mismatch` vergibt das Paket ebenfalls, der Code gehoert aber zum
/// Rand des Servers.
const Set<String> clientErrorCodes = {'route_missing', 'response_unreadable'};

/// Ist der Ausgang dieses Fehlers unklar? Dann den Aufruf **nicht
/// wiederholen**, sondern das Ergebnis nachlesen. Gilt fuer jede Fehlerart;
/// nur [KasseneckApiError] und [KasseneckHttpError] koennen unklar sein.
///
/// **Noch nicht** fuer Einlesefehler nach der Signatur:
/// [KasseneckReceiptFormatError] und `KasseneckValidationError` mit
/// `kind: 'response'` und `receiptId` liefern hier `false`, obwohl der Beleg
/// bzw. Storno existiert. Bis sie als `response_unreadable` kommen, gilt fuer
/// sie ebenfalls: nachlesen, nie wiederholen.
bool isOutcomeUnknown(Object? error) =>
    (error is KasseneckApiError && error.outcome == ErrorOutcome.unknown) ||
    (error is KasseneckHttpError && error.outcome == ErrorOutcome.unknown);

/// Fachlicher Fehler des Backends (PIN falsch, Kasse belegt, Geraet gesperrt …).
///
/// Das Paket vergibt selbst zwei Codes: `route_missing` (HTTP 200 mit einer
/// HTML-Seite, die Auffangregel des Hostings hat geantwortet, keine Function
/// sah den Aufruf) und `dialect_mismatch` (die Antwort traegt das
/// `/v3`-Kennzeichen nicht; ein Rand ohne `/v3` hat geantwortet, Ausgang
/// unklar). Entscheidend ist [outcome].
class KasseneckApiError implements Exception {
  const KasseneckApiError(this.functionName, this.message, {this.code, this.details = const {}});

  final String functionName;
  final String message;

  /// Stabiler Fehlercode des Backends (`code` aus der Antworthuelle), wenn der
  /// Endpunkt einen legt — heute `cancelReceipt` (siehe `cancellationErrorCodes`).
  /// **Daran entscheiden, nie an [message]:** der Text darf sich aendern, der
  /// Code nicht. Null bei Endpunkten ohne Codes und bei Auth-/Parameterfehlern.
  final String? code;

  /// Die uebrige Nutzlast der Fehlerantwort (`data`), immer ein Objekt: etwa
  /// `errors` bei `validation`, `missing` bei `invoice_setup_incomplete` oder
  /// `remainingCents` bei `credit_exceeds_invoice` (Rechnungs-API). Zwilling
  /// von `KasseneckApiError.details` im JS-Paket.
  final Map<String, dynamic> details;

  /// [ErrorOutcome.unknown] bei `dialect_mismatch`, `receipt_outcome_unknown`,
  /// `cancellation_outcome_unknown`, `response_unreadable` und
  /// `response_translation_failed` (ausser mit `details.handled == false`);
  /// sonst [ErrorOutcome.rejected]. Bei unknown nie wiederholen, nachlesen.
  ErrorOutcome get outcome => _ausgangAusCode(code, details);

  @override
  String toString() => 'KasseneckApiError($functionName): $message${code == null ? '' : ' [$code]'}';
}

/// Der `code` einer Antworthuelle — nur ein nicht leerer Text zaehlt, alles
/// andere waere ein geratener Vertrag.
String? errorCodeFrom(Map<dynamic, dynamic> huelle) {
  final code = huelle['code'];
  return code is String && code.isNotEmpty ? code : null;
}

/// Ein Beleg kam an, liess sich aber nicht lesen — ein Pflichtfeld fehlt oder
/// hat den falschen Typ.
///
/// **Der Beleg existiert an dieser Stelle bereits.** Er ist signiert, steht in
/// der Signaturkette und im DEP; unbrauchbar ist nur die Antwort darueber. Ein
/// roher `TypeError` waere hier der schlimmste Fall: fuer den Aufrufer nicht von
/// „Verkauf fehlgeschlagen" zu unterscheiden, und mit der verworfenen Antwort
/// ginge die [receiptId] verloren — dann bliebe nichts, womit sich der Beleg
/// nachholen liesse, und der naheliegende zweite Versuch waere ein zweiter
/// Umsatz in der Signaturkette.
///
/// Deshalb traegt dieser Fehler die Kennung mit, sooft sie in der Antwort
/// stand. Sie ist der Faden zum Beleg: `KasseneckApi.getReceipt(receiptId)`
/// bzw. `RegisterReceiptClient.get(receiptId)` holt ihn nach.
class KasseneckReceiptFormatError implements Exception {
  const KasseneckReceiptFormatError(this.field, {this.receiptId, this.causeType});

  /// Das Feld, das fehlt oder den falschen Typ hat — nie sein Wert.
  final String field;

  /// Die Belegkennung, **sofern** sie in der Antwort stand. `null` heisst: der
  /// Beleg ist von hier aus nicht mehr auffindbar.
  final String? receiptId;

  /// Die **Art** der zugrunde liegenden Ausnahme (`TypeError`,
  /// `FormatException` …), wenn das Einlesen an einer anderen Stelle scheiterte.
  ///
  /// Nur der Typname, nie die Meldung: eine `FormatException` traegt ihre
  /// Eingabe im Text, und Antwortinhalte gehoeren nicht ins Protokoll — dieselbe
  /// Regel, die [KasseneckHttpError] befolgt.
  final String? causeType;

  @override
  String toString() => 'KasseneckReceiptFormatError('
      '${receiptId ?? 'ohne receiptId'}): '
      'Feld "$field" fehlt oder hat den falschen Typ'
      '${causeType == null ? '' : ' ($causeType)'}';
}

/// Die Antwort war keine brauchbare Huelle `{status, data}` oder der HTTP-Weg
/// scheiterte. Traegt bewusst **nichts** aus dem Rumpf: dort koennten Werte
/// stehen, die wir gerade nicht ins Protokoll lassen wollen.
class KasseneckHttpError implements Exception {
  const KasseneckHttpError(this.functionName, this.statusCode, this.reason,
      {this.causeType, this.outcome = ErrorOutcome.rejected, this.timeout});

  /// Die Frist ist abgelaufen. Die Anfrage war **draussen**; der Zeitablauf
  /// beendet nur das Warten, nicht die Arbeit des Servers. Ueber einem
  /// veraendernden Aufruf heisst das: der Beleg kann laengst signiert und in der
  /// Kette sein.
  static const String reasonTimeout = 'timeout';

  /// Der Transport ist gescheitert — Verbindung nicht zustande gekommen,
  /// abgebrochen, DNS, TLS.
  ///
  /// **Das ist keine Aussage, dass nichts passiert ist.** `package:http`
  /// trennt „Verbindung wurde nie hergestellt" nicht von „Verbindung riss,
  /// nachdem die Anfrage draussen war" — beides kommt als `ClientException`
  /// bzw. `SocketException` an. Wer daraus „der Beleg existiert sicher nicht"
  /// liest, macht denselben Fehler wie am 24.08. am Terminal: aus Nichtwissen
  /// eine Behauptung. Fuer einen veraendernden Aufruf gilt deshalb auch hier:
  /// nachsehen, nicht wiederholen.
  static const String reasonNetwork = 'network';

  final String functionName;
  final int statusCode;

  /// Warum es scheiterte: [reasonTimeout], [reasonNetwork], `'server-error'` (HTTP
  /// nicht 200), `'empty-body'`, `'not-json'`, `'missing-status'`,
  /// `'data-not-object'`.
  ///
  /// Die Unterscheidung [reasonTimeout] gegen [reasonNetwork] wird **erhalten**, nicht
  /// verworfen: sie ist die einzige Handhabe, die der Aufrufer hat. Welche
  /// Folge er daraus zieht, entscheidet er — dieses Paket entscheidet sie
  /// nicht fuer ihn, weil keiner der beiden Faelle beweist, dass nichts
  /// passiert ist (siehe [reasonNetwork]).
  final String reason;

  /// Die **Art** der zugrunde liegenden Ausnahme (`TimeoutException`,
  /// `SocketException`, `ClientException` …), sofern es eine gab.
  ///
  /// Nur der Typname, nie die Meldung — die kann Werte aus dem Rumpf tragen.
  /// Nach dem 24.08. war fehlendes Protokoll ausdruecklich das Problem; ein
  /// restlos verworfener Ursprungsfehler laesst sich hinterher nicht mehr
  /// rekonstruieren.
  final String? causeType;

  /// [ErrorOutcome.unknown] auf einem Aufruf mit Wirkung (`createReceipt`,
  /// `cancelReceipt`, `financeWebService`, `hobexPayApi`, `hobexRefundApi`,
  /// `stripeCaptureIntent`), wenn die Anfrage unterwegs war:
  /// Netzfehler oder Zeitlimit nach dem Senden, HTTP 5xx, oder eine
  /// unlesbare Antwort mit HTTP 200 und `/v3`-Kennzeichen (leer, kein JSON,
  /// ohne Statusfeld, HTML). Sonst [ErrorOutcome.rejected].
  final ErrorOutcome outcome;

  /// Die abgelaufene Frist, wenn [reason] [reasonTimeout] ist.
  final Duration? timeout;

  @override
  String toString() => 'KasseneckHttpError($functionName): HTTP $statusCode ($reason)'
      '${causeType == null ? '' : ' [$causeType]'}'
      '${outcome == ErrorOutcome.unknown ? ' [Ausgang unklar]' : ''}';
}

/// Liest die Erfolgsantwort eines **wirkenden** Aufrufs (Beleg, Storno,
/// Kartenbelastung). Scheitert das Lesen (fehlender Beleg, fehlender Bezug,
/// unbrauchbares Feld oder ein Laufzeitfehler beim Umwandeln), hat der Server
/// trotzdem Erfolg gemeldet: der Beleg ist signiert und im DEP, die Karte
/// belastet. Das darf nie als gewoehnlicher Fehler enden, sonst kassiert die
/// Kasse ein zweites Mal. Darum wird daraus [KasseneckApiError] mit Code
/// `response_unreadable` und Ausgang unklar (Zwilling von `signiertGelesen`
/// im npm-Paket).
///
/// Der Grund stammt vom Paket; aus der Antwort wird nichts uebernommen ausser
/// der Kennung des Belegs, soweit [receiptId] sie findet: `details.receiptId`
/// ist der Faden zum Beleg (`getReceipt`), `details.field` das Feld, an dem
/// das Lesen scheiterte.
T readSignedResponse<T>(String functionName, T Function() lesen, {String? Function()? receiptId}) {
  try {
    return lesen();
  } on KasseneckApiError {
    rethrow;
  } catch (ursache) {
    String? id;
    try {
      id = receiptId?.call();
    } catch (_) {
      id = null;
    }
    final (String grund, String? feld) = switch (ursache) {
      KasseneckValidationError(:final reason) => (reason, null),
      KasseneckReceiptFormatError(:final field) => ('Feld "$field" fehlt oder hat den falschen Typ', field),
      KasseneckHttpError(:final reason) => (reason, null),
      _ => ('Antwort nicht lesbar', null),
    };
    if (ursache is KasseneckReceiptFormatError) id ??= ursache.receiptId;
    if (ursache is KasseneckValidationError) id ??= ursache.receiptId;
    throw KasseneckApiError(
      functionName,
      'Erfolg gemeldet, Antwort aber unlesbar ($grund). Der Vorgang kann ausgefuehrt sein: '
      'nicht wiederholen, sondern nachlesen.',
      code: 'response_unreadable',
      details: {'receiptId': ?id, 'field': ?feld},
    );
  }
}
