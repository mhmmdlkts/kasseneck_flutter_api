/// Ausgaben eines Belegs: auf welchem Weg ein Beleg den Betrieb verlassen hat
/// (Erstdruck, Duplikat, E-Mail, Link oder PDF geteilt, vom Kunden geoeffnet).
///
/// Registrierkassen-Erlass BMF-AV Nr. 2/2026, Abschnitt 4.2: die Art der
/// Belegerteilung ist zu dokumentieren. Das Protokoll fuehrt das Backend neben
/// dem Beleg (nie am Beleg, nie im DEP); die Kasse meldet ihre Drucke und das
/// Teilen mit `logReceiptOutputs`, `getReceipt` liefert unter `/v3` die
/// neuesten 20 Eintraege als `outputs`.
///
/// Zwilling von `models/receipt-output.ts` und `logReceiptOutputs` in
/// `@kreiseck/kasseneck-api` 1.14.0.
library;

import '../aufrufe.dart';
import '../receipt/codes.dart'
    show
        receiptOutputEntriesMax,
        receiptOutputEntryErrorCodes,
        receiptOutputErrorCodes,
        receiptOutputKinds,
        receiptOutputLogKinds,
        receiptOutputResults;
import '../register/codes.dart' show FieldError, fieldErrors;
import '../register/fehler.dart';

/// Wer die Ausgabe ausloeste: der Kassen-Benutzer, beim Geraet mit api_key
/// das Konto (`name` dann `null`).
class ReceiptOutputActor {
  const ReceiptOutputActor({required this.id, this.name});

  final String id;
  final String? name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  @override
  bool operator ==(Object other) => other is ReceiptOutputActor && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'ReceiptOutputActor($id, $name)';
}

/// Ein Eintrag aus `outputs` einer `getReceipt`-Antwort (`/v3`), gelesen am
/// Beleg (`KasseneckReceipt.outputs`). Eine Art oder ein Ergebnis, das dieses
/// Paket noch nicht kennt (neuerer Server), bleibt lesbar stehen; die Kasse
/// zeigt es ohne Beschriftung (`receiptOutputLabel` gibt dann `null`).
class ReceiptOutput {
  const ReceiptOutput({required this.kind, required this.at, required this.result, this.by, this.count});

  /// Meist aus [receiptOutputKinds]; ein fremder Wert bleibt erhalten.
  final String kind;

  /// Zeitpunkt, ISO 8601 mit Wiener Zonenoffset; bei Kassenmeldungen der
  /// Zeitpunkt am Geraet, beim Abruf der letzte der Stunde. Bewusst Text: der
  /// Offset ist Teil der Aussage.
  final String at;

  /// Meist aus [receiptOutputResults]; ein fremder Wert bleibt erhalten.
  final String result;

  /// `null` beim Abruf durch den Kunden.
  final ReceiptOutputActor? by;

  /// Nur bei `opened`: Zahl der Abrufe in dieser Stunde.
  final int? count;

  /// Die Form der Antwort (`count` nur, wenn gesetzt).
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'at': at,
        'result': result,
        'by': by?.toJson(),
        'count': ?count,
      };

  @override
  bool operator ==(Object other) =>
      other is ReceiptOutput &&
      other.kind == kind &&
      other.at == at &&
      other.result == result &&
      other.by == by &&
      other.count == count;

  @override
  int get hashCode => Object.hash(kind, at, result, by, count);

  @override
  String toString() => 'ReceiptOutput($kind, $at, $result, by: $by, count: $count)';
}

const int _groessteSichere = 9007199254740991;

/// Ganze Zahl im sicheren Bereich (wie `Number.isSafeInteger`), auch als
/// `3.0` gelesen; sonst `null`.
int? _ganzeZahl(Object? w) {
  if (w is int) return w.abs() <= _groessteSichere ? w : null;
  if (w is double && w.isFinite && w == w.truncateToDouble() && w.abs() <= _groessteSichere) return w.toInt();
  return null;
}

