/// DEP-Export fuer die Kassennachschau: der Vertrag der fuenf Endpunkte
/// `createDepExport`, `getDepExport`, `getDepExportFile`,
/// `createDepHandoverLink` und `revokeDepHandoverLink` (nur `/v3`). Seit 11.13
/// auf zwei Wegen: api_key + `cashregister-token` wie `listReceipts`
/// (`KasseneckApi`) und der Kassenweg mit der Kassen-Anmeldung
/// (`RegisterReceiptClient`, nur der Chef). Pruefung vor dem Senden, Warten
/// und Laden ueber den Lese-Link stehen hier einmal fuer beide.
///
/// Der Export laeuft im Hintergrund des Servers; der Aufrufer legt ihn an,
/// wartet ([KasseneckApi.waitForDepExport]) und holt die Dateien. Kleine
/// Dateien kommen direkt als Bytes, grosse als kurzlebiger Lese-Link mit
/// Pruefsumme -- diesem Link folgt das Paket selbst und prueft Groesse und
/// SHA-256, wo der Server sie nennt.
///
/// Aus der Antwort wird nichts erfunden: ein fehlendes oder fremdes Feld ist
/// `null`, eine Kennung oder Zahl, die da sein muss, ein Antwortfehler. Alle
/// Zeiten kommen als ISO 8601 in UTC (`2026-10-30T08:00:00.000Z`) und bleiben
/// Text.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

import '../lager/lesen.dart' show antwortfehler, ganzzahlVon, objekt;
import '../register/fehler.dart' show KasseneckHttpError, KasseneckValidationError;

/// Stabile Fehlercodes der fuenf Endpunkte unter `/v3` (Katalog
/// `dep_nachschau`). Sie kommen als `KasseneckApiError.code` an; der Code
/// eines fehlgeschlagenen Exports steht ausserdem in
/// [DepExportFailedException.error].
const Set<String> depExportErrorCodes = {
  'validation',
  'invalid_period',
  // Dieselbe requestId gehoert zu einem Export mit anderem Zeitraum.
  'idempotency_conflict',
  'export_running',
  'too_many_exports',
  'export_not_found',
  'export_not_ready',
  'export_failed',
  'invalid_file',
  'file_not_available',
  'too_many_links',
  'link_not_found',
  // Kassenweg (seit 11.13): nur der Chef exportiert, also der Inhaber oder ein
  // Kassen-Benutzer mit dem Recht `layout`; ein Geraet mit api_key nie.
  'manager_only',
  'server_error',
};

/// Werte von `status` eines Exports.
const String depExportRunning = 'running';
const String depExportDone = 'done';
const String depExportFailed = 'failed';

/// Die Dateien eines Exports (`file` von `getDepExportFile`): das DEP
/// (JSON), das Protokoll (PDF), die Positionen (CSV) und das ZIP mit allem.
const Set<String> depExportFiles = {'dep', 'protocol', 'items', 'zip'};

/// Ein Export, wie ihn `createDepExport` (nur Kennung, Status, Zeitraum) und
/// `getDepExport` liefern. Felder, die der Server erst nach dem Lauf kennt,
/// sind vorher `null`.
class DepExport {
  const DepExport({
    required this.exportId,
    required this.status,
    required this.from,
    required this.to,
    this.createdAt,
    this.finishedAt,
    this.receiptCount,
    this.counterFrom,
    this.counterTo,
    this.sha256,
    this.size,
    this.findings,
    this.items,
    this.handoverLinks = const [],
    this.error,
  });

  /// Kennung `DEP-YYYY-MM-DD-NNNN`.
  final String exportId;

  /// [depExportRunning], [depExportDone] oder [depExportFailed]; einen
  /// anderen Wert weist das Paket als Antwortfehler ab
  /// ([KasseneckValidationError], `kind: response`).
  final String status;

  /// Zeitraum, wie angefragt (`YYYY-MM-DD`); `null` = unbegrenzt.
  final String? from;
  final String? to;

