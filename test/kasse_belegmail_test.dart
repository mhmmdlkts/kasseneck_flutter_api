import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/kasse.dart';
import 'package:kasseneck_api/register.dart';

/// Beleg per E-Mail an den Endkunden (`sendReceiptEmail`) auf dem
/// Kassen-Benutzer-Weg — Zwilling des gleichnamigen Aufrufs im JS-Paket.
///
/// Rot-Probe je Fall (belegt, nicht behauptet):
///   * „Aufruf und Nutzlast": Endpunktname auf `sendReceiptEmail` belassen und
///     `to` durch `email` ersetzt → rot; Adresse ungetrimmt → rot.
///   * „Sprache": `language` immer mitschicken → rot beim leeren Fall.
///   * „fehlende Pflichtangabe": den Wurf entfernen → rot (es ginge ein Aufruf
///     mit leerer Adresse hinaus, den erst das Backend abweist).
///   * „Fehlercodes": `code: fehlercodeAus(huelle)` im Transport streichen →
///     rot (die Kasse entschiede dann am deutschen Text).
///   * „kaputte Antwort nach erfolgreichem Versand": ein Wurf bei fehlendem
///     `at` → rot; `to` als Pflichtfeld lesen → rot.
///   * „Nicht-JSON": Rumpf blind als Hülle lesen → rot.

({RegisterReceiptClient client, List<http.Request> log}) clientMit(Object antwort) {
  final log = <http.Request>[];
  final mock = MockClient((request) async {
    log.add(request);
    return http.Response(
      antwort is String ? antwort : jsonEncode(antwort),
      200,
      headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'},
    );
  });
  return (
    client: RegisterReceiptClient(
      RegisterTransport(
        idToken: () async => 'id-token-1',
        sessionId: () async => 'sess-1',
        cashregisterId: 'KASSE1',
        httpClient: mock,
      ),
    ),
    log: log,
  );
}

Map<String, dynamic> erfolg({
  String to = 'gast@example.com',
  String? at = '2026-09-11T21:12:00+02:00',
  String? via = 'own',
}) =>
    {
      'status': 'success',
      'data': {
        'to': to,
        'at': ?at,
        'via': ?via,
      },
    };

