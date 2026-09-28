import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/enums/credit_card_provider.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/kasse.dart' show RegisterReceiptClient;
import 'package:kasseneck_api/register.dart';

import 'helpers/test_receipts.dart';

/// `payments` am Verkauf und am Storno — Zwilling der Regeln in
/// `client/receipts.ts` (createReceiptParams, gepruefteStornoZahlungen):
/// ausschliesslich neben Einzel-Zahlungsart und Kartenfeldern, `mixed` wird nie
/// gesendet, Betraege in ganzen Cent. Jeder Fehler faellt, bevor etwas
/// hinausgeht.

KasseneckApi apiWith(MockClient client) => KasseneckApi(
      apiKey: 'test-key',
      cashregisterToken: base64Encode(utf8.encode('KECK-1:secret')),
      httpClient: client,
    );

http.Response huelle(Map<String, dynamic> j) =>
    http.Response(jsonEncode(j), 200, headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'});

MockClient nieGerufen() => MockClient((r) async => fail('darf nicht rausgehen: ${r.url}'));

final ware = KasseneckItem(name: 'x', quantity: 1, vat: VatRate.vat20, priceCents: 3500);

const karte = KeckPaymentInput(
  method: KeckPaymentMethod.creditCard,
  amountCents: 2000,
  provider: CreditCardProvider.sumup,
  providerPaymentId: 'S-1',
  providerData: {'cardLastDigits': '4720'},
);
const bar = KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 1500, tenderedCents: 2000);

Map<String, dynamic> stornoAntwort() => {
      'status': 'success',
      'data': {
        ...buildReceipt().toJson(),
        'cancellationOf': {'receiptId': 'KECK-1-ID-12'},
        'remaining': [0],
      },
    };

({RegisterReceiptClient client, List<http.Request> log}) kasseMit(Map<String, dynamic> antwort) {
  final log = <http.Request>[];
  final mock = MockClient((request) async {
    log.add(request);
    return huelle(antwort);
  });
  return (
    client: RegisterReceiptClient(RegisterTransport(
      idToken: () async => 'id-token-1',
      sessionId: () async => 'sess-1',
      cashregisterId: 'KASSE1',
      httpClient: mock,
    )),
    log: log,
  );
}

Map<String, dynamic> belegAntwort() => {'status': 'success', 'data': buildReceipt().toJson()};