  /// Beginn und Ende des Exports, ISO 8601 in UTC (`…Z`).
  final String? createdAt;
  final String? finishedAt;

  /// Belege im Export und der Bereich ihrer Belegzaehler.
  final int? receiptCount;
  final int? counterFrom;
  final int? counterTo;

  /// SHA-256 und Groesse (Bytes) der DEP-Datei.
  final String? sha256;
  final int? size;

  /// Befund der Pruefung: Luecken, Kettenbruch, Belege ohne Zaehler oder Signatur.
  final DepFindings? findings;

  /// Die Positionsdatei (CSV); `null` bei Exporten ohne Positionen.
  final DepExportItems? items;

  /// Die Pruefer-Links dieses Exports (`createDepHandoverLink`), ohne Code und Adresse.
  final List<DepHandoverLinkInfo> handoverLinks;

  /// Nur bei `failed`: `export_failed`, `export_stalled` oder ein Code des Exports.
  final String? error;

  bool get isDone => status == depExportDone;
  bool get isFailed => status == depExportFailed;
}

/// Befund eines Exports (`findings`): was an der Belegkette auffaellt.
class DepFindings {
  const DepFindings({
    required this.receiptCount,
    required this.counterFrom,
    required this.counterTo,
    required this.gaps,
    required this.chainBreaks,
    required this.withoutCounter,
    required this.withoutSignature,
  });

  final int? receiptCount;
  final int? counterFrom;
  final int? counterTo;

  /// Fehlende Belegzaehler als lueckenlose Bereiche (beide Enden einschliesslich).
  final List<DepCounterRange> gaps;

  /// Der erste Bruch der Signaturkette (hoechstens ein Eintrag).
  final List<DepChainBreak> chainBreaks;

  /// Kennungen der Belege ohne Zaehler bzw. ohne Signatur.
  final List<String> withoutCounter;
  final List<String> withoutSignature;

  /// Keine Auffaelligkeit.
  bool get isClean => gaps.isEmpty && chainBreaks.isEmpty && withoutCounter.isEmpty && withoutSignature.isEmpty;
}

class DepCounterRange {
  const DepCounterRange({required this.from, required this.to});
  final int from;
  final int to;
}

class DepChainBreak {
  const DepChainBreak({required this.counter, required this.expected, required this.found});
  final int? counter;
  final String? expected;
  final String? found;
}

/// Die Positionsdatei eines Exports.
class DepExportItems {
  const DepExportItems({required this.rowCount, required this.sha256, required this.size});
  final int? rowCount;
  final String? sha256;
  final int? size;
}

/// Ein Pruefer-Link, wie ihn `getDepExport` aufzaehlt. Code und Adresse
/// kennt nur die Antwort von `createDepHandoverLink`.
class DepHandoverLinkInfo {
  const DepHandoverLinkInfo({
    required this.linkId,
    required this.createdAt,
    required this.expiresAt,
    required this.revokedAt,
    required this.firstAccessAt,
    required this.accessCount,
  });

  final String linkId;

  /// Angelegt, gueltig bis, widerrufen und erster Abruf, je ISO 8601 in UTC (`…Z`).
  final String? createdAt;
  final String? expiresAt;
  final String? revokedAt;
  final String? firstAccessAt;
  final int accessCount;
}

/// Ein neuer Pruefer-Link: Adresse (das Geheimnis steht im Fragment), der
/// 6-stellige Code und der Ablauf (14 Tage). Den Code zeigt die Kasse dem
/// Pruefer; **beides ist nur in dieser Antwort zu haben** und gehoert weder in
/// ein Protokoll noch in eine Mail.
class DepHandoverLink {
  const DepHandoverLink({required this.linkId, required this.url, required this.code, required this.expiresAt});

  final String linkId;
  final String url;
  final String code;

  /// Ablauf des Links (14 Tage), ISO 8601 in UTC (`…Z`); fehlt er, ist die
  /// Antwort unbrauchbar.
  final String expiresAt;

