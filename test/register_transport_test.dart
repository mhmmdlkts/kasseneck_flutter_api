import 'dart:convert';

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
}
