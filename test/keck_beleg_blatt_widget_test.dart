import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/models/beleg_blatt.dart';
import 'package:kasseneck_api/models/beleg_layout.dart';
import 'package:kasseneck_api/services/logo_service.dart';
import 'package:kasseneck_api/src/printing/qr_groesse.dart';
import 'package:kasseneck_api/src/printing/raster/raster_codec.dart';
import 'package:kasseneck_api/src/printing/raster/raster_image.dart';
import 'package:kasseneck_api/widgets/keck_beleg_blatt_widget.dart';
import 'package:qr_flutter/qr_flutter.dart';

ReceiptLayout _fixture(String name) => ReceiptLayout.fromJson(
    jsonDecode(File('test/fixtures/vertrag/expected/$name.lines.json').readAsStringSync()))!;

Widget _huelle(Widget kind) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: kind)));

void main() {
  testWidgets('jede Zeile des Blatts steht zeichengleich und in Reihenfolge; Zeile = 2 Zeichenbreiten', (tester) async {
    final layout = _fixture('test-cashregister-sale');
    await tester.pumpWidget(_huelle(KeckReceiptSheetWidget(layout: layout, brandMark: true)));
    final blatt = receiptSheet(layout, brandMark: true);
    final soll = [for (final b in blatt.blocks) if (b is SheetLine) b.text];
    final ist = <String>[];
    for (var i = 0; i < blatt.blocks.length; i++) {
      final f = find.byKey(Key('keck-blatt-zeile-$i'));
      if (f.evaluate().isEmpty) continue;
      ist.add(tester.widget<Text>(find.descendant(of: f, matching: find.byType(Text))).data!);
    }
    expect(ist, soll);
    final breite = tester.getSize(find.byKey(const Key('keck-blatt'))).width;
    final zeile = tester.getSize(find.byKey(const Key('keck-blatt-zeile-0'))).height;
    expect(zeile, closeTo(2 * breite / blatt.charsPerLine, 0.01));
    final qr = blatt.blocks.whereType<SheetQr>().single;
    expect(tester.getSize(find.byKey(const Key('keck-blatt-qr'))).width, closeTo(qr.widthFraction * breite, 0.01));
  });

  testWidgets('ohne logoUrl kein Logo-Block; Aufdruck ist Text, nicht gefuellt', (tester) async {
    await tester.pumpWidget(_huelle(KeckReceiptSheetWidget(layout: _fixture('cancellation-full'))));
    expect(find.byKey(const Key('keck-blatt-logo')), findsNothing);
    // cancellation-full traegt paperSize mm80 -> 48 Zeichen, also 48 Gleichheitszeichen je Rahmenzeile.
    expect(find.text('=' * 48), findsNWidgets(2));
  });

  testWidgets('geladenes Logo: Groesse folgt breiteAnteil x Blattbreite und hoeheZeilen x 2 Zeichenbreiten', (tester) async {
    const url = 'https://example.test/blatt-logo.png';
    late Uint8List png;
    await tester.runAsync(() async {
      png = await encodePng(RasterImage.filled(40, 20, 0, 0, 0, 255));
    });
    LogoService.httpClient = MockClient((_) async => http.Response.bytes(png, 200));

    final layout = _fixture('test-cashregister-sale');
    // Der ganze Ladeweg -- HTTP-Abruf plus Bild-Decode -- ist echtes Async
    // (kein Timer): er muss ausserhalb der FakeAsync-Zone des Widget-Tests
    // laufen, sonst haengt `ui.instantiateImageCodec` fuer immer.
    await tester.runAsync(() async {
      await tester.pumpWidget(_huelle(KeckReceiptSheetWidget(layout: layout, logoUrl: url)));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    final logoFinder = find.byKey(const Key('keck-blatt-logo'));
    expect(logoFinder, findsOneWidget, reason: 'Logo-Block fehlt -- Decode nicht abgeschlossen?');

    final mass = logoDimensions(const SheetLogo(size: SheetLogoSize.m, pixelWidth: 40, pixelHeight: 20), receiptSheet(layout).charsPerLine);
    final breite = tester.getSize(find.byKey(const Key('keck-blatt'))).width;
    final logoGroesse = tester.getSize(logoFinder);
    expect(logoGroesse.width, closeTo(mass.widthFraction * breite, 0.5));
    final zeilenHoehe = tester.getSize(find.byKey(const Key('keck-blatt-zeile-0'))).height;
    expect(logoGroesse.height, closeTo(mass.heightLines * zeilenHoehe, 0.5));

    // Flutter soll nur in der angezeigten Groesse dekodieren, nicht in der
    // vollen Bildaufloesung -- sonst kostet jeder Beleg einen vollen
    // Mehr-Megapixel-Decode, obwohl das Logo nur wenige Dutzend Punkte breit steht.
    final image = tester.widget<Image>(find.descendant(of: logoFinder, matching: find.byType(Image)));
    final erwarteteCacheBreite = (logoGroesse.width * tester.view.devicePixelRatio).round();
    expect(image.image, isA<ResizeImage>());
    expect((image.image as ResizeImage).width, erwarteteCacheBreite);
  });

  // Der Bondruck verwirft Logos ueber 4096 px je Seite (logoPixelZulaessig,
  // lib/models/logo_raster.dart) -- dieselbe Grenze gilt jetzt auch am
  // Bildschirm: ein zu grosses Logo steht sonst auf der Fertig-Seite, fehlt
  // aber auf jedem gedruckten Bon.
  for (final (px, py, erwartetLogo) in [(5000, 1200, false), (400, 100, true), (4096, 10, true), (4097, 10, false)]) {
    testWidgets('Logo $px x $py: Logo-Block ${erwartetLogo ? "steht" : "fehlt (Pixelgrenze)"}', (tester) async {
      final url = 'https://example.test/blatt-logo-$px-$py.png';
      late Uint8List png;
      await tester.runAsync(() async {
        png = await encodePng(RasterImage.filled(px, py, 0, 0, 0, 255));
      });
      LogoService.httpClient = MockClient((_) async => http.Response.bytes(png, 200));

      final layout = _fixture('test-cashregister-sale');
      await tester.runAsync(() async {
        await tester.pumpWidget(_huelle(KeckReceiptSheetWidget(layout: layout, logoUrl: url)));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(find.byKey(const Key('keck-blatt-logo')), erwartetLogo ? findsOneWidget : findsNothing);
      if (!erwartetLogo) {
        // Wie ohne logoUrl: dieselben Zeilen, kein Logo-Block dazwischen.
        final ohneLogo = receiptSheet(layout);
        final sollZeilen = [for (final b in ohneLogo.blocks) if (b is SheetLine) b.text];
        final istZeilen = <String>[];
        for (var i = 0; i < ohneLogo.blocks.length; i++) {
          final f = find.byKey(Key('keck-blatt-zeile-$i'));
          if (f.evaluate().isEmpty) continue;
          istZeilen.add(tester.widget<Text>(find.descendant(of: f, matching: find.byType(Text))).data!);
        }
        expect(istZeilen, sollZeilen);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('QR am Schirm mit Korrektur M; Ruhezone: Innenflaeche = Kasten x Module / (Module + 8)', (tester) async {
    final layout = _fixture('test-cashregister-sale');
    await tester.pumpWidget(_huelle(KeckReceiptSheetWidget(layout: layout, brandMark: true)));
    final ansicht = tester.widget<QrImageView>(find.byType(QrImageView));
    // qr_flutter setzt ohne Angabe L -- dann haette der Schirm bei mancher
    // Nutzlast weniger Module als Bon und Blatt.
    expect(ansicht.errorCorrectionLevel, QrErrorCorrectLevel.M);

    final qr = receiptSheet(layout, brandMark: true).blocks.whereType<SheetQr>().single;
    final module = qrModuleCount(qr.payload);
    final kasten = tester.getSize(find.byKey(const Key('keck-blatt-qr')));
    final innen = tester.getSize(find.byType(QrImageView));
    expect(innen.width, closeTo(kasten.width * module / (module + 2 * QrMetrics.quietZoneModules), 0.01));
    expect(innen.height, closeTo(innen.width, 0.01));
    // Die Innenflaeche steht mittig im Kasten: vier Module Rand je Seite.
    expect(tester.getCenter(find.byType(QrImageView)).dx, closeTo(tester.getCenter(find.byKey(const Key('keck-blatt-qr'))).dx, 0.01));
  });

  // Die App setzt den Beleg in `SizedBox(width: 280/380)` unter `FittedBox`:
  // eine straffe Breite von aussen darf das Blatt nicht auseinanderziehen,
  // sonst stimmt die Zeichenbreite nicht mehr mit Zeilenhoehe und QR-Anteil.
  for (final (zeichen, aussen) in [(48, 380.0), (32, 280.0)]) {
    testWidgets('unter erzwungener Breite $aussen bleibt das Blatt $zeichen Zeichen breit, QR und Zeilen mittig', (tester) async {
      final layout = _fixture('test-cashregister-sale');
      // fontSize 7: in der Testschrift ist ein Zeichen so breit wie hoch, das
      // Blatt passt dann samt Rand in beide Breiten.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: aussen,
                child: KeckReceiptSheetWidget(layout: layout, charsPerLine: zeichen, brandMark: true, fontSize: 7),
              ),
            ),
          ),
        ),
      ));
      final blatt = find.byKey(const Key('keck-blatt'));
      final cw = tester.getSize(find.byKey(const Key('keck-blatt-zeile-0'))).height / 2;
      expect(tester.getSize(blatt).width, closeTo(zeichen * cw, 0.01));
      expect(tester.getSize(blatt).width, lessThan(aussen - 4 * cw), reason: 'Probe muss schmaler als die Huelle sein');

      final mitte = tester.getCenter(blatt).dx;
      expect(tester.getCenter(find.byKey(const Key('keck-blatt-qr'))).dx, closeTo(mitte, 0.01));
      final bloecke = receiptSheet(layout, charsPerLine: zeichen, brandMark: true).blocks;
      expect(bloecke.last, isA<SheetBrandMark>(), reason: 'Marke ist der letzte Block, kein Text mehr');
      final markeFinder = find.byKey(const Key('keck-blatt-marke'));
      expect(markeFinder, findsOneWidget);
      expect(tester.getCenter(markeFinder).dx, closeTo(mitte, 0.01));
      // Die Huelle selbst ist so breit wie verlangt -- das Blatt steht darin oben mittig.
      final huelle = find.byType(KeckReceiptSheetWidget);
      expect(tester.getSize(huelle).width, aussen);
      expect(mitte, closeTo(tester.getCenter(huelle).dx, 0.01));
    });
  }

  testWidgets('Logo-Adresse ohne Bild (404): kein Absturz, kein Logo-Block', (tester) async {
    // Ohne Bytes gibt es kein Logo-Block -- das Blatt steht ohne Logo.
    LogoService.httpClient = MockClient((_) async => http.Response('nicht da', 404));
    await tester.runAsync(() async {
      await tester.pumpWidget(_huelle(KeckReceiptSheetWidget(layout: _fixture('sale-cash'), logoUrl: 'https://example.test/weg.png')));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    expect(find.byKey(const Key('keck-blatt-logo')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('kaputte Logo-Datei (PNG-Kopf, Rest unlesbar): kein Absturz, kein Logo-Block', (tester) async {
    // Der Puffer nimmt die Bytes an, erst ImageDescriptor.encoded wirft -- das Blatt
    // steht ohne Logo, und der Puffer wird trotzdem freigegeben (finally).
    LogoService.httpClient = MockClient((_) async => http.Response.bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4], 200));
    await tester.runAsync(() async {
      await tester.pumpWidget(_huelle(KeckReceiptSheetWidget(layout: _fixture('sale-cash'), logoUrl: 'https://example.test/kaputt.png')));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    expect(find.byKey(const Key('keck-blatt-logo')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('QR-Inhalt ohne passende Version: Hinweistext statt QR, keine Ausnahme, Zeilen stehen', (tester) async {
    final json = jsonDecode(File('test/fixtures/vertrag/expected/test-cashregister-sale.lines.json').readAsStringSync()) as Map<String, dynamic>;
    json['lines'] = [
      for (final z in (json['lines'] as List).cast<Map<String, dynamic>>())
        if (z['kind'] == 'qr') {...z, 'data': 'x' * 2332} else z,
    ];
    final layout = ReceiptLayout.fromJson(json)!;
    await tester.pumpWidget(_huelle(KeckReceiptSheetWidget(layout: layout)));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('keck-blatt-qr')), findsNothing);
    expect(find.byKey(const Key('keck-blatt-qr-fehlt')), findsOneWidget);
    expect(find.text('Der QR-Code konnte nicht erzeugt werden. Bitte einen Papierbeleg ausgeben.'), findsOneWidget);
  });

  testWidgets('qrFehltBuilder bekommt die Nutzlast und ersetzt den Standard-Hinweis', (tester) async {
    final json = jsonDecode(File('test/fixtures/vertrag/expected/test-cashregister-sale.lines.json').readAsStringSync()) as Map<String, dynamic>;
    json['lines'] = [
      for (final z in (json['lines'] as List).cast<Map<String, dynamic>>())
        if (z['kind'] == 'qr') {...z, 'data': 'x' * 2332} else z,
    ];
    final layout = ReceiptLayout.fromJson(json)!;
    String? empfangeneNutzlast;
    await tester.pumpWidget(_huelle(KeckReceiptSheetWidget(
      layout: layout,
      qrMissingBuilder: (nutzlast) {
        empfangeneNutzlast = nutzlast;
        return const Text('eigener Hinweis', key: Key('eigener-qr-fehlt-hinweis'));
      },
    )));
    expect(empfangeneNutzlast, hasLength(2332));
    expect(find.byKey(const Key('eigener-qr-fehlt-hinweis')), findsOneWidget);
    expect(find.byKey(const Key('keck-blatt-qr-fehlt')), findsNothing);
    expect(find.byKey(const Key('keck-blatt-qr')), findsNothing);
  });

  testWidgets('leere QR-Nutzlast: weder Hinweis noch QR (kein Ausfall, sondern nichts zu zeigen)', (tester) async {
    final json = jsonDecode(File('test/fixtures/vertrag/expected/test-cashregister-sale.lines.json').readAsStringSync()) as Map<String, dynamic>;
    json['lines'] = [
      for (final z in (json['lines'] as List).cast<Map<String, dynamic>>())
        if (z['kind'] == 'qr') {...z, 'data': ''} else z,
    ];
    final layout = ReceiptLayout.fromJson(json)!;
    await tester.pumpWidget(_huelle(KeckReceiptSheetWidget(layout: layout)));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('keck-blatt-qr')), findsNothing);
    expect(find.byKey(const Key('keck-blatt-qr-fehlt')), findsNothing);
  });
}
