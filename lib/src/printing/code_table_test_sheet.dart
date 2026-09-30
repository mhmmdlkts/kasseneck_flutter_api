/// Das Testblatt fuer den Zeichensatz: welche Code-Tabelle druckt auf diesem
/// Drucker die Umlaute richtig? (Zwilling von `code-table-test-sheet.ts` im
/// npm-Paket ab 1.1.0.)
///
/// Oben steht die Vorlage-Zeile als Rasterbild -- ein Bild druckt jeder
/// Drucker gleich, egal welche Tabelle er gerade hat. Darunter je Tabelle des
/// Katalogs eine Zeile mit ihrer Nummer (gross), umgeschaltet mit `ESC t n`
/// und mit den Bytes dieser Tabelle. Richtig ist die Zeile ohne falsches
/// Zeichen; eine Luecke (Zeichen fehlt der Tabelle) ist in Ordnung, bei
/// mehreren die mit den wenigsten Luecken, sonst Zeile 6 (Ersatzbuchstaben).
/// Nicht „die erste Zeile mit richtigen Umlauten“: ein Drucker mit nur PC437
/// druckt Zeile 2 und 3 mit richtigen Umlauten, aber falschem € und §.
///
/// Alles ausserhalb der Testzeilen steht mit Ersatzbuchstaben (reines ASCII),
/// auch die Anleitung: „Lücke“ aus dem Katalog steht am Blatt als „Luecke“.
///
/// Bildschirm und Papier zeigen dasselbe Blatt: [codeTableTestSheet] liefert
/// es im Zeilenmodell des Beleg-Blatts ([ReceiptSheet]), das
/// `KeckReceiptSheetWidget.fromSheet` zeichnet; [codeTableTestSheetBytes]
/// druckt genau diese Zeilen. Das Blatt hat immer 32 Spalten (58 mm); auf
/// 80 mm steht der Block ueber den linken Rand (`GS L`) mittig.
///
/// Gemeinsamer Prueffall mit dem npm-Paket:
/// `expected/code-table-test-sheet.{mm58,mm80}.hex` und `.lines.json`.
library;

import 'dart:typed_data' show Uint8List;

import '../../enums/keck_paper_size.dart';
import '../../models/brand_mark.dart' show unpackRasterBits;
import '../../models/logo_raster.dart';
import '../../models/receipt_grid.dart' show wrapWords;
import '../../models/receipt_sheet.dart';
import '../../services/vienna_time.dart';
import '../kasse/texte.dart' show labelText, messageText;
import 'code_table_reference_data.dart';
import 'code_tables.dart';
import 'escpos/escpos.dart';

/// Spalten des Testblatts -- immer 58-mm-Format.
const int codeTableTestSheetChars = 32;

/// Eine Testzeile: Nummer, Tabelle und die Zeichen, die ihr fehlen (fuer
/// „ohne €“ am Bildschirm).
class CodeTableTestSheetRow {
  final int number;
  final CodeTableId codeTable;
  final List<String> missing;
  const CodeTableTestSheetRow({required this.number, required this.codeTable, required this.missing});

  /// In der Form des Vertrags (`code-table-test-sheet.lines.json`).
  Map<String, Object> toJson() => {'number': number, 'codeTable': codeTable.name, 'missing': missing};
}

/// Das Testblatt im Zeilenmodell des Beleg-Blatts, dazu die Testzeilen.
class CodeTableTestSheet extends ReceiptSheet {
  final List<CodeTableTestSheetRow> rows;
  const CodeTableTestSheet({required super.charsPerLine, required super.blocks, required this.rows});

  @override
  Map<String, Object> toJson() => {...super.toJson(), 'rows': [for (final r in rows) r.toJson()]};
}

/// Die zehn Zeichen der Vorlage, in der Reihenfolge des Katalogs.
const List<String> _vorlage = ['ä', 'ö', 'ü', 'Ä', 'Ö', 'Ü', 'ß', '€', '§', '°'];

/// Spalte des ersten Zeichens; danach jede zweite. Muss zum Raster der
/// Vorlage passen (npm scripts/zeichensatz-vorlage.py).
const int _ersteSpalte = 5;

/// Breite der Nummernzelle: eine Ziffer doppelt breit.
const int _nummerSpalten = 2;
const String _trenner = ' | ';

/// Linker Rand, der den 32-Spalten-Block auf 80 mm (576 Punkte) mittig setzt.
const int _rand80 = (576 - codeTableTestSheetChars * 12) ~/ 2;

