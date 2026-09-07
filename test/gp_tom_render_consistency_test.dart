import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/credit_card_provider.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/enums/qr_print_mode.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/src/printing/escpos/escpos.dart';
import 'package:kasseneck_api/widgets/keck_receipt_widget.dart';

import 'helpers/test_receipts.dart';

/// GP-Tom-Kartenbeleg: das Plugin liefert ab 0.1.0 den Betrag in CENT
/// (int), aeltere gespeicherte Belege haben Euro (double). Alle Render-Pfade
/// muessen denselben Betrag zeigen — hier Thermodruck vs. Beleg-Widget; das
/// Beleg-PDF im Backend nutzt dieselbe Heuristik und ist mit DENSELBEN
/// Fixture-Werten getestet (kasseneck: functions/test/unit/helper.test.js,
/// describe 'helper.formatGpTomAmount').
///
/// Hintergrund: Das Backend-PDF druckte einen 10-Cent-GP-Tom-Beleg als
/// "10,00 EUR", waehrend App-Viewer/Druck korrekt "0,10" zeigten.

Map<String, dynamic> gpTomData(dynamic amount) => {
      'batchNumber': 7,
      'externalTransactionID': 'EXT-123',
      'terminalID': 'T1234567',
      'emvAid': 'A0000000031010',
      'emvAppLable': 'VISA CREDIT',
      'cardDataEntry': 'CONTACTLESS',
      'cardBrand': 'VISA',
      'cardNumber': '**** 1234',
      'amount': amount,
      'currencyCode': 'EUR',
      'pinOk': true,
      'approvedCode': '00',
      'sequenceNumber': 42,
      // Plugin-`toMap` schreibt den Key mit Tippfehler.
      'transacitonType': 1,
    };

KasseneckReceipt gpTomReceipt({
  required dynamic cardAmount,
  required int itemPriceCents,
  Map<String, dynamic>? statt,
  Set<String> ohne = const {},
}) =>
    buildReceipt(
      items: [KasseneckItem(name: 'Testartikel', quantity: 1, vat: VatRate.vat20, priceCents: itemPriceCents)],
      paymentMethod: KeckPaymentMethod.creditCard,
      cardProvider: CreditCardProvider.gpTomAndroid,
      cardPaymentData: {
        ...gpTomData(cardAmount),
        ...?statt,
      }..removeWhere((k, _) => ohne.contains(k)),
    );

Future<List<String>> renderPrintTexts(KasseneckReceipt receipt) async {
  final paper = PrintPaper(paperSize: KeckPaperSize.mm58, profile: CapabilityProfile());
  await paper.setKeckReceipt(receipt, qrMode: QrPrintMode.native);
  return paper.myPosPaper.commands
      .where((c) => c['type'] == 'text')
      .map((c) => c['value'] as String)
      .toList();
}

Future<List<String>> renderWidgetTexts(WidgetTester tester, KasseneckReceipt receipt) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: KeckReceiptWidget(receipt: receipt))),
  ));
  return tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').toList();
}

