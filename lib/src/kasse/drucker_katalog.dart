/// Druckerkatalog der Kasse: bekannte Bondrucker mit den Druck-Einstellungen,
/// die an ihnen im Geraetetest stimmen. Findet Kasseneck Connect ein bekanntes
/// Modell, uebernimmt die Kasse diese Werte mit einem Klick; bei einem
/// unbekannten Modell fragt sie nur die Papierbreite. Der Katalog liegt im
/// Paket (nicht im Admin, nicht in Connect), damit Web-Kasse und Kassen-App
/// offline dieselben Werte haben und jede Aenderung versioniert und getestet
/// ausgeliefert wird.
///
/// Zwilling von `pos/drucker-katalog.ts` im npm-Paket (1.35.0), gleich
/// aufgebaut. Vertrag ist `printer-catalog.json`: dieselben Eintraege wie hier
/// und die Prueffaelle, die beide Seiten gegen dieselbe Datei rechnen. Die
/// Daten unten prueft nur der Test ([printerCatalogProblems]); zur Laufzeit
/// wird nichts still repariert oder verworfen.
library;

import '../../models/receipt_grid.dart' show charsPer58mm, charsPer80mm;
import 'einstellungen.dart' show PosCodePage, PosCut, PosPaperSize, PosQrMode, PosSettingValue;

// ------------------------------------------------------------------ Wertemengen

/// Schnitt eines Eintrags: nur, was die Kasse unter „Papier abschneiden“
/// anbietet (Teilschnitt oder keiner). Die Einstellung kennt auch
/// [PosCut.full], Bondrucker schneiden aber nie ganz durch; ein Katalogwert,
/// den die Kasse nicht anzeigt, waere fuer den Chef nicht pruefbar.
const List<PosCut> printerCatalogCuts = [PosCut.partial, PosCut.none];

/// QR-Weg eines Eintrags. [PosQrMode.auto] heisst „noch niemand hat
/// entschieden“ und ist darum keine Aussage ueber ein Modell.
const List<PosQrMode> printerCatalogQrModes = [PosQrMode.escpos, PosQrMode.raster];

/// Zeichen je Zeile je Papierbreite, wie das Raster des Bons sie setzt
/// (`CHARS_PER_PAPER_SIZE` im npm-Paket).
const Map<PosPaperSize, int> printerCatalogCharsPerLine = {
  PosPaperSize.mm58: charsPer58mm,
  PosPaperSize.mm80: charsPer80mm,
};

// ------------------------------------------------------------------ Typen

/// Der Wert zu einem Namen des Vertrags; die Abbildung ist allein [PosSettingValue.value].
T _wert<T extends PosSettingValue>(List<T> werte, Object? wert, String feld) =>
    werte.firstWhere((w) => w.value == wert, orElse: () => throw FormatException('$feld: unbekannter Wert', wert));

/// Druck-Werte eines Modells mit den Namen und Werten der
/// Geraete-Einstellungen unter /v3.
class PrinterCatalogValues {
  const PrinterCatalogValues({
    required this.paperSize,
    required this.charsPerLine,
    required this.cut,
    required this.drawerKick,
    required this.qrMode,
    required this.codePage,
  });

  factory PrinterCatalogValues.fromJson(Map<String, dynamic> json) => PrinterCatalogValues(
    paperSize: _wert(PosPaperSize.values, json['paperSize'], 'paperSize'),
    charsPerLine: json['charsPerLine'] as int,
    cut: _wert(PosCut.values, json['cut'], 'cut'),
    drawerKick: json['drawerKick'] as bool,
    qrMode: _wert(PosQrMode.values, json['qrMode'], 'qrMode'),
    codePage: _wert(PosCodePage.values, json['codePage'], 'codePage'),
  );

  final PosPaperSize paperSize;

  /// Zeichen je Zeile, im Geraetetest bestaetigt. Keine Einstellung: die Kasse
  /// leitet sie aus [paperSize] ab ([printerCatalogCharsPerLine]). Der Eintrag
  /// haelt fest, dass beides an diesem Drucker zusammenpasst; ein Drucker mit
  /// anderer Zeichenzahl braeuchte erst eine neue Einstellung.
  final int charsPerLine;
  final PosCut cut;

