// test/integration/kasseneck_demo_integration_test.dart
//
// Echte Requests gegen die Kasseneck-DEMO-Kasse. Bewusst OHNE
// TestWidgetsFlutterBinding: nur so ist echtes HTTP in flutter test möglich.
// Ohne credentials.local.json werden alle Tests übersprungen.

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/enums/receipt_type.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';

import 'credentials.dart';

void main() {
  final creds = DemoCredentials.tryLoad();

  group('Kasseneck-Demo', () {
    late KasseneckApi api;

    setUp(() {
      api = KasseneckApi(
        apiKey: creds!.apiKey,
        cashregisterToken: creds.cashregisterToken,
      );
    });

    test('Nullbeleg wird ausgestellt und signiert', () async {
      final receipt = await api.zeroReceipt();
      expect(receipt, isNotNull);
      expect(receipt!.receiptId, isNotEmpty);
      expect(receipt.receiptType, ReceiptType.zero);
      expect(receipt.sig, isNotEmpty);
      expect(receipt.qr, isNotEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('Kartenzahlungs-Beleg + Storno (räumt sich selbst auf)', () async {
      final receipt = await api.sellReceipt(
        paymentMethod: KeckPaymentMethod.creditCard,
        items: [
          KasseneckItem(
            name: 'Integrationstest Fahrt',
            quantity: 1,
            vat: VatRate.vat10,
            priceCents: 1250,
          ),
        ],
      );
      expect(receipt, isNotNull);
      expect(receipt!.receiptId, isNotEmpty);
      expect(receipt.paymentMethod, KeckPaymentMethod.creditCard);
      expect(receipt.sumCents, 1250); // Integer-Cents bis in die Antwort
      expect(receipt.sig, isNotEmpty);
      expect(receipt.qr, isNotEmpty);

      // Aufräumen gehört zum Test: Demo-Beleg sofort stornieren.
      final cancel = await api.cancelReceipt(receipt: receipt);
      expect(cancel, isNotNull);
      expect(cancel!.receiptType, ReceiptType.cancellation);
      expect(cancel.sumCents, -receipt.sumCents);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('ungültiger API-Key → sauberer Serverfehler, kein Crash', () async {
      final bad = KasseneckApi(
        apiKey: 'invalid-demo-key',
        cashregisterToken: 'invalid-token',
      );
      await expectLater(bad.zeroReceipt(), throwsException);
    }, timeout: const Timeout(Duration(minutes: 2)));
  },
      skip: creds == null
          ? 'test/integration/credentials.local.json fehlt — Demo-Integrationstests übersprungen'
          : null);
}
