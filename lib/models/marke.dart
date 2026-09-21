/// Die Marke als Rasterbild -- Zwilling von `markeBild`/`entpackeRasterBits`
/// in `@kreiseck/kasseneck-api` ab 0.26.0. Zur Laufzeit wird nichts gerastert
/// und nichts skaliert: die beiden Masse (352x51 auf 80 mm, 234x34 auf 58 mm)
/// stehen fest, damit JS und Dart fuer denselben Beleg dieselben Bytes
/// erzeugen (siehe `docs/specs/2026-09-21-marke-einheitlich-design.md`, § 3.3).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/models/logo_raster.dart';
import 'package:kasseneck_api/models/marke_daten.dart';

/// Entpackt gepackte Rasterzeilen (Base64, MSB zuerst, je Zeile auf volle
/// Bytes aufgefuellt) in ein Punkt-je-Byte-Bild -- dieselbe Rechnung wie
/// `entpackeRasterBits` im JS-Paket. Jede Zeile wird eigenstaendig indiziert
/// (`byteJeZeile` pro Zeile, nicht `breite / 8` insgesamt): bei einer Breite,
/// die nicht durch 8 teilbar ist (234 auf 58 mm), fuellt jede Zeile fuer sich
/// auf ein volles Byte auf, der Rest bleibt 0.
///
/// Eigene Funktion statt Code inline in [markeBild]: ein Rundlauf-Test kann so
/// denselben Entpacker pruefen, den die Marke zur Laufzeit auch benutzt.
LogoRaster entpackeRasterBits(String bitsBase64, int breite, int hoehe) {
  final byteJeZeile = (breite / 8).ceil();
  final roh = base64.decode(bitsBase64);
  final punkte = Uint8List(breite * hoehe);
  for (var y = 0; y < hoehe; y++) {
    for (var x = 0; x < breite; x++) {
      final byte = roh[y * byteJeZeile + (x >> 3)];
      punkte[y * breite + x] = (byte >> (7 - (x & 7))) & 1;
    }
  }
  return LogoRaster(breite: breite, hoehe: hoehe, punkte: punkte);
}

/// Die Marke als Rasterbild fuer diese Papierbreite.
LogoRaster markeBild(KeckPaperSize paperSize) {
  final d = markeRaster[paperSize]!;
  return entpackeRasterBits(d.bits, d.breite, d.hoehe);
}
