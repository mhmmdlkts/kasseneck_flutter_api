import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/register.dart';

/// Der gemeinsame Weg aller Aufrufe der laufenden Sitzung: ID-Token als
/// Bearer, Sitzung als Kopfzeile `register-session`, Kasse als Parameter.
///
/// Es gibt ihn genau einmal, damit Sitzung, Belege und Einstellungen nicht
/// jeweils ihre eigene Fassung derselben Hülle pflegen — und damit die Zusage
/// „ein Beleg wird nicht wiederholt" an einer einzigen Stelle steht.

({RegisterTransport transport, List<http.Request> log}) transportMit(
  Object antwort, {
  int status = 200,
  String? idToken = 'id-token-1',
  String? sessionId = 'sess-1',
  Duration? timeout,
}) {
  final log = <http.Request>[];
  final mock = MockClient((request) async {
    log.add(request);
    return http.Response(
      antwort is String ? antwort : jsonEncode(antwort),
      status,
      headers: {'content-type': 'application/json'},
    );
  });
  return (
    transport: RegisterTransport(
      idToken: () async => idToken,
      sessionId: () async => sessionId,
      cashregisterId: 'KASSE1',
      httpClient: mock,
      timeout: timeout,
    ),
    log: log,
  );
}

void main() {
  test('Ausweis in den Kopfzeilen, Kasse im Rumpf', () async {
    final f = transportMit({'status': 'success', 'data': {'ok': true}});
    final daten = await f.transport.rufen('irgendwas');

    expect(daten, {'ok': true});
    final anfrage = f.log.single;
    expect(anfrage.url.toString(), 'https://kasse.kasseneck.at/api/irgendwas');
    expect(anfrage.headers['Authorization'], 'Bearer id-token-1');
    expect(anfrage.headers['register-session'], 'sess-1');
    expect(jsonDecode(anfrage.body)['params'], {'cashregisterId': 'KASSE1'});
  });

  test('eigene Parameter kommen dazu, die Kasse bleibt', () async {
    final f = transportMit({'status': 'success', 'data': {}});
    await f.transport.rufen('listMyReceipts', params: {'limit': 20, 'cashregisterid': 'KASSE1'});

    expect(jsonDecode(f.log.single.body)['params'], {
      'cashregisterId': 'KASSE1',
      'limit': 20,
      'cashregisterid': 'KASSE1',
    });
  });

  test('null-Parameter gehen gar nicht erst hinaus', () async {
    // Sonst stuende `"limit": null` im Rumpf und das Backend deutete das als
    // ausdrueckliche Angabe statt als „nicht gesetzt".
    final f = transportMit({'status': 'success', 'data': {}});
    await f.transport.rufen('listMyReceipts', params: {'limit': null, 'from': '2026-08-19'});

    expect(jsonDecode(f.log.single.body)['params'], {
      'cashregisterId': 'KASSE1',
      'from': '2026-08-19',
    });
  });

  test('Ausweis wird bei JEDEM Aufruf frisch geholt', () async {
    var nummer = 0;
    final log = <http.Request>[];
    final transport = RegisterTransport(
      idToken: () async => 'token-${++nummer}',
      sessionId: () async => 'sess-1',
      cashregisterId: 'KASSE1',
      httpClient: MockClient((r) async {
        log.add(r);
        return http.Response('{"status":"success","data":{}}', 200);
      }),
    );

    await transport.rufen('a');
    await transport.rufen('b');
    expect(log.map((r) => r.headers['Authorization']), ['Bearer token-1', 'Bearer token-2']);
  });

  test('ohne Token gibt es keinen Aufruf', () async {
    final f = transportMit({'status': 'success', 'data': {}}, idToken: null);
    await expectLater(f.transport.rufen('a'), throwsA(isA<KasseneckValidationError>()));
    expect(f.log, isEmpty, reason: 'ohne Ausweis geht nichts hinaus');
  });

  test('fachlicher Fehler traegt die Meldung des Backends', () async {
    final f = transportMit({'status': 'error', 'message': 'Sitzung beendet — bitte neu anmelden.'});
    await expectLater(
      f.transport.rufen('a'),
      throwsA(isA<KasseneckApiError>().having((e) => e.message, 'message', 'Sitzung beendet — bitte neu anmelden.')),
    );
  });

  test('kaputte Antwort ist ein HTTP-Fehler, kein Erfolg', () async {
    final f = transportMit('<html>404</html>', status: 404);
    await expectLater(
      f.transport.rufen('a'),
      throwsA(isA<KasseneckHttpError>().having((e) => e.statusCode, 'statusCode', 404)),
    );
  });

  test('eigene Frist je Aufruf — der Abschluss darf laenger warten', () async {
    // Nicht der Wert zaehlt, sondern dass es ihn gibt: ein Abbruch beendet nur
    // das Warten der Kasse, nicht die Arbeit des Servers.
    final f = transportMit({'status': 'success', 'data': {}});
    expect(
      () => f.transport.rufen('createReceipt', frist: const Duration(minutes: 2)),
      returnsNormally,
    );
  });

  group('Zeitablauf und Netzfehler bleiben unterscheidbar', () {
    // Ueber `createReceipt` sind das zwei verschiedene Lagen: eine abgelaufene
    // Frist heisst „die Anfrage war draussen, der Ausgang ist unbekannt" — der
    // Beleg kann laengst signiert sein. Beides in denselben Ausgang zu werfen
    // nahm dem Aufrufer die einzige Handhabe, die er hat; das ist dieselbe
    // Vermischung von Nichtwissen und Aussage wie am 24.08. am Terminal.
    RegisterTransport transportDurch(http.Client client, {Duration? timeout}) => RegisterTransport(
          idToken: () async => 'id-token-1',
          sessionId: () async => 'sess-1',
          cashregisterId: 'KASSE1',
          httpClient: client,
          timeout: timeout,
        );

    test('abgelaufene Frist: reason "timeout", nicht "network"', () async {
      final transport = transportDurch(
        MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 20),
      );

      await expectLater(
        transport.rufen('createReceipt'),
        throwsA(isA<KasseneckHttpError>()
            .having((e) => e.reason, 'reason', KasseneckHttpError.zeitablauf)
            .having((e) => e.causeType, 'causeType', 'TimeoutException')),
      );
    });

    test('Verbindungsfehler: reason "network", mit Ursachentyp im Protokoll', () async {
      final transport = transportDurch(
        MockClient((_) async => throw const SocketException('Connection refused')),
      );

      await expectLater(
        transport.rufen('createReceipt'),
        throwsA(isA<KasseneckHttpError>()
            .having((e) => e.reason, 'reason', KasseneckHttpError.netz)
            .having((e) => e.causeType, 'causeType', 'SocketException')),
      );
    });

    test('kein Wert aus der Ursache faehrt mit — nur ihr Typ', () async {
      final transport = transportDurch(
        MockClient((_) async => throw http.ClientException('geheim-abc123')),
      );

      await expectLater(
        transport.rufen('a'),
        throwsA(isA<KasseneckHttpError>()
            .having((e) => e.toString(), 'toString', isNot(contains('geheim-abc123')))),
      );
    });

    test('ein Programmierfehler wird nicht als Netzstoerung gemeldet', () async {
      // Der `jsonEncode` stand im selben try wie der Request: ein nicht
      // serialisierbarer Parameter sah damit aus wie ein Netzfehler — also wie
      // einer, nach dem ein Beleg entstanden sein koennte.
      final log = <http.Request>[];
      final transport = transportDurch(MockClient((r) async {
        log.add(r);
        return http.Response('{"status":"success","data":{}}', 200);
      }));

      await expectLater(
        transport.rufen('createReceipt', params: {'kaputt': Object()}),
        throwsA(isNot(isA<KasseneckHttpError>())),
      );
      expect(log, isEmpty, reason: 'es geht nichts hinaus');
    });
  });

  group('data: leer ist etwas anderes als kaputt', () {
    test('fehlendes data bleibt ein leeres Objekt', () async {
      final f = transportMit({'status': 'success'});
      expect(await f.transport.rufen('a'), <String, dynamic>{});
    });

    test('data, das kein Objekt ist, ist ein Antwortfehler', () async {
      // Frueher still `{}` — und `KasseSettings.aus({})` machte daraus den
      // vollen Standardsatz. Der Bildschirm meldete „der Betrieb hat nichts
      // eingestellt", obwohl die Antwort kaputt war.
      for (final kaputt in <Object>[<dynamic>[], 42, 'text', true]) {
        await expectLater(
          transportMit({'status': 'success', 'data': kaputt}).transport.rufen('getKasseSettings'),
          throwsA(isA<KasseneckHttpError>().having((e) => e.reason, 'reason', 'data-not-object')),
          reason: 'data=$kaputt',
        );
      }
    });
  });
}
