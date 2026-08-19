import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/register.dart';

/// Die beiden Aufrufe der **laufenden** Sitzung. Anders als Kopplung und
/// Anmeldung haben sie eine Identität: ID-Token als Bearer, die Sitzung als
/// Kopfzeile `register-session`, die Kasse als Parameter. Eigene Parameter
/// führen sie keine — welche Sitzung gemeint ist, steht im Ausweis.

({RegisterSessionClient client, List<http.Request> log}) clientWith(
  Object antwort, {
  String idToken = 'id-token-1',
  String sessionId = 'sess-1',
}) {
  final log = <http.Request>[];
  final mock = MockClient((request) async {
    log.add(request);
    return http.Response(
      antwort is String ? antwort : jsonEncode(antwort),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  return (
    client: RegisterSessionClient(
      idToken: () async => idToken,
      sessionId: () async => sessionId,
      cashregisterId: 'KASSE1',
      httpClient: mock,
    ),
    log: log,
  );
}

void main() {
  ausClient();

  test('verlängern: Ausweis in den Kopfzeilen, Kasse im Rumpf, neuer Ablauf zurück', () async {
    final f = clientWith({'status': 'success', 'data': {'expiresAt': 1776000180000}});
    final bis = await f.client.renewRegisterSession();

    expect(bis, 1776000180000);
    final anfrage = f.log.single;
    expect(anfrage.url.toString(), 'https://kasse.kasseneck.at/api/renewRegisterSession');
    expect(anfrage.headers['Authorization'], 'Bearer id-token-1');
    expect(anfrage.headers['register-session'], 'sess-1');
    expect(jsonDecode(anfrage.body)['params'], {'cashregisterId': 'KASSE1'});
  });

  test('Ausweis wird bei JEDEM Aufruf frisch geholt — Tokens laufen ab', () async {
    var nummer = 0;
    final log = <http.Request>[];
    final client = RegisterSessionClient(
      idToken: () async => 'token-${++nummer}',
      sessionId: () async => 'sess-1',
      cashregisterId: 'KASSE1',
      httpClient: MockClient((r) async {
        log.add(r);
        return http.Response(jsonEncode({'status': 'success', 'data': {'expiresAt': 1}}), 200);
      }),
    );
    await client.renewRegisterSession();
    await client.renewRegisterSession();
    expect(log.map((r) => r.headers['Authorization']), ['Bearer token-1', 'Bearer token-2']);
  });

  test('ohne Ablaufzeitpunkt ist die Verlängerung kein Erfolg', () async {
    for (final daten in [<String, dynamic>{}, {'expiresAt': 'bald'}, {'expiresAt': null}]) {
      final f = clientWith({'status': 'success', 'data': daten});
      await expectLater(f.client.renewRegisterSession(), throwsA(isA<KasseneckValidationError>()));
    }
  });

  test('beendete Sitzung: der fachliche Satz kommt durch', () async {
    final f = clientWith({'status': 'error', 'message': 'Sitzung beendet — bitte neu anmelden.'});
    await expectLater(
      f.client.renewRegisterSession(),
      throwsA(isA<KasseneckApiError>().having((e) => e.message, 'Meldung', contains('neu anmelden'))),
    );
  });

  test('ohne Token oder Sitzung geht nichts hinaus', () async {
    final log = <http.Request>[];
    http.Client mock() => MockClient((r) async {
          log.add(r);
          return http.Response('{"status":"success","data":{"expiresAt":1}}', 200);
        });
    final ohneToken = RegisterSessionClient(
      idToken: () async => '', sessionId: () async => 's', cashregisterId: 'K', httpClient: mock(),
    );
    final ohneSitzung = RegisterSessionClient(
      idToken: () async => 't', sessionId: () async => '', cashregisterId: 'K', httpClient: mock(),
    );
    await expectLater(ohneToken.renewRegisterSession(), throwsA(isA<KasseneckValidationError>()));
    await expectLater(ohneSitzung.renewRegisterSession(), throwsA(isA<KasseneckValidationError>()));
    expect(log, isEmpty);
  });

  test('beenden schickt dieselbe Identität und erwartet nichts zurück', () async {
    final f = clientWith({'status': 'success', 'data': {}});
    await f.client.endRegisterSession();
    expect(f.log.single.url.toString(), endsWith('/endRegisterSession'));
    expect(f.log.single.headers['register-session'], 'sess-1');
  });
}

void ausClient() {
  test('der Sitzungs-Client erbt Adresse und Verbindung des RegisterClient', () async {
    final log = <http.Request>[];
    final mock = MockClient((r) async {
      log.add(r);
      return http.Response(jsonEncode({'status': 'success', 'data': {'expiresAt': 7}}), 200);
    });
    final client = RegisterClient(baseUrl: 'https://test.example/v9', httpClient: mock);
    final sitzung = client.sitzung(
      idToken: () async => 'tok',
      sessionId: () async => 'sess',
      cashregisterId: 'KASSE2',
    );
    expect(await sitzung.renewRegisterSession(), 7);
    expect(log.single.url.toString(), 'https://test.example/v9/renewRegisterSession');
    expect(log.single.headers['Authorization'], 'Bearer tok');
  });
}
