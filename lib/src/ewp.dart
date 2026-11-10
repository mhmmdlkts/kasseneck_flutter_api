/// EWP-Meldung (Einwegpfand-Meldung): die Monatsmeldung der Einweg-Verpackungen
/// je GTIN, die ein Abfuellbetrieb dem Pfandsystem meldet (Faelligkeit am 5. des
/// Folgemonats). Nur unter `/v3`, mit dem API-Schluessel, nur fuer Betriebe mit
/// der Rolle Abfueller (sonst `filler_role_required`); einen Kassen-Token
/// braucht keiner der Aufrufe.
///
/// Die Meldung entsteht aus drei Quellen ([EwpLineSources]): den Belegen der
/// Kassen, den Rechnungen und den Lieferscheinen, dazu die Zusatzmengen, die das
/// Fremdsystem selbst nachtraegt (Haustrunk, Muster, Spende ...). Der laufende
/// Monat ist vorlaeufig ([EwpReport.provisional]). Mengen sind ganze Stueck.
///
/// Zwilling von `client/ewp.ts` im JS-Paket (npm 1.36.0). Antworten werden hier
/// zu Typen gelesen; was nicht lesbar ist, wirft ein [KasseneckValidationError]
/// (`kind: response`), nie einen rohen `TypeError`.
library;

import 'register/fehler.dart' show KasseneckValidationError;

/// Gruende einer Zusatzmenge, in der Reihenfolge des Backends.
const List<String> ewpReasons = [
  'own_consumption',
  'sampling',
  'donation',
  'theft',
  'free_goods',
  'stocktake',
  'return',
  'external_system',
  'other',
];

/// Warnungen der Meldung ([EwpWarning.code]); welche Angaben eine Warnung
/// traegt, steht an [EwpWarning].
const List<String> ewpWarningCodes = [
  'gtin_not_registered',
  'foreign_not_reportable',
  'master_data_missing',
  'negative_quantity',
  'invalid_posting',
];

/// Stammdaten einer GTIN fuer die Meldung; fehlende Angaben kommen als leerer Text.
class EwpMasterData {
  const EwpMasterData({
    this.barcodeType = '',
    this.productOrigin = '',
    this.depositFee = '',
    this.producerFee = '',
    this.ecoImpact = '',
    this.intBarcodeUsage = '',
  });

  factory EwpMasterData.fromJson(Map<String, dynamic> j) => EwpMasterData(
        barcodeType: _text(j['barcodeType']),
        productOrigin: _text(j['productOrigin']),
        depositFee: _text(j['depositFee']),
        producerFee: _text(j['producerFee']),
        ecoImpact: _text(j['ecoImpact']),
        intBarcodeUsage: _text(j['intBarcodeUsage']),
      );

  final String barcodeType;
  final String productOrigin;
  final String depositFee;
  final String producerFee;
  final String ecoImpact;
  final String intBarcodeUsage;
}

/// Woher die Menge einer Zeile kommt (Stueck): Kasse, Rechnungen,
/// Lieferscheine, Zusatzmengen.
class EwpLineSources {
  const EwpLineSources({this.register = 0, this.invoices = 0, this.deliveryNotes = 0, this.extra = 0});

  factory EwpLineSources.fromJson(Map<String, dynamic> j) => EwpLineSources(
        register: _zahl(j['register']),
        invoices: _zahl(j['invoices']),
        deliveryNotes: _zahl(j['deliveryNotes']),
        extra: _zahl(j['extra']),
      );

  final int register;
  final int invoices;
  final int deliveryNotes;
  final int extra;
}

/// Eine Zeile der Meldung: eine registrierte GTIN mit ihren Mengen im Inland
/// und Ausland.
class EwpLine {
  const EwpLine({
    required this.gtin,
    required this.name,
    this.masterData,
    required this.domestic,
    required this.foreign,
    required this.sources,
  });

  factory EwpLine.fromJson(Map<String, dynamic> j) {
    final stamm = j['masterData'];
    final quellen = j['sources'];
    return EwpLine(
      gtin: _pflichtText(j, 'gtin'),
      name: _pflichtText(j, 'name'),
      masterData: stamm is Map ? EwpMasterData.fromJson(_objekt(stamm)) : null,
      domestic: _pflichtZahl(j, 'domestic'),
      foreign: _pflichtZahl(j, 'foreign'),
      sources: quellen is Map ? EwpLineSources.fromJson(_objekt(quellen)) : const EwpLineSources(),
    );
  }

