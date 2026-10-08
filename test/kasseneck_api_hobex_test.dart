import 'dart:convert';
import 'dart:io';


import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/src/receipt/codes.dart' show anmeldungUndRandCodes;
import 'package:kasseneck_api/src/register/fehler.dart' show paymentCallRejectedCodes;

KasseneckApi _mit(Object? daten, List<http.Request> log) => KasseneckApi(
      apiKey: 'k',
      cashregisterToken: 'dGVzdDp0ZXN0',
      httpClient: MockClient((r) async {
        log.add(r);
        return http.Response(jsonEncode({'status': 'success', 'message': '', 'data': daten}), 200,
            headers: const {'content-type': 'application/json', 'kasseneck-api-version': 'v3'});
      }),
    );

void main() {
  // Zwilling von npm rc.2 (06679d1, test/geldwege-ausgang.test.ts): Erfolg
  // gemeldet heisst, die Karte ist belastet bzw. der Einzug gelaufen. Ist die
  // Nutzlast dann unbrauchbar, ist das `response_unreadable` mit Ausgang
  // unklar, nie ein gewoehnlicher Lesefehler, der zum zweiten Versuch einluede.
  group('Geldwege: Erfolg gemeldet, Nutzlast unbrauchbar', () {
    final faelle = <(String, Object?, Future<Object?> Function(KasseneckApi))>[
      ('hobexPayApi', <String, dynamic>{}, (api) => api.hobexPay(transactionId: 'tx-1', amountCents: 1234)),
      ('hobexPayApi', null, (api) => api.hobexPay(transactionId: 'tx-1', amountCents: 1234)),
      ('stripeCaptureIntent', {'id': 'pi_1'}, (api) => api.stripeCaptureIntent(stripeSessionId: 'cs_test_a1b2c3')),
      ('stripeCaptureIntent', null, (api) => api.stripeCaptureIntent(stripeSessionId: 'cs_test_a1b2c3')),
    ];
    for (final (name, daten, aufruf) in faelle) {
      test('$name mit data ${jsonEncode(daten)} ist response_unreadable, Ausgang unklar, genau ein Aufruf', () async {
        final log = <http.Request>[];
        await expectLater(
          aufruf(_mit(daten, log)),
          throwsA(isA<KasseneckApiError>()
              .having((e) => e.functionName, 'functionName', name)
              .having((e) => e.code, 'code', 'response_unreadable')
              .having((e) => e.outcome, 'outcome', ErrorOutcome.unknown)
              .having((e) => isOutcomeUnknown(e), 'isOutcomeUnknown', isTrue)),
        );
        expect(log, hasLength(1));
      });
    }
  });

  group('Fristen im Cloud-Weg', () {
    test('hobexPay bekommt die Kartenfrist, nicht die kurze Lesefrist', () async {
      // Eine Antwort, die laenger braucht als die Lesefrist, aber kuerzer als
      // die Kartenfrist: die Zahlung darf daran NICHT scheitern.
      final mock = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        return http.Response(
          '{"status":"success","data":{"transactionId":"TX-1","tid":"T1","receipt":"1","'
          'approvalCode":"A1","transactionDate":"2026-08-24T10:00:00",'
          '"cardNumber":"1234","cardExpiry":"1230","brand":"visa",'
          '"cardIssuer":"bank","responseCode":"0","transactionType":"purchase",'
          '"currency":"EUR","cvm":"0"}}',
          200, headers: const {'kasseneck-api-version': 'v3'});
      });
      final api = KasseneckApi(
        apiKey: 'k',
        cashregisterToken: 'dGVzdDp0ZXN0',
        httpClient: mock,
        readTimeout: const Duration(milliseconds: 30),
        cardTimeout: const Duration(seconds: 2),
      );

      final receipt = await api.hobexPay(transactionId: 'TX-1', amountCents: 2500);
      expect(receipt.responseCode, '0');
    });

    test('eine lesende Abfrage laeuft weiterhin in die kurze Frist', () async {
      final mock = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return http.Response('{"status":"success","data":[]}', 200, headers: const {'kasseneck-api-version': 'v3'});
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
        throwsA(isA<KasseneckHttpError>().having((e) => e.reason, 'reason', KasseneckHttpError.reasonTimeout)),
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
          200, headers: const {'kasseneck-api-version': 'v3'});
      });
      final api = KasseneckApi(apiKey: 'k', cashregisterToken: 'dGVzdDp0ZXN0', httpClient: mock);

      final receipt = await api.hobexGetStatus(transactionId: 'TX-1');

      expect(receipt, isNotNull);
      expect(receipt!.transactionId, 'TX-1');
      expect(seen.url.path, contains('hobexGetStatus'));
    });

    test('hobexGetStatus: unbekannte Kennung -> null statt Ausnahme', () async {
      final mock = MockClient((_) async => http.Response('{"status":"error"}', 200, headers: const {'kasseneck-api-version': 'v3'}));
      final api = KasseneckApi(apiKey: 'k', cashregisterToken: 'dGVzdDp0ZXN0', httpClient: mock);
      expect(await api.hobexGetStatus(transactionId: 'TX-unbekannt'), isNull);
    });

    test('hobexGetStatus: Server-Fehler ist ein Transportfehler und darf NICHT als null (unbelastet) gelesen werden', () async {
      final mock = MockClient((_) async => http.Response('server explodiert', 500, headers: const {'kasseneck-api-version': 'v3'}));
      final api = KasseneckApi(apiKey: 'k', cashregisterToken: 'dGVzdDp0ZXN0', httpClient: mock);
      await expectLater(
        api.hobexGetStatus(transactionId: 'TX-1'),
        throwsA(isA<Exception>()),
      );
    });

    test('hobexGetStatus: unerwarteter Rumpf (kein Objekt) wirft eine aussagekraeftige Ausnahme statt eines rohen TypeError', () async {
      final mock = MockClient((_) async => http.Response('[1,2,3]', 200, headers: const {'kasseneck-api-version': 'v3'}));
      final api = KasseneckApi(apiKey: 'k', cashregisterToken: 'dGVzdDp0ZXN0', httpClient: mock);
      await expectLater(
        api.hobexGetStatus(transactionId: 'TX-1'),
        throwsA(isA<KasseneckHttpError>()
            .having((e) => e.functionName, 'functionName', contains('hobexGetStatus'))
            .having((e) => e.reason, 'reason', 'missing-status')),
      );
    });

    test('hobexGetStatus: die Meldung traegt den Antwortrumpf nicht', () async {
      // Der Rumpf kann tragen, was nicht ins Protokoll gehoert. Die
      // Klaerschleife schreibt ihre Ausnahmen in den Nachweistext, der im
      // Belastungsstreit gelesen wird -- dieselbe Regel wie in _huelle.
      final mock = MockClient((_) async => http.Response('["GEHEIM-4711"]', 200, headers: const {'kasseneck-api-version': 'v3'}));
      final api = KasseneckApi(apiKey: 'k', cashregisterToken: 'dGVzdDp0ZXN0', httpClient: mock);
      await expectLater(
        api.hobexGetStatus(transactionId: 'TX-1'),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), 'ohne Rumpf', isNot(contains('GEHEIM')))),
      );
    });

    test('hobexGetStatus: 200 mit HTML ist ein benannter Fehler, keine rohe FormatException', () async {
      // Captive Portal oder CDN-Fehlerseite. json.decode stand hier
      // ungesichert -- die FormatException traegt ihre Eingabe im Text.
      final mock = MockClient((_) async => http.Response('<html>Gateway GEHEIM-4711</html>', 200, headers: const {'kasseneck-api-version': 'v3'}));
      final api = KasseneckApi(apiKey: 'k', cashregisterToken: 'dGVzdDp0ZXN0', httpClient: mock);
      await expectLater(
        api.hobexGetStatus(transactionId: 'TX-1'),
        throwsA(isA<KasseneckHttpError>()
            .having((e) => e.reason, 'reason', 'not-json')
            .having((e) => e.toString(), 'ohne Rumpf', isNot(contains('GEHEIM')))),
      );
    });
  });

  // Schlussreview F1: der Sammelfang des Backends antwortet nach dem Anstoss
  // bei hobex bzw. Stripe mit einer Fehlerhuelle OHNE Code
  // (payment-endpoints.js, `Error hobex details`, `Fehler beim Capturing`).
  // Auf den Geldwegen ist das Ausgang unklar; abgelehnt ist nur ein Code, der
  // vor dem Anbieter entsteht.
  group('Geldwege: Fehlerhuelle', () {
    KasseneckApi fehlerApi(Map<String, dynamic> huelle, List<http.Request> log) => KasseneckApi(
          apiKey: 'k',
          cashregisterToken: 'dGVzdDp0ZXN0',
          httpClient: MockClient((r) async {
            log.add(r);
            return http.Response(jsonEncode(huelle), 200,
                headers: const {'content-type': 'application/json', 'kasseneck-api-version': 'v3'});
          }),
        );
    final geldwege = <(String, Future<Object?> Function(KasseneckApi))>[
      ('hobexPayApi', (api) => api.hobexPay(transactionId: 'tx-1', amountCents: 1234)),
      ('hobexRefundApi', (api) => api.hobexRefund(transactionId: 'tx-1', amountCents: 1234)),
      ('stripeCaptureIntent', (api) => api.stripeCaptureIntent(stripeSessionId: 'cs_test_a1b2c3')),
    ];

    for (final (name, aufruf) in geldwege) {
      test('$name: Huelle ohne Code ist Ausgang unklar, genau ein Aufruf', () async {
        final log = <http.Request>[];
        await expectLater(
          aufruf(fehlerApi({'status': 'error', 'message': 'Error hobex details:', 'data': null}, log)),
          throwsA(isA<KasseneckApiError>()
              .having((e) => e.functionName, 'functionName', name)
              .having((e) => e.code, 'code', isNull)
              .having((e) => e.outcome, 'outcome', ErrorOutcome.unknown)
              .having((e) => isOutcomeUnknown(e), 'isOutcomeUnknown', isTrue)),
        );
        expect(log, hasLength(1));
      });

      test('$name: ein Code ausserhalb der Ablehnungsliste ist Ausgang unklar', () async {
        for (final code in ['server_error', 'payments_invalid', 'send_failed']) {
          await expectLater(
            aufruf(fehlerApi({'status': 'error', 'message': 'm', 'code': code}, [])),
            throwsA(isA<KasseneckApiError>().having((e) => e.outcome, 'outcome', ErrorOutcome.unknown)),
            reason: code,
          );
        }
      });

      test('$name: jeder Ablehnungscode ist rejected', () async {
        for (final code in paymentCallRejectedCodes) {
          await expectLater(
            aufruf(fehlerApi({'status': 'error', 'message': 'm', 'code': code, 'data': {'code': code}}, [])),
            throwsA(isA<KasseneckApiError>()
                .having((e) => e.code, 'code', code)
                .having((e) => e.outcome, 'outcome', ErrorOutcome.rejected)),
            reason: code,
          );
        }
      });
    }

    test('ausserhalb der Geldwege bleibt eine Huelle ohne Code rejected', () {
      expect(const KasseneckApiError('getReceipt', 'm').outcome, ErrorOutcome.rejected);
      expect(const KasseneckApiError('createPaymentLinkStripe', 'm').outcome, ErrorOutcome.rejected);
      expect(const KasseneckApiError('hobexGetStatus', 'm').outcome, ErrorOutcome.rejected);
    });

    test('die Codes mit unklarem Ausgang bleiben auf den Geldwegen unklar', () {
      for (final code in ['dialect_mismatch', 'response_unreadable', 'response_translation_failed']) {
        expect(KasseneckApiError('hobexPayApi', 'm', code: code).outcome, ErrorOutcome.unknown, reason: code);
      }
    });

    test('die Ablehnungsliste stammt aus dem Vertrag: Anmeldung, Rand, Modul/Rechte, route_missing', () {
      final vok = jsonDecode(File('test/fixtures/vertrag/v3/v3-vokabular.json').readAsStringSync())
          as Map<String, dynamic>;
      final alle = ((vok['errorCodes'] as Map)['all'] as List).cast<String>().toSet();
      final erlaubt = {...anmeldungUndRandCodes, 'module_inactive', 'not_permitted', 'route_missing'}
        ..removeAll(['dialect_mismatch', 'response_translation_failed']);
      for (final code in paymentCallRejectedCodes) {
        expect(alle.contains(code) || clientErrorCodes.contains(code), isTrue, reason: '$code nicht im Vertrag');
        expect(erlaubt, contains(code), reason: '$code entsteht nicht sicher vor dem Anbieter');
      }
      expect(paymentCallRejectedCodes, isNot(contains('response_unreadable')));
      // Und keiner fehlt: festgeschrieben wie PAYMENT_CALL_REJECTED_CODES im
      // npm-Paket (26 seit 1.8.0 bzw. 10.7 mit app_check_missing und
      // app_check_invalid). Fehlt hier ein Code, der vor dem Anbieter
      // abweist, meldete der Geldweg ihn als unklar.
      expect(paymentCallRejectedCodes, erlaubt);
      expect(paymentCallRejectedCodes, hasLength(26));
      expect(paymentCallRejectedCodes, containsAll(['app_check_missing', 'app_check_invalid']));
    });
  });

  // Schlussreview F4: Betraege in ganzen Cent wie im npm-Paket; umgerechnet
  // wird genau einmal, an der Hobex-Grenze.
  group('Hobex-Betraege in Cent', () {
    test('hobexPay und hobexRefund schicken Euro aus ganzen Cent', () async {
      final log = <http.Request>[];
      final api = _mit({'transactionId': 'tx-1'}, log);
      await api.hobexRefund(transactionId: 'tx-1', amountCents: 1234, tipCents: 5);
      final rumpf = (jsonDecode(log.single.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;
      expect(rumpf['amount'], 12.34);
      expect(rumpf['tip'], 0.05);
      expect(rumpf['transactionId'], 'tx-1');
    });

    test('Eingabefehler werfen vor dem Netz KasseneckValidationError', () async {
      final log = <http.Request>[];
      final api = _mit(const <String, dynamic>{}, log);
      final faelle = <Future<Object?> Function()>[
        () => api.hobexPay(transactionId: 'tx-1', amountCents: 0),
        () => api.hobexPay(transactionId: 'tx-1', amountCents: 100, tipCents: -1),
        () => api.hobexPay(transactionId: ' ', amountCents: 100),
        () => api.hobexRefund(transactionId: 'tx-1', amountCents: 0),
      ];
      for (final f in faelle) {
        await expectLater(f(), throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'request')));
      }
      expect(log, isEmpty);
    });
  });
}