  /// Ladenanschluss, der auf den Impuls der Kasse (`ESC p 0 25 250`) oeffnet;
  /// Vorschlag fuer `drawerEnabled`.
  final bool drawerKick;
  final PosQrMode qrMode;
  final PosCodePage codePage;

  Map<String, Object> toJson() => {
    'paperSize': paperSize.value,
    'charsPerLine': charsPerLine,
    'cut': cut.value,
    'drawerKick': drawerKick,
    'qrMode': qrMode.value,
    'codePage': codePage.value,
  };
}

/// Protokoll des Geraetetests, der einen Eintrag freigibt.
class PrinterDeviceTest {
  const PrinterDeviceTest({
    required this.date,
    required this.connectVersion,
    required this.firmware,
    required this.testedBy,
  });

  factory PrinterDeviceTest.fromJson(Map<String, dynamic> json) => PrinterDeviceTest(
    date: json['date'] as String,
    connectVersion: json['connectVersion'] as String,
    firmware: json['firmware'] as String,
    testedBy: json['testedBy'] as String,
  );

  /// Tag des Tests, `JJJJ-MM-TT` (Wiener Tag).
  final String date;

  /// Version von Kasseneck Connect, mit der geprueft wurde.
  final String connectVersion;

  /// Firmware des geprueften Druckers.
  final String firmware;

  /// Wer geprueft hat: Kuerzel, kein voller Name (die Datei reist im Paket mit).
  final String testedBy;

  Map<String, Object> toJson() => {
    'date': date,
    'connectVersion': connectVersion,
    'firmware': firmware,
    'testedBy': testedBy,
  };
}

/// Freigabe eines Eintrags. Nur `approved: true` wirkt; ohne Geraetetest gibt
/// es keine Freigabe.
class PrinterCatalogApproval {
  const PrinterCatalogApproval({required this.approved, required this.deviceTest});

  factory PrinterCatalogApproval.fromJson(Map<String, dynamic> json) {
    final test = json['deviceTest'];
    return PrinterCatalogApproval(
      approved: json['approved'] as bool,
      deviceTest: test == null ? null : PrinterDeviceTest.fromJson((test as Map).cast<String, dynamic>()),
    );
  }

  final bool approved;
  final PrinterDeviceTest? deviceTest;

  Map<String, Object?> toJson() => {'approved': approved, 'deviceTest': deviceTest?.toJson()};
}

class PrinterCatalogEntry {
  const PrinterCatalogEntry({
    required this.id,
    required this.manufacturer,
    required this.model,
    required this.matchNames,
    required this.values,
    required this.approval,
  });

  factory PrinterCatalogEntry.fromJson(Map<String, dynamic> json) => PrinterCatalogEntry(
    id: json['id'] as String,
    manufacturer: json['manufacturer'] as String,
    model: json['model'] as String,
    matchNames: List.unmodifiable((json['matchNames'] as List).cast<String>()),
    values: PrinterCatalogValues.fromJson((json['values'] as Map).cast<String, dynamic>()),
    approval: PrinterCatalogApproval.fromJson((json['approval'] as Map).cast<String, dynamic>()),
  );

  /// Feste Kennung `<hersteller>-<modell>`, klein.
  final String id;
  final String manufacturer;

  /// Modellname zum Anzeigen, so geschrieben wie vom Hersteller.
  final String model;

  /// Normierte Modellnamen (aus mDNS und `GS I`), an denen der Eintrag erkannt
  /// wird.
  final List<String> matchNames;
  final PrinterCatalogValues values;
  final PrinterCatalogApproval approval;

  /// Der Eintrag in der Form des Vertrags (`printers[]`).
  Map<String, Object?> toJson() => {
    'id': id,
    'manufacturer': manufacturer,
    'model': model,
    'matchNames': matchNames,
    'values': values.toJson(),
    'approval': approval.toJson(),
  };
}

/// Der Teil der Geraete-Einstellungen, den ein bekanntes Modell vorschlaegt.
class PrinterCatalogSettings {
  const PrinterCatalogSettings({
    required this.paperSize,
    required this.codePage,
    required this.cut,
    required this.qrMode,
    required this.drawerEnabled,
  });