/// `ESC t` der Vorgabe ohne gewaehlte Tabelle (WPC1252).
const int _vorgabeEscT = 16;

/// Die Vorlage-Zeile als Rasterbild (384 x 24 Punkte), wie sie am Papier steht.
///
/// Anders als npm (`RasterImage` mit `dots`) kommt ein [LogoRaster]: das
/// Dart-`RasterImage` ist ein RGBA-Bild, das Punkt-je-Byte-Bild mit `dots`
/// (1 = schwarz) heisst hier `LogoRaster`, wie bei Logo und Marke.
/// `toRasterImage()` macht daraus das Bild fuer den Erzeuger.
LogoRaster codeTableReferenceImage() =>
    unpackRasterBits(codeTableReferenceRaster.bits, codeTableReferenceRaster.width, codeTableReferenceRaster.height);

/// Text in reines ASCII (Ersatzbuchstaben): steht auf jedem Drucker gleich,
/// egal welche Tabelle gilt.
String _nurAscii(String text) => String.fromCharCodes(encodeForCodeTable(text, CodeTableId.replacement));

SheetLine _zeile(String text, {bool bold = false, bool mittig = false, int? doubleSizeLead}) {
  final rest = codeTableTestSheetChars - text.length;
  final links = mittig ? rest ~/ 2 : 0;
  return SheetLine(
    text: ' ' * links + text + ' ' * (rest - links),
    bold: bold,
    blank: false,
    doubleSizeLead: doubleSizeLead,
  );
}

List<SheetLine> _zeilen(String text, {bool bold = false, bool mittig = false}) =>
    [for (final t in wrapWords(_nurAscii(text), codeTableTestSheetChars)) _zeile(t, bold: bold, mittig: mittig)];

/// Die Zeichen einer Tabelle an ihren Spalten; ein fehlendes Zeichen laesst seine Luecke.
String _zeichenDerTabelle(CodeTable tabelle) =>
    _vorlage.map((z) => tabelle.missing.contains(z) ? ' ' : z).join(' ').trimRight();

SheetLine _nummernZeile(int nummer, String text) =>
    _zeile('$nummer'.padLeft(_nummerSpalten) + _trenner + text, doubleSizeLead: _nummerSpalten);

String _zweistellig(int n) => '$n'.padLeft(2, '0');

/// Das Testblatt im Zeilenmodell des Beleg-Blatts -- dieselben Zeilen wie am
/// Papier. [cashregisterLabel] steht in der Kopfzeile (keine Personendaten),
/// [time] in Wiener Zeit; [paper] aendert das Blatt nicht (immer 32 Spalten).
///
/// Anders als npm (ein Objekt `options` mit denselben drei Feldern) sind es
/// benannte Parameter, der uebliche Weg in Dart; das Papier ist
/// [KeckPaperSize] statt `'mm58' | 'mm80'`. Gilt ebenso fuer
/// [codeTableTestSheetBytes].
CodeTableTestSheet codeTableTestSheet({
  required String cashregisterLabel,
  required DateTime time,
  required KeckPaperSize paper,
}) =>
    _blattBauen(cashregisterLabel, time).blatt;

/// Baut das Blatt und merkt sich dabei, welcher Block die Vorlage-Zeile ist.
/// Die Bytes suchen sie nicht am Text, sondern nehmen genau diese Stelle.
({CodeTableTestSheet blatt, int vorlage}) _blattBauen(String cashregisterLabel, DateTime time) {
  final uhr = ViennaTime.toWallClock(time);
  final zeit = '${_zweistellig(uhr.day)}.${_zweistellig(uhr.month)}. ${_zweistellig(uhr.hour)}:${_zweistellig(uhr.minute)}';
  final doppelt = _zeile('=' * codeTableTestSheetChars);
  final einfach = _zeile('-' * codeTableTestSheetChars);
  final einzug = ' ' * _ersteSpalte;

  final bloecke = <SheetBlock>[
    doppelt,
    ..._zeilen(labelText('codetable.title'), bold: true, mittig: true),
    ..._zeilen('${cashregisterLabel.trim()}  $zeit', mittig: true),
    doppelt,
    ..._zeilen(labelText('codetable.reference')),
  ];
  // Am Papier ein Bild (codeTableReferenceImage), am Bildschirm Text.
  final vorlage = bloecke.length;
  bloecke.add(_zeile(einzug + _vorlage.join(' ')));
  bloecke.add(einfach);
  final ersatz = codeTableById(CodeTableId.replacement);
  for (final t in codeTables) {
    if (t.id == CodeTableId.replacement) continue;
    bloecke.add(_nummernZeile(t.number, _zeichenDerTabelle(t)));
  }
  bloecke.add(einfach);
  final ersatzText = String.fromCharCodes(encodeForCodeTable(_vorlage.join(' '), CodeTableId.replacement));
  final ersatzZeilen = wrapWords(ersatzText, codeTableTestSheetChars - _ersteSpalte);
  bloecke.add(_nummernZeile(ersatz.number, ersatzZeilen.first));
  for (final t in ersatzZeilen.skip(1)) {
    bloecke.add(_zeile(einzug + t));
  }
  bloecke.add(_zeile(einzug + _nurAscii(labelText('codetable.replacement_note'))));
  bloecke.add(doppelt);
  bloecke.addAll(_zeilen(labelText('codetable.instruction_title'), bold: true));
  bloecke.addAll(_zeilen(messageText('codetable.instruction')));
  bloecke.addAll(_zeilen(messageText('codetable.instruction_none', {'number': ersatz.number})));
  bloecke.add(doppelt);

  return (
    blatt: CodeTableTestSheet(
      charsPerLine: codeTableTestSheetChars,
      blocks: List.unmodifiable(bloecke),
      rows: List.unmodifiable([
        for (final t in codeTables) CodeTableTestSheetRow(number: t.number, codeTable: t.id, missing: t.missing),
      ]),
    ),
    vorlage: vorlage,
  );
}