void main() {
  group('KasseneckApi.sellReceipt mit payments', () {
    test('payments gehen hinaus, paymentMethod und Kartenfelder nicht', () async {
      late Map params;
      final api = apiWith(MockClient((r) async {
        params = (jsonDecode(r.body) as Map)['params'] as Map;
        return huelle(belegAntwort());
      }));
      await api.sellReceipt(items: [ware], payments: [karte, bar]);
      expect(params['payments'], [
        {'method': 'creditCard', 'amountCents': 2000, 'provider': 'sumup', 'providerPaymentId': 'S-1', 'providerData': {'cardLastDigits': '4720'}},
        {'method': 'cash', 'amountCents': 1500, 'tenderedCents': 2000},
      ]);
      expect(params.containsKey('paymentMethod'), isFalse);
      expect(params.containsKey('creditCardProvider'), isFalse);
      expect(params.containsKey('cardPaymentId'), isFalse);
      expect(params.containsKey('cardPaymentData'), isFalse);
    });

    test('Formfehler einer Zahlung wirft vor dem Netz', () {
      final api = apiWith(nieGerufen());
      expect(
          () => api.sellReceipt(items: [ware], payments: const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 0)]),
          throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('Zahlung 1'))));
      expect(() => api.sellReceipt(items: [ware], payments: const [KeckPaymentInput(method: KeckPaymentMethod.mixed, amountCents: 100)]),
          throwsArgumentError);
    });
  });

  group('KasseneckApi.stornieren mit zahlungen', () {
    test('Rueckzahlungen gehen hinaus', () async {
      late Map params;
      final api = apiWith(MockClient((r) async {
        params = (jsonDecode(r.body) as Map)['params'] as Map;
        return huelle(stornoAntwort());
      }));
      await api.stornieren(
        cashregisterId: 'KECK-1',
        originalReceiptId: 'KECK-1-ID-12',
        grund: 'input_error',
        zahlungen: const [
          KeckPaymentInput(
              method: KeckPaymentMethod.creditCard, amountCents: -2000, refundOf: 'p1', provider: CreditCardProvider.sumup, providerPaymentId: 'rf-1'),
          KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: -1500, refundOf: 'p2'),
        ],
      );
      expect(params['payments'], [
        {'method': 'creditCard', 'amountCents': -2000, 'provider': 'sumup', 'providerPaymentId': 'rf-1', 'refundOf': 'p1'},
        {'method': 'cash', 'amountCents': -1500, 'refundOf': 'p2'},
      ]);
      expect(params.containsKey('paymentMethod'), isFalse);
    });

    test('positive Betraege, mixed und Karte ohne Bezug -- alles vor dem Netz', () {
      final api = apiWith(nieGerufen());
      Future<void> storno(List<KeckPaymentInput> z) =>
          api.stornieren(cashregisterId: 'KECK-1', originalReceiptId: 'KECK-1-ID-12', grund: 'input_error', zahlungen: z);
      expect(() => storno(const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 100)]),
          throwsA(isA<KasseneckValidationError>()));
      expect(() => storno(const [KeckPaymentInput(method: KeckPaymentMethod.mixed, amountCents: -100)]),
          throwsA(isA<KasseneckValidationError>()));
      expect(() => storno(const [KeckPaymentInput(method: KeckPaymentMethod.creditCard, amountCents: -100, refundOf: 'p1')]),
          throwsA(isA<KasseneckValidationError>()));
    });
  });

  group('RegisterReceiptClient', () {
    test('verkaufen mit zahlungen: Liste geht hinaus, keine Einzel-Zahlungsart', () async {
      final f = kasseMit(belegAntwort());
      await f.client.verkaufen(positionen: [ware], zahlungen: [karte, bar]);
      final params = jsonDecode(f.log.single.body)['params'] as Map<String, dynamic>;
      expect((params['payments'] as List).length, 2);
      expect(params.containsKey('paymentMethod'), isFalse);
    });

    test('verkaufen: mixed und ungueltige Betraege werfen vor dem Netz', () async {
      final f = kasseMit(belegAntwort());
      await expectLater(
          f.client.verkaufen(positionen: [ware], zahlungen: const [KeckPaymentInput(method: KeckPaymentMethod.mixed, amountCents: 100)]),
          throwsA(isA<KasseneckValidationError>()));
      await expectLater(
          f.client.verkaufen(positionen: [ware], zahlungen: const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: -1)]),
          throwsA(isA<KasseneckValidationError>()));
      expect(f.log, isEmpty);
    });

    test('stornieren mit zahlungen: Rueckzahlungen gehen hinaus; Karte ohne Bezug wirft vor dem Netz', () async {
      final f = kasseMit(stornoAntwort());
      await f.client.stornieren(
        originalReceiptId: 'KASSE1-ID-42',
        grund: 'input_error',
        zahlungen: const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: -500, refundOf: 'p2')],
      );
      final params = jsonDecode(f.log.single.body)['params'] as Map<String, dynamic>;
      expect(params['payments'], [
        {'method': 'cash', 'amountCents': -500, 'refundOf': 'p2'},
      ]);
      await expectLater(
          f.client.stornieren(
            originalReceiptId: 'KASSE1-ID-42',
            grund: 'input_error',
            zahlungen: const [
              KeckPaymentInput(method: KeckPaymentMethod.creditCard, amountCents: -500, refundOf: 'p1', provider: CreditCardProvider.gpTomAndroid),
            ],
          ),
          throwsA(isA<KasseneckValidationError>()));
      expect(f.log.length, 1);
    });
  });
}