  final PosPaperSize paperSize;
  final PosCodePage codePage;
  final PosCut cut;
  final PosQrMode qrMode;
  final bool drawerEnabled;

  /// Als Teil der Geraete-Einstellungen am Draht, etwa fuer
  /// `RegisterSettingsClient.saveDevice`.
  Map<String, Object> toJson() => {
    'paperSize': paperSize.value,
    'codePage': codePage.value,
    'cut': cut.value,
    'qrMode': qrMode.value,
    'drawerEnabled': drawerEnabled,
  };
}

// ------------------------------------------------------------------ Daten

/// Startbestand laut Spec connect-betrieb (Stufe 1), noch ohne Geraetetest und
/// darum nicht freigegeben. Je Eintrag stehen die Werte ausgeschrieben, auch wo sie
/// gleich sind: jeder ist eine eigene Aussage ueber ein Modell und wird einzeln
/// freigegeben.
const List<PrinterCatalogEntry> printerCatalog = [
  PrinterCatalogEntry(
    id: 'epson-tm-m30iii',
    manufacturer: 'Epson',
    model: 'TM-m30III',
    matchNames: ['TM-M30III'],
    values: PrinterCatalogValues(
      paperSize: PosPaperSize.mm80,
      charsPerLine: 48,
      cut: PosCut.partial,
      drawerKick: true,
      qrMode: PosQrMode.escpos,
      codePage: PosCodePage.cp1252,
    ),
    approval: PrinterCatalogApproval(approved: false, deviceTest: null),
  ),
  PrinterCatalogEntry(
    id: 'epson-tm-m30ii',
    manufacturer: 'Epson',
    model: 'TM-m30II',
    matchNames: ['TM-M30II'],
    values: PrinterCatalogValues(
      paperSize: PosPaperSize.mm80,
      charsPerLine: 48,
      cut: PosCut.partial,
      drawerKick: true,
      qrMode: PosQrMode.escpos,
      codePage: PosCodePage.cp1252,
    ),
    approval: PrinterCatalogApproval(approved: false, deviceTest: null),
  ),
  PrinterCatalogEntry(
    id: 'epson-tm-t20iii',
    manufacturer: 'Epson',
    model: 'TM-T20III',
    matchNames: ['TM-T20III'],
    values: PrinterCatalogValues(
      paperSize: PosPaperSize.mm80,
      charsPerLine: 48,
      cut: PosCut.partial,
      drawerKick: true,
      qrMode: PosQrMode.escpos,
      codePage: PosCodePage.cp1252,
    ),
    approval: PrinterCatalogApproval(approved: false, deviceTest: null),
  ),
  PrinterCatalogEntry(
    id: 'epson-tm-t88vi',
    manufacturer: 'Epson',
    model: 'TM-T88VI',
    matchNames: ['TM-T88VI'],
    values: PrinterCatalogValues(
      paperSize: PosPaperSize.mm80,
      charsPerLine: 48,
      cut: PosCut.partial,
      drawerKick: true,
      qrMode: PosQrMode.escpos,
      codePage: PosCodePage.cp1252,
    ),
    approval: PrinterCatalogApproval(approved: false, deviceTest: null),
  ),
  PrinterCatalogEntry(
    id: 'epson-tm-t88vii',
    manufacturer: 'Epson',
    model: 'TM-T88VII',
    matchNames: ['TM-T88VII'],
    values: PrinterCatalogValues(
      paperSize: PosPaperSize.mm80,
      charsPerLine: 48,
      cut: PosCut.partial,
      drawerKick: true,
      qrMode: PosQrMode.escpos,
      codePage: PosCodePage.cp1252,
    ),
    approval: PrinterCatalogApproval(approved: false, deviceTest: null),
  ),
  PrinterCatalogEntry(
    id: 'epson-tm-m10',
    manufacturer: 'Epson',
    model: 'TM-m10',
    matchNames: ['TM-M10'],
    values: PrinterCatalogValues(
      paperSize: PosPaperSize.mm58,
      charsPerLine: 32,
      cut: PosCut.partial,
      drawerKick: true,
      qrMode: PosQrMode.escpos,
      codePage: PosCodePage.cp1252,
    ),
    approval: PrinterCatalogApproval(approved: false, deviceTest: null),
  ),
];