/// Das Testblatt als ESC/POS-Bytes. Jede Testzeile schaltet nach ihrer
/// Nummer einmal mit `FS .` + `ESC t n` auf ihre Tabelle und traegt deren
/// Bytes ([encodeForCodeTable], also das echte €-Byte, wo die Tabelle es hat).
/// Die Nummer steht doppelt breit und hoch (`GS !`) und fett, die Vorlage als
/// Rasterbild (`GS v 0`).
Uint8List codeTableTestSheetBytes({
  required String cashregisterLabel,
  required DateTime time,
  required KeckPaperSize paper,
}) {
  final (:blatt, vorlage: vorlageIndex) = _blattBauen(cashregisterLabel, time);
  final vorlage = blatt.blocks[vorlageIndex];
  if (vorlage is! SheetLine) throw StateError('Testblatt: Vorlage-Zeile fehlt (Block $vorlageIndex)');
  // Der Erzeuger ist immer 58 mm (32 Spalten, Druckbereich 384 Punkte) und
  // ohne globale Tabelle: nur die Testzeilen schalten um.
  final gen = EscPosGenerator(EscPaperSize.mm58, CapabilityProfile());
  final bytes = <int>[...gen.reset()];
  if (paper == KeckPaperSize.mm80) bytes.addAll([0x1d, 0x4c, _rand80 & 0xff, _rand80 >> 8]);

  var tabellen = 0;
  for (final block in blatt.blocks) {
    if (block is! SheetLine) continue;
    if (identical(block, vorlage)) {
      bytes.addAll(gen.imageRaster(codeTableReferenceImage().toRasterImage(), align: PosAlign.left));
      continue;
    }
    final lead = block.doubleSizeLead;
    if (lead == null) {
      bytes.addAll(gen.text(block.text.trimRight(), styles: PosStyles(align: PosAlign.left, bold: block.bold)));
      continue;
    }
    final tabelle = blatt.rows[tabellen];
    tabellen += 1;
    // Die Ziffer ist ASCII und steht in jeder Tabelle gleich: keine
    // Umschaltung davor, die Zeile schaltet genau einmal, vor ihren Bytes.
    bytes.addAll(gen.setStyles(const PosStyles(bold: true, width: PosTextSize.size2, height: PosTextSize.size2)));
    bytes.addAll(encodeForCodeTable(block.text.substring(0, lead).trim(), CodeTableId.replacement));
    bytes.addAll(gen.setStyles(PosStyles(codeTable: tabelle.codeTable.name)));
    bytes.addAll(encodeForCodeTable(block.text.substring(lead).trimRight(), tabelle.codeTable));
    bytes.add(0x0a);
  }
  // Endzustand wie ohne Wahl: Tabelle 16 (WPC1252) und auf 80 mm Rand 0.
  // Ein Druck danach ohne `ESC @` stuende sonst in der Tabelle der letzten
  // Testzeile und um den Rand verschoben.
  bytes.addAll([0x1b, 0x74, _vorgabeEscT]);
  if (paper == KeckPaperSize.mm80) bytes.addAll([0x1d, 0x4c, 0, 0]);
  bytes.addAll(gen.cut());
  return Uint8List.fromList(bytes);
}
