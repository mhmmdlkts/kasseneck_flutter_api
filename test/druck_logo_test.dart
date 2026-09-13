import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/models/beleg_blatt.dart';
import 'package:kasseneck_api/services/druck_logo.dart';

({int breite, int hoehe, Uint8List rgba}) _schwarz(int b, int h) {
  final rgba = Uint8List(b * h * 4);
  for (var i = 3; i < rgba.length; i += 4) {
    rgba[i] = 255;
  }
  return (breite: b, hoehe: h, rgba: rgba);
}

void main() {
  setUp(druckLogoSpeicherLeeren);

  test('rastert in der Groesse, die das Blatt dem Logo gibt', () async {
    final logo = await ladeDruckLogo('https://x/l.png', LogoStufe.s, KeckPaperSize.mm80, pixel: (_) async => _schwarz(1000, 100));
    final soll = logoRasterMass(logoMass(const BlattLogo(stufe: LogoStufe.s, pxBreite: 1000, pxHoehe: 100), 48), 48);
    expect(logo, isNotNull);
    expect((logo!.raster.breite, logo.raster.hoehe), (soll.breite, soll.hoehe));
    expect(logo.stufe, LogoStufe.s);
  });

  test('ohne URL oder bei einem Ladefehler: kein Logo, keine Ausnahme', () async {
    expect(await ladeDruckLogo(null, LogoStufe.m, KeckPaperSize.mm58, pixel: (_) async => _schwarz(10, 10)), isNull);
    expect(await ladeDruckLogo('https://x/weg.png', LogoStufe.m, KeckPaperSize.mm58, pixel: (_) async => throw Exception('404')), isNull);
  });

  test('merkt sich das Ergebnis je Adresse, Stufe und Papier', () async {
    var geladen = 0;
    Future<({int breite, int hoehe, Uint8List rgba})> lader(String _) async {
      geladen += 1;
      return _schwarz(20, 20);
    }

    await ladeDruckLogo('https://x/l.png', LogoStufe.m, KeckPaperSize.mm80, pixel: lader);
    await ladeDruckLogo('https://x/l.png', LogoStufe.m, KeckPaperSize.mm80, pixel: lader);
    expect(geladen, 1);
    await ladeDruckLogo('https://x/l.png', LogoStufe.m, KeckPaperSize.mm58, pixel: lader);
    expect(geladen, 2);
  });
}