// ------------------------------------------------------------------ Normierung

/// Trenner im normierten Namen.
const String _trenner = '-';

final RegExp _kleinbuchstabe = RegExp('[a-z]');
final RegExp _keinNamenszeichen = RegExp('[^A-Z0-9]+');

/// Grossbuchstaben und Teile: aus `a-z` wird `A-Z` (nur ASCII, damit npm und
/// Dart gleich rechnen; `toUpperCase` machte aus „ß“ zwei Zeichen), jede Folge
/// anderer Zeichen als `A-Z`/`0-9` wird ein Trenner, am Rand keiner.
///
/// Die Trenner bleiben als ein Zeichen stehen statt zu verschwinden: sonst
/// waere das eigene Modell TM-T20II-i gleich TM-T20III und TM-T88V-i gleich
/// TM-T88VI. Leerzeichen, Bindestrich, Unterstrich und Klammer gelten dabei
/// gleich, damit „tm m30iii“, „TM-m30III“ und „(EPSON TM-m30III)“ (IPP
/// `product`) denselben Namen ergeben.
String _inTeilen(String text) => text
    .replaceAllMapped(_kleinbuchstabe, (m) => m[0]!.toUpperCase())
    .split(_keinNamenszeichen)
    .where((t) => t.isNotEmpty)
    .join(_trenner);

/// Hersteller als Vorsilbe (`EPSON-`), aus den Eintraegen selbst: ein neuer
/// Hersteller braucht keine zweite Liste.
final List<String> _herstellerVorsilben = List.unmodifiable({
  for (final e in printerCatalog) '${_inTeilen(e.manufacturer)}$_trenner',
});

/// Normierter Modellname: [_inTeilen], dann ohne einen vorangestellten
/// Hersteller des Katalogs. `null` ohne Namen. `EPSON TM-m30III`, `TM-M30III`
/// und `tm m30iii` ergeben `TM-M30III`; der Hersteller allein (`EPSON`) bleibt
/// stehen.
String? normalizePrinterModel(String? model) {
  if (model == null) return null;
  final name = _inTeilen(model);
  if (name.isEmpty) return null;
  for (final vorsilbe in _herstellerVorsilben) {
    if (name.startsWith(vorsilbe)) return name.substring(vorsilbe.length);
  }
  return name;
}

// ------------------------------------------------------------------ Erkennen

/// Der freigegebene Eintrag aus [catalog], an dem [model] erkannt wird, sonst
/// `null`. Ein nicht freigegebener Eintrag verhaelt sich wie ein unbekanntes
/// Modell. Das Ergebnis ist eindeutig, weil kein Name in zwei Eintraegen steht
/// (Prueffall [PrinterCatalogProblemReason.matchNameAmbiguous]).
PrinterCatalogEntry? findPrinterCatalogEntry(List<PrinterCatalogEntry> catalog, String? model) {
  final name = normalizePrinterModel(model);
  if (name == null) return null;
  for (final e in catalog) {
    if (e.approval.approved && e.matchNames.contains(name)) return e;
  }
  return null;
}

/// Der freigegebene Katalogeintrag zu einem Modellnamen, wie Connect ihn meldet
/// (mDNS, `GS I`), oder `null` fuer ein unbekanntes Modell. Gross- und
/// Kleinschreibung, ein vorangestelltes `EPSON` und die Art der Trenner zaehlen
/// nicht. Zwilling von `printerCatalogEntry`.
PrinterCatalogEntry? printerCatalogEntry(String? model) => findPrinterCatalogEntry(printerCatalog, model);

/// Die Geraete-Einstellungen, die ein Eintrag vorschlaegt; `drawerKick` wird zu
/// `drawerEnabled`. Zwilling von `printerCatalogSettings`.
PrinterCatalogSettings printerCatalogSettings(PrinterCatalogEntry entry) {
  final v = entry.values;
  return PrinterCatalogSettings(
    paperSize: v.paperSize,
    codePage: v.codePage,
    cut: v.cut,
    qrMode: v.qrMode,
    drawerEnabled: v.drawerKick,
  );
}

// ------------------------------------------------------------------ Pruefung

