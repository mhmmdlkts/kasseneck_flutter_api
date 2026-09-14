import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/models/beleg_blatt.dart';
import 'package:kasseneck_api/services/druck_logo.dart';
import 'package:kasseneck_api/services/logo_service.dart';

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

  test('ein Fehlschlag wird nicht gemerkt: der naechste Aufruf laedt neu', () async {
    var geladen = 0;
    final erst = await ladeDruckLogo('https://x/wackel.png', LogoStufe.m, KeckPaperSize.mm80, pixel: (_) async {
      geladen += 1;
      throw Exception('Netz weg');
    });
    expect(erst, isNull);
    final dann = await ladeDruckLogo('https://x/wackel.png', LogoStufe.m, KeckPaperSize.mm80, pixel: (_) async {
      geladen += 1;
      return _schwarz(20, 20);
    });
    expect(dann, isNotNull);
    expect(geladen, 2);
  });

  test('ein Pixel-Lader, der nie fertig wird: null innerhalb der Frist', () async {
    final sw = Stopwatch()..start();
    final logo = await ladeDruckLogo(
      'https://x/haengt.png',
      LogoStufe.m,
      KeckPaperSize.mm80,
      pixel: (_) => Completer<({int breite, int hoehe, Uint8List rgba})>().future,
      frist: const Duration(milliseconds: 30),
    );
    sw.stop();
    expect(logo, isNull);
    expect(sw.elapsedMilliseconds, lessThan(1000));
  });

  test('nach einer Frist-Ueberschreitung laedt der naechste Aufruf neu (kein Cache)', () async {
    var geladen = 0;
    final erst = await ladeDruckLogo(
      'https://x/haengt2.png',
      LogoStufe.m,
      KeckPaperSize.mm80,
      pixel: (_) {
        geladen += 1;
        return Completer<({int breite, int hoehe, Uint8List rgba})>().future;
      },
      frist: const Duration(milliseconds: 30),
    );
    expect(erst, isNull);
    final dann = await ladeDruckLogo(
      'https://x/haengt2.png',
      LogoStufe.m,
      KeckPaperSize.mm80,
      pixel: (_) async {
        geladen += 1;
        return _schwarz(20, 20);
      },
      frist: const Duration(milliseconds: 30),
    );
    expect(dann, isNotNull);
    expect(geladen, 2);
  });

  test('ein Lader, der erst nach der Frist fertig wird: kein Eintrag im Speicher', () async {
    final spaet = Completer<({int breite, int hoehe, Uint8List rgba})>();
    var geladen = 0;
    final erst = await ladeDruckLogo(
      'https://x/spaet.png',
      LogoStufe.m,
      KeckPaperSize.mm80,
      pixel: (_) {
        geladen += 1;
        return spaet.future;
      },
      frist: const Duration(milliseconds: 30),
    );
    expect(erst, isNull);
    spaet.complete(_schwarz(20, 20)); // kommt zu spaet, darf den Speicher nicht mehr fuellen
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final dann = await ladeDruckLogo(
      'https://x/spaet.png',
      LogoStufe.m,
      KeckPaperSize.mm80,
      pixel: (_) async {
        geladen += 1;
        return _schwarz(30, 30);
      },
      frist: const Duration(milliseconds: 30),
    );
    expect(dann, isNotNull);
    expect(dann!.pxBreite, 30); // waere 20, haette der spaete Treffer den Speicher gefuellt
    expect(geladen, 2);
  });

  test('ein Lader, der rechtzeitig fertig wird: liefert das Logo trotz Frist', () async {
    final logo = await ladeDruckLogo(
      'https://x/schnell.png',
      LogoStufe.m,
      KeckPaperSize.mm80,
      pixel: (_) async => _schwarz(15, 15),
      frist: const Duration(milliseconds: 200),
    );
    expect(logo, isNotNull);
    expect(logo!.pxBreite, 15);
  });

  test('ein Bild ueber der Pixel-Obergrenze: null statt Rasterlauf, naechster Aufruf laedt neu', () async {
    var geladen = 0;
    final zuGross = await ladeDruckLogo(
      'https://x/riesig.png',
      LogoStufe.m,
      KeckPaperSize.mm80,
      pixel: (_) async {
        geladen += 1;
        return _schwarz(4097, 10); // ueber logoPixelMax (4096)
      },
    );
    expect(zuGross, isNull);
    final dann = await ladeDruckLogo(
      'https://x/riesig.png',
      LogoStufe.m,
      KeckPaperSize.mm80,
      pixel: (_) async {
        geladen += 1;
        return _schwarz(20, 20);
      },
    );
    expect(dann, isNotNull);
    expect(geladen, 2); // der Ausschluss wurde nicht gemerkt -- wie jeder andere Fehlschlag
  });

  test('Standardweg: ein haengender Fetch liefert null innerhalb der aeusseren Frist', () async {
    // LogoService.httpClient ist ein bestehender, oeffentlicher Test-Seam
    // (schon von logo_service_test.dart genutzt) -- kein neuer Parameter
    // noetig, um den Standardweg (_ausLogoService -> LogoService -> decodePng)
    // statt des Test-Laders pixel zu pruefen.
    final alterClient = LogoService.httpClient;
    final alteFrist = LogoService.frist;
    addTearDown(() {
      LogoService.httpClient = alterClient;
      LogoService.frist = alteFrist;
    });
    LogoService.httpClient = MockClient((_) => Completer<http.Response>().future);

    final sw = Stopwatch()..start();
    final logo = await ladeDruckLogo(
      'https://x/standardweg-haengt.png',
      LogoStufe.m,
      KeckPaperSize.mm80,
      frist: const Duration(milliseconds: 30),
    );
    sw.stop();
    expect(logo, isNull);
    expect(sw.elapsedMilliseconds, lessThan(1000));
  });

  test('Leeren waehrend eines Fehlschlags: der neuere Abruf im Speicher bleibt stehen', () async {
    final sperre = Completer<void>();
    var geladen = 0;
    final alt = ladeDruckLogo('https://x/l.png', LogoStufe.m, KeckPaperSize.mm80, pixel: (_) async {
      await sperre.future;
      throw Exception('zu spaet');
    });
    druckLogoSpeicherLeeren();
    final neu = await ladeDruckLogo('https://x/l.png', LogoStufe.m, KeckPaperSize.mm80, pixel: (_) async {
      geladen += 1;
      return _schwarz(20, 20);
    });
    sperre.complete();
    expect(await alt, isNull);
    // Der alte Fehlschlag darf den Eintrag des neuen Abrufs nicht entfernen.
    final wieder = await ladeDruckLogo('https://x/l.png', LogoStufe.m, KeckPaperSize.mm80, pixel: (_) async {
      geladen += 1;
      return _schwarz(20, 20);
    });
    expect(identical(neu, wieder), isTrue);
    expect(geladen, 1);
  });
}