  // Adresse und Code nie in einem Protokoll: toString nennt nur die Kennung.
  @override
  String toString() => 'DepHandoverLink($linkId)';
}

/// Antwort von `revokeDepHandoverLink`.
class DepHandoverRevocation {
  const DepHandoverRevocation({required this.linkId, required this.revokedAt});
  final String linkId;

  /// Zeitpunkt des Widerrufs, ISO 8601 in UTC (`…Z`); ein zweiter Widerruf nennt den ersten.
  final String? revokedAt;
}

/// Eine heruntergeladene Datei eines Exports.
class DepExportFile {
  const DepExportFile({required this.bytes, required this.fileName, required this.contentType});

  final Uint8List bytes;
  final String fileName;
  final String contentType;
}

/// Der Export ist fehlgeschlagen ([error]: `export_failed`, `export_stalled`
/// oder ein Code des Exports); ein neuer Export mit neuer `requestId` ist
/// moeglich.
class DepExportFailedException implements Exception {
  const DepExportFailedException(this.exportId, this.error);

  final String exportId;
  final String error;

  @override
  String toString() => 'DepExportFailedException($exportId): $error';
}

/// [KasseneckApi.waitForDepExport] gab auf, bevor der Export fertig war. Der
/// Export laeuft serverseitig weiter; `getDepExport(exportId)` fragt ihn
/// spaeter noch einmal ab.
class DepExportTimeoutException implements Exception {
  const DepExportTimeoutException(this.exportId, this.timeout);

  final String exportId;
  final Duration timeout;

  @override
  String toString() => 'DepExportTimeoutException($exportId): nach ${timeout.inSeconds} s nicht fertig';
}

/// Der Lese-Link einer grossen Datei (`getDepExportFile` mit `download`).
class DepDownloadLink {
  const DepDownloadLink({
    required this.url,
    required this.expiresAt,
    required this.size,
    required this.sha256,
    required this.fileName,
    required this.contentType,
  });

  final String url;

  /// Ablauf des Links (15 Minuten), ISO 8601 in UTC (`…Z`); fehlt er, ist die Antwort unbrauchbar.
  final String expiresAt;
  final int? size;
  final String? sha256;
  final String fileName;
  final String contentType;
}

// ---- Eingaben (vor dem Senden) ---------------------------------------------

KasseneckValidationError _eingabefehler(String name, String grund) => KasseneckValidationError(name, grund, 'request');

final RegExp _tag = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final RegExp _anfrageId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
final RegExp _sha256 = RegExp(r'^[0-9a-fA-F]{64}$');

// Ein echter Kalendertag `JJJJ-MM-TT` (kein 30.02.), ohne Zeitzone gerechnet.
bool _istKalendertag(String text) {
  if (!_tag.hasMatch(text)) return false;
  final teile = text.split('-').map(int.parse).toList();
  final d = DateTime.utc(teile[0], teile[1], teile[2]);
  return d.year == teile[0] && d.month == teile[1] && d.day == teile[2];
}

/// Prueft Zeitraum und requestId von `createDepExport` vor dem Senden (wie das
/// npm-Paket): echte Tage `JJJJ-MM-TT`, [to] nicht vor [from], [requestId]
/// hoechstens 64 Zeichen aus `A-Z a-z 0-9 _ -`.
void pruefeDepExportEingabe(String name, {String? from, String? to, String? requestId}) {
  if (from != null && !_istKalendertag(from)) throw _eingabefehler(name, 'from muss ein Datum JJJJ-MM-TT sein');
  if (to != null && !_istKalendertag(to)) throw _eingabefehler(name, 'to muss ein Datum JJJJ-MM-TT sein');
  if (from != null && to != null && to.compareTo(from) < 0) throw _eingabefehler(name, 'to liegt vor from');
  if (requestId != null && !_anfrageId.hasMatch(requestId)) {
    throw _eingabefehler(name, 'requestId: hoechstens 64 Zeichen aus A-Z, a-z, 0-9, _ und -');
  }
}

