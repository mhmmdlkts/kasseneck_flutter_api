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
    http.Response(jsonEncode(j), 200, headers: {'content-type': 'application/json'});

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
      grund: 'kunde_storniert',
      anmerkung: 'Auftrag abgesagt',
    );

    expect(gesendet.url.toString(), 'https://api.kasseneck.at/v1/cancelReceipt');
    expect(gesendet.headers['Authorization'], 'Bearer test-key');
    final params = (jsonDecode(gesendet.body) as Map)['params'] as Map;
    expect(params, {
      'cashregisterId': 'KECK-1',
      'originalReceiptId': 'KECK-1-ID-12',
      'reason': 'kunde_storniert',
      'note': 'Auftrag abgesagt',
    });
    expect(erg.originalReceiptId, 'KECK-1-ID-12');
    expect(erg.originalFullReceiptId, 'voll-12');
    expect(erg.restmengen, [0, 0]);
    expect(erg.beleg.receiptId, isNotEmpty);
  });

  test('Teilstorno und Kartendaten der Erstattung gehen mit', () async {
    late Map params;
    final api = apiWith(MockClient((r) async {
      params = (jsonDecode(r.body) as Map)['params'] as Map;
      return huelle(stornoAntwort());
    }));

    await api.stornieren(
      cashregisterId: 'KECK-1',
      originalReceiptId: 'KECK-1-ID-12',
      grund: 'fehleingabe',
      positionen: [(index: 1, menge: 2)],
      zahlungsart: KeckPaymentMethod.creditCard,
      kartenanbieter: CreditCardProvider.hobexHps,
      kartenzahlungId: '178834783507100000',
      kartenzahlungsdaten: {'cardNumber': '541333******0021'},
    );

    expect(params['items'], [
      {'index': 1, 'quantity': 2}
    ]);
    expect(params['paymentMethod'], 'creditCard');
    expect(params['creditCardProvider'], 'hobexHps');
    expect(params['cardPaymentId'], '178834783507100000');
    expect(params['cardPaymentData'], {'cardNumber': '541333******0021'});
  });

  test('ohne Kartendaten keine Kartenfelder', () async {
    late Map params;
    final api = apiWith(MockClient((r) async {
      params = (jsonDecode(r.body) as Map)['params'] as Map;
      return huelle(stornoAntwort());
    }));
    await api.stornieren(cashregisterId: 'KECK-1', originalReceiptId: 'KECK-1-ID-12', grund: 'fehleingabe');
    expect(params.containsKey('creditCardProvider'), isFalse);
    expect(params.containsKey('cardPaymentId'), isFalse);
    expect(params.containsKey('cardPaymentData'), isFalse);
  });

  group('Abweisung vor dem Aufruf', () {
    final api = apiWith(nieGerufen());

    test('unbekannter Grund', () {
      expect(
        () => api.stornieren(cashregisterId: 'KECK-1', originalReceiptId: 'KECK-1-ID-12', grund: 'weil'),
        throwsA(isA<KasseneckValidationError>()),
      );
    });

    test('leere Positionsliste waere ein stiller Vollstorno', () {
      expect(
        () => api.stornieren(cashregisterId: 'KECK-1', originalReceiptId: 'KECK-1-ID-12', grund: 'fehleingabe', positionen: []),
        throwsA(isA<KasseneckValidationError>()),
      );
    });

    test('Kartendaten bei Barerstattung', () {
      expect(
        () => api.stornieren(
          cashregisterId: 'KECK-1',
          originalReceiptId: 'KECK-1-ID-12',
          grund: 'kunde_storniert',
          zahlungsart: KeckPaymentMethod.cash,
          kartenzahlungId: 'x',
        ),
        throwsA(isA<KasseneckValidationError>()),
      );
    });

    test('fehlender Bezug', () {
      expect(
        () => api.stornieren(cashregisterId: 'KECK-1', originalReceiptId: ' ', grund: 'fehleingabe'),
        throwsA(isA<KasseneckValidationError>()),
      );
    });
  });

  test('fachliche Ablehnung kommt mit stabilem Code', () async {
    final api = apiWith(MockClient((r) async => huelle({
          'status': 'error',
          'message': 'Beleg ist bereits vollständig storniert.',
          'code': 'bereits_storniert',
        })));
    await expectLater(
      api.stornieren(cashregisterId: 'KECK-1', originalReceiptId: 'KECK-1-ID-12', grund: 'fehleingabe'),
      throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'bereits_storniert')),
    );
    expect(istStornoFehlercode('bereits_storniert'), isTrue);
  });

  test('Antwort ohne Bezug: Fehler traegt die Kennung des schon signierten Stornos', () async {
    final antwort = stornoAntwort();
    (antwort['data'] as Map).remove('cancellationOf');
    final api = apiWith(MockClient((r) async => huelle(antwort)));
    await expectLater(
      api.stornieren(cashregisterId: 'KECK-1', originalReceiptId: 'KECK-1-ID-12', grund: 'fehleingabe'),
      throwsA(isA<KasseneckValidationError>().having((e) => e.receiptId, 'receiptId', isNotNull)),
    );
  });
}
