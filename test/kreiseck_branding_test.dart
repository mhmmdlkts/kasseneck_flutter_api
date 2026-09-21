import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/widgets/keck_receipt_widget.dart';
import 'package:kreiseck_design/kreiseck_design.dart';

import 'helpers/test_receipts.dart';
import 'print_rendering_test.dart' show render, texts;

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
