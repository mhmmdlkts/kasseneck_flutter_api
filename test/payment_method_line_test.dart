import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/credit_card_provider.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/enums/qr_print_mode.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/src/printing/escpos/escpos.dart';
import 'package:kasseneck_api/widgets/keck_receipt_widget.dart';

import 'helpers/test_receipts.dart';

/// Auf jedem Beleg steht direkt unter der Gesamt-Zeile "Zahlungsart: <Label>"
/// -- unabhaengig davon, ob danach noch ein Provider-Kartenblock (GP Tom/
/// Stripe/...) folgt. Parity zum Backend-Beleg-PDF (paymentMethodToString).

Future<List<({String left, String right})>> renderPrintDoubles(KasseneckReceipt receipt) async {
  final paper = PrintPaper(paperSize: KeckPaperSize.mm58, profile: CapabilityProfile());
  await paper.setKeckReceipt(receipt, qrMode: QrPrintMode.native);
  return paper.myPosPaper.commands
      .where((c) => c['type'] == 'doubleText')
      .map((c) => (left: c['leftValue'] as String, right: c['rightValue'] as String))
      .toList();
}

Future<List<String>> renderWidgetTexts(WidgetTester tester, KasseneckReceipt receipt) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: KeckReceiptWidget(receipt: receipt))),
  ));
  return tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').toList();
}

void main() {
  testWidgets('Druck: Barzahlungs-Beleg zeigt Zahlungsart direkt nach Gesamt', (tester) async {
    final receipt = buildReceipt(items: cartA().items, paymentMethod: KeckPaymentMethod.cash);
    final doubles = (await tester.runAsync(() => renderPrintDoubles(receipt)))!;

    final gesamtIndex = doubles.indexWhere((d) => d.left == 'Gesamt:');
    expect(gesamtIndex, isNonNegative);
    expect(doubles[gesamtIndex + 1].left, 'Zahlungsart:');
    expect(doubles[gesamtIndex + 1].right, 'Barzahlung');
  });

  testWidgets('Druck: Stripe-Kartenbeleg zeigt Zahlungsart ZUSAETZLICH zum Provider-Block', (tester) async {
    final receipt = buildReceipt(
      items: cartA().items,
      paymentMethod: KeckPaymentMethod.creditCard,
      cardProvider: CreditCardProvider.stripe,
      cardPaymentId: 'pi_3Txxxxxxxxxxxxxx',
      cardPaymentData: {
        'paymentMethodType': 'card',
        'amount': 6086,
        'currency': 'eur',
        'cardBrand': 'visa',
        'cardLastDigits': '4242',
      },
    );
    final doubles = (await tester.runAsync(() => renderPrintDoubles(receipt)))!;

    final gesamtIndex = doubles.indexWhere((d) => d.left == 'Gesamt:');
    expect(gesamtIndex, isNonNegative);
    expect(doubles[gesamtIndex + 1].left, 'Zahlungsart:');
    expect(doubles[gesamtIndex + 1].right, 'Kartenzahlung');

    // Provider-Block bleibt zusaetzlich vorhanden
    final printer = PrintPaper(paperSize: KeckPaperSize.mm58, profile: CapabilityProfile());
    await printer.setKeckReceipt(receipt, qrMode: QrPrintMode.native);
    final texts = printer.myPosPaper.commands.where((c) => c['type'] == 'text').map((c) => c['value'] as String);
    expect(texts, contains('Online-Zahlung (Stripe)'));
  });

  testWidgets('Widget: Barzahlungs-Beleg zeigt Zahlungsart-Zeile', (tester) async {
    final receipt = buildReceipt(items: cartA().items, paymentMethod: KeckPaymentMethod.cash);
    final texts = await renderWidgetTexts(tester, receipt);
    expect(texts, contains('Zahlungsart:'));
    expect(texts, contains('Barzahlung'));
  });

  testWidgets('Widget: Kartenzahlungs-Beleg zeigt Zahlungsart-Zeile', (tester) async {
    final receipt = buildReceipt(items: cartA().items, paymentMethod: KeckPaymentMethod.creditCard);
    final texts = await renderWidgetTexts(tester, receipt);
    expect(texts, contains('Zahlungsart:'));
    expect(texts, contains('Kartenzahlung'));
  });
}
