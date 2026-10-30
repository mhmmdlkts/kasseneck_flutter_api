/// DEP-Export fuer die Kassennachschau: der Vertrag der fuenf Endpunkte
/// `createDepExport`, `getDepExport`, `getDepExportFile`,
/// `createDepHandoverLink` und `revokeDepHandoverLink` (nur `/v3`, api_key +
/// `cashregister-token` wie `listReceipts`).
///
/// Der Export laeuft im Hintergrund des Servers; der Aufrufer legt ihn an,
/// wartet ([KasseneckApi.waitForDepExport]) und holt die Dateien. Kleine
/// Dateien kommen direkt als Bytes, grosse als kurzlebiger Lese-Link mit
/// Pruefsumme -- diesem Link folgt das Paket selbst und prueft Groesse und
/// SHA-256, wo der Server sie nennt.
///
/// Aus der Antwort wird nichts erfunden: ein fehlendes oder fremdes Feld ist
/// `null`, eine Kennung oder Zahl, die da sein muss, ein Antwortfehler.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../lager/lesen.dart' show antwortfehler, ganzzahlVon, objekt;

/// Stabile Fehlercodes der fuenf Endpunkte unter `/v3` (Katalog
/// `dep_nachschau`). Sie kommen als `KasseneckApiError.code` an; der Code
/// eines fehlgeschlagenen Exports steht ausserdem in
/// [DepExportFailedException.error].
const Set<String> depExportErrorCodes = {
  'validation',
  'invalid_period',
  'export_running',
  'too_many_exports',
  'export_not_found',
  'export_not_ready',
  'export_failed',
  'invalid_file',
  'file_not_available',
  'too_many_links',
  'link_not_found',
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

  /// [depExportRunning], [depExportDone] oder [depExportFailed]; ein hier
  /// unbekannter Wert wird wie `running` behandelt, nie als fertig.
  final String status;

  /// Zeitraum, wie angefragt (`YYYY-MM-DD`); `null` = unbegrenzt.
  final String? from;
  final String? to;

  /// Wiener Wanduhr ohne Offset.
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
  final String? expiresAt;

  // Adresse und Code nie in einem Protokoll: toString nennt nur die Kennung.
  @override
  String toString() => 'DepHandoverLink($linkId)';
}

/// Antwort von `revokeDepHandoverLink`.
class DepHandoverRevocation {
  const DepHandoverRevocation({required this.linkId, required this.revokedAt});
  final String linkId;
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
  final String? expiresAt;
  final int? size;
  final String? sha256;
  final String fileName;
  final String contentType;
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

/// Ein Export aus `data` von `createDepExport` oder `getDepExport`.
DepExport depExportAus(String name, Map<String, dynamic> d) {
  final status = _text(d['status']);
  if (status == null) throw antwortfehler(name, 'Antwort ist unbrauchbar (data.status fehlt)');
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
  if (url is! String || url.isEmpty || code is! String || code.isEmpty) {
    throw antwortfehler(name, 'Antwort ist unbrauchbar (data.url oder data.code fehlt)');
  }
  return DepHandoverLink(
    linkId: _kennung(name, 'linkId', d['linkId']),
    url: url,
    code: code,
    expiresAt: _text(d['expiresAt']),
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

DepDownloadLink _downloadLink(String name, String exportId, String file, Map<String, dynamic> dl) {
  final url = dl['url'];
  final uri = url is String ? Uri.tryParse(url) : null;
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http') || uri.host.isEmpty) {
    throw antwortfehler(name, 'Antwort ist unbrauchbar (data.download.url)');
  }
  final sha = dl['sha256'];
  if (sha != null && !(sha is String && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha))) {
    throw antwortfehler(name, 'Antwort ist unbrauchbar (data.download.sha256)');
  }
  final name0 = _text(dl['fileName']);
  return DepDownloadLink(
    url: url as String,
    expiresAt: _text(dl['expiresAt']),
    size: ganzzahlVon(dl['size']),
    sha256: (sha as String?)?.toLowerCase(),
    fileName: name0 == null ? '$exportId${_endung(file)}' : _nurName(name0),
    contentType: _text(dl['contentType']) ?? 'application/octet-stream',
  );
}
