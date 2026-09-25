import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/qr_print_mode.dart';
import 'package:kasseneck_api/models/beleg_blatt.dart';
import 'package:kasseneck_api/models/beleg_layout.dart';
import 'package:kasseneck_api/models/logo_raster.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/services/logo_service.dart';
import 'package:kasseneck_api/src/printing/escpos/escpos.dart';
import 'package:kasseneck_api/widgets/keck_beleg_blatt_widget.dart';

/// Jeder Zeichner gegen JEDES Blatt-Golden (Zwilling von
/// `test/blatt-zeichner.test.tsx` im npm-Paket): der ESC/POS-Druck und das
/// Widget muessen Block fuer Block die Folge aus
/// `erwartet/<name>.blatt<zeichen>.json` setzen.
///
/// Die Erwartung ist die Golden-Datei selbst -- `belegBlatt` wird hier bewusst
/// NICHT noch einmal gerechnet. Sonst pruefte der Test nur, dass zwei Aufrufe
/// derselben Funktion uebereinstimmen, und ein Fehler im Blatt fiele an beiden
/// Seiten gleich aus.
final _wurzel = Directory('test/fixtures/vertrag');

final List<String> _namen = (() {
  final manifest = jsonDecode(File('${_wurzel.path}/manifest.json').readAsStringSync()) as Map<String, dynamic>;
  return (manifest['belege'] as Map<String, dynamic>).keys.toList()..sort();
})();

BelegLayout _layout(String name) =>
    BelegLayout.fromJson(jsonDecode(File('${_wurzel.path}/erwartet/$name.lines.json').readAsStringSync()))!;

List<Map<String, dynamic>> _golden(String name, int zeichen) {
  final blatt = jsonDecode(File('${_wurzel.path}/erwartet/$name.blatt$zeichen.json').readAsStringSync()) as Map<String, dynamic>;
  expect(blatt['zeichen'], zeichen, reason: '$name/$zeichen');
  return (blatt['bloecke'] as List).cast<Map<String, dynamic>>();
}

/// Dasselbe Probe-Logo, mit dem die Goldens erzeugt wurden (npm `scripts/belege-fixtures.mjs`).
const _probe = BlattLogo(stufe: LogoStufe.m, pxBreite: 300, pxHoehe: 120);

DruckLogo _druckLogo(int zeichen) {
  final m = logoRasterMass(logoMass(_probe, zeichen), zeichen);
  return DruckLogo(
    stufe: _probe.stufe,
    pxBreite: _probe.pxBreite,
    pxHoehe: _probe.pxHoehe,
    raster: LogoRaster(breite: m.breite, hoehe: m.hoehe, punkte: Uint8List(m.breite * m.hoehe)..fillRange(0, m.breite * m.hoehe, 1)),
  );
}

/// Die druckbare Form einer Zeile, wie `PrintPaper` sie vor dem Rastern
/// herstellt: Euro wird "EUR", Striche werden '-', typografische Zeichen ASCII.
String _druckbar(String text) {
  const ersatz = {
    0x2013: '-', 0x2014: '-', 0x2011: '-', 0x2212: '-',
    0x201C: '"', 0x201D: '"', 0x201E: '"', 0x201F: '"',
    0x2018: "'", 0x2019: "'", 0x201A: "'", 0x2032: "'",
    0x2026: '...', 0x2022: '*', 0x2713: 'x', 0x2714: 'x',
    0x20AC: 'EUR', 0x2122: 'TM', 0x20BA: 'TL',
  };
  final sb = StringBuffer();
  for (final r in text.runes) {
    sb.write(ersatz[r] ?? (r <= 0xFF ? String.fromCharCode(r) : '?'));
  }
  return sb.toString();
}

int _anzahl(String heu, String nadel) => nadel.allMatches(heu).length;

