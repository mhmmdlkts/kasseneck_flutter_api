import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/kasseneck_api.dart' show SheetLine;
import 'package:kasseneck_api/pos.dart' show labelText, messageText;
import 'package:kasseneck_api/printing.dart';

/// Das Testblatt des Zeichensatzes gegen die gemeinsamen Prueffaelle des
/// npm-Pakets (`expected/code-table-test-sheet.{lines.json,mm58.hex,mm80.hex}`)
/// und dieselben Einzelfaelle wie `code-table-test-sheet.test.ts`.
void main() {
  const vertrag = 'test/fixtures/vertrag/expected';
  final fall = jsonDecode(File('$vertrag/code-table-test-sheet.lines.json').readAsStringSync()) as Map<String, dynamic>;
  final eingabe = (fall['input'] as Map).cast<String, dynamic>();
  final String kasse = eingabe['cashregisterLabel'] as String;
  final DateTime zeit = DateTime.parse(eingabe['time'] as String);

  CodeTableTestSheet blatt({String? label, DateTime? time}) =>
      codeTableTestSheet(cashregisterLabel: label ?? kasse, time: time ?? zeit, paper: KeckPaperSize.mm58);
  List<String> texte({String? label, DateTime? time}) =>
      [for (final b in blatt(label: label, time: time).blocks) (b as SheetLine).text];

  String hexZeilen(List<int> bytes) {
    final teile = <String>[];
    for (var i = 0; i < bytes.length; i += 32) {
      teile.add(bytes.sublist(i, i + 32 > bytes.length ? bytes.length : i + 32).map((b) => b.toRadixString(16).padLeft(2, '0')).join());
    }
    return '${teile.join('\n')}\n';
  }

  int finde(List<int> heu, List<int> nadel, [int ab = 0]) {
    outer:
    for (var i = ab; i <= heu.length - nadel.length; i++) {
      for (var j = 0; j < nadel.length; j++) {
        if (heu[i + j] != nadel[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  test('Zeilen wie der Prueffall des npm-Pakets (Bildschirm)', () {
    expect(jsonDecode(jsonEncode(blatt().toJson())), fall['sheet']);
  });

  test('Bytes 58 mm und 80 mm wie der Prueffall des npm-Pakets (Papier)', () {
    for (final (paper, name) in [(KeckPaperSize.mm58, 'mm58'), (KeckPaperSize.mm80, 'mm80')]) {
      final soll = File('$vertrag/code-table-test-sheet.$name.hex').readAsStringSync();
      expect(hexZeilen(codeTableTestSheetBytes(cashregisterLabel: kasse, time: zeit, paper: paper)), soll, reason: name);
    }
  });

  test('immer 32 Spalten, jede Zeile genau so breit, auch fuer 80 mm und lange Namen', () {
    for (final paper in KeckPaperSize.values) {
      final b = codeTableTestSheet(cashregisterLabel: 'Kasse mit einem sehr langen Namen am Tresen', time: zeit, paper: paper);
      expect(b.charsPerLine, 32);
      for (final z in b.blocks) {
        expect((z as SheetLine).text.length, 32, reason: z.text);
      }
    }
  });

  test('Texte kommen aus dem Katalog', () {
    final t = texte().map((z) => z.trim()).toList();
    expect(t, contains(labelText('codetable.title')));
    expect(t, contains(labelText('codetable.reference')));
    expect(t, contains(labelText('codetable.replacement_note')));
    expect(t.sublist(17, 20).join(' '), messageText('codetable.instruction'));
  });

  test('Nummern gross (doubleSizeLead 2), je Zeile Tabelle und fehlende Zeichen', () {
    final b = blatt();
    final gross = b.blocks.whereType<SheetLine>().where((z) => z.doubleSizeLead != null).toList();
    expect([for (final z in gross) [z.text.substring(0, 2), z.doubleSizeLead, z.bold]], [for (var n = 1; n <= 6; n++) [' $n', 2, false]]);
    expect([for (final r in b.rows) r.codeTable], codeTables.map((t) => t.id).toList());
    expect([for (final r in b.rows) r.number], [1, 2, 3, 4, 5, 6]);
    expect(b.rows[2].missing, ['€']);
    expect(b.rows[3].missing, ['€', '§']);
  });

  test('Kopfzeile in Wiener Zeit, auch um Mitternacht UTC', () {
    expect(texte(time: DateTime.utc(2026, 9, 29, 23, 30))[2].trim(), 'Kasse KECK-1  30.09. 01:30');
    expect(texte(time: DateTime.utc(2026, 12, 31, 23, 30))[2].trim(), 'Kasse KECK-1  01.01. 00:30');
  });

  test('Kassenname mit Umlaut steht als Ersatzbuchstaben', () {
    expect(texte(label: 'Bäckerei Straße')[2].trim(), 'Baeckerei Strasse  30.09. 14:05');
  });

  test('Vorlage-Zeile: Rasterbild 384 x 24, direkt nach ihrer Ueberschrift, Tinte nur in den Spalten der Zeichen', () {
    final bild = codeTableReferenceImage();
    expect((bild.width, bild.height), (384, 24));
    final vorlage = texte()[5];
    for (var spalte = 0; spalte < 32; spalte++) {
      var tinte = 0;
      for (var y = 0; y < 24; y++) {
        for (var x = spalte * 12; x < spalte * 12 + 12; x++) {
          tinte += bild.dots[y * 384 + x];
        }
      }
      if (vorlage[spalte] == ' ') {
        expect(tinte, 0, reason: 'Spalte $spalte leer');
      } else {
        expect(tinte, greaterThan(8), reason: 'Spalte $spalte (${vorlage[spalte]})');
      }
    }
    final bytes = codeTableTestSheetBytes(cashregisterLabel: kasse, time: zeit, paper: KeckPaperSize.mm58);
    final ueberschrift = finde(bytes, [...labelText('codetable.reference').codeUnits, 0x0a]);
    expect(ueberschrift, greaterThan(0));
    final nach = ueberschrift + labelText('codetable.reference').length + 1;
    expect(bytes.sublist(nach, nach + 10), [0x1c, 0x2e, 0x1d, 0x76, 0x30, 0x00, 48, 0, 24, 0]);
  });

  test('jede Testzeile: Nummer doppelt gross und fett, dann genau einmal ESC t n und die Bytes der Tabelle', () {
    final bytes = codeTableTestSheetBytes(cashregisterLabel: kasse, time: zeit, paper: KeckPaperSize.mm58);
    var ab = 0;
    for (final t in codeTables) {
      final rest = t.id == CodeTableId.replacement ? 'ae oe ue Ae Oe Ue ss EUR' : 'ä ö ü Ä Ö Ü ß € § °';
      final zeichen = t.id == CodeTableId.replacement
          ? rest.codeUnits
          : [for (final z in 'ä ö ü Ä Ö Ü ß € § °'.split(' ')) t.missing.contains(z) ? ' ' : z]
              .join(' ')
              .trimRight()
              .runes
              .expand((r) => encodeForCodeTable(String.fromCharCode(r), t.id))
              .toList();
      final folge = [
        0x1b, 0x45, 1, 0x1d, 0x21, 0x11, 0x1c, 0x2e, 0x30 + t.number, //
        0x1b, 0x45, 0, 0x1d, 0x21, 0x00, 0x1c, 0x2e, 0x1b, 0x74, t.escT, //
        ...' | '.codeUnits, ...zeichen, 0x0a,
      ];
      final i = finde(bytes, folge, ab);
      expect(i, greaterThanOrEqualTo(0), reason: t.id.name);
      ab = i + folge.length;
    }
  });

  test('am Ende Vorgabe-Tabelle (ESC t 16), auf 80 mm Rand 0, dann der Schnitt; 80 mm mittig ueber GS L 96', () {
    final b58 = codeTableTestSheetBytes(cashregisterLabel: kasse, time: zeit, paper: KeckPaperSize.mm58);
    final b80 = codeTableTestSheetBytes(cashregisterLabel: kasse, time: zeit, paper: KeckPaperSize.mm80);
    const schnitt = [0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x1d, 0x56, 0x30];
    expect(b58.sublist(b58.length - 11), [0x1b, 0x74, 16, ...schnitt]);
    expect(b80.sublist(b80.length - 15), [0x1b, 0x74, 16, 0x1d, 0x4c, 0, 0, ...schnitt]);
    expect(b58.sublist(0, 10), [0x1b, 0x40, 0x1d, 0x4c, 0, 0, 0x1d, 0x57, 0x80, 0x01]);
    expect(b80.sublist(10, 14), [0x1d, 0x4c, 96, 0]);
  });
}