  final String gtin;
  final String name;

  /// Fehlt, wenn zur GTIN keine Stammdaten vorliegen.
  final EwpMasterData? masterData;
  final int domestic;
  final int foreign;
  final EwpLineSources sources;
}

/// Eine Warnung zur Meldung; sie sperrt nichts. Welche Angaben dabei stehen:
///
/// - `gtin_not_registered`: [gtin], [quantity] (die GTIN ist nicht registriert,
///   ihre Menge steht nicht in [EwpReport.lines])
/// - `foreign_not_reportable`: [gtin], [country], [quantity] (Auslandsmenge einer
///   oesterreichischen GTIN, nicht meldepflichtig)
/// - `master_data_missing`: [gtin], [fields] (die fehlenden Stammdaten)
/// - `negative_quantity`: [gtin], [column] (`domestic` oder `foreign`), [amount]
/// - `invalid_posting`: [count] (nicht lesbare Posten)
///
/// [code] ist einer aus [ewpWarningCodes]; ein Code, den dieses Paket nicht
/// kennt, bleibt wortwoertlich erhalten.
class EwpWarning {
  const EwpWarning({
    required this.code,
    this.gtin,
    this.country,
    this.quantity,
    this.fields,
    this.count,
    this.column,
    this.amount,
  });

  factory EwpWarning.fromJson(Map<String, dynamic> j) => EwpWarning(
        code: _pflichtText(j, 'code'),
        gtin: j['gtin'] is String ? j['gtin'] as String : null,
        country: j['country'] is String ? j['country'] as String : null,
        quantity: j['quantity'] is num ? (j['quantity'] as num).toInt() : null,
        fields: j['fields'] is List ? [for (final f in j['fields'] as List) if (f is String) f] : null,
        count: j['count'] is num ? (j['count'] as num).toInt() : null,
        column: j['column'] is String ? j['column'] as String : null,
        amount: j['amount'] is num ? (j['amount'] as num).toInt() : null,
      );

  final String code;
  final String? gtin;
  final String? country;
  final int? quantity;
  final List<String>? fields;
  final int? count;

  /// `domestic` oder `foreign`.
  final String? column;
  final int? amount;
}

/// Eine Zusatzmenge, wie die Meldung sie fuehrt.
class EwpExtraQuantity {
  const EwpExtraQuantity({
    required this.gtin,
    required this.domestic,
    required this.foreign,
    required this.reason,
    this.text,
    required this.at,
    this.by,
  });

  factory EwpExtraQuantity.fromJson(Map<String, dynamic> j) => EwpExtraQuantity(
        gtin: _pflichtText(j, 'gtin'),
        domestic: _pflichtZahl(j, 'domestic'),
        foreign: _pflichtZahl(j, 'foreign'),
        reason: _pflichtText(j, 'reason'),
        text: j['text'] is String ? j['text'] as String : null,
        at: _pflichtZahl(j, 'at'),
        by: j['by'] is String ? j['by'] as String : null,
      );

  final String gtin;
  final int domestic;
  final int foreign;

  /// Ein Wert aus [ewpReasons].
  final String reason;
  final String? text;

  /// Zeitpunkt des Eintrags (Millisekunden).
  final int at;

  /// Kennung des Absenders: die uid der Anmeldung im Panel, `'api'` fuer einen
  /// API-Schluessel; bei Altbestand `null`.
  final String? by;
}

/// Eine Zusatzmenge beim Setzen ([KasseneckApi.setEwpExtraQuantities]).
class EwpExtraQuantityInput {
  const EwpExtraQuantityInput({
    required this.gtin,
    required this.domestic,
    required this.foreign,
    required this.reason,
    this.text,
  });

  final String gtin;
  final int domestic;
  final int foreign;

  /// Ein Wert aus [ewpReasons]; die Pruefung macht der Server (`validation`
  /// mit Feldpfad), damit ein Grund, den dieses Paket noch nicht kennt, nicht
  /// schon hier scheitert.
  final String reason;

  /// Hoechstens 200 Zeichen.
  final String? text;

