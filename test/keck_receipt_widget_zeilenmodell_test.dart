import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/credit_card_provider.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/receipt_layout.dart';
import 'package:kasseneck_api/models/receipt_sheet.dart';
import 'package:kasseneck_api/widgets/keck_receipt_sheet_widget.dart';
import 'package:kasseneck_api/widgets/keck_receipt_widget.dart';

import 'helpers/test_receipts.dart';

// Belege mit Zeilenmodell des Servers: KeckReceiptWidget zeichnet dann das
// Blatt (KeckReceiptSheetWidget) statt des lokalen Rueckfalls. Anlass: eine App
// zeigte bei Karte + Trinkgeld bar nur „Zahlungsart: Mehrere Zahlungsarten“,
// obwohl der Server-Beleg die Zahlungen einzeln auffuehrt.

ReceiptLayout _fixture(String name) => ReceiptLayout.fromJson(
    jsonDecode(File('test/fixtures/vertrag/expected/$name.lines.json').readAsStringSync()))!;

/// Gemischter Beleg mit dem Server-Layout `split-tip-card` (Karte mit
/// Trinkgeld + bar). Ohne Layout zeichnete der Rueckfall nur das Label.
KasseneckReceipt _gemischt({ReceiptLayout? layout}) =>
    buildReceipt(items: cartA().items, paymentMethod: KeckPaymentMethod.mixed)..layout = layout;

Future<List<String>> _texte(WidgetTester tester, Widget kind, {double? breite}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Center(child: SizedBox(width: breite, child: kind)),
      ),
    ),
  ));
  return tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').toList();
}

void main() {
  group('KeckReceiptWidget mit Zeilenmodell des Servers', () {
    testWidgets('zeichnet das Blatt: Zahlungen einzeln mit Betrag, nicht nur das Label', (tester) async {
      final texte = await _texte(tester, KeckReceiptWidget(receipt: _gemischt(layout: _fixture('split-tip-card'))));
      expect(find.byKey(const Key('keck-blatt')), findsOneWidget);
      expect(texte.any((t) => t.startsWith('Zahlungsarten:')), isTrue);
      expect(texte.any((t) => t.startsWith('1. Kartenzahlung') && t.trimRight().endsWith('€')), isTrue);
      expect(texte.any((t) => t.startsWith('2. Barzahlung') && t.trimRight().endsWith('€')), isTrue);
      expect(texte.any((t) => t.contains('Mehrere Zahlungsarten')), isFalse);
    });

    testWidgets('dieselben Zeilen wie KeckReceiptSheetWidget mit demselben Layout', (tester) async {
      final layout = _fixture('split-tip-card');
      final blatt = receiptSheet(layout);
      final soll = [for (final b in blatt.blocks) if (b is SheetLine) b.text];
      await _texte(tester, KeckReceiptWidget(receipt: _gemischt(layout: layout)));
      final ist = <String>[];
      for (var i = 0; i < blatt.blocks.length; i++) {
        final f = find.byKey(Key('keck-blatt-zeile-$i'));
        if (f.evaluate().isEmpty) continue;
        ist.add(tester.widget<Text>(find.descendant(of: f, matching: find.byType(Text))).data!);
      }
      expect(ist, soll);
    });

    testWidgets('reicht Farben, verdeckten QR und Logo-Angaben des Belegs an das Blatt weiter', (tester) async {
      final beleg = _gemischt(layout: _fixture('split-tip-card'))
        ..logoUrl = 'https://example.test/logo.png'
        ..logoScale = SheetLogoSize.l
        ..showKreiseckLogo = true;
      await _texte(
        tester,
        KeckReceiptWidget(
          receipt: beleg,
          paperColor: Colors.amber,
          qrColor: Colors.indigo,
          qrCovered: true,
          qrCoveredText: 'Tippen',
        ),
      );
      final blatt = tester.widget<KeckReceiptSheetWidget>(find.byType(KeckReceiptSheetWidget));
      expect(blatt.paperColor, Colors.amber);
      expect(blatt.textColor, Colors.indigo);
      expect(blatt.qrCovered, isTrue);
      expect(blatt.qrCoveredText, 'Tippen');
      expect(blatt.logoUrl, 'https://example.test/logo.png');
      expect(blatt.logoSize, SheetLogoSize.l);
      expect(blatt.brandMark, isTrue);
      expect(find.byKey(const Key('keck-blatt-qr-toggle')), findsOneWidget);
    });

    testWidgets('schmaler als das Blatt: verkleinert statt abgeschnitten', (tester) async {
      final beleg = _gemischt(layout: _fixture('split-tip-card'));
      await _texte(tester, KeckReceiptWidget(receipt: beleg), breite: 2000);
      final voll = tester.getSize(find.byKey(const Key('keck-blatt'))).width;

      await _texte(tester, KeckReceiptWidget(receipt: beleg), breite: 200);
      // Das Blatt selbst behaelt seine Zeichenbreite (keine Zeile verliert
      // Zeichen), es steht nur kleiner in den 200 Punkten.
      expect(tester.getSize(find.byKey(const Key('keck-blatt'))).width, closeTo(voll, 0.01));
      expect(tester.getRect(find.byKey(const Key('keck-blatt'))).width, lessThanOrEqualTo(200));
      expect(tester.takeException(), isNull);
    });
  });

  group('KeckReceiptWidget ohne vollstaendiges Zeilenmodell', () {
    testWidgets('ohne Layout: lokaler Rueckfall', (tester) async {
      final texte = await _texte(tester, KeckReceiptWidget(receipt: _gemischt()));
      expect(find.byKey(const Key('keck-blatt')), findsNothing);
      expect(texte, containsAll(['Zahlungsart:', 'Mehrere Zahlungsarten']));
    });

    // Kasse und karteck rufen das Widget genau fuer diesen Fall als Rueckfall
    // auf (Layout eines Backends ohne Kartenblock je Zahlung): dort zeichnet
    // nur der lokale Weg den Kartenbeleg.
    testWidgets('Layout ohne den Kartenblock des Belegs: lokaler Rueckfall mit Kartenblock', (tester) async {
      final beleg = buildReceipt(
        items: cartA().items,
        paymentMethod: KeckPaymentMethod.creditCard,
        cardProvider: CreditCardProvider.sumup,
        cardPaymentData: {'success': true, 'cardType': 'VISA', 'cardLastDigits': '1234',
          'paymentType': 'POS', 'amount': 12.5, 'currency': 'EUR', 'transactionCode': 'TC1', 'entryMode': 'nfc'},
      )..layout = _fixture('split-cash-change');
      expect(beleg.isLayoutComplete, isFalse);
      final texte = await _texte(tester, KeckReceiptWidget(receipt: beleg));
      expect(find.byKey(const Key('keck-blatt')), findsNothing);
      expect(texte, contains('SumUp Beleg'));
    });
  });
}