/// Liest `data.outputs` **nachsichtig**: das Protokoll ist eine Auskunft
/// neben dem Beleg und darf das Lesen, Anzeigen und Nachdrucken des Belegs nie
/// scheitern lassen. Keine Liste: `null` (Antwort ohne Protokoll, etwa der
/// Verkauf). Ein Eintrag ohne lesbare Art, Zeit oder Ergebnis faellt weg; ein
/// Handelnder ohne Kennung gilt als `null`, eine Anzahl, die keine ganze Zahl
/// ab 0 ist, fehlt. Dieselbe Regel wie `receiptOutputsFromWire` im npm-Paket.
/// Paketintern.
List<ReceiptOutput>? ausgabenLesen(Object? roh) {
  if (roh is! List) return null;
  final raus = <ReceiptOutput>[];
  for (final e in roh) {
    if (e is! Map) continue;
    final kind = e['kind'];
    final at = e['at'];
    final result = e['result'];
    if (kind is! String || kind.isEmpty || at is! String || at.isEmpty || result is! String || result.isEmpty) continue;
    final anzahl = _ganzeZahl(e['count']);
    raus.add(ReceiptOutput(
      kind: kind,
      at: at,
      result: result,
      by: _handelnder(e['by']),
      count: anzahl != null && anzahl >= 0 ? anzahl : null,
    ));
  }
  return raus;
}

ReceiptOutputActor? _handelnder(Object? w) {
  if (w is! Map) return null;
  final id = w['id'];
  if (id is! String || id.isEmpty) return null;
  final name = w['name'];
  return ReceiptOutputActor(id: id, name: name is String ? name : null);
}

/// Idempotenzschluessel eines Eintrags, wie der Server ihn annimmt.
final RegExp _schluessel = RegExp(r'^[A-Za-z0-9_-]{8,64}$');

/// Zeitpunkt als Text: RFC 3339 mit Zone, bis zu sechs Nachkommastellen (wie
/// der Server).
final RegExp _zeitMitZone = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$');

/// Felder eines Eintrags, in der Reihenfolge des Vertrags.
const List<String> _eintragsfelder = ['key', 'receiptId', 'at', 'kind', 'result'];

/// Eine Ausgabe, wie die Kasse sie puffert und meldet: ein Druck oder ein
/// Teilen des Belegs. Siehe `RegisterReceiptClient.logReceiptOutputs`.
class ReceiptOutputEntry {
  const ReceiptOutputEntry({
    required this.key,
    required this.receiptId,
    required this.kind,
    required this.at,
    this.result,
  });

  /// Liest einen gepufferten Eintrag ([toJson]) zurueck, **streng**: ein
  /// unbekanntes Feld oder ein Feld mit falschem Typ wirft
  /// [KasseneckValidationError] (`kind: request`). Ein unbekanntes Feld ginge
  /// sonst still verloren (der Puffer haette etwas gemerkt, das nie gemeldet
  /// wird). Ob die Werte gueltig sind, prueft erst das Melden.
  factory ReceiptOutputEntry.fromJson(Map<String, dynamic> json) {
    const name = Aufrufe.logReceiptOutputs;
    for (final feld in json.keys) {
      if (!_eintragsfelder.contains(feld)) throw KasseneckValidationError(name, 'unbekanntes Feld "$feld"', 'request');
    }
    String text(String feld) {
      final w = json[feld];
      if (w is! String) throw KasseneckValidationError(name, '$feld muss ein Text sein', 'request');
      return w;
    }

    final at = json['at'];
    final ergebnis = json['result'];
    if (ergebnis != null && ergebnis is! String) {
      throw const KasseneckValidationError(name, 'result muss ein Text sein', 'request');
    }
    return ReceiptOutputEntry(
      key: text('key'),
      receiptId: text('receiptId'),
      kind: text('kind'),
      at: _ganzeZahl(at) ?? at ?? '',
      result: ergebnis as String?,
    );
  }

  /// Idempotenzschluessel des Eintrags, am Geraet beim Puffern vergeben und
  /// beim Nachsenden unveraendert: ein zweites Melden legt keinen zweiten
  /// Eintrag an. 8-64 Zeichen `[A-Za-z0-9_-]` (Regel des Servers); ein anderer
  /// Schluessel wirft vor dem Senden.
  final String key;

  /// Beleg in der Kasse der Anmeldung; ein Beleg einer anderen Kasse ist
  /// `receipt_not_found`.
  final String receiptId;

