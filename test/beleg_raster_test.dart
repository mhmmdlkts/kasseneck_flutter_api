import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/models/beleg_layout.dart';
import 'package:kasseneck_api/models/beleg_raster.dart';

/// Das Dart-Raster ist der Zwilling von `renderReceiptGrid` (JS-Paket): fuer
/// jede Golden-Fixture muss der Klartext zeichengenau den `grid32.txt` und
/// `grid48.txt` des Pakets entsprechen. Damit setzen App-Druck, Kasse,
/// Backend-PDF und Labor exakt dieselben Zeilen.
final _wurzel = Directory('test/fixtures/vertrag');

void main() {
  final manifest = jsonDecode(File('${_wurzel.path}/manifest.json').readAsStringSync()) as Map<String, dynamic>;
  final namen = (manifest['receipts'] as Map<String, dynamic>).keys.toList()..sort();

  test('Golden: grid32/grid48 aller Fixtures zeichengenau', () {
    expect(namen.length, greaterThanOrEqualTo(17));
    for (final n in namen) {
      final layout = ReceiptLayout.fromJson(jsonDecode(File('${_wurzel.path}/expected/$n.lines.json').readAsStringSync()))!;
      for (final zeichen in [32, 48]) {
        final soll = File('${_wurzel.path}/expected/$n.grid$zeichen.txt').readAsStringSync();
        expect(ReceiptGrid.render(layout, charsPerLine: zeichen).toText(), soll, reason: '$n @$zeichen');
      }
    }
  });

  test('wortzeilen: wortweise, ueberlanges Wort hart, Leerzeichen an der Grenze faellt weg', () {
    expect(wrapWords('TESTSIGNATUR — kein gültiger Beleg', 32), ['TESTSIGNATUR — kein gültiger', 'Beleg']);
    expect(wrapWords('ABCDEFGHIJKLMNOPQRSTUVWXYZ', 10), ['ABCDEFGHIJ', 'KLMNOPQRST', 'UVWXYZ']);
    expect(wrapWords('Ein sehr langer Artikelname', 15), ['Ein sehr langer', 'Artikelname']);
    expect(wrapWords('a  b', 3), ['a', 'b']);
    expect(gridColumnWidths([7, 5], 32), [18, 14]);
    expect(gridColumnWidths([2, 3, 3, 4], 48), [8, 12, 12, 16]);
  });
}
