/// RGBA-Pixel -> einfarbiges Rasterbild in der Groesse, die das Blatt dem Logo
/// gibt (Zwilling von `logoRaster` in `@kreiseck/kasseneck-api` ab 0.14.0).
/// Flaechenmittel je Druckpunkt, Durchsichtiges auf Papierweiss, BT.601,
/// Floyd-Steinberg mit Schwelle 128. Golden: `expected/logo-sample.raster32.txt`.
/// Die Reihenfolge der Rechenschritte nicht aendern -- nur so kommen JS und
/// Dart auf dieselben Punkte.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:kasseneck_api/models/receipt_sheet.dart';
import 'package:kasseneck_api/src/printing/raster/raster_image.dart';

class LogoRaster {
  final int width;
  final int height;

  /// `dots[y * breite + x]`, 1 = schwarz.
  final Uint8List dots;
  const LogoRaster({required this.width, required this.height, required this.dots});

  /// Als deckendes Schwarz-Weiss-Bild fuer den Druck-Stack (GS v 0, myPOS-PNG).
  RasterImage toRasterImage() {
    final rgba = Uint8List(width * height * 4);
    for (var i = 0; i < width * height; i++) {
      final wert = dots[i] == 1 ? 0 : 255;
      rgba[i * 4] = wert;
      rgba[i * 4 + 1] = wert;
      rgba[i * 4 + 2] = wert;
      rgba[i * 4 + 3] = 255;
    }
    return RasterImage(width, height, rgba);
  }
}

/// Obergrenze der Rohpixel, die [logoRaster] noch anfasst (Zwilling von
/// `LOGO_PIXEL_MAX` im Druck-Kit der Browser-Kasse). Die Flaechenmittel-
/// Schleife in [logoRaster] laeuft synchron ueber `pixelWidth x pxHoehe` --
/// bei einem stark komprimierten Logo unter der Upload-Grenze (1 MB), das
/// trotzdem auf z. B. 6000x6000 Rohpixel entpackt, blockiert das den
/// UI-Isolate weit laenger als die Drei-Sekunden-Hausregel; `Future.timeout`
/// in `loadPrintLogo` kann laufenden synchronen Code nicht unterbrechen.
/// Eigene, pure Funktion, damit die Grenze ohne echtes Bild testbar ist.
const logoPixelMax = 4096;

/// `true`, wenn [logoRaster] das Bild noch anfassen darf.
bool isLogoPixelSizeAllowed(int width, int height) => width > 0 && height > 0 && width <= logoPixelMax && height <= logoPixelMax;

LogoRaster logoRaster(Uint8List rgba, int pixelWidth, int pixelHeight, LogoDimensions dimensions, int chars) {
  if (pixelWidth < 1 || pixelHeight < 1 || rgba.length != pixelWidth * pixelHeight * 4) {
    throw ArgumentError('RGBA-Laenge passt nicht zum Pixelmass');
  }
  final m = logoRasterSize(dimensions, chars);
  final breite = m.width;
  final hoehe = m.height;
  final grau = Float64List(breite * hoehe);
  final sx = pixelWidth / breite;
  final sy = pixelHeight / hoehe;
  for (var y = 0; y < hoehe; y++) {
    final y0 = (y * sy).floor();
    final y1 = math.min(pixelHeight, math.max(y0 + 1, ((y + 1) * sy).floor()));
    for (var x = 0; x < breite; x++) {
      final x0 = (x * sx).floor();
      final x1 = math.min(pixelWidth, math.max(x0 + 1, ((x + 1) * sx).floor()));
      var summe = 0.0;
      var anzahl = 0;
      for (var py = y0; py < y1; py++) {
        for (var px = x0; px < x1; px++) {
          final i = (py * pixelWidth + px) * 4;
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
  return LogoRaster(width: breite, height: hoehe, dots: punkte);
}
