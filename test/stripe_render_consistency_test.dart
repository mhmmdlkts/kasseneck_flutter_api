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
import 'print_rendering_test.dart' show expectedStripePaidAt;

/// Stripe-`cardPaymentData` (Online-Zahlung ueber Payment-Link): das Backend
/// haengt seit Juli 2026 `creditCardProvider:'stripe'`, `cardPaymentId` und
/// `cardPaymentData` an Online-Belege. Die Fixture-Werte hier sind 1:1 das
/// Beispiel aus der Backend-Doku (amount in CENT, paidAt in Unix-SEKUNDEN),
/// damit ein zukuenftiger Parity-Test gegen das Beleg-PDF dieselben Werte
/// nutzen kann. Hier: Thermodruck und App-Widget muessen fuer dieselbe
/// Fixture denselben Betrag und dieselben Kernwerte zeigen.
Map<String, dynamic> stripeCardData() => {
      'paymentMethodType': 'card',
      'amount': 1250,
      'currency': 'eur',
      'receiptUrl': 'https://pay.stripe.com/receipts/xyz', // wird nie gerendert
      'paidAt': 1784300000,
      'statementDescriptor': 'KASSENECK',
      'cardBrand': 'visa',
      'cardLastDigits': '4242',
      'wallet': 'apple_pay',
      'cardFunding': 'debit',
      'threeDSecure': 'authenticated',
    };

KasseneckReceipt stripeReceipt({required int itemPriceCents}) => buildReceipt(
      items: [KasseneckItem(name: 'Testartikel', quantity: 1, vat: VatRate.vat20, priceCents: itemPriceCents)],
      paymentMethod: KeckPaymentMethod.creditCard,
      cardProvider: CreditCardProvider.stripe,
      cardPaymentId: 'pi_3Txxxxxxxxxxxxxx',
      cardPaymentData: stripeCardData(),
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
  testWidgets('Stripe-Karte: Print == Widget bei Betrag, Datum, Referenz', (tester) async {
    final receipt = stripeReceipt(itemPriceCents: 1250);
    final printTexts = (await tester.runAsync(() => renderPrintTexts(receipt)))!;
    final widgetTexts = await renderWidgetTexts(tester, receipt);

    const expectedAmount = 'Gesamtbetrag 12,50 EUR';
    final expectedPaidAt = 'Bezahlt: ${expectedStripePaidAt(1784300000)}';
    const expectedRef = 'Referenz: pi_3Txxxxxxxxxxxxxx';
    const expectedBrandLine = 'visa Debitkarte (Apple Pay)';
    const expectedMasked = '**** **** **** 4242';

    expect(printTexts, contains(expectedAmount));
    expect(widgetTexts, contains(expectedAmount));

    expect(printTexts, contains(expectedPaidAt));
    expect(widgetTexts, contains(expectedPaidAt));

    expect(printTexts, contains(expectedRef));
    expect(widgetTexts, contains(expectedRef));

    expect(printTexts, contains(expectedBrandLine));
    expect(widgetTexts, contains(expectedBrandLine));

    expect(printTexts, contains(expectedMasked));
    expect(widgetTexts, contains(expectedMasked));

    // receiptUrl darf in keinem Pfad auftauchen
    expect(printTexts.any((t) => t.contains('pay.stripe.com')), isFalse);
    expect(widgetTexts.any((t) => t.contains('pay.stripe.com')), isFalse);
  });

  testWidgets('Stripe-EPS: Print == Widget bei EPS-Zeile und Betrag', (tester) async {
    final receipt = buildReceipt(
      items: [KasseneckItem(name: 'Testartikel', quantity: 1, vat: VatRate.vat20, priceCents: 500)],
      paymentMethod: KeckPaymentMethod.creditCard,
      cardProvider: CreditCardProvider.stripe,
      cardPaymentId: 'pi_epsxxxxxxxxxxxx',
      cardPaymentData: {
        'paymentMethodType': 'eps',
        'epsBank': 'bank_austria',
        'amount': 500,
        'currency': 'eur',
      },
    );
    final printTexts = (await tester.runAsync(() => renderPrintTexts(receipt)))!;
    final widgetTexts = await renderWidgetTexts(tester, receipt);

    const expectedEpsLine = 'EPS - Bank Austria';
    const expectedAmount = 'Gesamtbetrag 5,00 EUR';

    expect(printTexts, contains(expectedEpsLine));
    expect(widgetTexts, contains(expectedEpsLine));
    expect(printTexts, contains(expectedAmount));
    expect(widgetTexts, contains(expectedAmount));

    expect(printTexts.where((t) => t.startsWith('****')), isEmpty);
    expect(widgetTexts.where((t) => t.startsWith('****')), isEmpty);
  });
}
