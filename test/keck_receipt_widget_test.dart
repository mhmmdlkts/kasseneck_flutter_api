import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/credit_card_provider.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/services/rksv_service.dart';
import 'package:kasseneck_api/widgets/keck_receipt_widget.dart';

import 'helpers/test_receipts.dart';
import 'print_rendering_test.dart' show helperMarker, expectedStripePaidAt;

Future<List<String>> pump(WidgetTester tester, KasseneckReceipt receipt) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: KeckReceiptWidget(receipt: receipt))),
  ));
  return tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').toList();
}

void main() {
  group('Karten-Bloecke je Provider (Widget)', () {
    testWidgets('hobexHps: PAN + bedingte Zeilen', (tester) async {
      final texts = await pump(tester, buildReceipt(
        items: cartA().items,
        cardProvider: CreditCardProvider.hobexHps,
        cardPaymentData: {
          'date': 'd', 'tid': 't', 'no': '42', 'type': 'SELL', 'cardBrand': 'Visa',
          'cardNumber': '****1234', 'responseCode': '0', 'cvm': '0',
          'approvalCode': 'ABC', 'cardExpiry': '2612',
        },
      ));
      expect(texts, containsAll(['Hobex Beleg', 'PAN:', '****1234', 'Gueltig:', '2612', 'Genehmigung:', 'ABC']));
      expect(texts, isNot(contains('Unterschrift')));
    });

    testWidgets('myposPro: Datum formatiert + Unterschrift bei signature_required', (tester) async {
      final texts = await pump(tester, buildReceipt(
        items: cartA().items,
        cardProvider: CreditCardProvider.myposPro,
        cardPaymentData: {
          'TID': 'T1', 'date_time': '260612104530', 'application_name': 'VISA',
          'pan': '**1234', 'signature_required': true, 'STAN': 7,
          'authorization_code': 'A1', 'reference_number': 'R1', 'AID': 'AID1',
        },
      ));
      expect(texts, containsAll(['MyPos Beleg', '12.06.2026 10:45:30', '**1234', '000007', 'Unterschrift']));
    });

    testWidgets('sumup: gerenderte Felder', (tester) async {
      final texts = await pump(tester, buildReceipt(
        items: cartA().items,
        cardProvider: CreditCardProvider.sumup,
        cardPaymentData: {'success': true, 'cardType': 'VISA', 'cardLastDigits': '1234',
          'paymentType': 'POS', 'amount': 12.5, 'currency': 'EUR', 'transactionCode': 'TC1', 'entryMode': 'nfc'},
      ));
      expect(texts, containsAll(['SumUp Beleg', 'VISA', '**** 1234', 'TC1', 'NFC']));
    });

    testWidgets('custom-Provider rendert keinen Karten-Block', (tester) async {
      final texts = await pump(tester, buildReceipt(
        items: cartA().items,
        cardProvider: CreditCardProvider.custom,
        cardPaymentData: {'foo': 'bar'},
      ));
      expect(texts.where((t) => t.contains('Beleg') && t != 'Beleg-ID:'), isEmpty);
    });

    testWidgets('stripe (Karte): Titel, maskierte Nummer, Referenz', (tester) async {
      final texts = await pump(tester, buildReceipt(
        items: cartA().items,
        cardProvider: CreditCardProvider.stripe,
        cardPaymentId: 'pi_3Txxxxxxxxxxxxxx',
        cardPaymentData: {
          'paymentMethodType': 'card',
          'amount': 1250,
          'currency': 'eur',
          'receiptUrl': 'https://pay.stripe.com/receipts/xyz',
          'paidAt': 1784300000,
          'statementDescriptor': 'KASSENECK',
          'cardBrand': 'visa',
          'cardLastDigits': '4242',
          'wallet': 'apple_pay',
          'cardFunding': 'debit',
          'threeDSecure': 'authenticated',
        },
      ));
      expect(texts, containsAll([
        'Online-Zahlung (Stripe)',
        'visa Debitkarte (Apple Pay)',
        '**** **** **** 4242',
        '3-D Secure: ja',
        'Gesamtbetrag 12,50 EUR',
        'Bezahlt: ${expectedStripePaidAt(1784300000)}',
        'Abrechnung: KASSENECK',
        'Referenz: pi_3Txxxxxxxxxxxxxx',
      ]));
      expect(texts.any((t) => t.contains('pay.stripe.com')), isFalse);
    });

    testWidgets('stripe (EPS): EPS-Zeile statt Kartenzeilen', (tester) async {
      final texts = await pump(tester, buildReceipt(
        items: cartA().items,
        cardProvider: CreditCardProvider.stripe,
        cardPaymentId: 'pi_epsxxxxxxxxxxxx',
        cardPaymentData: {
          'paymentMethodType': 'eps',
          'epsBank': 'bank_austria',
          'amount': 500,
          'currency': 'eur',
        },
      ));
      expect(texts, containsAll([
        'Online-Zahlung (Stripe)',
        'EPS - Bank Austria',
        'Gesamtbetrag 5,00 EUR',
        'Referenz: pi_epsxxxxxxxxxxxx',
      ]));
      expect(texts.where((t) => t.startsWith('3-D Secure')), isEmpty);
      expect(texts.where((t) => t.startsWith('****')), isEmpty);
    });
  });

  group('Crash-Guard: kaputte cardPaymentData', () {
    for (final (provider, data) in [
      (CreditCardProvider.myposPro, {'TID': 'x'}),            // date_time fehlt
      (CreditCardProvider.sumup, {'amount': 'kein-bool'}),     // success fehlt/cast bricht
      (CreditCardProvider.gpTomAndroid, {'amount': 'abc'}),    // amount-cast bricht
      (CreditCardProvider.stripe, {'paymentMethodType': 'card', 'wallet': 42}), // Wallet kein String
    ]) {
      testWidgets('$provider mit kaputten Daten -> kein roter Screen, Beleg rendert', (tester) async {
        final texts = await pump(tester, buildReceipt(
          items: cartA().items,
          cardProvider: provider,
          cardPaymentData: data,
        ));
        expect(tester.takeException(), isNull, reason: 'Widget darf nicht crashen');
        expect(texts, contains('Footer Eins'));
        expect(texts, contains('Gesamt:'));
      });
    }
  });

  group('Beleg-Bausteine', () {
    testWidgets('Ausfalltext bei beschaedigter Signatur', (tester) async {
      final texts = await pump(tester, buildReceipt(items: cartA().items, sig: 'h.p.${helperMarker()}'));
      expect(texts, contains(RKSVService.signatureDeviceDamagedKey));
    });
    testWidgets('Kunde-Block nur wenn customerDetails vorhanden', (tester) async {
      final with_ = await pump(tester, buildReceipt(items: cartA().items)..customerDetails = ['Max']);
      expect(with_, contains('Kunde:'));
      final without = await pump(tester, buildReceipt(items: cartA().items));
      expect(without, isNot(contains('Kunde:')));
    });
    testWidgets('thanksMessage + legalMessage werden gerendert', (tester) async {
      final texts = await pump(tester, buildReceipt(items: cartA().items)
        ..legalMessage = ['Fahrzeug: W-1']
        ..thanksMessage = ['Danke!']);
      expect(texts, containsAll(['Fahrzeug: W-1', 'Danke!']));
    });
  });
}