/// Eine Kennung (exportId, linkId), die nicht leer sein darf.
void pruefeDepKennung(String name, String feld, String wert) {
  if (wert.trim().isEmpty) throw _eingabefehler(name, '$feld fehlt oder ist leer');
}

/// Eine Frist, die positiv sein muss.
void pruefeDepFrist(String name, String feld, Duration wert) {
  if (wert <= Duration.zero) throw _eingabefehler(name, '$feld muss positiv sein');
}

/// Eine bekannte SHA-256-Pruefsumme (64 Hexzeichen), klein geschrieben; `null` bleibt `null`.
String? pruefeDepSha256(String name, String? wert) {
  if (wert == null) return null;
  if (!_sha256.hasMatch(wert)) throw _eingabefehler(name, 'sha256 muss 64 Hexzeichen haben');
  return wert.toLowerCase();
}

/// Prueft die Eingaben von `getDepExportFile` vor dem Senden (Kennung, Datei,
/// Pruefsumme, Frist) und liefert die bekannte Pruefsumme klein geschrieben
/// oder `null`.
String? pruefeDepDateiEingabe(
  String name, {
  required String exportId,
  required String file,
  required String? sha256,
  required Duration downloadTimeout,
}) {
  pruefeDepKennung(name, 'exportId', exportId);
  if (!depExportFiles.contains(file)) throw _eingabefehler(name, 'file muss dep, protocol, items oder zip sein');
  final bekannt = pruefeDepSha256(name, sha256);
  pruefeDepFrist(name, 'downloadTimeout', downloadTimeout);
  return bekannt;
}

// ---- Warten ----------------------------------------------------------------

/// Wartet, bis der Export fertig ist, und liefert ihn; [abfrage] ist
/// `getDepExport` des jeweiligen Wegs.
///
/// Fragt sofort, dann nach 2 s, mit je 1,5-fachem Abstand, hoechstens alle
/// 15 s; die letzte Pause endet auf der Frist. `failed` wirft
/// [DepExportFailedException], die Frist [DepExportTimeoutException]. Ein
/// Fehler der Abfrage geht unveraendert durch und beendet das Warten; der
/// Export laeuft serverseitig weiter.
Future<DepExport> depAbwarten(
  String exportId,
  Duration timeout,
  Future<DepExport> Function(String exportId) abfrage,
) async {
  pruefeDepKennung('waitForDepExport', 'exportId', exportId);
  pruefeDepFrist('waitForDepExport', 'timeout', timeout);
  var abstand = const Duration(seconds: 2);
  const hoechstens = Duration(seconds: 15);
  // Der Fortschritt zaehlt die Wartezeiten mit: die Uhr des Geraets allein
  // liesse sich in Tests nicht vorstellen, und Abfragezeit zaehlt die Stoppuhr.
  final uhr = Stopwatch()..start();
  var gewartet = Duration.zero;
  for (;;) {
    final stand = await abfrage(exportId);
    if (stand.isDone) return stand;
    if (stand.isFailed) {
      throw DepExportFailedException(exportId, stand.error ?? 'export_failed');
    }
    final vergangen = uhr.elapsed > gewartet ? uhr.elapsed : gewartet;
    if (vergangen >= timeout) throw DepExportTimeoutException(exportId, timeout);
    final rest = timeout - vergangen;
    final pause = abstand < rest ? abstand : rest;
    await Future<void>.delayed(pause);
    gewartet += pause;
    final naechster = Duration(milliseconds: (abstand.inMilliseconds * 1.5).round());
    abstand = naechster > hoechstens ? hoechstens : naechster;
  }
}

// ---- Lesen -----------------------------------------------------------------

String? _text(Object? w) => w is String && w.isNotEmpty ? w : null;

String _kennung(String name, String feld, Object? w) {
  if (w is! String || w.isEmpty) throw antwortfehler(name, 'Antwort enthaelt keine Kennung (data.$feld fehlt)');
  return w;
}

