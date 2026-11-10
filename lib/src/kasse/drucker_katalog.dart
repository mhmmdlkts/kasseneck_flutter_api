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

/// Ein Wertfeld eines Eintrags ([PrinterCatalogValues]); der Geraetetest
/// nennt, welche am Geraet geprueft sind. [value] ist der Name im Vertrag,
/// ein Test haelt die Liste vollstaendig.
enum PrinterCatalogValueField implements PosSettingValue {
  paperSize,
  charsPerLine,
  cut,
  drawerKick,
  qrMode,
  codePage;

  @override
  String get value => name;
}

// ------------------------------------------------------------------ Typen

/// Der Wert zu einem Namen des Vertrags; die Abbildung ist allein [PosSettingValue.value].
T _wert<T extends PosSettingValue>(List<T> werte, Object? wert, String feld) =>
    werte.firstWhere((w) => w.value == wert, orElse: () => throw FormatException('$feld: unbekannter Wert', wert));

List<T> _werte<T extends PosSettingValue>(List<T> werte, Object? liste, String feld) =>
    List.unmodifiable([for (final w in liste as List) _wert(werte, w, feld)]);

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

  /// Werkseinstellung der Papierbreite; welche Breiten das Modell sonst kann,
  /// steht in [PrinterCatalogEntry.paperSizes].
  final PosPaperSize paperSize;

  /// Zeichen je Zeile bei der Werkseinstellung, im Geraetetest bestaetigt.
  /// Keine Einstellung: die Kasse leitet sie aus [paperSize] ab
  /// ([printerCatalogCharsPerLine]). Der Eintrag haelt fest, dass beides an
  /// diesem Drucker zusammenpasst; ein Drucker mit anderer Zeichenzahl
  /// braeuchte erst eine neue Einstellung.
  final int charsPerLine;
  final PosCut cut;

  /// Ladenanschluss, der auf den Impuls der Kasse (`ESC p 0 25 250`) oeffnet.
  final bool drawerKick;
  final PosQrMode qrMode;
  final PosCodePage codePage;

  Map<String, Object> toJson() => {
    PrinterCatalogValueField.paperSize.value: paperSize.value,
    PrinterCatalogValueField.charsPerLine.value: charsPerLine,
    PrinterCatalogValueField.cut.value: cut.value,
    PrinterCatalogValueField.drawerKick.value: drawerKick,
    PrinterCatalogValueField.qrMode.value: qrMode.value,
    PrinterCatalogValueField.codePage.value: codePage.value,
  };
}

/// Protokoll des Geraetetests, der einen Eintrag freigibt.
class PrinterDeviceTest {
  const PrinterDeviceTest({
    required this.date,
    required this.connectVersion,
    required this.firmware,
    required this.testedBy,
    required this.checked,
    required this.checkedPaperSizes,
  });

  factory PrinterDeviceTest.fromJson(Map<String, dynamic> json) => PrinterDeviceTest(
    date: json['date'] as String,
    connectVersion: json['connectVersion'] as String,
    firmware: json['firmware'] as String,
    testedBy: json['testedBy'] as String,
    checked: _werte(PrinterCatalogValueField.values, json['checked'], 'checked'),
    checkedPaperSizes: _werte(PosPaperSize.values, json['checkedPaperSizes'], 'checkedPaperSizes'),
  );

  /// Tag des Tests, `JJJJ-MM-TT` (Wiener Tag).
  final String date;

  /// Version von Kasseneck Connect, mit der geprueft wurde.
  final String connectVersion;

  /// Firmware des geprueften Druckers.
  final String firmware;

  /// Wer geprueft hat: Kuerzel, kein voller Name (die Datei reist im Paket mit).
  final String testedBy;

  /// Die am Geraet geprueften Wertfelder (`codePage` heisst: € und Umlaute
  /// stehen richtig am Bon). Vollstaendig ist der Test erst mit jedem Feld aus
  /// `values`: eine Freigabe soll nichts behaupten, was niemand gesehen hat.
  final List<PrinterCatalogValueField> checked;

