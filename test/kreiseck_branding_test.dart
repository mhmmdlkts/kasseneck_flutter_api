import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/widgets/keck_receipt_widget.dart';

import 'helpers/test_receipts.dart';
import 'print_rendering_test.dart' show render, texts;

/// Kreiseck-Branding am Belegende: gesteuert ueber das Backend-Metadatum
/// `kreiseck_logo` (Firestore: users/{uid}.branding.kreiseck_logo).
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
    test('Flag an: "powered by" UEBER dem Logo als letzter Block vor dem Cut', () async {
      final p = await render(buildReceipt(items: cartA().items, showKreiseckLogo: true));
      final t = texts(p);
      // letzter Text-Befehl ist die powered-by-Zeile (nach den Footern) ...
      expect(t.last, 'powered by');
      // ... und das Logo-Bild kommt DANACH (Text ueber Logo)
      final cmds = p.myPosPaper.commands;
      final poweredIdx = cmds.lastIndexWhere((c) => c['value'] == 'powered by');
      expect(cmds.sublist(poweredIdx + 1).any((c) => c['type'] == 'image'), isTrue);
    });
    test('Flag aus: kein Branding', () async {
      final p = await render(buildReceipt(items: cartA().items));
      expect(texts(p), isNot(contains('powered by')));
    });
  });

  group('Widget', () {
    testWidgets('Flag an: Logo + powered-by-Zeile am Ende', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(
          child: KeckReceiptWidget(receipt: buildReceipt(items: cartA().items, showKreiseckLogo: true)),
        )),
      ));
      expect(find.text('powered by'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) =>
            w is Image && w.image is AssetImage && (w.image as AssetImage).assetName.contains('kreiseck_logo_print')),
        findsOneWidget,
      );
    });
    testWidgets('Flag aus: kein Branding', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(
          child: KeckReceiptWidget(receipt: buildReceipt(items: cartA().items)),
        )),
      ));
      expect(find.text('powered by'), findsNothing);
    });
  });
}