  Map<String, dynamic> toJson() => {
        'gtin': gtin,
        'domestic': domestic,
        'foreign': foreign,
        'reason': reason,
        if (text != null) 'text': text,
      };
}

/// Die Meldung eines Monats ([KasseneckApi.getEwpReport]).
class EwpReport {
  const EwpReport({
    required this.month,
    required this.dueDate,
    required this.provisional,
    required this.test,
    required this.lines,
    required this.warnings,
    required this.extraQuantities,
    this.downloadedAt,
  });

  /// Liest die Antwort von [call]; eine Antwort, die keine Meldung ist, wirft
  /// ein [KasseneckValidationError] (`kind: response`).
  factory EwpReport.fromJson(String call, Object? raw) {
    try {
      if (raw is! Map) throw const FormatException('Antwort ist kein Objekt');
      final j = _objekt(raw);
      if (j['month'] is! String) throw const FormatException('Antwort ohne month');
      return EwpReport(
        month: j['month'] as String,
        dueDate: _text(j['dueDate']),
        provisional: j['provisional'] == true,
        test: j['test'] == true,
        lines: [for (final e in _liste(j, 'lines')) EwpLine.fromJson(e)],
        warnings: [for (final e in _liste(j, 'warnings')) EwpWarning.fromJson(e)],
        extraQuantities: [for (final e in _liste(j, 'extraQuantities')) EwpExtraQuantity.fromJson(e)],
        downloadedAt: j['downloadedAt'] is num ? (j['downloadedAt'] as num).toInt() : null,
      );
    } on FormatException catch (e) {
      throw KasseneckValidationError(call, e.message, 'response');
    }
  }

  /// Meldemonat `YYYY-MM`.
  final String month;

  /// Faelligkeit `YYYY-MM-DD` (der 5. des Folgemonats).
  final String dueDate;

  /// Der Monat laeuft noch.
  final bool provisional;

  /// Die Meldung stammt aus der Test-Umgebung (`kr_test_`-Schluessel).
  final bool test;
  final List<EwpLine> lines;
  final List<EwpWarning> warnings;
  final List<EwpExtraQuantity> extraQuantities;

  /// Zeitpunkt (Millisekunden) des letzten CSV-Abrufs eines abgeschlossenen
  /// Monats, sonst `null`.
  final int? downloadedAt;
}

/// Die CSV der Meldung ([KasseneckApi.downloadEwpReport]).
class EwpReportFile {
  const EwpReportFile({required this.csv, required this.filename, required this.contentType});

  factory EwpReportFile.fromJson(String call, Object? raw) {
    if (raw is Map && raw['csv'] is String && raw['filename'] is String && raw['contentType'] is String) {
      return EwpReportFile(
          csv: raw['csv'] as String, filename: raw['filename'] as String, contentType: raw['contentType'] as String);
    }
    throw KasseneckValidationError(call, 'Antwort ohne csv, filename und contentType', 'response');
  }

  final String csv;
  final String filename;
  final String contentType;
}

/// Prueft den Monat vor dem Senden: leer ist ein Fehler der Anfrage.
String ewpMonat(String call, String? month) {
  if (month == null || month.isEmpty) {
    throw KasseneckValidationError(call, 'month fehlt (Monat als JJJJ-MM)', 'request');
  }
  return month;
}

// ---- Lesehilfen -----------------------------------------------------------------

Map<String, dynamic> _objekt(Map wert) => wert is Map<String, dynamic> ? wert : Map<String, dynamic>.from(wert);

String _text(Object? wert) => wert is String ? wert : '';

int _zahl(Object? wert) => wert is num ? wert.toInt() : 0;

String _pflichtText(Map<String, dynamic> j, String feld) {
  final wert = j[feld];
  if (wert is String) return wert;
  throw FormatException('Antwort ohne $feld');
}

int _pflichtZahl(Map<String, dynamic> j, String feld) {
  final wert = j[feld];
  if (wert is num) return wert.toInt();
  throw FormatException('Antwort ohne $feld');
}

List<Map<String, dynamic>> _liste(Map<String, dynamic> j, String feld) {
  final wert = j[feld];
  if (wert is! List) throw FormatException('Antwort ohne Liste $feld');
  return [for (final e in wert) if (e is Map) _objekt(e) else throw FormatException('Antwort ohne Liste $feld')];
}
