import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/models/marke.dart';
import 'package:kasseneck_api/models/marke_daten.dart';

/// Zwilling von `test/marke-daten.test.ts` im JS-Paket: dieselben Masse,
/// dasselbe Raster, derselbe Entpacker-Randfall.
final _vertrag = jsonDecode(File('test/fixtures/vertrag/marke.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  test('marke_daten.dart stimmt mit dem Vertrag ueberein -- nicht abgetippt, nicht neu erzeugt', () {
    final raster = _vertrag['raster'] as Map<String, dynamic>;
    for (final papier in KeckPaperSize.values) {
      final soll = raster[papier.name] as Map<String, dynamic>;
      final ist = markeRaster[papier]!;
      expect(ist.breite, soll['breite'], reason: '${papier.name}: Breite');
      expect(ist.hoehe, soll['hoehe'], reason: '${papier.name}: Hoehe');
      expect(ist.bits, soll['bits'], reason: '${papier.name}: Bits');
    }
  });

  test('die Marke hat je Papierbreite genau ein Mass', () {
    expect(markeBild(KeckPaperSize.mm80).breite, 352);
    expect(markeBild(KeckPaperSize.mm80).hoehe, 51);
    expect(markeBild(KeckPaperSize.mm58).breite, 234);
    expect(markeBild(KeckPaperSize.mm58).hoehe, 34);
  });

  test('das Raster ist ein Punkt je Byte und traegt Schwarz, aber nicht nur', () {
    for (final papier in KeckPaperSize.values) {
      final bild = markeBild(papier);
      expect(bild.punkte.length, bild.breite * bild.hoehe);
      final schwarz = bild.punkte.fold<int>(0, (s, p) => s + p);
      // Ein leeres oder volles Bild waere ein Fehler beim Ziehen, den man
      // sonst erst am Papier saehe.
      expect(schwarz, greaterThan(bild.punkte.length * 0.05), reason: '${papier.name}: zu wenig gesetzt');
      expect(schwarz, lessThan(bild.punkte.length * 0.6), reason: '${papier.name}: zu viel gesetzt');
    }
  });

  test('Randfall: Breite nicht durch 8 teilbar -- jede Zeile wird EIGENSTAENDIG aufgefuellt', () {
    // 3 Zeilen a 10 Bit, also 2 Byte je Zeile (10 Bit + 6 Fuellbits). Wuerde
    // der Entpacker die Bytes durchlaufend statt zeilenweise indizieren,
    // liefe die dritte Zeile auf falsche Bytes -- genau der Fehler, den
    // `byteJeZeile` pro Zeile (statt fuer den ganzen Puffer) verhindert.
    // Zeile 0: alle 10 Punkte gesetzt      -> 0xFF, 0xC0
    // Zeile 1: nur die ersten 8 gesetzt    -> 0xFF, 0x00
    // Zeile 2: nur das neunte Bit gesetzt  -> 0x00, 0x80
    final bits = base64.encode([0xFF, 0xC0, 0xFF, 0x00, 0x00, 0x80]);
    final bild = entpackeRasterBits(bits, 10, 3);
    expect(bild.punkte.sublist(0, 10), List.filled(10, 1), reason: 'Zeile 0');
    expect(bild.punkte.sublist(10, 20), [1, 1, 1, 1, 1, 1, 1, 1, 0, 0], reason: 'Zeile 1');
    expect(bild.punkte.sublist(20, 30), [0, 0, 0, 0, 0, 0, 0, 0, 1, 0], reason: 'Zeile 2');
  });
}
