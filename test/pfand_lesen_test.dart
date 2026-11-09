import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/kasseneck_api.dart';

/// `listDepositTypes`: die Pfandarten des Betriebs mit dem API-Schluessel
/// lesen. Zwilling von `test/pfand-lesen.test.ts` im JS-Paket (npm 1.34.0).

const _kopf = {'content-type': 'application/json', 'kasseneck-api-version': 'v3'};

KasseneckApi _api(http.Client client) => KasseneckApi(
      apiKey: 'kr_test_x',
      cashregisterToken: base64Encode(utf8.encode('KECK-1:secret')),
      httpClient: client,
    );

http.Response _erfolg(Object? daten) =>
    http.Response(jsonEncode({'status': 'success', 'data': daten}), 200, headers: _kopf);

void main() {
  test('ruft listDepositTypes ohne Parameter', () async {
    final log = <http.Request>[];
    final api = _api(MockClient((r) async {
      log.add(r);
      return _erfolg({'deposit': null});
    }));
    await api.listDepositTypes();
    expect(log, hasLength(1));
    expect(log.single.url.path, endsWith('/listDepositTypes'));
    expect((jsonDecode(log.single.body) as Map)['params'], isEmpty);
  });

  test('deposit: null (Pfand aus) ergibt null', () async {
    final api = _api(MockClient((_) async => _erfolg({'deposit': null})));
    expect(await api.listDepositTypes(), isNull);
  });

  test('liest Einweg, Mehrweg und die Pfandarten', () async {
    final api = _api(MockClient((_) async => _erfolg({
          'deposit': {
            'singleUse': true,
            'reusable': true,
            'depositTypes': [
              {
                'id': 'p1',
                'kind': 'reusable',
                'name': 'Bierflasche',
                'type': 'bottle',
                'amounts': [
                  {'from': '2026-01-01', 'cents': 9}
                ],
                'returnRate': 20,
                'used': true,
                'active': true,
              }
            ],
          }
        })));
    final d = await api.listDepositTypes();
    expect(d, isNotNull);
    expect(d!.singleUse, isTrue);
    expect(d.reusable, isTrue);
    expect(d.depositTypes.single.id, 'p1');
    expect(d.depositTypes.single.kind, 'reusable');
    expect(d.depositTypes.single.amounts.single.cents, 9);
  });

  test('unlesbare Antwort wirft den Antwortfehler', () async {
    for (final daten in <Object?>[
      {'deposit': 'x'},
      {'deposit': 5},
      <String, dynamic>{},
    ]) {
      final api = _api(MockClient((_) async => _erfolg(daten)));
      await expectLater(
        api.listDepositTypes(),
        throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'response')),
        reason: '$daten',
      );
    }
  });
}