void main() {
  group('belegSenden', () {
    test('Aufruf und Nutzlast: Beleg und Adresse gehen an sendReceiptEmail', () async {
      final f = clientMit(erfolg());

      final erg = await f.client.sendReceipt(
        fullReceiptId: 'voll-42',
        to: '  Gast@Example.com  ',
      );

      final anfrage = f.log.single;
      expect(anfrage.url.toString(), endsWith('/sendReceiptEmail'));
      expect(anfrage.headers['Authorization'], 'Bearer id-token-1');
      expect(anfrage.headers['register-session'], 'sess-1');
      final params = jsonDecode(anfrage.body)['params'] as Map<String, dynamic>;
      // Die Kasse steht im Transport, nicht in der Nutzlast dieses Aufrufs.
      expect(params, {
        'cashregisterId': 'KASSE1',
        'fullReceiptId': 'voll-42',
        'to': 'Gast@Example.com',
      });
      expect(erg.to, 'gast@example.com');
      expect(erg.at, '2026-09-11T21:12:00+02:00');
      expect(erg.via, 'own');
    });

    test('Sprache geht nur mit, wenn sie gesetzt ist', () async {
      final mit = clientMit(erfolg());
      await mit.client.sendReceipt(fullReceiptId: 'voll-42', to: 'gast@example.com', language: 'de');
      expect((jsonDecode(mit.log.single.body)['params'] as Map)['language'], 'de');

      final ohne = clientMit(erfolg());
      await ohne.client.sendReceipt(fullReceiptId: 'voll-42', to: 'gast@example.com', language: '  ');
      expect((jsonDecode(ohne.log.single.body)['params'] as Map).containsKey('language'), isFalse);
    });

    test('ohne Beleg oder ohne Adresse geht nichts hinaus', () async {
      final f = clientMit(erfolg());
      await expectLater(
        f.client.sendReceipt(fullReceiptId: '   ', to: 'gast@example.com'),
        throwsA(isA<KasseneckValidationError>()),
      );
      await expectLater(
        f.client.sendReceipt(fullReceiptId: 'voll-42', to: '   '),
        throwsA(isA<KasseneckValidationError>()),
      );
      expect(f.log, isEmpty);
    });

    test('eine Adresse, die das Backend ablehnt, wird hier NICHT vorab abgewiesen', () async {
      // Der Vertrag hat genau eine Adressprüfung, und die steht im Backend
      // (`kreiseck_validator`). Eine zweite, anders strenge hier würde
      // Adressen abweisen, die dort durchgehen — und mit einem anderen
      // Fehlertyp, an dem die Kasse nicht entscheiden kann.
      final f = clientMit({
        'status': 'error',
        'message': 'Die E-Mail-Adresse ist ungültig.',
        'code': 'invalid_address',
        'data': {'code': 'invalid_address'},
      });
      await expectLater(
        f.client.sendReceipt(fullReceiptId: 'voll-42', to: 'gast@@example'),
        throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'invalid_address')),
      );
      expect((jsonDecode(f.log.single.body)['params'] as Map)['to'], 'gast@@example');
    });

    for (final code in receiptEmailErrorCodes) {
      test('der Fehlercode "$code" kommt unverändert an', () async {
        final f = clientMit({
          'status': 'error',
          'message': 'irgendein deutscher Text, der sich ändern darf',
          'code': code,
          'data': {'code': code},
        });
        await expectLater(
          f.client.sendReceipt(fullReceiptId: 'voll-42', to: 'gast@example.com'),
          throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', code)),
        );
      });
    }

    test('eine kaputte Antwort nach erfolgreichem Versand wirft NICHT', () async {
      // Die Mail ist zu diesem Zeitpunkt draussen. Ein Wurf hier läse sich für
      // die Kasse wie „nicht gesendet" — und der Kassier schickte sie erneut.
      final f = clientMit({'status': 'success', 'data': {}});

      final erg = await f.client.sendReceipt(fullReceiptId: 'voll-42', to: 'gast@example.com');

      expect(erg.to, 'gast@example.com', reason: 'ohne data.to gilt die gesendete Adresse');
      expect(erg.at, isNull);
      expect(erg.via, isNull);
    });

    test('ein data, das gar keine Hülle ist, bleibt ein Fehler', () async {
      // Nachsichtig gelesen werden die einzelnen Felder, nicht die Hülle:
      // kommt statt eines Objekts ein Text zurück, hat nicht dieses Backend
      // geantwortet — dann ist auch „gesendet" nicht belegt. Dieselbe Grenze
      // zieht der API-Schlüssel-Weg (`_daten`).
      final f = clientMit({'status': 'success', 'data': 'ja'});
      await expectLater(
        f.client.sendReceipt(fullReceiptId: 'voll-42', to: 'gast@example.com'),
        throwsA(isA<KasseneckHttpError>().having((e) => e.reason, 'reason', 'data-not-object')),
      );
    });

    test('eine Nicht-JSON-Antwort ist ein HTTP-Fehler, keine leere Zusage', () async {
      final f = clientMit('<html>Gateway</html>');
      await expectLater(
        f.client.sendReceipt(fullReceiptId: 'voll-42', to: 'gast@example.com'),
        throwsA(isA<KasseneckHttpError>().having((e) => e.reason, 'reason', 'not-json')),
      );
    });

    test('ein Netzfehler wird nicht wiederholt', () async {
      // Der Versand kann draussen gewesen sein; ein zweiter Versuch wäre eine
      // zweite Mail an den Gast.
      var versuche = 0;
      final client = RegisterReceiptClient(
        RegisterTransport(
          idToken: () async => 'id-token-1',
          sessionId: () async => 'sess-1',
          cashregisterId: 'KASSE1',
          httpClient: MockClient((r) async {
            versuche += 1;
            throw http.ClientException('kaputt');
          }),
        ),
      );

      await expectLater(
        client.sendReceipt(fullReceiptId: 'voll-42', to: 'gast@example.com'),
        throwsA(isA<KasseneckHttpError>().having((e) => e.reason, 'reason', KasseneckHttpError.reasonNetwork)),
      );
      expect(versuche, 1);
    });
  });

  group('Fehlercode-Katalog', () {
    test('beginnt mit den vier fachlichen Codes des Backends (Rest: receipt_v3_codes_test)', () {
      expect(receiptEmailErrorCodes.take(4), [
        'invalid_address',
        'receipt_not_found',
        'too_many_requests',
        'send_failed',
      ]);
      expect(isReceiptEmailErrorCode('zu_oft'), isFalse, reason: 'alter Code aus /v1');
    });

    test('ein unbekannter Versandweg kommt als null an, auch der alte deutsche', () async {
      for (final (roh, soll) in [('own', 'own'), ('platform_fallback', 'platform_fallback'), ('eigen', null), ('plattform-fallback', null)]) {
        final f = clientMit({'status': 'success', 'data': {'to': 'gast@example.com', 'at': '2026-09-11T21:12:00+02:00', 'via': roh}});
        final erg = await f.client.sendReceipt(fullReceiptId: 'voll-42', to: 'gast@example.com');
        expect(erg.via, soll, reason: roh);
      }
    });

    test('ein Anzeigetext ist kein Code', () {
      expect(isReceiptEmailErrorCode('too_many_requests'), isTrue);
      expect(isReceiptEmailErrorCode('Zu viele Versandversuche'), isFalse);
      expect(isReceiptEmailErrorCode(null), isFalse);
      expect(isReceiptEmailErrorCode(7), isFalse);
    });
  });
}
