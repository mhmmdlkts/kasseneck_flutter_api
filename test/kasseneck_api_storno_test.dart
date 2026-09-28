import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/enums/credit_card_provider.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/kasseneck_api.dart';

import 'helpers/test_receipts.dart';

/// Storno mit Bezug ueber den API-Schluessel-Zugang (`KasseneckApi.stornieren`)
/// — Zwilling von `cancelReceipt` im Client des npm-Pakets.
KasseneckApi apiWith(MockClient client) => KasseneckApi(
      apiKey: 'test-key',
      cashregisterToken: base64Encode(utf8.encode('KECK-1:secret')),
      httpClient: client,
    );

http.Response huelle(Map<String, dynamic> j) =>
    http.Response(jsonEncode(j), 200, headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'});

Map<String, dynamic> stornoAntwort() => {
      'status': 'success',
      'data': {
        ...buildReceipt().toJson(),
        'cancellationOf': {'receiptId': 'KECK-1-ID-12', 'fullReceiptId': 'voll-12'},
        'remaining': [0, 0],
      },
    };

MockClient nieGerufen() => MockClient((r) async => fail('darf nicht rausgehen: ${r.url}'));

void main() {
  test('ruft den Endpunkt cancelReceipt mit Bezug und Grund und liest Restmengen', () async {
    late http.Request gesendet;
    final api = apiWith(MockClient((r) async {
      gesendet = r;
      return huelle(stornoAntwort());
    }));

    final erg = await api.stornieren(
      cashregisterId: 'KECK-1',
      originalReceiptId: 'KECK-1-ID-12',
      grund: 'customer_cancelled',
      anmerkung: 'Auftrag abgesagt',
    );

    expect(gesendet.url.toString(), 'https://api.kasseneck.at/v3/cancelReceipt');
    expect(gesendet.headers['Authorization'], 'Bearer test-key');
    final params = (jsonDecode(gesendet.body) as Map)['params'] as Map;
    expect(params, {
      'cashregisterId': 'KECK-1',
      'originalReceiptId': 'KECK-1-ID-12',
      'reason': 'customer_cancelled',
      'note': 'Auftrag abgesagt',
    });
    expect(erg.originalReceiptId, 'KECK-1-ID-12');
    expect(erg.originalFullReceiptId, 'voll-12');
    expect(erg.restmengen, [0, 0]);
    expect(erg.beleg.receiptId, isNotEmpty);
  });

  test('Teilstorno und Kartendaten der Erstattung gehen in der Zahlung mit, nie als Einzelfelder', () async {
    late Map params;
    final api = apiWith(MockClient((r) async {
      params = (jsonDecode(r.body) as Map)['params'] as Map;
      return huelle(stornoAntwort());
    }));

    await api.stornieren(
      cashregisterId: 'KECK-1',
      originalReceiptId: 'KECK-1-ID-12',
      grund: 'input_error',
      positionen: [(index: 1, menge: 2)],
      zahlungen: const [
        KeckPaymentInput(
          method: KeckPaymentMethod.creditCard,
          amountCents: -700,
          refundOf: 'p1',
          provider: CreditCardProvider.hobexHps,
          providerPaymentId: '178834783507100000',
          providerData: {'cardNumber': '541333******0021'},
        ),
      ],
    );

    expect(params['items'], [
      {'index': 1, 'quantity': 2}
    ]);
    expect(params['payments'], [
      {
        'method': 'creditCard',
        'amountCents': -700,
        'provider': 'hobexHps',
        'providerPaymentId': '178834783507100000',
        'providerData': {'cardNumber': '541333******0021'},
        'refundOf': 'p1',
      }
    ]);
    for (final alt in ['paymentMethod', 'creditCardProvider', 'cardPaymentId', 'cardPaymentData']) {
      expect(params.containsKey(alt), isFalse, reason: alt);
    }
  });

  group('Abweisung vor dem Aufruf', () {
    final api = apiWith(nieGerufen());

    test('unbekannter Grund, auch der alte deutsche', () {
      for (final grund in ['weil', 'fehleingabe', 'kunde_storniert']) {
        expect(
          () => api.stornieren(cashregisterId: 'KECK-1', originalReceiptId: 'KECK-1-ID-12', grund: grund),
          throwsA(isA<KasseneckValidationError>()),
          reason: grund,
        );
      }
    });

    test('leere Positionsliste waere ein stiller Vollstorno', () {
      expect(
        () => api.stornieren(cashregisterId: 'KECK-1', originalReceiptId: 'KECK-1-ID-12', grund: 'input_error', positionen: []),
        throwsA(isA<KasseneckValidationError>()),
      );
    });

    test('Karten-Rueckbuchung ohne Anbieter und ohne Kennung', () {
      expect(
        () => api.stornieren(
          cashregisterId: 'KECK-1',
          originalReceiptId: 'KECK-1-ID-12',
          grund: 'customer_cancelled',
          zahlungen: const [KeckPaymentInput(method: KeckPaymentMethod.creditCard, amountCents: -700, refundOf: 'p1')],
        ),
        throwsA(isA<KasseneckValidationError>().having((e) => e.reason, 'reason', contains('ohne Anbieter'))),
      );
    });

    test('Karten-Rueckbuchung ueber einen Anbieter ohne Bezug', () {
      expect(
        () => api.stornieren(
          cashregisterId: 'KECK-1',
          originalReceiptId: 'KECK-1-ID-12',
          grund: 'customer_cancelled',
          zahlungen: const [
            KeckPaymentInput(method: KeckPaymentMethod.creditCard, amountCents: -700, refundOf: 'p1', provider: CreditCardProvider.sumup),
          ],
        ),
        throwsA(isA<KasseneckValidationError>().having((e) => e.reason, 'reason', contains('ohne Bezug'))),
      );
    });

    test('fehlender Bezug', () {
      expect(
        () => api.stornieren(cashregisterId: 'KECK-1', originalReceiptId: ' ', grund: 'input_error'),
        throwsA(isA<KasseneckValidationError>()),
      );
    });
  });

  test('custom braucht keine Kennung, und das Original vom Kassenweg liefert den Bezug', () async {
    var gerufen = 0;
    final api = apiWith(MockClient((r) async {
      gerufen++;
      return huelle(stornoAntwort());
    }));
    await api.stornieren(
      cashregisterId: 'KECK-1',
      originalReceiptId: 'KECK-1-ID-12',
      grund: 'input_error',
      zahlungen: const [
        KeckPaymentInput(method: KeckPaymentMethod.creditCard, amountCents: -700, refundOf: 'p1', provider: CreditCardProvider.custom),
      ],
    );
    final original = buildReceipt()
      ..payments = const [
        KeckPayment(id: 'p1', methodValue: 'creditCard', amountCents: 700, providerValue: 'sumup', providerPaymentId: 'tx-4711'),
      ];
    await api.stornieren(
      cashregisterId: 'KECK-1',
      originalReceiptId: 'KECK-1-ID-12',
      grund: 'input_error',
      original: original,
      zahlungen: const [
        KeckPaymentInput(method: KeckPaymentMethod.creditCard, amountCents: -700, refundOf: 'p1', provider: CreditCardProvider.sumup),
      ],
    );
    expect(gerufen, 2);
  });

  test('fachliche Ablehnung kommt mit stabilem Code', () async {
    final api = apiWith(MockClient((r) async => huelle({
          'status': 'error',
          'message': 'Beleg ist bereits vollständig storniert.',
          'code': 'already_cancelled',
        })));
    await expectLater(
      api.stornieren(cashregisterId: 'KECK-1', originalReceiptId: 'KECK-1-ID-12', grund: 'input_error'),
      throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'already_cancelled')),
    );
    expect(istStornoFehlercode('already_cancelled'), isTrue);
    expect(istStornoFehlercode('bereits_storniert'), isFalse);
  });

  test('Antwort ohne Bezug: response_unreadable mit Ausgang unklar und der Kennung des schon signierten Stornos', () async {
    final antwort = stornoAntwort();
    (antwort['data'] as Map).remove('cancellationOf');
    final api = apiWith(MockClient((r) async => huelle(antwort)));
    await expectLater(
      api.stornieren(cashregisterId: 'KECK-1', originalReceiptId: 'KECK-1-ID-12', grund: 'input_error'),
      throwsA(isA<KasseneckApiError>()
          .having((e) => e.code, 'code', 'response_unreadable')
          .having((e) => e.outcome, 'outcome', ErrorOutcome.unknown)
          .having((e) => e.details['receiptId'], 'receiptId', isNotNull)),
    );
  });
}