void main() {
  // Fixture-Werte 1:1 wie im Backend-Test (helper.formatGpTomAmount) — so ist
  // die Cent/Euro-Heuristik repo-uebergreifend festgenagelt.
  group('formatGpTomAmount (Paritaet mit Backend-PDF)', () {
    test('ganzzahlig -> Cent', () {
      expect(formatGpTomAmount(10), '0,10'); // 10 Cent, NICHT 10 Euro
      expect(formatGpTomAmount(1000), '10,00');
      expect(formatGpTomAmount(0), '0,00');
    });
    test('Kommazahl -> Euro (Alt-Beleg)', () {
      expect(formatGpTomAmount(12.34), '12,34');
      expect(formatGpTomAmount(0.1), '0,10');
    });
    test('null -> "-"', () {
      expect(formatGpTomAmount(null), '-');
    });
    test('Nicht-Zahl -> "-"', () {
      // Das Backend antwortet auf denselben Wert mit '-' („null/Nicht-Zahl",
      // functions/helper.js). Hier warf der Cast, und der `catch (_)` um den
      // Kartenblock schnitt alles ab, was nach der Betragszeile kommt.
      expect(formatGpTomAmount('12,34'), '-');
      expect(formatGpTomAmount(true), '-');
      expect(formatGpTomAmount(double.nan), '-');
      expect(formatGpTomAmount(double.infinity), '-');
    });
  });

  group('gpTomTransactionType (Paritaet mit Backend-PDF)', () {
    test('liest beide Keys, Labels wie im PDF', () {
      expect(gpTomTransactionType({'transacitonType': 1}), 'Sale');
      expect(gpTomTransactionType({'transactionType': 3}), 'Refund');
      expect(gpTomTransactionType({'transacitonType': 4}), 'Close Batch');
      expect(gpTomTransactionType({}), '');
    });
  });

  testWidgets('GP-Tom 10 Cent: Print == Widget == 0,10 (nie 10,00)', (tester) async {
    final receipt = gpTomReceipt(cardAmount: 10, itemPriceCents: 10);
    // runAsync: CapabilityProfile.load() macht echtes Asset-I/O (siehe
    // print_widget_consistency_test.dart).
    final printTexts = (await tester.runAsync(() => renderPrintTexts(receipt)))!;
    final widgetTexts = await renderWidgetTexts(tester, receipt);

    const expectedLine = 'Sale Amount EUR 0,10';
    expect(printTexts, contains(expectedLine));
    expect(widgetTexts, contains(expectedLine));

    // Der 100x-Fehler darf in KEINEM Pfad auftauchen.
    expect(printTexts.where((t) => t.contains('10,00')), isEmpty);
    expect(widgetTexts.where((t) => t.contains('10,00')), isEmpty);
  });

  testWidgets('GP-Tom Alt-Beleg (Euro-double): Print == Widget == 12,34', (tester) async {
    final receipt = gpTomReceipt(cardAmount: 12.34, itemPriceCents: 1234);
    final printTexts = (await tester.runAsync(() => renderPrintTexts(receipt)))!;
    final widgetTexts = await renderWidgetTexts(tester, receipt);

    const expectedLine = 'Sale Amount EUR 12,34';
    expect(printTexts, contains(expectedLine));
    expect(widgetTexts, contains(expectedLine));
  });

  /// Ein `pinOk`, das nicht `true` oder `false` ist, darf den Block nicht
  /// abschneiden.
  ///
  /// `InquireResult.pinOk` ist `bool?` und fehlt bei jeder kontaktlosen Zahlung
  /// ohne PIN — der Normalfall unter 50 €. Der Druck stolperte darueber, und der
  /// `catch (_)` um den Kartenblock verschluckte den Fehler: gedruckt wurde bis
  /// zur Betragszeile, PIN, Autorisierungscode und Sequenznummer fehlten. Das
  /// Widget entschied schon immer mit `== true` und blieb vollstaendig — genau
  /// diese Abweichung faengt der Vergleich hier.
  ///
  /// Die drei letzten Zeilen sind das, was der Test wirklich prueft: sie stehen
  /// HINTER der Stelle, an der es riss.
  for (final (name, receipt) in [
    ('pinOk fehlt ganz', gpTomReceipt(cardAmount: 1000, itemPriceCents: 1000, ohne: {'pinOk'})),
    ('pinOk ist null', gpTomReceipt(cardAmount: 1000, itemPriceCents: 1000, statt: {'pinOk': null})),
    ('pinOk ist Text', gpTomReceipt(cardAmount: 1000, itemPriceCents: 1000, statt: {'pinOk': 'true'})),
    ('pinOk ist Zahl', gpTomReceipt(cardAmount: 1000, itemPriceCents: 1000, statt: {'pinOk': 1})),
  ]) {
    testWidgets('GP-Tom, $name: der Block bleibt vollstaendig, Print == Widget', (tester) async {
      final printTexts = (await tester.runAsync(() => renderPrintTexts(receipt)))!;
      final widgetTexts = await renderWidgetTexts(tester, receipt);

      for (final zeile in ['PIN NOT OK', 'Authorization Code 00', 'Sequence Number: 42']) {
        expect(printTexts, contains(zeile), reason: 'Druck, $name');
        expect(widgetTexts, contains(zeile), reason: 'Widget, $name');
      }
    });
  }

  testWidgets('GP-Tom, amount als Text: der Block bleibt vollstaendig', (tester) async {
    // Derselbe Riss eine Zeile hoeher: der Betrag kam als Text herein, der Cast
    // warf, und der Kartenblock endete nach der Kartennummer.
    final receipt = gpTomReceipt(cardAmount: '10,00', itemPriceCents: 1000);
    final printTexts = (await tester.runAsync(() => renderPrintTexts(receipt)))!;
    final widgetTexts = await renderWidgetTexts(tester, receipt);

    for (final zeile in ['Sale Amount EUR -', 'PIN OK', 'Authorization Code 00', 'Sequence Number: 42']) {
      expect(printTexts, contains(zeile), reason: 'Druck');
      expect(widgetTexts, contains(zeile), reason: 'Widget');
    }
  });

  testWidgets('GP-Tom, pinOk true: es bleibt bei PIN OK', (tester) async {
    // Gegenprobe zur Null-Haertung: `== true` darf die Aussage nicht verlieren.
    final receipt = gpTomReceipt(cardAmount: 1000, itemPriceCents: 1000);
    final printTexts = (await tester.runAsync(() => renderPrintTexts(receipt)))!;
    final widgetTexts = await renderWidgetTexts(tester, receipt);

    expect(printTexts, contains('PIN OK'));
    expect(widgetTexts, contains('PIN OK'));
  });
}
