/// RGBA-Pixel -> einfarbiges Rasterbild in der Groesse, die das Blatt dem Logo
/// gibt (Zwilling von `logoRaster` in `@kreiseck/kasseneck-api` ab 0.14.0).
/// Flaechenmittel je Druckpunkt, Durchsichtiges auf Papierweiss, BT.601,
/// Floyd-Steinberg mit Schwelle 128. Golden: `erwartet/logo-probe.raster32.txt`.
/// Die Reihenfolge der Rechenschritte nicht aendern -- nur so kommen JS und
/// Dart auf dieselben Punkte.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:kasseneck_api/models/beleg_blatt.dart';
import 'package:kasseneck_api/src/printing/raster/raster_image.dart';

class LogoRaster {
  final int breite;
  final int hoehe;

  /// `punkte[y * breite + x]`, 1 = schwarz.
  final Uint8List punkte;
  const LogoRaster({required this.breite, required this.hoehe, required this.punkte});

  /// Als deckendes Schwarz-Weiss-Bild fuer den Druck-Stack (GS v 0, myPOS-PNG).
  RasterImage alsRasterImage() {
    final rgba = Uint8List(breite * hoehe * 4);
    for (var i = 0; i < breite * hoehe; i++) {
      final wert = punkte[i] == 1 ? 0 : 255;
      rgba[i * 4] = wert;
      rgba[i * 4 + 1] = wert;
      rgba[i * 4 + 2] = wert;
      rgba[i * 4 + 3] = 255;
    }
    return RasterImage(breite, hoehe, rgba);
  }
}

LogoRaster logoRaster(Uint8List rgba, int pxBreite, int pxHoehe, LogoMass mass, int zeichen) {
  if (pxBreite < 1 || pxHoehe < 1 || rgba.length != pxBreite * pxHoehe * 4) {
    throw ArgumentError('RGBA-Laenge passt nicht zum Pixelmass');
  }
  final m = logoRasterMass(mass, zeichen);
  final breite = m.breite;
  final hoehe = m.hoehe;
  final grau = Float64List(breite * hoehe);
  final sx = pxBreite / breite;
  final sy = pxHoehe / hoehe;
  for (var y = 0; y < hoehe; y++) {
    final y0 = (y * sy).floor();
    final y1 = math.min(pxHoehe, math.max(y0 + 1, ((y + 1) * sy).floor()));
    for (var x = 0; x < breite; x++) {
      final x0 = (x * sx).floor();
      final x1 = math.min(pxBreite, math.max(x0 + 1, ((x + 1) * sx).floor()));
      var summe = 0.0;
      var anzahl = 0;
      for (var py = y0; py < y1; py++) {
        for (var px = x0; px < x1; px++) {
          final i = (py * pxBreite + px) * 4;
          final deckung = rgba[i + 3] / 255;
          final hell = 0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2];
          summe += hell * deckung + 255 * (1 - deckung);
          anzahl += 1;
        }
      }
      grau[y * breite + x] = anzahl == 0 ? 255 : summe / anzahl;
    }
  }
  final punkte = Uint8List(breite * hoehe);
  for (var y = 0; y < hoehe; y++) {
    for (var x = 0; x < breite; x++) {
      final i = y * breite + x;
      final alt = grau[i];
      final neu = alt < 128 ? 0.0 : 255.0;
      if (neu == 0) punkte[i] = 1;
      final fehler = alt - neu;
      if (x + 1 < breite) grau[i + 1] = grau[i + 1] + (fehler * 7) / 16;
      if (y + 1 < hoehe) {
        if (x > 0) grau[i + breite - 1] = grau[i + breite - 1] + (fehler * 3) / 16;
        grau[i + breite] = grau[i + breite] + (fehler * 5) / 16;
        if (x + 1 < breite) grau[i + breite + 1] = grau[i + breite + 1] + fehler / 16;
      }
    }
  }
  return LogoRaster(breite: breite, hoehe: hoehe, punkte: punkte);
}