  /// `print` (Erstdruck), `reprint` (Duplikat, gedruckt mit
  /// `markAsDuplicate`), `link_shared`, `pdf_shared` ([receiptOutputLogKinds]).
  /// `email` und `opened` gehen hinaus und kommen als `invalid_output_kind`
  /// zurueck.
  final String kind;

  /// Zeitpunkt am Geraet: Millisekunden seit 1970 ([int]), ISO 8601 **mit
  /// Zone** ([String], `DateTime.now().toUtc().toIso8601String()`) oder
  /// [DateTime] (geht als Millisekunden hinaus, wie bei den Ladeoeffnungen).
  /// Text ohne Zone wirft vor dem Senden. Frueher als eine Minute vor der
  /// Belegzeit oder spaeter als fuenf Minuten nach dem Eingang:
  /// `output_time_out_of_range`.
  final Object at;

  /// Ergebnis eines Drucks: `ok`, `failed` (sicher nicht gedruckt) oder
  /// `unclear` (Ausgang offen). Pflicht bei `print` und `reprint` (sonst lehnt
  /// der Server den Eintrag mit `validation` ab); beim Teilen ohne Angabe `ok`.
  final String? result;

  /// Die Form am Draht und im Puffer; [ReceiptOutputEntry.fromJson] liest sie
  /// zurueck.
  Map<String, dynamic> toJson() => {
        'key': key,
        'receiptId': receiptId,
        'at': at is DateTime ? (at as DateTime).millisecondsSinceEpoch : at,
        'kind': kind,
        'result': ?result,
      };

  @override
  String toString() => 'ReceiptOutputEntry($key, $receiptId, $kind, $at, $result)';
}

/// Ein abgelehnter Eintrag: dauerhaft, aus dem Puffer nehmen und nicht noch
/// einmal senden.
class RejectedReceiptOutput {
  const RejectedReceiptOutput({required this.key, required this.code});

  final String key;

  /// Aus [receiptOutputEntryErrorCodes]; ein Code, den das Paket nicht kennt,
  /// bleibt lesbar.
  final String code;

  Map<String, dynamic> toJson() => {'key': key, 'code': code};

  @override
  bool operator ==(Object other) => other is RejectedReceiptOutput && other.key == key && other.code == code;

  @override
  int get hashCode => Object.hash(key, code);

  @override
  String toString() => 'RejectedReceiptOutput($key, $code)';
}

/// Antwort von `logReceiptOutputs`.
class LogReceiptOutputsResult {
  const LogReceiptOutputsResult({required this.accepted, required this.rejected});

  /// Angenommene Eintraege, auch die schon frueher gemeldeten (gleicher Schluessel).
  final int accepted;
  final List<RejectedReceiptOutput> rejected;

  Map<String, dynamic> toJson() => {
        'accepted': accepted,
        'rejected': [for (final r in rejected) r.toJson()],
      };

  @override
  String toString() => 'LogReceiptOutputsResult(accepted: $accepted, rejected: $rejected)';
}

/// Prueft die Eintraege vor dem Senden und gibt die Nutzlast `entries`.
///
/// Abgewiesen wird nur, was die ganze Anfrage scheitern liesse oder ohne Netz
/// sicher falsch ist: keine oder mehr als 50 Eintraege, ein fehlender Beleg,
/// ein Schluessel ausserhalb der Regel des Servers, eine Art oder ein Ergebnis
/// ausserhalb des Katalogs, eine Zeit, die weder ganze Millisekunden ab 0 noch
/// ISO 8601 mit Zone ist. Paketintern; die beiden Wege (Kasse und
/// `KasseneckApi`) pruefen damit gleich.
List<Map<String, dynamic>> ausgabenNutzlast(String name, List<ReceiptOutputEntry> entries) {
  KasseneckValidationError anfrage(String grund) => KasseneckValidationError(name, grund, 'request');
  if (entries.isEmpty || entries.length > receiptOutputEntriesMax) {
    throw anfrage('entries muss 1–$receiptOutputEntriesMax Eintraege haben');
  }
  return [
    for (final (i, e) in entries.indexed) _eintragPruefen(anfrage, 'entries[$i]', e),
  ];
}

