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
import 'package:kasseneck_api/src/printing/raster/raster_codec.dart';
import 'package:kasseneck_api/src/printing/raster/raster_image.dart';
import 'package:kasseneck_api/widgets/keck_beleg_blatt_widget.dart';

BelegLayout _fixture(String name) => BelegLayout.fromJson(
    jsonDecode(File('test/fixtures/vertrag/erwartet/$name.lines.json').readAsStringSync()))!;

Widget _huelle(Widget kind) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: kind)));

void main() {
  testWidgets('jede Zeile des Blatts steht zeichengleich und in Reihenfolge; Zeile = 2 Zeichenbreiten', (tester) async {
    final layout = _fixture('testkasse-verkauf');
    await tester.pumpWidget(_huelle(KeckBelegBlattWidget(layout: layout, marke: true)));
    final blatt = belegBlatt(layout, marke: true);
    final soll = [for (final b in blatt.bloecke) if (b is BlattZeile) b.text];
    final ist = <String>[];
    for (var i = 0; i < blatt.bloecke.length; i++) {
      final f = find.byKey(Key('keck-blatt-zeile-$i'));
      if (f.evaluate().isEmpty) continue;
      ist.add(tester.widget<Text>(find.descendant(of: f, matching: find.byType(Text))).data!);
    }
    expect(ist, soll);
    final breite = tester.getSize(find.byKey(const Key('keck-blatt'))).width;
    final zeile = tester.getSize(find.byKey(const Key('keck-blatt-zeile-0'))).height;
    expect(zeile, closeTo(2 * breite / blatt.zeichen, 0.01));
    final qr = blatt.bloecke.whereType<BlattQr>().single;
    expect(tester.getSize(find.byKey(const Key('keck-blatt-qr'))).width, closeTo(qr.breiteAnteil * breite, 0.01));
  });

  testWidgets('ohne logoUrl kein Logo-Block; Aufdruck ist Text, nicht gefuellt', (tester) async {
    await tester.pumpWidget(_huelle(KeckBelegBlattWidget(layout: _fixture('storno-voll'))));
    expect(find.byKey(const Key('keck-blatt-logo')), findsNothing);
    // storno-voll traegt paperSize mm80 -> 48 Zeichen, also 48 Gleichheitszeichen je Rahmenzeile.
    expect(find.text('=' * 48), findsNWidgets(2));
  });

  testWidgets('geladenes Logo: Groesse folgt breiteAnteil x Blattbreite und hoeheZeilen x 2 Zeichenbreiten', (tester) async {
    const url = 'https://example.test/blatt-logo.png';
    late Uint8List png;
    await tester.runAsync(() async {
      png = await encodePng(RasterImage.filled(40, 20, 0, 0, 0, 255));
    });
    LogoService.httpClient = MockClient((_) async => http.Response.bytes(png, 200));

    final layout = _fixture('testkasse-verkauf');
    // Der ganze Ladeweg -- HTTP-Abruf plus Bild-Decode -- ist echtes Async
    // (kein Timer): er muss ausserhalb der FakeAsync-Zone des Widget-Tests
    // laufen, sonst haengt `ui.instantiateImageCodec` fuer immer.
    await tester.runAsync(() async {
      await tester.pumpWidget(_huelle(KeckBelegBlattWidget(layout: layout, logoUrl: url)));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    final logoFinder = find.byKey(const Key('keck-blatt-logo'));
    expect(logoFinder, findsOneWidget, reason: 'Logo-Block fehlt -- Decode nicht abgeschlossen?');

    final mass = logoMass(const BlattLogo(stufe: LogoStufe.m, pxBreite: 40, pxHoehe: 20), belegBlatt(layout).zeichen);
    final breite = tester.getSize(find.byKey(const Key('keck-blatt'))).width;
    final logoGroesse = tester.getSize(logoFinder);
    expect(logoGroesse.width, closeTo(mass.breiteAnteil * breite, 0.5));
    final zeilenHoehe = tester.getSize(find.byKey(const Key('keck-blatt-zeile-0'))).height;
    expect(logoGroesse.height, closeTo(mass.hoeheZeilen * zeilenHoehe, 0.5));
  });
}