  /// Die Papierbreiten, mit denen am Geraet gedruckt wurde; jede aus
  /// [PrinterCatalogEntry.paperSizes] muss dabei sein.
  final List<PosPaperSize> checkedPaperSizes;

  Map<String, Object> toJson() => {
    'date': date,
    'connectVersion': connectVersion,
    'firmware': firmware,
    'testedBy': testedBy,
    'checked': [for (final f in checked) f.value],
    'checkedPaperSizes': [for (final p in checkedPaperSizes) p.value],
  };
}

/// Freigabe eines Eintrags. Nur `approved: true` wirkt; ohne vollstaendigen
/// Geraetetest gibt es keine Freigabe.
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
    required this.paperSizes,
    required this.nativeCharsPerLine,
    required this.values,
    required this.approval,
  });

  factory PrinterCatalogEntry.fromJson(Map<String, dynamic> json) => PrinterCatalogEntry(
    id: json['id'] as String,
    manufacturer: json['manufacturer'] as String,
    model: json['model'] as String,
    matchNames: List.unmodifiable((json['matchNames'] as List).cast<String>()),
    paperSizes: _werte(PosPaperSize.values, json['paperSizes'], 'paperSizes'),
    nativeCharsPerLine: json['nativeCharsPerLine'] as int,
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

  /// Die Einstellungen der Papierbreite, die an diesem Modell passen (fuer
  /// eine andere Rolle mit Papierfuehrung und Einstellung am Drucker), in der
  /// Reihenfolge von [PosPaperSize]. Mehr als eine heisst: die
  /// Werkseinstellung in [values] kann am Geraet anders stehen.
  final List<PosPaperSize> paperSizes;

  /// Zeichen je Zeile, die der Drucker in seiner Werkseinstellung mit Schrift A
  /// selbst druckt (Datenblatt). Keine Breite aus [paperSizes] darf mehr
  /// Zeichen setzen; ist es mehr als `values.charsPerLine`, nutzt die Kasse
  /// bewusst ihr schmaleres Layout, bis es eine Einstellung mit dieser
  /// Zeichenzahl gibt.
  final int nativeCharsPerLine;
  final PrinterCatalogValues values;
  final PrinterCatalogApproval approval;

  /// Der Eintrag in der Form des Vertrags (`printers[]`).
  Map<String, Object?> toJson() => {
    'id': id,
    'manufacturer': manufacturer,
    'model': model,
    'matchNames': matchNames,
    'paperSizes': [for (final p in paperSizes) p.value],
    'nativeCharsPerLine': nativeCharsPerLine,
    'values': values.toJson(),
    'approval': approval.toJson(),
  };
}

