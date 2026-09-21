import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/models/logo_raster.dart';
import 'package:kasseneck_api/models/marke.dart';
import 'package:kasseneck_api/models/marke_daten.dart';

/// Zwilling von `test/marke-daten.test.ts` im JS-Paket: dieselben Masse,
/// dasselbe Raster, derselbe Rundlauf, dasselbe Golden.
final _vertrag = jsonDecode(File('test/fixtures/vertrag/marke.json').readAsStringSync()) as Map<String, dynamic>;

/// Gegenstueck zu `rasterZeilenBytes` im JS-Paket -- packt ein Punkt-je-Byte-Bild
/// (wie [entpackeRasterBits] es liefert) MSB zuerst, jede Zeile eigenstaendig auf
/// volle Bytes aufgefuellt. Nur zum Bauen der Testmatrix: dieses Paket packt
/// nichts selbst, es entpackt nur den fertigen Vertrag.
Uint8List _rasterZeilenBytes(int breite, int hoehe, Uint8List punkte) {
  final byteJeZeile = (breite / 8).ceil();
  final bytes = Uint8List(byteJeZeile * hoehe);
  for (var y = 0; y < hoehe; y++) {
    for (var x = 0; x < breite; x++) {
      if (punkte[y * breite + x] == 0) continue;
      bytes[y * byteJeZeile + (x >> 3)] |= 0x80 >> (x & 7);
    }
  }
  return bytes;
}

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

  // Der Schwarzanteil-Test oben ist eine Verhaeltnispruefung: ein vertauschter
  // Bit-Index (LSB statt MSB) oder ein Versatz bei byteJeZeile ergaebe
  // dieselbe Anzahl gesetzter Punkte, nur an falscher Stelle -- der Test
  // bliebe gruen, das Logo kaeme schief aus dem Drucker. Dieser Test sichert
  // darum die ANORDNUNG: ein bekanntes Bitmuster mit _rasterZeilenBytes
  // packen (Gegenstueck zum JS-Packer) und mit entpackeRasterBits (demselben
  // Entpacker, den markeBild benutzt) wieder auspacken -- heraus muss
  // bitgenau dasselbe Bild kommen. Real Breiten (234, 352), nicht synthetisch
  // -- 234 ist kein Vielfaches von 8, die letzte Spalte einer 234er-Zeile
  // liegt in einem Byte mit ungenutzten Fuellbits danach: genau der Fall, an
  // dem ein Versatz zuerst sichtbar wuerde. 352 ist ein Vielfaches von 8 und
  // laeuft zum Vergleich mit.
  test('Rundlauf _rasterZeilenBytes -> entpackeRasterBits: ein bekanntes Bitmuster bleibt bitgenau erhalten', () {
    for (final breite in [234, 352]) {
      const hoehe = 3;
      final punkte = Uint8List(breite * hoehe);
      // Zeile 0: Bytegrenzen (0, 7, 8, 9, 15, 16) und die letzten beiden Spalten.
      for (final x in [0, 7, 8, 9, 15, 16, breite - 2, breite - 1]) {
        punkte[x] = 1;
      }
      // Zeile 1: jedes achte Bit -- deckt jede Byte-Position innerhalb der Zeile ab.
      for (var x = 0; x < breite; x += 8) {
        punkte[breite + x] = 1;
      }
      // Zeile 2: nur die letzte Spalte -- der von der Pruefung benannte Sonderfall.
      punkte[2 * breite + (breite - 1)] = 1;

      final gepackt = _rasterZeilenBytes(breite, hoehe, punkte);
      final entpackt = entpackeRasterBits(base64.encode(gepackt), breite, hoehe);
      expect(entpackt.punkte, punkte, reason: 'Breite $breite: Rundlauf muss bitgenau sein');
    }
  });

  // Golden auf das tatsaechlich erzeugte Raster der echten Marke: schlaegt an,
  // sobald sich am Ergebnis von scripts/marke-raster.mjs (JS-Paket) oder am
  // Entpacker irgendetwas aendert -- beabsichtigt (dann den Hash bewusst
  // nachziehen) oder nicht (dann ist es ein Befund). Dieselben Hashes wie
  // test/marke-daten.test.ts im JS-Paket: stimmen sie ueberein, entpacken
  // beide Seiten denselben Vertrag bitgenau gleich.
  test('Golden: das erzeugte Raster der echten Marke stimmt mit dem JS-Zwilling ueberein', () {
    String hash(LogoRaster bild) => sha256.convert(bild.punkte).toString();
    expect(hash(markeBild(KeckPaperSize.mm80)), 'ce3a6fb81f86cae93a56870d893c437e07d97bafec16114cf63dfa5368d25e7f');
    expect(hash(markeBild(KeckPaperSize.mm58)), '7fb8dcf856622eb204e68abab4a66456500ca4cbdaea17bb1592caa499d70210');
  });
}
