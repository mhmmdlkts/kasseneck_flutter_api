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
  final namen = (manifest['belege'] as Map<String, dynamic>).keys.toList()..sort();

  test('Golden: grid32/grid48 aller Fixtures zeichengenau', () {
    expect(namen.length, greaterThanOrEqualTo(17));
    for (final n in namen) {
      final layout = BelegLayout.fromJson(jsonDecode(File('${_wurzel.path}/erwartet/$n.lines.json').readAsStringSync()))!;
      for (final zeichen in [32, 48]) {
        final soll = File('${_wurzel.path}/erwartet/$n.grid$zeichen.txt').readAsStringSync();
        expect(BelegRaster.render(layout, zeichen: zeichen).alsText(), soll, reason: '$n @$zeichen');
      }
    }
  });

  test('wortzeilen: wortweise, ueberlanges Wort hart, Leerzeichen an der Grenze faellt weg', () {
    expect(wortzeilen('TESTSIGNATUR — kein gültiger Beleg', 32), ['TESTSIGNATUR — kein gültiger', 'Beleg']);
    expect(wortzeilen('ABCDEFGHIJKLMNOPQRSTUVWXYZ', 10), ['ABCDEFGHIJ', 'KLMNOPQRST', 'UVWXYZ']);
    expect(wortzeilen('Ein sehr langer Artikelname', 15), ['Ein sehr langer', 'Artikelname']);
    expect(wortzeilen('a  b', 3), ['a', 'b']);
    expect(rasterSpaltenBreiten([7, 5], 32), [18, 14]);
    expect(rasterSpaltenBreiten([2, 3, 3, 4], 48), [8, 12, 12, 16]);
  });
}