/// Der Teil der Geraete-Einstellungen, den ein bekanntes Modell beim ersten
/// Einrichten vorschlaegt.
class PrinterCatalogDeviceSettings {
  const PrinterCatalogDeviceSettings({
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

  /// Aus `drawerKick`: nur ein Vorschlag fuer das erste Einrichten. Hat der
  /// Chef die Lade bewusst ausgeschaltet, bleibt sie aus; die Kasse
  /// ueberschreibt eine getroffene Wahl nie.
  final bool drawerEnabled;

  /// Als Teil der Geraete-Einstellungen am Draht, unveraendert sendbar mit
  /// `PosSettingsClient.saveDevice`.
  Map<String, Object> toJson() => {
    'paperSize': paperSize.value,
    'codePage': codePage.value,
    'cut': cut.value,
    'qrMode': qrMode.value,
    'drawerEnabled': drawerEnabled,
  };
}

/// Was ein Eintrag beim Einrichten vorschlaegt.
class PrinterCatalogSettings {
  const PrinterCatalogSettings({required this.device, required this.paperSizeNeedsCheck});

  /// Unveraendert als Teil der Geraete-Einstellungen sendbar.
  final PrinterCatalogDeviceSettings device;

  /// Das Modell kann mehr als eine Papierbreite: `device.paperSize` ist dann
  /// nur die Werkseinstellung, und die Kasse bestaetigt die Breite beim ersten
  /// Einrichten mit einem Testdruck.
  final bool paperSizeNeedsCheck;

  Map<String, Object> toJson() => {'device': device.toJson(), 'paperSizeNeedsCheck': paperSizeNeedsCheck};
}

// ------------------------------------------------------------------ Daten

/// Startbestand laut Spec connect-betrieb (Stufe 1), noch ohne Geraetetest und
/// darum nicht freigegeben. Je Eintrag stehen die Werte ausgeschrieben, auch wo
/// sie gleich sind: jeder ist eine eigene Aussage ueber ein Modell und wird
/// einzeln freigegeben.
///
/// Papierbreiten laut Epson-Datenblatt: TM-m30III, TM-m30II und TM-T20III
/// lassen sich mit der beiliegenden Papierfuehrung auf 58 mm umstellen (dann
/// 420 Punkte, Schrift A 35 Spalten; die Kasse setzt 32 Zeichen), der TM-m10
/// kann nur 58 mm. Bestaetigt ist das erst mit dem Geraetetest.
///
/// TM-T88VI und TM-T88VII drucken mit 180 dpi (512 Punkte auf 80 mm, Schrift
/// A 42 Spalten); 48 Zeichen passen nicht. Sie bekommen darum das
/// 58-mm-Layout der Kasse (32 Zeichen, die 384 Punkte von `GS W` passen in
/// ihre 512), auch mit 80-mm-Papier, bis es eine Einstellung mit 42 Zeichen
/// gibt.
const List<PrinterCatalogEntry> printerCatalog = [
  PrinterCatalogEntry(
    id: 'epson-tm-m30iii',
    manufacturer: 'Epson',
    model: 'TM-m30III',
    matchNames: ['TM-M30III'],
    paperSizes: [PosPaperSize.mm58, PosPaperSize.mm80],
    nativeCharsPerLine: 48,
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
    paperSizes: [PosPaperSize.mm58, PosPaperSize.mm80],
    nativeCharsPerLine: 48,
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
    paperSizes: [PosPaperSize.mm58, PosPaperSize.mm80],
    nativeCharsPerLine: 48,
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
    paperSizes: [PosPaperSize.mm58],
    nativeCharsPerLine: 42,
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
  PrinterCatalogEntry(
    id: 'epson-tm-t88vii',
    manufacturer: 'Epson',
    model: 'TM-T88VII',
    matchNames: ['TM-T88VII'],
    paperSizes: [PosPaperSize.mm58],
    nativeCharsPerLine: 42,
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
  PrinterCatalogEntry(
    id: 'epson-tm-m10',
    manufacturer: 'Epson',
    model: 'TM-m10',
    matchNames: ['TM-M10'],
    paperSizes: [PosPaperSize.mm58],
    nativeCharsPerLine: 35,
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

/// Ein Zeichen ausserhalb von ASCII, das weder Satzzeichen noch Leerraum ist.
final RegExp _fremdesZeichen = RegExp(r'[^\x00-\x7F\p{P}\p{Z}]', unicode: true);

/// Grossbuchstaben und Teile, oder `null` fuer einen Namen mit fremdem
/// Zeichen.
///
/// Gefaltet wird nur `a-z` zu `A-Z`: `toUpperCase` machte aus „ı“ ein I und
/// aus „ﬀ“ ein FF und damit aus einem fremden Namen womoeglich einen bekannten.
/// Steht danach ein Zeichen ausserhalb von ASCII, das weder Satzzeichen noch
/// Leerraum ist (Ï, é, ®), gilt der Name als unbekannt. Jede Folge anderer
/// Zeichen als `A-Z`/`0-9` wird ein Trenner, am Rand keiner; Leerzeichen,
/// Bindestrich, Unterstrich, Klammer und geschuetzter Bindestrich gelten dabei
/// gleich, damit „tm m30iii“, „TM-m30III“ und „(EPSON TM-m30III)“ (IPP
/// `product`) denselben Namen ergeben.
///
/// Der Trenner bleibt als ein Zeichen stehen, statt zu verschwinden:
/// TM-T20II-i ist ein eigenes Modell und darf nicht TM-T20III werden. Das
/// traegt nur, wo der Name einen Trenner hat; „TM-T20IIi“ ohne Bindestrich ist
/// von TM-T20III nicht zu unterscheiden (Prueffall).
String? _inTeilen(String text) {
  final gross = text.replaceAllMapped(_kleinbuchstabe, (m) => m[0]!.toUpperCase());
  if (_fremdesZeichen.hasMatch(gross)) return null;
  return gross.split(_keinNamenszeichen).where((t) => t.isNotEmpty).join(_trenner);
}

/// Die Hersteller eines Katalogs als Vorsilben (`EPSON-`), laengste zuerst:
/// „Star Micronics“ muss vor „Star“ greifen. Aus den Eintraegen selbst, damit
/// ein neuer Hersteller keine zweite Liste braucht. Gleich lange Vorsilben
/// koennen nicht beide vor demselben Namen stehen, ihre Reihenfolge ist darum
/// gleichgueltig.
List<String> _herstellerVorsilben(List<PrinterCatalogEntry> catalog) {
  final vorsilben = <String>{};
  for (final e in catalog) {
    final hersteller = _inTeilen(e.manufacturer);
    if (hersteller != null && hersteller.isNotEmpty) vorsilben.add('$hersteller$_trenner');
  }
  return vorsilben.toList()..sort((a, b) => b.length - a.length);
}

/// [_inTeilen], dann ohne die erste passende Vorsilbe; `null` ohne Namen oder
/// mit fremdem Zeichen.
String? _normiert(String? model, List<String> vorsilben) {
  if (model == null) return null;
  final name = _inTeilen(model);
  if (name == null || name.isEmpty) return null;
  for (final vorsilbe in vorsilben) {
    if (name.startsWith(vorsilbe)) return name.substring(vorsilbe.length);
  }
  return name;
}

/// Normierter Modellname, die Hersteller aus [catalog]. `EPSON TM-m30III`,
/// `TM-M30III` und `tm m30iii` ergeben `TM-M30III`; der Hersteller allein
/// (`EPSON`) bleibt stehen.
String? normalizePrinterModel(String? model, [List<PrinterCatalogEntry> catalog = printerCatalog]) =>
    _normiert(model, _herstellerVorsilben(catalog));

// ------------------------------------------------------------------ Erkennen

/// Der freigegebene Eintrag aus [catalog], an dem [model] erkannt wird, sonst
/// `null`. Ein nicht freigegebener Eintrag verhaelt sich wie ein unbekanntes
/// Modell. Das Ergebnis ist eindeutig, weil kein Name in zwei Eintraegen steht
/// (Prueffall [PrinterCatalogProblemReason.matchNameAmbiguous]).
PrinterCatalogEntry? findPrinterCatalogEntry(List<PrinterCatalogEntry> catalog, String? model) {
  final name = normalizePrinterModel(model, catalog);
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

/// Was ein Eintrag beim Einrichten vorschlaegt; `drawerKick` wird zu
/// `drawerEnabled`. Zwilling von `printerCatalogSettings`.
PrinterCatalogSettings printerCatalogSettings(PrinterCatalogEntry entry) {
  final v = entry.values;
  return PrinterCatalogSettings(
    device: PrinterCatalogDeviceSettings(
      paperSize: v.paperSize,
      codePage: v.codePage,
      cut: v.cut,
      qrMode: v.qrMode,
      drawerEnabled: v.drawerKick,
    ),
    paperSizeNeedsCheck: entry.paperSizes.any((p) => p != v.paperSize),
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
  paperSizesInvalid('paper_sizes_invalid'),
  paperSizeNotListed('paper_size_not_listed'),
  paperSizeTooWide('paper_size_too_wide'),
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

/// Ein Geraetetest belegt den Eintrag ganz: Kopf ausgefuellt, jedes Wertfeld
/// und jede Breite geprueft.
bool _vollstaendig(PrinterDeviceTest t, PrinterCatalogEntry e) =>
    _tag.hasMatch(t.date) &&
    t.connectVersion.isNotEmpty &&
    t.firmware.isNotEmpty &&
    t.testedBy.isNotEmpty &&
    PrinterCatalogValueField.values.every(t.checked.contains) &&
    e.paperSizes.every(t.checkedPaperSizes.contains);

/// Alle Funde in einem Katalog; leer = gueltig. Die einzige Stelle, an der die
/// Regeln stehen. Der Test ruft sie fuer den ausgelieferten Katalog und die
/// Prueffaelle; ein Fund macht ihn rot, statt zur Laufzeit still zu wirken.
List<PrinterCatalogProblem> printerCatalogProblems(List<PrinterCatalogEntry> catalog) {
  final probleme = <PrinterCatalogProblem>[];
  final vorsilben = _herstellerVorsilben(catalog);
  final ids = <String>{};
  // Name -> Index des Eintrags, der ihn zuerst fuehrt.
  final namen = <String, int>{};
  for (var index = 0; index < catalog.length; index++) {
    final e = catalog[index];
    void melde(PrinterCatalogProblemReason reason) => probleme.add(PrinterCatalogProblem(e.id, reason));
    if (!ids.add(e.id)) melde(PrinterCatalogProblemReason.duplicateId);
    if (e.matchNames.isEmpty) melde(PrinterCatalogProblemReason.matchNamesMissing);
    for (final name in e.matchNames) {
      if (_normiert(name, vorsilben) != name) melde(PrinterCatalogProblemReason.matchNameNotNormalized);
      final erster = namen.putIfAbsent(name, () => index);
      if (erster != index) melde(PrinterCatalogProblemReason.matchNameAmbiguous);
    }
    // Der eigene Modellname muss den Eintrag finden; sonst passen Anzeige und
    // Erkennung nicht zusammen (Tippfehler).
    final eigenerName = _normiert(e.model, vorsilben);
    if (eigenerName == null || !e.matchNames.contains(eigenerName)) melde(PrinterCatalogProblemReason.modelNotMatched);
    // Eine feste Reihenfolge ohne Doppel haelt Vertrag und Vergleich eindeutig.
    final geordnet = [
      for (final p in PosPaperSize.values)
        if (e.paperSizes.contains(p)) p,
    ];
    if (e.paperSizes.join() != geordnet.join()) melde(PrinterCatalogProblemReason.paperSizesInvalid);
    if (!e.paperSizes.contains(e.values.paperSize)) melde(PrinterCatalogProblemReason.paperSizeNotListed);
    // Eine Breite, deren Layout mehr Zeichen setzt, als der Drucker hat, bricht
    // jede Zeile um (TM-T88: 48 auf 42).
    if (e.paperSizes.any((p) => printerCatalogCharsPerLine[p]! > e.nativeCharsPerLine)) {
      melde(PrinterCatalogProblemReason.paperSizeTooWide);
    }
    // Die Enums der Einstellungen kennen mehr Werte als der Katalog
    // (`full`, `auto`); was ein Eintrag davon traegt, faellt hier auf.
    if (!printerCatalogCuts.contains(e.values.cut)) melde(PrinterCatalogProblemReason.cutNotAllowed);
    if (!printerCatalogQrModes.contains(e.values.qrMode)) melde(PrinterCatalogProblemReason.qrModeNotAllowed);
    if (printerCatalogCharsPerLine[e.values.paperSize] != e.values.charsPerLine) {
      melde(PrinterCatalogProblemReason.charsPerLineMismatch);
    }
    final test = e.approval.deviceTest;
    if (e.approval.approved && test == null) melde(PrinterCatalogProblemReason.deviceTestMissing);
    if (test != null && !_vollstaendig(test, e)) melde(PrinterCatalogProblemReason.deviceTestIncomplete);
  }
  return probleme;
}
