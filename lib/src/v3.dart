/// Der gemeinsame Rand aller Kasseneck-Aufrufe unter `/v3`: Basen, Anfrage-
/// Kopfzeilen und die Pruefung der Antwort, **bevor** ihr Rumpf gelesen wird.
/// Zwilling von `src/client/transport.ts` im npm-Paket 1.0.
///
/// **Nur `/v3`, fail closed.** Jede Antwort muss das Kennzeichen
/// `Kasseneck-Api-Version: v3` tragen. Fehlt es, wirft der Transport
/// `dialect_mismatch` und liest nichts: ein Rand ohne `/v3` haette die
/// englischen Parameter deutsch gedeutet, und ob dabei ein Beleg entstand,
/// weiss niemand (Ausgang unklar). Eine HTML-Seite bei HTTP 200 ist
/// `route_missing`: die Auffangregel des Hostings hat geantwortet, keine
/// Function hat den Aufruf gesehen.
///
/// **Die beiden Kopfzeilen nur an Kasseneck-Basen.** Terminals, Drucker,
/// Connect und Bildabrufe bekommen sie nie; sie binden diese Datei nicht ein.
///
/// **Nichts wird wiederholt.** Bei Ausgang unklar nachlesen, nie ein zweites
/// Mal senden: ein Beleg ist nicht folgenlos wiederholbar.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'register/fehler.dart';

/// Basis der oeffentlichen API.
const String kPublicBaseUrl = 'https://api.kasseneck.at/v3';

/// Basis des Kassenwegs (Kanal `app`). Die Web-Kasse ruft denselben Weg im
/// gleichen Ursprung als `/api/v3`.
const String kPosBaseUrl = 'https://kasse.kasseneck.at/api/v3';

/// Version dieses Pakets, wie in `pubspec.yaml` (ein Test haelt beide gleich).
const String kPackageVersion = '10.0.0-dev';

const String _versionKopf = 'Kasseneck-Api-Version';
const String _clientKopf = 'Kasseneck-Client';
const String _versionWert = 'v3';

/// Hosts, die als Kasseneck-Basis gelten: nur https, ohne Port und ohne
/// Zugangsdaten. Proxys, Emulator und `127.0.0.1` bekommen keine Kopfzeilen.
const Set<String> _kasseneckHosts = {'api.kasseneck.at', 'kasse.kasseneck.at'};

/// Aufrufe, die signieren bzw. bei FinanzOnline etwas ausloesen. Scheitert
/// einer, nachdem die Anfrage unterwegs war, ist sein Ausgang offen.
const Set<String> signingCalls = {'createReceipt', 'cancelReceipt', 'financeWebService'};

/// Produkte, die das Backend in `Kasseneck-Client` zaehlt (Positivliste).
const Set<String> _clientProdukte = {'kasse-web', 'kasse-app', 'kasseneck-api', 'kasseneck_api'};
final RegExp _clientVersion = RegExp(r'^[0-9A-Za-z.+-]{1,40}$');
const int _clientMax = 64;

/// Ist [functionName] (auch mit Vorgang, `financeWebService/status_cashbox`)
/// ein signierender Aufruf?
bool isSigningCall(String functionName) => signingCalls.contains(functionName.split('/').first);

/// Ausgang einer unlesbaren Antwort, die der `/v3`-Rand mit HTTP 200 und
/// Kennzeichen geschickt hat: bei einem signierenden Aufruf kann der Handler
/// gelaufen sein.
ErrorOutcome unreadableOutcome(String functionName) =>
    isSigningCall(functionName) ? ErrorOutcome.unknown : ErrorOutcome.rejected;

/// Prueft eine eigene Basis beim Anlegen: sie muss nach Abschneiden
/// abschliessender Schraegstriche auf `/v3` enden (`/api/v3` eingeschlossen).
/// Ohne Angabe gilt [vorgabe].
String v3BaseUrl(String owner, String? basis, String vorgabe) {
  if (basis == null) return vorgabe;
  final ohne = basis.replaceAll(RegExp(r'/+$'), '');
  if (!ohne.endsWith('/v3')) {
    throw KasseneckValidationError(
      owner,
      'baseUrl muss auf /v3 oder /api/v3 enden (10.x spricht nur /v3; z. B. /api/v3 statt /api, /v3 statt /v1)',
      'request',
    );
  }
  return ohne;
}

