import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/kasseneck_api.dart';

/// Der Kassen-Token ist optional (11.27.0, Zwilling von `apiKeyAuth` in npm
/// 1.36.0): Aufrufe, die dem Betrieb statt einer Kasse gelten, brauchen nur den
/// API-Schluessel.

const _kopf = {'content-type': 'application/json', 'kasseneck-api-version': 'v3'};
const _token = 'cb_test_EXAMPLE00000000';

({KasseneckApi api, List<http.Request> log}) _mit({String? token, Object? data}) {
  final log = <http.Request>[];
  final client = MockClient((r) async {
    log.add(r);
    return http.Response(jsonEncode({'status': 'success', 'data': data ?? {'deposit': null}}), 200, headers: _kopf);
  });
  return (api: KasseneckApi(apiKey: 'kr_test_x', cashregisterToken: token, httpClient: client), log: log);
}

void main() {
  test('ohne Token geht keine Kopfzeile cashregister-token mit', () async {
    final (:api, :log) = _mit();
    await api.listDepositTypes();
    expect(log.single.headers['Authorization'], 'Bearer kr_test_x');
    expect(log.single.headers.keys.map((k) => k.toLowerCase()), isNot(contains('cashregister-token')));
    expect(api.cashregisterToken, isNull);
  });

  test('mit Token wie bisher', () async {
    final (:api, :log) = _mit(token: _token);
    await api.listDepositTypes();
    expect(log.single.headers['cashregister-token'], _token);
    expect(api.cashregisterToken, _token);
  });

  test('ein leerer Text oder nur Leerraum gilt als kein Token: nichts wirft, keine Kopfzeile', () async {
    // Eine App setzt den Client beim Abmelden mit leerem Schluessel und leerem
    // Token zurueck; das muss wie bisher ohne Fehler gehen.
    expect(() => KasseneckApi(apiKey: '', cashregisterToken: ''), returnsNormally);
    for (final leer in ['', ' ', '\t\n']) {
      final (:api, :log) = _mit(token: leer);
      await api.listDepositTypes();
      expect(log.single.headers.keys.map((k) => k.toLowerCase()), isNot(contains('cashregister-token')),
          reason: jsonEncode(leer));
    }
  });

  test('cashregisterId: null wirft, leer liest leer, mit Token liest sie die Kasse', () {
    expect(() => KasseneckApi(apiKey: 'kr_test_x').cashregisterId, throwsFormatException);
    // Leerer Token: wie in 11.26.1 eine leere Kennung, kein Fehler.
    expect(KasseneckApi(apiKey: '', cashregisterToken: '').cashregisterId, '');
    final mit = KasseneckApi(apiKey: 'kr_test_x', cashregisterToken: 'cb_test_${base64Url.encode(utf8.encode('KECK-1:geheim')).replaceAll('=', '')}');
    expect(mit.cashregisterId, 'KECK-1');
  });

  test('ein Aufruf, der eine Kasse braucht, kommt ohne Token als cashregister_token_missing zurueck', () async {
    final client = MockClient((r) async {
      expect(r.headers.keys.map((k) => k.toLowerCase()), isNot(contains('cashregister-token')));
      return http.Response(
          jsonEncode({
            'status': 'error',
            'message': 'Kassen-Token fehlt',
            'code': 'cashregister_token_missing',
            'data': {'code': 'cashregister_token_missing'},
          }),
          200,
          headers: _kopf);
    });
    final api = KasseneckApi(apiKey: 'kr_test_x', httpClient: client);
    await expectLater(
      api.listReceipts(date: '2026-11-10'),
      throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'cashregister_token_missing')),
    );
  });
}
