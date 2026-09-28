import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/models/beleg_blatt.dart';
import 'package:kasseneck_api/services/druck_logo.dart';
import 'package:kasseneck_api/services/logo_service.dart';

({int width, int height, Uint8List rgba}) _schwarz(int b, int h) {
  final rgba = Uint8List(b * h * 4);
  for (var i = 3; i < rgba.length; i += 4) {
    rgba[i] = 255;
  }
  return (width: b, height: h, rgba: rgba);
}

void main() {
  setUp(clearPrintLogoCache);

  test('rastert in der Groesse, die das Blatt dem Logo gibt', () async {
    final logo = await loadPrintLogo('https://x/l.png', SheetLogoSize.s, KeckPaperSize.mm80, pixel: (_) async => _schwarz(1000, 100));
    final soll = logoRasterSize(logoDimensions(const SheetLogo(size: SheetLogoSize.s, pixelWidth: 1000, pixelHeight: 100), 48), 48);
    expect(logo, isNotNull);
    expect((logo!.raster.width, logo.raster.height), (soll.width, soll.height));
    expect(logo.size, SheetLogoSize.s);
  });

  test('ohne URL oder bei einem Ladefehler: kein Logo, keine Ausnahme', () async {
    expect(await loadPrintLogo(null, SheetLogoSize.m, KeckPaperSize.mm58, pixel: (_) async => _schwarz(10, 10)), isNull);
    expect(await loadPrintLogo('https://x/weg.png', SheetLogoSize.m, KeckPaperSize.mm58, pixel: (_) async => throw Exception('404')), isNull);
  });

  test('merkt sich das Ergebnis je Adresse, Stufe und Papier', () async {
    var geladen = 0;
    Future<({int width, int height, Uint8List rgba})> lader(String _) async {
      geladen += 1;
      return _schwarz(20, 20);
    }

    await loadPrintLogo('https://x/l.png', SheetLogoSize.m, KeckPaperSize.mm80, pixel: lader);
    await loadPrintLogo('https://x/l.png', SheetLogoSize.m, KeckPaperSize.mm80, pixel: lader);
    expect(geladen, 1);
    await loadPrintLogo('https://x/l.png', SheetLogoSize.m, KeckPaperSize.mm58, pixel: lader);
    expect(geladen, 2);
  });

  test('ein Fehlschlag wird ausserhalb der Negativ-Frist nicht gemerkt: der naechste Aufruf laedt neu', () async {
    // negativFrist: Duration.zero schaltet das Negativ-Gedaechtnis (unten
    // eigens getestet) fuer diesen Test aus -- er prueft etwas anderes: dass
    // ein Fehlschlag ohne (bzw. mit abgelaufener) Sperre keinen Dauerzustand
    // hinterlaesst.
    var geladen = 0;
    final erst = await loadPrintLogo(
      'https://x/wackel.png', SheetLogoSize.m, KeckPaperSize.mm80,
      pixel: (_) async {
        geladen += 1;
        throw Exception('Netz weg');
      },
      negativeCacheTtl: Duration.zero,
    );
    expect(erst, isNull);
    final dann = await loadPrintLogo(
      'https://x/wackel.png', SheetLogoSize.m, KeckPaperSize.mm80,
      pixel: (_) async {
        geladen += 1;
        return _schwarz(20, 20);
      },
      negativeCacheTtl: Duration.zero,
    );
    expect(dann, isNotNull);
    expect(geladen, 2);
  });

  test('ein Fehlschlag wird kurz gemerkt: innerhalb der Negativ-Frist versucht der naechste Aufruf es nicht erneut', () async {
    // Genau der Fall aus dem Auftrag: eine kaputte Adresse kostete bisher auf
    // JEDEM Bon erneut bis zu drei Sekunden (bzw. hier: einen Aufruf des
    // Laders). Ein Fehlschlag wird jetzt kurz gemerkt.
    var geladen = 0;
    final erst = await loadPrintLogo('https://x/kaputt.png', SheetLogoSize.m, KeckPaperSize.mm80, pixel: (_) async {
      geladen += 1;
      throw Exception('404');
    });
    expect(erst, isNull);
    final dann = await loadPrintLogo('https://x/kaputt.png', SheetLogoSize.m, KeckPaperSize.mm80, pixel: (_) async {
      geladen += 1;
      return _schwarz(20, 20);
    });
    expect(dann, isNull, reason: 'innerhalb der Negativ-Frist kein neuer Versuch');
    expect(geladen, 1, reason: 'der zweite Lader wurde gar nicht erst aufgerufen');
  });

  test('nach Ablauf der Negativ-Frist versucht der naechste Aufruf es wieder', () async {
    var geladen = 0;
    final erst = await loadPrintLogo(
      'https://x/kaputt-kurz.png', SheetLogoSize.m, KeckPaperSize.mm80,
      pixel: (_) async {
        geladen += 1;
        throw Exception('404');
      },
      negativeCacheTtl: const Duration(milliseconds: 20),
    );
    expect(erst, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final dann = await loadPrintLogo(
      'https://x/kaputt-kurz.png', SheetLogoSize.m, KeckPaperSize.mm80,
      pixel: (_) async {
        geladen += 1;
        return _schwarz(20, 20);
      },
      negativeCacheTtl: const Duration(milliseconds: 20),
    );
    expect(dann, isNotNull);
    expect(geladen, 2);
  });

  test('ein Pixel-Lader, der nie fertig wird: null innerhalb der Frist', () async {
    final sw = Stopwatch()..start();
    final logo = await loadPrintLogo(
      'https://x/haengt.png',
      SheetLogoSize.m,
      KeckPaperSize.mm80,
      pixel: (_) => Completer<({int width, int height, Uint8List rgba})>().future,
      timeout: const Duration(milliseconds: 30),
    );
    sw.stop();
    expect(logo, isNull);
    expect(sw.elapsedMilliseconds, lessThan(1000));
  });

  test('nach einer Frist-Ueberschreitung laedt der naechste Aufruf neu (kein Cache)', () async {
    // negativFrist: Duration.zero, weil dieser Test die Positiv-Cache-Frage
    // prueft ("kein Cache" im Titel), nicht das Negativ-Gedaechtnis.
    var geladen = 0;
    final erst = await loadPrintLogo(
      'https://x/haengt2.png',
      SheetLogoSize.m,
      KeckPaperSize.mm80,
      pixel: (_) {
        geladen += 1;
        return Completer<({int width, int height, Uint8List rgba})>().future;
      },
      timeout: const Duration(milliseconds: 30),
      negativeCacheTtl: Duration.zero,
    );
    expect(erst, isNull);
    final dann = await loadPrintLogo(
      'https://x/haengt2.png',
      SheetLogoSize.m,
      KeckPaperSize.mm80,
      pixel: (_) async {
        geladen += 1;
        return _schwarz(20, 20);
      },
      timeout: const Duration(milliseconds: 30),
      negativeCacheTtl: Duration.zero,
    );
    expect(dann, isNotNull);
    expect(geladen, 2);
  });

  test('ein Lader, der erst nach der Frist fertig wird: kein Eintrag im Speicher', () async {
    final spaet = Completer<({int width, int height, Uint8List rgba})>();
    var geladen = 0;
    final erst = await loadPrintLogo(
      'https://x/spaet.png',
      SheetLogoSize.m,
      KeckPaperSize.mm80,
      pixel: (_) {
        geladen += 1;
        return spaet.future;
      },
      timeout: const Duration(milliseconds: 30),
      negativeCacheTtl: Duration.zero,
    );
    expect(erst, isNull);
    spaet.complete(_schwarz(20, 20)); // kommt zu spaet, darf den Speicher nicht mehr fuellen
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final dann = await loadPrintLogo(
      'https://x/spaet.png',
      SheetLogoSize.m,
      KeckPaperSize.mm80,
      pixel: (_) async {
        geladen += 1;
        return _schwarz(30, 30);
      },
      timeout: const Duration(milliseconds: 30),
      negativeCacheTtl: Duration.zero,
    );
    expect(dann, isNotNull);
    expect(dann!.pixelWidth, 30); // waere 20, haette der spaete Treffer den Speicher gefuellt
    expect(geladen, 2);
  });

  test('ein Lader, der rechtzeitig fertig wird: liefert das Logo trotz Frist', () async {
    final logo = await loadPrintLogo(
      'https://x/schnell.png',
      SheetLogoSize.m,
      KeckPaperSize.mm80,
      pixel: (_) async => _schwarz(15, 15),
      timeout: const Duration(milliseconds: 200),
    );
    expect(logo, isNotNull);
    expect(logo!.pixelWidth, 15);
  });

  test('ein Bild ueber der Pixel-Obergrenze: null statt Rasterlauf, naechster Aufruf laedt neu', () async {
    var geladen = 0;
    final zuGross = await loadPrintLogo(
      'https://x/riesig.png',
      SheetLogoSize.m,
      KeckPaperSize.mm80,
      pixel: (_) async {
        geladen += 1;
        return _schwarz(4097, 10); // ueber logoPixelMax (4096)
      },
      negativeCacheTtl: Duration.zero,
    );
    expect(zuGross, isNull);
    final dann = await loadPrintLogo(
      'https://x/riesig.png',
      SheetLogoSize.m,
      KeckPaperSize.mm80,
      pixel: (_) async {
        geladen += 1;
        return _schwarz(20, 20);
      },
      negativeCacheTtl: Duration.zero,
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
    final alteFrist = LogoService.timeout;
    addTearDown(() {
      LogoService.httpClient = alterClient;
      LogoService.timeout = alteFrist;
    });
    LogoService.httpClient = MockClient((_) => Completer<http.Response>().future);

    final sw = Stopwatch()..start();
    final logo = await loadPrintLogo(
      'https://x/standardweg-haengt.png',
      SheetLogoSize.m,
      KeckPaperSize.mm80,
      timeout: const Duration(milliseconds: 30),
    );
    sw.stop();
    expect(logo, isNull);
    expect(sw.elapsedMilliseconds, lessThan(1000));
  });

  test('Leeren waehrend eines Fehlschlags: der neuere Abruf im Speicher bleibt stehen', () async {
    final sperre = Completer<void>();
    var geladen = 0;
    final alt = loadPrintLogo('https://x/l.png', SheetLogoSize.m, KeckPaperSize.mm80, pixel: (_) async {
      await sperre.future;
      throw Exception('zu spaet');
    });
    clearPrintLogoCache();
    final neu = await loadPrintLogo('https://x/l.png', SheetLogoSize.m, KeckPaperSize.mm80, pixel: (_) async {
      geladen += 1;
      return _schwarz(20, 20);
    });
    sperre.complete();
    expect(await alt, isNull);
    // Der alte Fehlschlag darf den Eintrag des neuen Abrufs nicht entfernen.
    final wieder = await loadPrintLogo('https://x/l.png', SheetLogoSize.m, KeckPaperSize.mm80, pixel: (_) async {
      geladen += 1;
      return _schwarz(20, 20);
    });
    expect(identical(neu, wieder), isTrue);
    expect(geladen, 1);
  });
}