List<String> _texte(Object? w) => w is List
    ? [
        for (final e in w)
          if (e is String) e,
      ]
    : const [];

const Set<String> _statuswerte = {depExportRunning, depExportDone, depExportFailed};

/// Ein Export aus `data` von `createDepExport` oder `getDepExport`. Ein
/// unbekannter Status ist ein Antwortfehler (wie im npm-Paket): als „laeuft
/// noch“ gelesen, wartete [KasseneckApi.waitForDepExport] bis zur Frist.
DepExport depExportAus(String name, Map<String, dynamic> d) {
  final status = _text(d['status']);
  if (status == null) throw antwortfehler(name, 'Antwort ist unbrauchbar (data.status fehlt)');
  if (!_statuswerte.contains(status)) throw antwortfehler(name, 'Antwort ist unbrauchbar (unbekannter data.status)');
  final befund = objekt(d['findings']);
  final positionen = objekt(d['items']);
  return DepExport(
    exportId: _kennung(name, 'exportId', d['exportId']),
    status: status,
    from: _text(d['from']),
    to: _text(d['to']),
    createdAt: _text(d['createdAt']),
    finishedAt: _text(d['finishedAt']),
    receiptCount: ganzzahlVon(d['receiptCount']),
    counterFrom: ganzzahlVon(d['counterFrom']),
    counterTo: ganzzahlVon(d['counterTo']),
    sha256: _text(d['sha256']),
    size: ganzzahlVon(d['size']),
    findings: befund == null ? null : _befund(befund),
    items: positionen == null
        ? null
        : DepExportItems(
            rowCount: ganzzahlVon(positionen['rowCount']),
            sha256: _text(positionen['sha256']),
            size: ganzzahlVon(positionen['size']),
          ),
    handoverLinks: [
      for (final l in (d['handoverLinks'] is List ? d['handoverLinks'] as List : const []))
        if (objekt(l) case final o?) _linkInfo(name, o),
    ],
    error: _text(d['error']),
  );
}

DepFindings _befund(Map<String, dynamic> b) => DepFindings(
  receiptCount: ganzzahlVon(b['receiptCount']),
  counterFrom: ganzzahlVon(b['counterFrom']),
  counterTo: ganzzahlVon(b['counterTo']),
  gaps: [
    for (final g in (b['gaps'] is List ? b['gaps'] as List : const []))
      if (objekt(g) case final o?)
        if (ganzzahlVon(o['from']) case final von?)
          if (ganzzahlVon(o['to']) case final bis?) DepCounterRange(from: von, to: bis),
  ],
  chainBreaks: [
    for (final k in (b['chainBreaks'] is List ? b['chainBreaks'] as List : const []))
      if (objekt(k) case final o?)
        DepChainBreak(counter: ganzzahlVon(o['counter']), expected: _text(o['expected']), found: _text(o['found'])),
  ],
  withoutCounter: _texte(b['withoutCounter']),
  withoutSignature: _texte(b['withoutSignature']),
);

DepHandoverLinkInfo _linkInfo(String name, Map<String, dynamic> l) => DepHandoverLinkInfo(
  linkId: _kennung(name, 'handoverLinks[].linkId', l['linkId']),
  createdAt: _text(l['createdAt']),
  expiresAt: _text(l['expiresAt']),
  revokedAt: _text(l['revokedAt']),
  firstAccessAt: _text(l['firstAccessAt']),
  accessCount: ganzzahlVon(l['accessCount']) ?? 0,
);

DepHandoverLink depHandoverLinkAus(String name, Map<String, dynamic> d) {
  final url = d['url'];
  final code = d['code'];
  final ablauf = _text(d['expiresAt']);
  if (url is! String || url.isEmpty || code is! String || code.isEmpty || ablauf == null) {
    throw antwortfehler(name, 'Antwort ist unbrauchbar (data.url, data.code oder data.expiresAt fehlt)');
  }
  return DepHandoverLink(
    linkId: _kennung(name, 'linkId', d['linkId']),
    url: url,
    code: code,
    expiresAt: ablauf,
  );
}