const _rasterbild = '\x1dv0'; // GS v 0
const _qrNativ = '\x1d(k'; // GS ( k

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Blatt-Zeichner: alle Golden-Belege liegen vor (wie npm: 40)', () {
    expect(_namen, hasLength(40));
    for (final name in _namen) {
      for (final zeichen in [32, 48]) {
        expect(File('${_wurzel.path}/erwartet/$name.blatt$zeichen.json').existsSync(), isTrue, reason: '$name/$zeichen');
      }
    }
  });

  for (final name in _namen) {
    test('Blatt-Zeichner $name: der Bon setzt Block fuer Block das Golden-Blatt (32 und 48 Zeichen)', () async {
      final layout = _layout(name);
      for (final zeichen in [32, 48]) {
        final soll = _golden(name, zeichen);
        final wo = '$name/$zeichen';
        final paper = PrintPaper(paperSize: zeichen == 32 ? KeckPaperSize.mm58 : KeckPaperSize.mm80, profile: CapabilityProfile());
        await paper.setBelegBlatt(layout, logo: _druckLogo(zeichen), marke: true, cut: false, qrMode: QrPrintMode.native);
        expect(paper.qrFehler, isNull, reason: '$wo: QR fiel aus');

        // Nach dem einen Kopfbefehl von reset() (Initialisieren + Codepage in
        // einem Block, seit Task 7 Punkt 4 nicht mehr doppelt) setzt jeder
        // Block genau einen Befehl: Text, Vorschub, Rasterbild, QR.
        final befehle = paper.bytes.skip(1).map((b) => latin1.decode(b, allowInvalid: true)).toList();
        expect(befehle, hasLength(soll.length), reason: '$wo: Anzahl der gesetzten Bloecke');
        final alles = befehle.join();
        // Zwei Rasterbilder: das Firmenlogo und die Marke am Ende (ab 0.26.0
        // ein eigenes Bild statt der frueheren Textzeile).
        expect(_anzahl(alles, _rasterbild), 2, reason: '$wo: genau zwei Rasterbilder (Logo und Marke)');

        // Fett ist Druckerzustand: der Generator schickt ESC E n nur, wenn
        // sich der Zustand aendert. Mitgefuehrt ueber alle Befehle.
        var fett = false;
        for (var i = 0; i < soll.length; i++) {
          final b = soll[i];
          final ist = befehle[i];
          final wo2 = '$wo Block $i';
          final an = ist.lastIndexOf('\x1bE\x01');
          final aus = ist.lastIndexOf('\x1bE\x00');
          if (an >= 0 || aus >= 0) fett = an > aus;
          switch (b['art']) {
            case 'zeile':
              final text = b['text'] as String;
              expect(text.length, zeichen, reason: '$wo2: Zeilenbreite');
              if (b['leer'] == true) {
                expect(text, ' ' * zeichen, reason: '$wo2: Leerzeile mit Inhalt');
                expect(paper.bytes[i + 1], [0x1b, 0x64, 1], reason: '$wo2: Leerzeile ist ein Vorschub');
              } else {
                final druck = _druckbar(text);
                expect(ist.contains(_rasterbild) || ist.contains(_qrNativ), isFalse, reason: wo2);
                if (druck.length == text.length) {
                  // Gleich lang druckbar: die Zeile steht zeichengleich im Befehl.
                  expect(ist, contains(druck.trimRight()), reason: wo2);
                } else {
                  // "EUR" statt "€" verschiebt die Fuellzeichen einer Zeile, die Woerter nicht.
                  final woerter = druck.trim().split(RegExp(r' +'));
                  expect(RegExp(woerter.map(RegExp.escape).join(' +')).hasMatch(ist), isTrue, reason: '$wo2: "$druck"');
                }
                expect(fett, b['fett'] == true, reason: '$wo2: fett');
              }
            case 'logo':
              expect(ist, startsWith('\x1ba'), reason: '$wo2: Logo mittig');
              expect(ist, contains(_rasterbild), reason: '$wo2: Logo als GS v 0');
            case 'marke':
              // Keine feste Ausrichtungsvorgabe wie beim Logo: die Ausrichtung
              // ist Druckerzustand (wie `fett`) und wird nur bei einer
              // Aenderung erneut gesetzt. Vor der Marke steht zuletzt oft der
              // QR -- der ist bereits zentriert, also bleibt ESC a hier
              // manchmal aus. Zentriert ist die Marke trotzdem, weil der
              // Zustand es schon ist.
              expect(ist, contains(_rasterbild), reason: '$wo2: Marke als GS v 0');
            case 'qr':
              expect(ist, contains(_qrNativ), reason: '$wo2: nativer QR');
              expect(ist, contains(b['nutzlast'] as String), reason: '$wo2: Nutzlast');
            default:
              fail('$wo2: unbekannte Art ${b['art']}');
          }
        }
        expect(soll.last, containsPair('art', 'marke'), reason: '$wo: Marke zuletzt');
      }
    });
  }

  group('Widget', () {
    const logoUrl = 'https://example.test/blatt-probe.png';
    late Uint8List png;

    setUpAll(() async {
      png = await encodePng(RasterImage.filled(_probe.pxBreite, _probe.pxHoehe, 0, 0, 0, 255));
    });
    setUp(() {
      LogoService.httpClient = MockClient((_) async => http.Response.bytes(png, 200));
    });

    /// Vergleicht jede Blattzeile des Widgets (Key `keck-blatt-zeile-<i>`) mit
    /// Block i der Erwartung; Logo und QR stehen an ihrem Index als Kasten.
    void blockFuerBlock(WidgetTester tester, List<Map<String, dynamic>> soll, int zeichen, String wo) {
      final breite = tester.getSize(find.byKey(const Key('keck-blatt'))).width;
      expect(find.byKey(Key('keck-blatt-zeile-${soll.length}')), findsNothing, reason: '$wo: Zeilen nach dem Ende');
      expect(find.byKey(const Key('keck-blatt-logo')), soll.any((b) => b['art'] == 'logo') ? findsOneWidget : findsNothing,
          reason: '$wo: Logo-Block');
      expect(find.byKey(const Key('keck-blatt-marke')), soll.any((b) => b['art'] == 'marke') ? findsOneWidget : findsNothing,
          reason: '$wo: Marken-Block');
      for (var i = 0; i < soll.length; i++) {
        final b = soll[i];
        final zeile = find.byKey(Key('keck-blatt-zeile-$i'));
        switch (b['art']) {
          case 'zeile':
            expect(zeile, findsOneWidget, reason: '$wo Block $i');
            final text = tester.widget<Text>(find.descendant(of: zeile, matching: find.byType(Text)));
            expect(text.data, b['text'], reason: '$wo Block $i');
            expect(text.style?.fontWeight, b['fett'] == true ? FontWeight.w500 : FontWeight.w400, reason: '$wo Block $i: fett');
          case 'logo':
            expect(zeile, findsNothing, reason: '$wo Block $i');
            expect(tester.getSize(find.byKey(const Key('keck-blatt-logo'))).width, closeTo((b['breiteAnteil'] as num) * breite, 0.01),
                reason: '$wo Block $i: Logo-Breite');
          case 'marke':
            // Kein Druckraster am Bildschirm (die Logo-Komponente aus
            // kreiseck_design zeichnet Vektorpfade) -- die Groesse pruefen
            // die dedizierten Marke-Tests in keck_beleg_blatt_widget_test.dart;
            // hier zaehlt nur die Reihenfolge/Position im Golden-Blatt.
            expect(zeile, findsNothing, reason: '$wo Block $i');
            expect(find.byKey(const Key('keck-blatt-marke')), findsOneWidget, reason: '$wo Block $i: Marke-Block');
          case 'qr':
            expect(zeile, findsNothing, reason: '$wo Block $i');
            expect(tester.getSize(find.byKey(const Key('keck-blatt-qr'))).width, closeTo((b['breiteAnteil'] as num) * breite, 0.01),
                reason: '$wo Block $i: QR-Kasten');
          default:
            fail('$wo Block $i: unbekannte Art ${b['art']}');
        }
      }
      // Eine Zeile ist zwei Zeichenbreiten hoch; Block 0 ist ohne fuehrenden Aufdruck das Logo.
      final erste = soll.indexWhere((b) => b['art'] == 'zeile');
      expect(breite / zeichen, closeTo(tester.getSize(find.byKey(Key('keck-blatt-zeile-$erste'))).height / 2, 0.01), reason: wo);
    }

    for (final name in _namen) {
      testWidgets('Blatt-Zeichner $name: das Widget zeigt mit Logo Block fuer Block das Golden-Blatt', (tester) async {
        final layout = _layout(name);
        for (final zeichen in [32, 48]) {
          final wo = '$name/$zeichen';
          // Abruf und Bild-Decode sind echtes Async: der Ladeweg muss ausserhalb
          // der FakeAsync-Zone beginnen, sonst haengt `ui.instantiateImageCodec`.
          await tester.runAsync(() => tester.pumpWidget(MaterialApp(
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: KeckBelegBlattWidget(
                        key: ValueKey(zeichen), layout: layout, zeichen: zeichen, logoUrl: logoUrl, logoStufe: _probe.stufe, marke: true),
                  ),
                ),
              )));
          for (var n = 0; n < 200 && find.byKey(const Key('keck-blatt-logo')).evaluate().isEmpty; n++) {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
            await tester.pump();
          }
          blockFuerBlock(tester, _golden(name, zeichen), zeichen, wo);
        }
      });

      testWidgets('Blatt-Zeichner $name: das Widget zeigt ohne Logo das Golden-Blatt ohne Logo-Block (Marke ohne Logo)', (tester) async {
        final layout = _layout(name);
        for (final zeichen in [32, 48]) {
          // Erwartung ohne Logo, aus dem Golden abgeleitet: der Vertrag setzt
          // vor das Logo eine Leerzeile, wenn fuehrende Aufdrucke darueber
          // stehen (Logo-Index > 0), und immer eine danach. Ohne Logo fallen
          // der Logo-Block und genau diese Leerzeilen weg -- sonst nichts.
          final golden = _golden(name, zeichen);
          final l = golden.indexWhere((b) => b['art'] == 'logo');
          expect(l, isNonNegative, reason: '$name/$zeichen: Golden ohne Logo');
          expect(golden[l + 1], containsPair('leer', true), reason: '$name/$zeichen: Leerzeile nach dem Logo');
          if (l > 0) expect(golden[l - 1], containsPair('leer', true), reason: '$name/$zeichen: Leerzeile vor dem Logo');
          final soll = [
            for (final (i, b) in golden.indexed)
              if (i != l && i != l + 1 && !(l > 0 && i == l - 1)) b,
          ];
          await tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: KeckBelegBlattWidget(key: ValueKey(zeichen), layout: layout, zeichen: zeichen, marke: true),
              ),
            ),
          ));
          blockFuerBlock(tester, soll, zeichen, '$name/$zeichen ohne Logo');
        }
      });
    }
  });
}