/// Die Anfrage-Kopfzeilen eines Wegs, beim Anlegen einmal festgelegt.
class V3Headers {
  /// Prueft [clientHeader] gegen Positivliste und Form; wirft sonst
  /// [KasseneckValidationError] im Namen von [owner].
  V3Headers(String owner, {String? clientHeader, bool omit = false})
      : _kennung = clientHeader ?? 'kasseneck_api/$kPackageVersion',
        _weglassen = omit {
    final text = _kennung;
    final trenner = text.indexOf('/');
    final produkt = trenner > 0 ? text.substring(0, trenner) : '';
    final version = trenner > 0 ? text.substring(trenner + 1) : '';
    if (text.length > _clientMax || !_clientProdukte.contains(produkt) || !_clientVersion.hasMatch(version)) {
      throw KasseneckValidationError(
        owner,
        'clientHeader muss <produkt>/<version> sein (Produkt: kasse-web, kasse-app, kasseneck-api, kasseneck_api)',
        'request',
      );
    }
  }

  final String _kennung;
  final bool _weglassen;

  /// Die beiden Kasseneck-Kopfzeilen fuer [basis], oder keine.
  Map<String, String> fuer(String basis) =>
      !_weglassen && isKasseneckBase(basis) ? {_versionKopf: _versionWert, _clientKopf: _kennung} : const {};
}

/// Ist [basis] eine Kasseneck-Basis? Relativ (gleicher Ursprung) immer, ausser
/// `//host`; absolut nur die beiden https-Hosts ohne Port und Zugangsdaten.
bool isKasseneckBase(String basis) {
  if (basis.startsWith('//')) return false;
  final adresse = Uri.tryParse(basis);
  if (adresse == null) return false;
  if (!adresse.hasScheme) return true;
  return adresse.scheme == 'https' &&
      !adresse.hasPort &&
      adresse.userInfo.isEmpty &&
      _kasseneckHosts.contains(adresse.host);
}

/// Traegt die Antwort das Kennzeichen `v3`?
bool _traegtKennzeichen(http.BaseResponse antwort) =>
    (antwort.headers[_versionKopf.toLowerCase()] ?? '').trim().toLowerCase() == _versionWert;

/// Ein POST an `<basis>/<name>` samt Pruefung der Antwort. Liefert die
/// gelesene Antwort nur bei HTTP 200 mit Kennzeichen; sonst wirft er:
///
/// 1. HTTP != 200: [KasseneckHttpError] `server-error` (5xx auf einem
///    signierenden Aufruf mit Ausgang unklar). Einzige Ausnahme ist die
///    404-Huelle des Rands mit Kennzeichen und Code (`not_found`).
/// 2. HTTP 200 mit HTML ohne Kennzeichen: `route_missing`. Mit Kennzeichen
///    bei einem signierenden Aufruf: unlesbar, Ausgang unklar.
/// 3. Kein Kennzeichen: `dialect_mismatch`, Ausgang unklar.
///
/// In allen drei Faellen bleibt der Rumpf ungelesen (ausser der 404-Huelle).
/// Netzfehler und Zeitlimit werden [KasseneckHttpError] mit
/// [KasseneckHttpError.netz] bzw. [KasseneckHttpError.zeitablauf]; die Frist
/// deckt Senden **und** Lesen des Rumpfs.
Future<http.Response> v3Post(
  http.Client client, {
  required String functionName,
  required String basis,
  required String name,
  required Map<String, String> headers,
  required V3Headers kasseneck,
  required String body,
  required Duration timeout,
}) async {
  final request = http.Request('POST', Uri.parse('$basis/$name'));
  request.headers.addAll(_ohneKasseneckKopfzeilen(headers));
  request.headers.addAll(kasseneck.fuer(basis));
  request.body = body;
  final signierend = isSigningCall(functionName);
  final ausgangNetz = signierend ? ErrorOutcome.unknown : ErrorOutcome.rejected;

  Future<http.Response> ablauf() async {
    final http.StreamedResponse antwort;
    try {
      antwort = await client.send(request);
    } on Object catch (e) {
      throw _Netzfehler(e);
    }
    final inhaltstyp = antwort.headers['content-type'];
    if (antwort.statusCode != 200) {
      if (antwort.statusCode == 404 && _traegtKennzeichen(antwort)) {
        final fehler = await _randFehler404(functionName, antwort);
        if (fehler != null) throw fehler;
      }
      throw KasseneckHttpError(functionName, antwort.statusCode, 'server-error',
          outcome: antwort.statusCode >= 500 && signierend ? ErrorOutcome.unknown : ErrorOutcome.rejected);
    }
    if (inhaltstyp != null && RegExp(r'^\s*text/html\b', caseSensitive: false).hasMatch(inhaltstyp)) {
      if (signierend && _traegtKennzeichen(antwort)) {
        throw KasseneckHttpError(functionName, 200, 'not-json', outcome: ErrorOutcome.unknown);
      }
      throw KasseneckApiError(functionName, 'Route fehlt: die Antwort ist eine HTML-Seite statt des Backends',
          code: 'route_missing');
    }
    if (!_traegtKennzeichen(antwort)) {
      throw KasseneckApiError(
          functionName, 'Server spricht nicht /v3 (Kennzeichen fehlt); Antwort verworfen',
          code: 'dialect_mismatch');
    }
    try {
      return await http.Response.fromStream(antwort);
    } on Object catch (e) {
      throw _Netzfehler(e);
    }
  }

  try {
    return await ablauf().timeout(timeout);
  } on TimeoutException catch (e) {
    // Die Anfrage war draussen; das Zeitlimit beendet nur das Warten, nicht
    // die Arbeit des Servers.
    throw KasseneckHttpError(functionName, 0, KasseneckHttpError.zeitablauf,
        causeType: '${e.runtimeType}', outcome: ausgangNetz, timeout: timeout);
  } on _Netzfehler catch (e) {
    // Nur der Typ, nie die Meldung: die kann Werte des Rumpfs tragen.
    throw KasseneckHttpError(functionName, 0, KasseneckHttpError.netz,
        causeType: '${e.ursache.runtimeType}', outcome: ausgangNetz);
  }
}

