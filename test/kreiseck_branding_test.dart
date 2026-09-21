import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/qr_print_mode.dart';
import 'package:kasseneck_api/models/beleg_layout.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/src/printing/escpos/escpos.dart';
import 'package:kasseneck_api/widgets/keck_receipt_widget.dart';
import 'package:kreiseck_design/kreiseck_design.dart';

import 'helpers/test_receipts.dart';
import 'print_rendering_test.dart' show render, texts;

/// Die Nutzdaten des einzigen Rasterbild-Befehls (`GS v 0`, ab der Kennung bis
/// zum Ende des Eintrags) in [bytes] -- ein Fehlschlag hier heisst, es steht
/// keiner oder mehr als einer, nicht "die Marke stimmt nicht". Gesucht wird
/// die Kennung IRGENDWO im Eintrag, nicht am Anfang: `imageRaster` setzt die
/// Ausrichtung als Druckerzustand voran (siehe blatt_zeichner_test.dart) --
/// mal steht `ESC a` davor, mal nicht, je nachdem, was zuvor gedruckt wurde.
/// Das ist fuer die Frage "dieselbe Marke?" unerheblich, ein starrer
/// Praefix-Vergleich waere hier falsch.
Uint8List _einzigesRasterbild(List<Uint8List> bytes) {
  final treffer = <Uint8List>[];
  for (final b in bytes) {
    for (var i = 0; i + 3 <= b.length; i++) {
      if (b[i] == 0x1d && b[i + 1] == 0x76 && b[i + 2] == 0x30) {
        treffer.add(Uint8List.sublistView(b, i));
        break;
      }
    }
  }
  expect(treffer, hasLength(1), reason: 'genau ein Rasterbild-Befehl erwartet');
  return treffer.single;
}

/// Marken-Branding am Belegende (alter Weg, `setKeckReceipt`/`KeckReceiptWidget`):
/// gesteuert ueber das Backend-Metadatum `kreiseck_logo` (Firestore:
/// users/{uid}.branding.kreiseck_logo). Der Name des Flags bleibt -- siehe
/// docs/specs/2026-09-21-marke-einheitlich-design.md, § 5 (Namensschiefstand) --,
/// gezeigt wird seit 0.26.0/8.0.0 aber dasselbe Kasseneck-Logo wie am Blatt,
/// nicht mehr das alte Kreiseck-Logo mit "powered by" darunter.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Model: kreiseck_logo-Metadatum', () {
    test('fromJson liest das Flag, fehlend -> false', () {
      final j = cartA().toJson();
      expect(KasseneckReceipt.fromJson(j).showKreiseckLogo, isFalse);
      j['kreiseck_logo'] = true;
      expect(KasseneckReceipt.fromJson(j).showKreiseckLogo, isTrue);
    });
    test('toJson/fromJson-Roundtrip erhaelt das Flag (lokale Speicherung)', () {
      final r = buildReceipt(items: cartA().items, showKreiseckLogo: true);
      expect(KasseneckReceipt.fromJson(r.toJson()).showKreiseckLogo, isTrue);
    });
    test('nicht-boolesche Werte -> false (robust)', () {
      final j = cartA().toJson();
      j['kreiseck_logo'] = 'yes';
      expect(KasseneckReceipt.fromJson(j).showKreiseckLogo, isFalse);
    });
  });

  group('Druck', () {
    test('Flag an: das Marken-Logo als Bild, keine "powered by"-Zeile mehr', () async {
      final p = await render(buildReceipt(items: cartA().items, showKreiseckLogo: true));
      expect(texts(p), isNot(contains('powered by')));
      expect(p.myPosPaper.commands.any((c) => c['type'] == 'image'), isTrue);
    });
    test('Flag aus: kein Branding', () async {
      final p = await render(buildReceipt(items: cartA().items));
      expect(texts(p), isNot(contains('powered by')));
      expect(p.myPosPaper.commands.any((c) => c['type'] == 'image'), isFalse);
    });

    test('alter Weg (_addKreiseckBranding) und neuer Weg (setBelegBlatt) drucken dieselben Bilddaten', () async {
      // Nicht nur "irgendein Bild": derselbe Rasterbild-Befehl (GS v 0 samt
      // Nutzdaten) muss auf beiden Wegen stehen -- sonst waere belegt, dass
      // beide etwas zeichnen, aber nicht, dass es dieselbe Marke ist.
      final alterWeg = await render(buildReceipt(items: cartA().items, showKreiseckLogo: true));
      final alteBytes = _einzigesRasterbild(alterWeg.bytes);

      final layout = BelegLayout.fromJson(
          jsonDecode(File('test/fixtures/vertrag/erwartet/verkauf-bar.lines.json').readAsStringSync()))!;
      final neuerWeg = PrintPaper(paperSize: KeckPaperSize.mm58, profile: CapabilityProfile());
      await neuerWeg.setBelegBlatt(layout, marke: true, cut: false, qrMode: QrPrintMode.native);
      final neueBytes = _einzigesRasterbild(neuerWeg.bytes);

      expect(alteBytes, neueBytes, reason: 'beide Wege muessen byteidentisch dieselbe Marke drucken');
    });
  });

  group('Widget', () {
    testWidgets('Flag an: Marken-Logo am Ende, keine "powered by"-Zeile mehr', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(
          child: KeckReceiptWidget(receipt: buildReceipt(items: cartA().items, showKreiseckLogo: true)),
        )),
      ));
      expect(find.text('powered by'), findsNothing);
      expect(find.byType(KdLogo), findsOneWidget);
    });
    testWidgets('Flag aus: kein Branding', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(
          child: KeckReceiptWidget(receipt: buildReceipt(items: cartA().items)),
        )),
      ));
      expect(find.text('powered by'), findsNothing);
      expect(find.byType(KdLogo), findsNothing);
    });
  });
}
