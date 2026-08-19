import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/kasse.dart';
import 'package:kasseneck_api/register.dart';

/// Einstellungen lesen und schreiben — die Chef-Einstellungen der Kasse.
///
/// Geschrieben wird **nur, was geändert wurde**, nie der ganze Stand: zwei
/// Kassen desselben Betriebs dürfen einander nicht überschreiben, bloß weil
/// beide gerade ihren Bildschirm offen hatten.

({KasseEinstellungenClient client, List<http.Request> log}) clientMit(Object antwort) {
  final log = <http.Request>[];
  final mock = MockClient((r) async {
    log.add(r);
    return http.Response(jsonEncode(antwort), 200, headers: {'content-type': 'application/json'});
  });
  return (
    client: KasseEinstellungenClient(
      RegisterTransport(
        idToken: () async => 'tok',
        sessionId: () async => 'sess',
        cashregisterId: 'KASSE1',
        httpClient: mock,
      ),
      deviceId: 'GERAET1',
    ),
    log: log,
  );
}

void main() {
  group('lesen', () {
    test('Gespeichertes kommt mit den Standardwerten gemischt', () async {
      final f = clientMit({
        'status': 'success',
        'data': {
          'betrieb': {'uhr': false},
          'geraet': {'touch': false},
        },
      });
      final e = await f.client.laden();

      expect(e.betrieb.uhr, isFalse, reason: 'gespeichert');
      expect(e.betrieb.zahlBar, isTrue, reason: 'Standard, weil nichts gespeichert');
      expect(e.geraet.touch, isFalse);

      expect(f.log.single.url.toString(), endsWith('/getKasseSettings'));
      expect(jsonDecode(f.log.single.body)['params']['deviceId'], 'GERAET1');
    });

    test('ohne gespeicherte Werte gelten die Standardwerte', () async {
      final f = clientMit({'status': 'success', 'data': {}});
      final e = await f.client.laden();
      expect(e.betrieb.uhr, const KasseSettings.standard().betrieb.uhr);
    });
  });

  group('Betrieb schreiben', () {
    test('nur die geänderten Felder gehen hinaus', () async {
      // Den ganzen Stand zu schicken hiesse, die Aenderung der Nebenkasse zu
      // ueberschreiben, die zufaellig eine Sekunde frueher gespeichert hat.
      final f = clientMit({
        'status': 'success',
        'data': {
          'betrieb': {'uhr': false},
        },
      });
      final betrieb = await f.client.betriebSpeichern({'uhr': false});

      expect(betrieb.uhr, isFalse);
      expect(f.log.single.url.toString(), endsWith('/setMyKasseSettings'));
      expect(jsonDecode(f.log.single.body)['params']['betrieb'], {'uhr': false});
    });

    test('ohne Änderung geht gar nichts hinaus', () async {
      final f = clientMit({'status': 'success', 'data': {}});
      await expectLater(f.client.betriebSpeichern(const {}), throwsA(isA<KasseneckValidationError>()));
      expect(f.log, isEmpty);
    });
  });

  group('Gerät schreiben', () {
    test('die Gerätekennung geht mit', () async {
      final f = clientMit({
        'status': 'success',
        'data': {
          'geraet': {'touch': false},
        },
      });
      final geraet = await f.client.geraetSpeichern({'touch': false});

      expect(geraet.touch, isFalse);
      final params = jsonDecode(f.log.single.body)['params'] as Map<String, dynamic>;
      expect(params['deviceId'], 'GERAET1');
      expect(params['geraet'], {'touch': false});
    });

    test('ohne Gerätekennung geht nichts hinaus', () async {
      final log = <http.Request>[];
      final client = KasseEinstellungenClient(
        RegisterTransport(
          idToken: () async => 'tok',
          sessionId: () async => 'sess',
          cashregisterId: 'KASSE1',
          httpClient: MockClient((r) async {
            log.add(r);
            return http.Response('{"status":"success","data":{}}', 200);
          }),
        ),
        deviceId: '  ',
      );

      await expectLater(client.geraetSpeichern(const {'touch': false}), throwsA(isA<KasseneckValidationError>()));
      expect(log, isEmpty);
    });
  });
}
