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
import 'package:kasseneck_api/models/keck_tip.dart';

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

    test('Trinkgeld kommt als eigene Position zurück (räumt sich selbst auf)',
        () async {
      final receipt = await api.sellReceipt(
        paymentMethod: KeckPaymentMethod.cash,
        items: [
          KasseneckItem(
            name: 'Integrationstest Leistung',
            quantity: 1,
            vat: VatRate.vat20,
            priceCents: 2000,
          ),
        ],
        // Ohne Empfänger: Über den API-Schlüssel ist niemand als
        // Kassen-Benutzer angemeldet, das Trinkgeld bleibt „nicht zugeordnet".
        // Genau dieser Fall trifft jede Anbindung ohne Kassen-Sitzung.
        tip: const KeckTip(cents: 150),
      );

      expect(receipt, isNotNull);
      // Der Server baut die Position — der Client hat nur den Betrag geschickt.
      expect(receipt!.tipItems.length, 1);
      expect(receipt.tipCents, 150);
      // Durchlaufender Posten: 0 %, und im Gesamtbetrag enthalten.
      expect(receipt.tipItems.single.vat.rate, 0);
      expect(receipt.staffTipCents, 150);
      expect(receipt.ownerTipCents, 0);
      expect(receipt.sumCents, 2150);
      expect(receipt.sig, isNotEmpty);
      expect(receipt.qr, isNotEmpty);

      final cancel = await api.cancelReceipt(receipt: receipt);
      expect(cancel, isNotNull);
      expect(cancel!.receiptType, ReceiptType.cancellation);
      expect(cancel.sumCents, -receipt.sumCents);
      // Die Spiegelung nimmt auch das Trinkgeld zurück — sonst bliebe der Topf
      // der Mitarbeiterin voll, obwohl der Beleg storniert ist.
      expect(cancel.tipCents, -150);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('Trinkgeld an einen Kassen-Benutzer (räumt sich selbst auf)',
        () async {
      final receipt = await api.sellReceipt(
        paymentMethod: KeckPaymentMethod.creditCard,
        items: [
          KasseneckItem(
            name: 'Integrationstest Leistung',
            quantity: 1,
            vat: VatRate.vat20,
            priceCents: 2000,
          ),
        ],
        tip: KeckTip.fuer(creds!.registerUserId!, cents: 200),
      );

      expect(receipt, isNotNull);
      expect(receipt!.tipCents, 200);
      final pos = receipt.tipItems.single;
      expect(pos.tipRecipientId, creds.registerUserId);
      expect(pos.tipRecipientName, isNotNull);
      // Zahlart des Trinkgelds: ohne Angabe die des Belegs.
      expect(pos.paymentMethod, 'creditCard');

      final cancel = await api.cancelReceipt(receipt: receipt);
      expect(cancel, isNotNull);
      expect(cancel!.tipCents, -200);
    },
        timeout: const Timeout(Duration(minutes: 3)),
        skip: creds?.registerUserId == null
            ? 'registerUserId fehlt in credentials.local.json'
            : null);

    test('ein abgelehnter Betrag verursacht keinen Beleg', () async {
      // Die Prüfung liegt im Client — hier steht, dass sie auch scharf ist,
      // wenn eine echte Kasse dahinterhängt.
      expect(
        () => api.sellReceipt(
          paymentMethod: KeckPaymentMethod.cash,
          items: [
            KasseneckItem(
              name: 'Integrationstest Leistung',
              quantity: 1,
              vat: VatRate.vat20,
              priceCents: 2000,
            ),
          ],
          tip: const KeckTip(cents: 0),
        ),
        throwsArgumentError,
      );
    }, timeout: const Timeout(Duration(minutes: 1)));

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
