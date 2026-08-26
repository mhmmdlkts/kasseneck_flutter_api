import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/kasseneck_api.dart';

void main() {
  group('Fristen im Cloud-Weg', () {
    test('hobexPay bekommt die Kartenfrist, nicht die kurze Lesefrist', () async {
      // Eine Antwort, die laenger braucht als die Lesefrist, aber kuerzer als
      // die Kartenfrist: die Zahlung darf daran NICHT scheitern.
      final mock = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        return http.Response(
          '{"data":{"transactionId":"TX-1","tid":"T1","receipt":"1","'
          'approvalCode":"A1","transactionDate":"2026-08-24T10:00:00",'
          '"cardNumber":"1234","cardExpiry":"1230","brand":"visa",'
          '"cardIssuer":"bank","responseCode":"0","transactionType":"purchase",'
          '"currency":"EUR","cvm":"0"}}',
          200,
        );
      });
      final api = KasseneckApi(
        apiKey: 'k',
        cashregisterToken: 'dGVzdDp0ZXN0',
        httpClient: mock,
        readTimeout: const Duration(milliseconds: 30),
        cardTimeout: const Duration(seconds: 2),
      );

      final receipt = await api.hobexPay(transactionId: 'TX-1', amount: 25);
      expect(receipt.responseCode, '0');
    });

    test('eine lesende Abfrage laeuft weiterhin in die kurze Frist', () async {
      final mock = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return http.Response('{"data":[]}', 200);
      });
      final api = KasseneckApi(
        apiKey: 'k',
        cashregisterToken: 'dGVzdDp0ZXN0',
        httpClient: mock,
        readTimeout: const Duration(milliseconds: 30),
        cardTimeout: const Duration(seconds: 2),
      );

      await expectLater(
        api.getReceipts(DateTime(2026, 8, 24), DateTime(2026, 8, 25)),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  group('hobexGetStatus', () {
    test('hobexGetStatus liefert den Beleg zur Kennung', () async {
      late http.Request seen;
      final mock = MockClient((request) async {
        seen = request;
        return http.Response(
          '{"status":"success","data":{"transactionId":"TX-1","tid":"T1",'
          '"receipt":"1","approvalCode":"A1","transactionDate":'
          '"2026-08-24T10:00:00","cardNumber":"1234","cardExpiry":"1230",'
          '"brand":"visa","cardIssuer":"bank","responseCode":"0",'
          '"transactionType":"purchase","currency":"EUR","cvm":"0"}}',
          200,
        );
      });
      final api = KasseneckApi(apiKey: 'k', cashregisterToken: 'dGVzdDp0ZXN0', httpClient: mock);

      final receipt = await api.hobexGetStatus(transactionId: 'TX-1');

      expect(receipt, isNotNull);
      expect(receipt!.transactionId, 'TX-1');
      expect(seen.url.path, contains('hobexGetStatus'));
    });

    test('hobexGetStatus: unbekannte Kennung -> null statt Ausnahme', () async {
      final mock = MockClient((_) async => http.Response('{"status":"error"}', 200));
      final api = KasseneckApi(apiKey: 'k', cashregisterToken: 'dGVzdDp0ZXN0', httpClient: mock);
      expect(await api.hobexGetStatus(transactionId: 'TX-unbekannt'), isNull);
    });

    test('hobexGetStatus: Server-Fehler ist ein Transportfehler und darf NICHT als null (unbelastet) gelesen werden', () async {
      final mock = MockClient((_) async => http.Response('server explodiert', 500));
      final api = KasseneckApi(apiKey: 'k', cashregisterToken: 'dGVzdDp0ZXN0', httpClient: mock);
      await expectLater(
        api.hobexGetStatus(transactionId: 'TX-1'),
        throwsA(isA<Exception>()),
      );
    });

    test('hobexGetStatus: unerwarteter Rumpf (kein Objekt) wirft eine aussagekraeftige Ausnahme statt eines rohen TypeError', () async {
      final mock = MockClient((_) async => http.Response('[1,2,3]', 200));
      final api = KasseneckApi(apiKey: 'k', cashregisterToken: 'dGVzdDp0ZXN0', httpClient: mock);
      await expectLater(
        api.hobexGetStatus(transactionId: 'TX-1'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'Meldung',
          contains('hobexGetStatus'),
        )),
      );
    });
  });
}
