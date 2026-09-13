import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/models/beleg_blatt.dart';
import 'package:kasseneck_api/models/logo_raster.dart';

/// Dieselbe Formel wie im npm-Golden-Test und `scripts/belege-fixtures.mjs`.
Uint8List _verlauf(int b, int h) {
  final rgba = Uint8List(b * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < b; x++) {
      final i = (y * b + x) * 4;
      final g = (x * 255) ~/ (b - 1);
      rgba[i] = g;
      rgba[i + 1] = (g * 3) % 256;
      rgba[i + 2] = 255 - g;
      // Teiltransparenz wie im npm-Golden: oben durchsichtig, dann Verlauf der Deckung, dann deckend.
      rgba[i + 3] = y < 10 ? 0 : (y < 30 ? ((y - 10) * 255) ~/ 19 : 255);
    }
  }
  return rgba;
}

/// Zweite Probe: hochformatig (100x400), voll deckend -- deckt den Zweig, in dem die Hoehe begrenzt.
Uint8List _hoch() {
  const b = 100, h = 400;
  final rgba = Uint8List(b * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < b; x++) {
      final i = (y * b + x) * 4;
      final g = (x * 255) ~/ (b - 1);
      rgba[i] = g;
      rgba[i + 1] = (g * 3) % 256;
      rgba[i + 2] = 255 - g;
      rgba[i + 3] = 255;
    }
  }
  return rgba;
}

void main() {
  test('Golden: hochformatige Logo-Probe 100x400, Stufe S, 32 Zeichen -- Punkt fuer Punkt wie npm', () {
    final mass = logoMass(const BlattLogo(stufe: LogoStufe.s, pxBreite: 100, pxHoehe: 400), 32);
    final bild = logoRaster(_hoch(), 100, 400, mass, 32);
    final zeilen = <String>[
      for (var y = 0; y < bild.hoehe; y++) bild.punkte.sublist(y * bild.breite, (y + 1) * bild.breite).join(),
    ];
    expect('${zeilen.join('\n')}\n', File('test/fixtures/vertrag/erwartet/logo-probe-hoch.raster32.txt').readAsStringSync());
  });

  test('Golden: Logo-Probe 300x100, Stufe S, 32 Zeichen -- Punkt fuer Punkt wie npm', () {
    final mass = logoMass(const BlattLogo(stufe: LogoStufe.s, pxBreite: 300, pxHoehe: 100), 32);
    final bild = logoRaster(_verlauf(300, 100), 300, 100, mass, 32);
    final zeilen = <String>[
      for (var y = 0; y < bild.hoehe; y++) bild.punkte.sublist(y * bild.breite, (y + 1) * bild.breite).join(),
    ];
    expect('${zeilen.join('\n')}\n', File('test/fixtures/vertrag/erwartet/logo-probe.raster32.txt').readAsStringSync());
  });

  test('falsche RGBA-Laenge wirft; alsRasterImage ist schwarz/weiss und deckend', () {
    expect(() => logoRaster(Uint8List(3), 1, 1, const LogoMass(breiteAnteil: 1 / 576, hoeheZeilen: 1 / 24), 48), throwsArgumentError);
    final r = LogoRaster(breite: 2, hoehe: 1, punkte: Uint8List.fromList([1, 0]));
    final img = r.alsRasterImage();
    expect(img.width, 2);
    expect(img.rgba, [0, 0, 0, 255, 255, 255, 255, 255]);
  });
}
