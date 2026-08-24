// ── Trinkgeld am Beleg ──────────────────────────────────────────────────────
// Der Client schickt nur den Betrag und wer ihn bekommt; die Positionen baut
// das Backend. Hier steht, dass genau das rausgeht — und dass ein falscher
// Betrag gar nicht erst losfliegt.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/enums/receipt_type.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/models/keck_tip.dart';

import 'helpers/test_receipts.dart';

KasseneckApi apiWith(MockClient client) => KasseneckApi(
      apiKey: 'test-key',
      cashregisterToken: base64Encode(utf8.encode('CASHBOX-9:secret')),
      httpClient: client,
    );

MockClient successClient(void Function(http.Request) capture) =>
    MockClient((request) async {
      capture(request);
      return http.Response(
        jsonEncode({'status': 'success', 'data': buildReceipt().toJson()}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

MockClient neverCalled() => MockClient((request) async {
      fail('HTTP-Request darf hier nicht passieren: ${request.url}');
    });

final ware = KasseneckItem(
    name: 'Maniküre', quantity: 1, vat: VatRate.vat20, priceCents: 4500);

Map<String, dynamic> paramsVon(http.Request r) =>
    (jsonDecode(r.body) as Map<String, dynamic>)['params']
        as Map<String, dynamic>;

void main() {
  group('KeckTip — Prüfungen', () {
    test('ohne Empfänger genügt ein Betrag', () {
      expect(const KeckTip(cents: 200).isValid, isTrue);
    });

    test('null und negativ sind kein Trinkgeld', () {
      expect(const KeckTip(cents: 0).isValid, isFalse);
      expect(const KeckTip(cents: -100).isValid, isFalse);
    });

    test('eine leere Empfängerliste ist ein Fehler, kein „egal"', () {
      // Sonst würde aus „ich wollte aufteilen, habe aber niemanden gewählt"
      // still ein Trinkgeld an den angemeldeten Benutzer.
      expect(const KeckTip(cents: 200, recipients: []).isValid, isFalse);
    });

    test('die Summe der Anteile muss der Betrag sein', () {
      const t = KeckTip(cents: 200, recipients: [
        KeckTipRecipient(registerUserId: 'ru_7', cents: 120),
        KeckTipRecipient(registerUserId: 'ru_9', cents: 70),
      ]);
      expect(t.fehler,
          'Trinkgeld: Summe der Empfänger (190) entspricht nicht dem Betrag (200)');
    });

    test('passt die Summe, ist die Aufteilung in Ordnung', () {
      const t = KeckTip(cents: 200, recipients: [
        KeckTipRecipient(registerUserId: 'ru_7', cents: 120),
        KeckTipRecipient(registerUserId: 'ru_9', cents: 80),
      ]);
      expect(t.fehler, isNull);
    });

    test('dieselbe Person zweimal ist ein Tippfehler', () {
      const t = KeckTip(cents: 200, recipients: [
        KeckTipRecipient(registerUserId: 'ru_7', cents: 100),
        KeckTipRecipient(registerUserId: 'ru_7', cents: 100),
      ]);
      expect(t.fehler, contains('doppelt'));
    });

    test('ein Anteil von 0 ist keiner', () {
      const t = KeckTip(cents: 100, recipients: [
        KeckTipRecipient(registerUserId: 'ru_7', cents: 100),
        KeckTipRecipient(registerUserId: 'ru_9', cents: 0),
      ]);
      expect(t.isValid, isFalse);
    });

    test('ohne Kassen-Benutzer geht es nicht', () {
      const t = KeckTip(cents: 100, recipients: [
        KeckTipRecipient(registerUserId: '  ', cents: 100),
      ]);
      expect(t.isValid, isFalse);
    });
  });

  group('KeckTip — Gestalt', () {
    test('fuer() legt alles auf eine Person', () {
      final t = KeckTip.fuer('ru_7', cents: 250);
      expect(t.recipients!.single.registerUserId, 'ru_7');
      expect(t.recipients!.single.cents, 250);
      expect(t.isValid, isTrue);
    });

    test('euro() rundet genau einmal auf Cent', () {
      expect(KeckTip.euro(amount: 1.15).cents, 115);
      expect(KeckTipRecipient.euro(registerUserId: 'ru_7', amount: 2.005).cents,
          201);
    });

    test('toJson ist die Langform, Leerstellen bleiben weg', () {
      expect(const KeckTip(cents: 200).toJson(), {'cents': 200});
    });

    test('Zahlart und Empfänger reisen mit', () {
      final t = KeckTip.fuer('ru_7',
          cents: 200, paymentMethod: KeckPaymentMethod.creditCard);
      expect(t.toJson(), {
        'cents': 200,
        'paymentMethod': 'creditCard',
        'recipients': [
          {'registerUserId': 'ru_7', 'cents': 200},
        ],
      });
    });
  });

  group('sellReceipt', () {
    test('schickt das Trinkgeld als Parameter — nicht als Position', () async {
      late http.Request captured;
      final api = apiWith(successClient((r) => captured = r));

      await api.sellReceipt(
        paymentMethod: KeckPaymentMethod.creditCard,
        items: [ware],
        tip: KeckTip.fuer('ru_7', cents: 200),
      );

      final params = paramsVon(captured);
      expect(params['tip'], {
        'cents': 200,
        'recipients': [
          {'registerUserId': 'ru_7', 'cents': 200},
        ],
      });
      // Die Positionen bleiben unberührt: Trinkgeld hängt das Backend an.
      expect((params['items'] as List).length, 1);
      expect((params['items'] as List).first['unitPriceCents'], 4500);
    });

    test('ohne Trinkgeld steht kein Feld im Aufruf', () async {
      late http.Request captured;
      final api = apiWith(successClient((r) => captured = r));

      await api
          .sellReceipt(paymentMethod: KeckPaymentMethod.cash, items: [ware]);

      expect(paramsVon(captured).containsKey('tip'), isFalse);
    });

    test('ein falscher Betrag fliegt gar nicht erst los', () async {
      final api = apiWith(neverCalled());
      expect(
        () => api.sellReceipt(
          paymentMethod: KeckPaymentMethod.cash,
          items: [ware],
          tip: const KeckTip(cents: 0),
        ),
        throwsArgumentError,
      );
    });

    test('eine falsche Aufteilung ebenfalls nicht', () async {
      final api = apiWith(neverCalled());
      expect(
        () => api.sellReceipt(
          paymentMethod: KeckPaymentMethod.cash,
          items: [ware],
          tip: const KeckTip(cents: 200, recipients: [
            KeckTipRecipient(registerUserId: 'ru_7', cents: 100),
          ]),
        ),
        throwsArgumentError,
      );
    });

    test('ein Beleg nur mit Trinkgeld ist keiner', () async {
      final api = apiWith(neverCalled());
      expect(
        () => api.sellReceipt(
          paymentMethod: KeckPaymentMethod.cash,
          items: const [],
          tip: KeckTip.fuer('ru_7', cents: 200),
        ),
        throwsArgumentError,
      );
    });
  });

  group('Belegarten', () {
    test('Trinkgeld nur auf Standard und Training', () {
      // Ein Storno spiegelt die Positionen des Originals; über den Parameter
      // entstünde beim Zurücknehmen neues Trinkgeld.
      expect(ReceiptType.standard.allowsTip, isTrue);
      expect(ReceiptType.training.allowsTip, isTrue);
      expect(ReceiptType.cancellation.allowsTip, isFalse);
      expect(ReceiptType.zero.allowsTip, isFalse);
      expect(ReceiptType.start.allowsTip, isFalse);
    });
  });
}