Map<String, dynamic> _eintragPruefen(
    KasseneckValidationError Function(String) anfrage, String wo, ReceiptOutputEntry e) {
  // Schluessel und Beleg nie getrimmt: ein veraenderter Schluessel waere ein anderer.
  if (e.key.trim().isEmpty) throw anfrage('$wo.key fehlt');
  if (e.receiptId.trim().isEmpty) throw anfrage('$wo.receiptId fehlt');
  // Dieselbe Regel wie der Server: so traegt jede Antwort (`rejected[].key`)
  // genau den Schluessel, unter dem die Kasse den Eintrag puffert.
  if (!_schluessel.hasMatch(e.key)) throw anfrage('$wo.key muss 8–64 Zeichen [A-Za-z0-9_-] haben');
  // Ein Wert ausserhalb des Katalogs liesse den Rand die ganze Anfrage abweisen.
  if (!receiptOutputKinds.contains(e.kind)) throw anfrage('$wo.kind muss ${receiptOutputKinds.join(', ')} sein');
  final ergebnis = e.result;
  if (ergebnis != null && !receiptOutputResults.contains(ergebnis)) {
    throw anfrage('$wo.result muss ${receiptOutputResults.join(', ')} sein');
  }
  // Text nur als ISO 8601 mit Zone (Regel des Servers): ohne Zone waere die
  // Zeit je nach Geraet eine andere; das ist ein Fehler der Kasse, kein Fall
  // fuer den Puffer.
  final at = e.at;
  final ms = at is DateTime ? at.millisecondsSinceEpoch : (at is int ? at : null);
  final zeitOk = (ms != null && ms >= 0 && ms <= _groessteSichere) || (at is String && _zeitMitZone.hasMatch(at));
  if (!zeitOk) throw anfrage('$wo.at muss Millisekunden seit 1970 oder ISO 8601 mit Zone sein');
  return e.toJson();
}

/// Antwort von `logReceiptOutputs`, **streng**: `accepted` ganze Zahl ab 0,
/// `rejected` Liste aus Schluessel und Code, sonst Antwortfehler
/// (`kind: response`). Nie „0 angenommen“ aus einer kaputten Antwort: die
/// Kasse naehme sonst Eintraege aus dem Puffer, die nie gezaehlt wurden.
/// Zusatzfelder werden uebergangen. Paketintern.
LogReceiptOutputsResult ausgabenGemeldet(String name, Object? daten) {
  KasseneckValidationError antwort(String grund) => KasseneckValidationError(name, grund, 'response');
  if (daten is! Map) throw antwort('Antwort ist kein Objekt');
  final accepted = _ganzeZahl(daten['accepted']);
  if (accepted == null || accepted < 0) throw antwort('Antwort enthaelt keine Zahl accepted');
  final rejected = daten['rejected'];
  if (rejected is! List) throw antwort('Antwort enthaelt keine Liste rejected');
  return LogReceiptOutputsResult(accepted: accepted, rejected: [
    for (final (i, r) in rejected.indexed)
      if (r is Map && r['key'] is String && r['code'] is String && (r['code'] as String).isNotEmpty)
        RejectedReceiptOutput(key: r['key'] as String, code: r['code'] as String)
      else
        throw antwort('rejected[$i] ohne Schluessel oder Code'),
  ]);
}

/// Ist [value] ein Code aus [receiptOutputErrorCodes]?
bool isReceiptOutputErrorCode(Object? value) => value is String && receiptOutputErrorCodes.contains(value);

/// Der Code eines geworfenen Fehlers, wenn er in [receiptOutputErrorCodes]
/// steht; sonst `null`.
String? receiptOutputErrorCode(Object? error) =>
    error is KasseneckApiError && isReceiptOutputErrorCode(error.code) ? error.code : null;

/// Ohne [code]: traegt der Fehler ueberhaupt einen Code aus
/// [receiptOutputErrorCodes]?
bool isReceiptOutputError(Object? error, [String? code]) {
  final gefunden = receiptOutputErrorCode(error);
  return gefunden != null && (code == null || gefunden == code);
}

/// Die Feldfehler einer `validation`-Antwort von `logReceiptOutputs`; leer,
/// wenn es keine sind.
List<FieldError> receiptOutputFieldErrors(Object? error) => fieldErrors(error);