/// Was an einem Katalog nicht stimmt. Jeder Grund gehoert zu genau einem Feld
/// des Eintrags, darum traegt ein Fund kein eigenes Feld. Reihenfolge =
/// Reihenfolge der Pruefung je Eintrag; [value] ist der Name im Vertrag.
enum PrinterCatalogProblemReason {
  duplicateId('duplicate_id'),
  matchNamesMissing('match_names_missing'),
  matchNameNotNormalized('match_name_not_normalized'),
  matchNameAmbiguous('match_name_ambiguous'),
  modelNotMatched('model_not_matched'),
  cutNotAllowed('cut_not_allowed'),
  qrModeNotAllowed('qr_mode_not_allowed'),
  charsPerLineMismatch('chars_per_line_mismatch'),
  deviceTestMissing('device_test_missing'),
  deviceTestIncomplete('device_test_incomplete');

  const PrinterCatalogProblemReason(this.value);
  final String value;
}

/// Ein Fund der Pruefung: welcher Eintrag, welcher Grund.
class PrinterCatalogProblem {
  const PrinterCatalogProblem(this.id, this.reason);

  final String id;
  final PrinterCatalogProblemReason reason;

  Map<String, String> toJson() => {'id': id, 'reason': reason.value};
}

/// Tag im Format `JJJJ-MM-TT`.
final RegExp _tag = RegExp(r'^\d{4}-\d{2}-\d{2}$');

bool _vollstaendig(PrinterDeviceTest t) =>
    _tag.hasMatch(t.date) && t.connectVersion.isNotEmpty && t.firmware.isNotEmpty && t.testedBy.isNotEmpty;

/// Alle Funde in einem Katalog; leer = gueltig. Die einzige Stelle, an der die
/// Regeln stehen. Der Test ruft sie fuer den ausgelieferten Katalog und die
/// Prueffaelle; ein Fund macht ihn rot, statt zur Laufzeit still zu wirken.
List<PrinterCatalogProblem> printerCatalogProblems(List<PrinterCatalogEntry> catalog) {
  final probleme = <PrinterCatalogProblem>[];
  final ids = <String>{};
  // Name -> Index des Eintrags, der ihn zuerst fuehrt.
  final namen = <String, int>{};
  for (var index = 0; index < catalog.length; index++) {
    final e = catalog[index];
    void melde(PrinterCatalogProblemReason reason) => probleme.add(PrinterCatalogProblem(e.id, reason));
    if (!ids.add(e.id)) melde(PrinterCatalogProblemReason.duplicateId);
    if (e.matchNames.isEmpty) melde(PrinterCatalogProblemReason.matchNamesMissing);
    for (final name in e.matchNames) {
      if (normalizePrinterModel(name) != name) melde(PrinterCatalogProblemReason.matchNameNotNormalized);
      final erster = namen.putIfAbsent(name, () => index);
      if (erster != index) melde(PrinterCatalogProblemReason.matchNameAmbiguous);
    }
    // Der eigene Modellname muss den Eintrag finden; sonst passen Anzeige und
    // Erkennung nicht zusammen (Tippfehler).
    final eigenerName = normalizePrinterModel(e.model);
    if (eigenerName == null || !e.matchNames.contains(eigenerName)) melde(PrinterCatalogProblemReason.modelNotMatched);
    // Die Enums der Einstellungen kennen mehr Werte als der Katalog
    // (`full`, `auto`); was ein Eintrag davon traegt, faellt hier auf.
    if (!printerCatalogCuts.contains(e.values.cut)) melde(PrinterCatalogProblemReason.cutNotAllowed);
    if (!printerCatalogQrModes.contains(e.values.qrMode)) melde(PrinterCatalogProblemReason.qrModeNotAllowed);
    if (printerCatalogCharsPerLine[e.values.paperSize] != e.values.charsPerLine) {
      melde(PrinterCatalogProblemReason.charsPerLineMismatch);
    }
    final test = e.approval.deviceTest;
    if (e.approval.approved && test == null) melde(PrinterCatalogProblemReason.deviceTestMissing);
    if (test != null && !_vollstaendig(test)) melde(PrinterCatalogProblemReason.deviceTestIncomplete);
  }
  return probleme;
}