class _Netzfehler implements Exception {
  _Netzfehler(this.ursache);
  final Object ursache;
}

/// Liest die 404-Huelle des Rands; liefert den fachlichen Fehler nur, wenn
/// es eine Fehlerhuelle mit Code ist.
Future<KasseneckApiError?> _randFehler404(String functionName, http.StreamedResponse antwort) async {
  try {
    final roh = jsonDecode(utf8.decode(await antwort.stream.toBytes()));
    if (roh is! Map || !roh.containsKey('status') || roh['status'] == 'success') return null;
    final fehler = envelopeError(functionName, Map<String, dynamic>.from(roh));
    return fehler.code == null ? null : fehler;
  } on Object {
    return null;
  }
}

/// Die Kasseneck-Kopfzeilen setzt allein der Transport; von aussen gelieferte
/// gleichnamige fallen weg (jede Schreibweise).
Map<String, String> _ohneKasseneckKopfzeilen(Map<String, String> kopfzeilen) {
  final gesperrt = {_versionKopf.toLowerCase(), _clientKopf.toLowerCase()};
  return {
    for (final e in kopfzeilen.entries)
      if (!gesperrt.contains(e.key.toLowerCase())) e.key: e.value,
  };
}

/// Die Huelle `{status, message, data, code}` einer gelesenen Antwort; wirft
/// [KasseneckHttpError] `empty-body`, `not-json` bzw. `missing-status`, bei
/// einem signierenden Aufruf mit Ausgang unklar.
Map<String, dynamic> readEnvelope(String functionName, http.Response antwort) {
  final ausgang = unreadableOutcome(functionName);
  final bytes = antwort.bodyBytes;
  if (utf8.decode(bytes, allowMalformed: true).trim().isEmpty) {
    throw KasseneckHttpError(functionName, antwort.statusCode, 'empty-body', outcome: ausgang);
  }
  final Object? roh;
  try {
    roh = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    // Der Rumpf selbst bleibt draussen: er gehoert nicht ins Protokoll.
    throw KasseneckHttpError(functionName, antwort.statusCode, 'not-json', outcome: ausgang);
  }
  if (roh is! Map || !roh.containsKey('status')) {
    throw KasseneckHttpError(functionName, antwort.statusCode, 'missing-status', outcome: ausgang);
  }
  return Map<String, dynamic>.from(roh);
}

/// Das `data`-Objekt einer Erfolgshuelle: fehlend ist leer, alles andere als
/// ein Objekt ist kaputt (`data-not-object`).
Map<String, dynamic> envelopeData(String functionName, Map<String, dynamic> huelle, int statusCode) {
  final daten = huelle['data'];
  if (daten == null) return <String, dynamic>{};
  if (daten is! Map) {
    throw KasseneckHttpError(functionName, statusCode, 'data-not-object', outcome: unreadableOutcome(functionName));
  }
  return Map<String, dynamic>.from(daten);
}

/// Der fachliche Fehler einer Huelle: Code neben `message`, sonst `data.code`;
/// `data` als Details (dort steht etwa `handled`).
KasseneckApiError envelopeError(String functionName, Map<String, dynamic> huelle, {String? fallback}) {
  final meldung = huelle['message'];
  final daten = huelle['data'];
  final datenCode = daten is Map && daten['code'] is String && (daten['code'] as String).isNotEmpty
      ? daten['code'] as String
      : null;
  return KasseneckApiError(
    functionName,
    meldung is String && meldung.isNotEmpty ? meldung : (fallback ?? 'Der Aufruf ist fehlgeschlagen.'),
    code: fehlercodeAus(huelle) ?? datenCode,
    details: daten is Map ? Map<String, dynamic>.from(daten) : const {},
  );
}