DepHandoverRevocation depWiderrufAus(String name, Map<String, dynamic> d) =>
    DepHandoverRevocation(linkId: _kennung(name, 'linkId', d['linkId']), revokedAt: _text(d['revokedAt']));

// ---- Dateiantwort ----------------------------------------------------------

/// `filename="…"` aus `Content-Disposition`, ohne Pfadanteil.
String? _dateinameAusKopf(String? kopf) {
  if (kopf == null) return null;
  final m = RegExp(r'filename="?([^";]+)"?', caseSensitive: false).firstMatch(kopf);
  return m == null ? null : _nurName(m.group(1)!);
}

// Ein Dateiname vom Server wird nie als Pfad benutzt: nur der letzte Teil.
String _nurName(String s) {
  final teile = s.split(RegExp(r'[\\/]'));
  return teile.last;
}

String _endung(String file) => switch (file) {
  'dep' => '.json',
  'protocol' => '.pdf',
  'items' => '_positionen.csv',
  _ => '.zip',
};

/// Ist die Antwort von `getDepExportFile` eine Huelle `{status, ...}` (Fehler
/// oder Lese-Link) statt der Datei selbst? Entschieden wird am Inhalt, nicht am
/// Inhaltstyp: auch das DEP ist JSON, traegt aber kein `status` an der Wurzel.
bool depAntwortIstHuelle(http.Response antwort) {
  final typ = (antwort.headers['content-type'] ?? '').toLowerCase();
  if (!typ.startsWith('application/json')) return false;
  try {
    final roh = jsonDecode(utf8.decode(antwort.bodyBytes));
    return roh is Map && (roh['status'] == 'success' || roh['status'] == 'error');
  } on Object {
    return false;
  }
}

/// Die Datei, die der Server direkt ausgeliefert hat (Bytes, Name und Typ aus
/// den Kopfzeilen; ohne `Content-Disposition` ein Name aus Kennung und Art).
DepExportFile depDirekteDatei(String exportId, String file, http.Response antwort) => DepExportFile(
  bytes: antwort.bodyBytes,
  fileName: _dateinameAusKopf(antwort.headers['content-disposition']) ?? '$exportId${_endung(file)}',
  contentType: antwort.headers['content-type'] ?? 'application/octet-stream',
);

/// Der Lese-Link aus der Erfolgshuelle von `getDepExportFile`.
DepDownloadLink depLeseLink(String name, String exportId, String file, Map<String, dynamic> huelle) {
  final daten = objekt(huelle['data']);
  final dl = daten == null ? null : objekt(daten['download']);
  if (dl == null) throw antwortfehler(name, 'Antwort ist unbrauchbar (data.download fehlt)');
  return _downloadLink(name, exportId, file, dl);
}

// Der signierte Link geht nur ueber https; http nur fuer den lokalen Storage-Emulator.
bool _linkErlaubt(Uri uri) {
  if (uri.host.isEmpty) return false;
  if (uri.scheme == 'https') return true;
  return uri.scheme == 'http' && (uri.host == 'localhost' || uri.host == '127.0.0.1');
}

DepDownloadLink _downloadLink(String name, String exportId, String file, Map<String, dynamic> dl) {
  final url = dl['url'];
  final uri = url is String ? Uri.tryParse(url) : null;
  if (uri == null || !_linkErlaubt(uri)) {
    throw antwortfehler(name, 'Antwort ist unbrauchbar (data.download.url)');
  }
  final sha = dl['sha256'];
  if (sha != null && !(sha is String && _sha256.hasMatch(sha))) {
    throw antwortfehler(name, 'Antwort ist unbrauchbar (data.download.sha256)');
  }
  final ablauf = _text(dl['expiresAt']);
  if (ablauf == null) throw antwortfehler(name, 'Antwort ist unbrauchbar (data.download.expiresAt fehlt)');
  final name0 = _text(dl['fileName']);
  return DepDownloadLink(
    url: url as String,
    expiresAt: ablauf,
    size: ganzzahlVon(dl['size']),
    sha256: (sha as String?)?.toLowerCase(),
    fileName: name0 == null ? '$exportId${_endung(file)}' : _nurName(name0),
    contentType: _text(dl['contentType']) ?? 'application/octet-stream',
  );
}

