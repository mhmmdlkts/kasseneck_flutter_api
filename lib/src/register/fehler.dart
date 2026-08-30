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

/// Fachlicher Fehler des Backends (PIN falsch, Kasse belegt, Geraet gesperrt ...).
///
/// [code] und [details] tragen die maschinenlesbare Beilage aus `data`. Die
/// Partner-API legt ihre Entscheidung naemlich nicht in den Text, sondern in
/// `data.code` (`vertrag_offen`, `signature_not_ready`, `activation_failed`
/// samt `data.schritt`); ohne diese Felder muesste ein Aufrufer die deutsche
/// Meldung nach Zeichenketten durchsuchen -- die Art Kopplung, die beim
/// naechsten Formulierungsschliff still bricht.
///
/// Die Beilage wird **gesiebt** und nicht durchgereicht, siehe
/// [fehlerDetails]. Beide Felder sind zusaetzlich und haben Vorgabewerte:
/// bestehende Aufrufstellen bleiben unveraendert.
class KasseneckApiError implements Exception {
  const KasseneckApiError(
    this.functionName,
    this.message, {
    this.code,
    this.details = const <String, dynamic>{},
  });

  final String functionName;
  final String message;

  /// Maschinenlesbarer Fehlercode aus `data.code`; `null`, wenn die Antwort
  /// keinen fuehrt (die aelteren Endpunkte tun das nicht).
  final String? code;

  /// Die uebrige Beilage aus `data`, gesiebt. Nie `null`, notfalls leer.
  final Map<String, dynamic> details;

  @override
  String toString() => 'KasseneckApiError($functionName)'
      '${code == null ? '' : ' [$code]'}: $message';
}

/// Grenzen des Siebs. Benannt, weil ein Test sie namentlich prueft -- eine
/// spaeter heraufgesetzte Grenze soll auffallen und nicht als Zahl im Code
/// untergehen.
const int kDetailTiefe = 4;
const int kDetailEintraege = 50;
const int kDetailTextMax = 300;
final RegExp _detailSchluessel = RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,63}$');

/// Siebt das `data` einer Fehlerantwort zu einer Form, die man gefahrlos an
/// einem Fehler mitfuehren kann.
///
/// Ein Fehler landet in Protokollen, und der Rumpf kommt ueber fremde Proxys.
/// Deshalb ueberlebt nur, was flach, klein und bezeichner-foermig benannt ist
/// -- und kein Wert, der mit einem der gesendeten [geheimnisse] ueberlappt.
/// Der Parameter hat aus demselben Grund **keinen** Vorgabewert: ein Sieb ohne
/// Abgleichliste waere nur ein Formfilter und damit keine Zusage.
Map<String, dynamic> fehlerDetails(Object? daten, List<String> geheimnisse) {
  final gesiebt = _sieben(daten, geheimnisse, 0);
  return gesiebt is Map<String, dynamic> ? gesiebt : <String, dynamic>{};
}

/// `_fehlt` statt `null`: `null` ist im Rumpf eine Aussage und muss von
/// "weggesiebt" unterscheidbar bleiben.
const Object _fehlt = Object();

Object? _sieben(Object? wert, List<String> geheimnisse, int tiefe) {
  if (wert == null || wert is bool) return wert;
  if (wert is num) return wert.isFinite ? wert : _fehlt;
  if (wert is String) {
    if (wert.length > kDetailTextMax) return _fehlt;
    for (final geheim in geheimnisse) {
      if (geheim.isNotEmpty && (geheim.contains(wert) || wert.contains(geheim))) return _fehlt;
    }
    return wert;
  }
  if (tiefe >= kDetailTiefe) return _fehlt;
  if (wert is List) {
    final liste = <dynamic>[];
    for (final eintrag in wert.take(kDetailEintraege)) {
      final s = _sieben(eintrag, geheimnisse, tiefe + 1);
      if (!identical(s, _fehlt)) liste.add(s);
    }
    return liste;
  }
  if (wert is Map) {
    final raus = <String, dynamic>{};
    for (final eintrag in wert.entries) {
      if (raus.length >= kDetailEintraege) break;
      final schluessel = eintrag.key;
      if (schluessel is! String || !_detailSchluessel.hasMatch(schluessel)) continue;
      final s = _sieben(eintrag.value, geheimnisse, tiefe + 1);
      if (identical(s, _fehlt)) continue;
      raus[schluessel] = s;
    }
    return raus;
  }
  return _fehlt;
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
/// bzw. `RegisterReceiptClient.holen(receiptId)` holt ihn nach.
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
  const KasseneckHttpError(this.functionName, this.statusCode, this.reason, {this.causeType});

  /// Die Frist ist abgelaufen. Die Anfrage war **draussen**; der Zeitablauf
  /// beendet nur das Warten, nicht die Arbeit des Servers. Ueber einem
  /// veraendernden Aufruf heisst das: der Beleg kann laengst signiert und in der
  /// Kette sein.
  static const String zeitablauf = 'timeout';

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
  static const String netz = 'network';

  final String functionName;
  final int statusCode;

  /// Warum es scheiterte: [zeitablauf], [netz], `'not-json'`,
  /// `'missing-status'`, `'data-not-object'`.
  ///
  /// Die Unterscheidung [zeitablauf] gegen [netz] wird **erhalten**, nicht
  /// verworfen: sie ist die einzige Handhabe, die der Aufrufer hat. Welche
  /// Folge er daraus zieht, entscheidet er — dieses Paket entscheidet sie
  /// nicht fuer ihn, weil keiner der beiden Faelle beweist, dass nichts
  /// passiert ist (siehe [netz]).
  final String reason;

  /// Die **Art** der zugrunde liegenden Ausnahme (`TimeoutException`,
  /// `SocketException`, `ClientException` …), sofern es eine gab.
  ///
  /// Nur der Typname, nie die Meldung — die kann Werte aus dem Rumpf tragen.
  /// Nach dem 24.08. war fehlendes Protokoll ausdruecklich das Problem; ein
  /// restlos verworfener Ursprungsfehler laesst sich hinterher nicht mehr
  /// rekonstruieren.
  final String? causeType;

  @override
  String toString() => 'KasseneckHttpError($functionName): HTTP $statusCode ($reason)'
      '${causeType == null ? '' : ' [$causeType]'}';
}