// ---- Datei holen -----------------------------------------------------------

/// Die Datei aus der Antwort von `getDepExportFile`, fuer beide Wege: direkt
/// ausgeliefert oder ueber den Lese-Link der Erfolgshuelle geladen
/// ([depLaden]), danach gegen [bekannt] geprueft (die Pruefsumme, die der
/// Aufrufer mitgab).
///
/// [erfolgsHuelle] liest die Huelle mit den Mitteln des Wegs und wirft deren
/// Fehler mit Code (`export_not_ready`, `manager_only`, ...); gerufen wird sie
/// nur, wenn die Antwort eine Huelle ist ([depAntwortIstHuelle]).
Future<DepExportFile> depDateiAusAntwort(
  String name, {
  required http.Client client,
  required String exportId,
  required String file,
  required http.Response antwort,
  required Map<String, dynamic> Function() erfolgsHuelle,
  required Duration frist,
  String? bekannt,
}) async {
  final DepExportFile datei;
  if (!depAntwortIstHuelle(antwort)) {
    datei = depDirekteDatei(exportId, file, antwort);
  } else {
    datei = await depLaden(client, name, depLeseLink(name, exportId, file, erfolgsHuelle()), frist);
  }
  if (bekannt != null && crypto.sha256.convert(datei.bytes).toString() != bekannt) {
    throw KasseneckValidationError(name, 'Pruefsumme der Datei passt nicht (SHA-256)', 'response');
  }
  return datei;
}

/// Laedt eine Datei ueber den signierten Lese-Link und prueft Groesse und
/// SHA-256, wo der Server sie nennt. [frist] deckt Kopf und Rumpf.
Future<DepExportFile> depLaden(
  http.Client client,
  String name,
  DepDownloadLink link,
  Duration frist,
) async {
  // Ohne Kopfzeilen des Backends: die Adresse ist signiert und gehoert dem
  // Speicherdienst. api_key, Kassen-Token, ID-Token und Kassen-Sitzung gehen
  // nie dorthin.
  final abbruch = Completer<void>();
  final anfrage = http.AbortableRequest('GET', Uri.parse(link.url), abortTrigger: abbruch.future);
  final http.Response antwort;
  try {
    antwort = await Future(() async => http.Response.fromStream(await client.send(anfrage))).timeout(
      frist,
      onTimeout: () {
        if (!abbruch.isCompleted) abbruch.complete();
        throw TimeoutException('download', frist);
      },
    );
  } on TimeoutException {
    throw KasseneckHttpError(name, 200, KasseneckHttpError.reasonTimeout, timeout: frist);
  } on Object catch (e) {
    throw KasseneckHttpError(name, 200, KasseneckHttpError.reasonNetwork, causeType: e.runtimeType.toString());
  }
  if (antwort.statusCode != 200) throw KasseneckHttpError(name, antwort.statusCode, 'server-error');
  final bytes = antwort.bodyBytes;
  if (link.size != null && bytes.length != link.size) {
    throw KasseneckValidationError(name, 'Dateigroesse weicht von der Angabe des Servers ab', 'response');
  }
  if (link.sha256 != null && crypto.sha256.convert(bytes).toString() != link.sha256) {
    throw KasseneckValidationError(name, 'Pruefsumme der Datei passt nicht (SHA-256)', 'response');
  }
  return DepExportFile(bytes: bytes, fileName: link.fileName, contentType: link.contentType);
}
