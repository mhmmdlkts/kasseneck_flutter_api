import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/kasseneck_api.dart';

/// Beleg per E-Mail (`sendReceiptEmail`) über den API-Schlüssel-Zugang —
/// derselbe Endpunkt wie auf dem Kassen-Weg, nur mit `api_key` und
/// `cashregister-token` statt Sitzung.
///
/// Rot-Probe je Fall: Endpunktname verdreht → rot; `cashregisterId` in die
/// Nutzlast gelegt → rot (die Kasse steht im Kopfzeilen-Token); `code` beim
/// Fehler weggelassen → rot; Wurf bei fehlendem `at` → rot.

KasseneckApi apiMit(MockClient client) => KasseneckApi(
      apiKey: 'test-key',
      cashregisterToken: base64Encode(utf8.encode('KECK-1:secret')),
      httpClient: client,
    );

http.Response huelle(Map<String, dynamic> j) =>
    http.Response(jsonEncode(j), 200, headers: {'content-type': 'application/json'});

void main() {
  test('ruft sendReceiptEmail mit Schlüssel, Kassen-Token und Nutzlast', () async {
    late http.Request gesendet;
    final api = apiMit(MockClient((r) async {
      gesendet = r;
      return huelle({
        'status': 'success',
        'data': {'to': 'gast@example.com', 'at': '2026-09-11T21:12:00+02:00', 'via': 'plattform'},
      });
    }));

    final erg = await api.belegSenden(fullReceiptId: 'voll-42', an: ' Gast@Example.com ');

    expect(gesendet.url.toString(), 'https://api.kasseneck.at/v1/sendReceiptEmail');
    expect(gesendet.headers['Authorization'], 'Bearer test-key');
    expect(gesendet.headers['cashregister-token'], isNotEmpty);
    final params = (jsonDecode(gesendet.body) as Map)['params'] as Map;
    // Kein cashregisterId: welche Kasse gemeint ist, steht im Token der
    // Kopfzeile. Ein Parameter daneben wäre eine zweite, widersprechbare Angabe.
    expect(params, {'fullReceiptId': 'voll-42', 'to': 'Gast@Example.com'});
    expect(erg.to, 'gast@example.com');
    expect(erg.at, '2026-09-11T21:12:00+02:00');
    expect(erg.via, 'plattform');
  });

  test('die Sprache geht mit, wenn sie gesetzt ist', () async {
    late Map params;
    final api = apiMit(MockClient((r) async {
      params = (jsonDecode(r.body) as Map)['params'] as Map;
      return huelle({'status': 'success', 'data': {'to': 'gast@example.com'}});
    }));

    await api.belegSenden(fullReceiptId: 'voll-42', an: 'gast@example.com', sprache: 'de');
    expect(params['sprache'], 'de');
  });

  test('ohne Beleg oder Adresse geht nichts hinaus', () async {
    final api = apiMit(MockClient((r) async => fail('darf nicht rausgehen: ${r.url}')));
    await expectLater(
      api.belegSenden(fullReceiptId: '  ', an: 'gast@example.com'),
      throwsA(isA<KasseneckValidationError>()),
    );
    await expectLater(
      api.belegSenden(fullReceiptId: 'voll-42', an: ''),
      throwsA(isA<KasseneckValidationError>()),
    );
  });

  test('der Fehlercode des Backends kommt unverändert an', () async {
    final api = apiMit(MockClient((r) async => huelle({
          'status': 'error',
          'message': 'Zu viele Versandversuche — bitte später erneut versuchen.',
          'code': 'zu_oft',
          'data': {'code': 'zu_oft'},
        })));

    await expectLater(
      api.belegSenden(fullReceiptId: 'voll-42', an: 'gast@example.com'),
      throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'zu_oft')),
    );
  });

  test('ein data, das gar keine Hülle ist, bleibt ein Fehler', () async {
    // Wie auf dem Kassen-Weg: nachsichtig sind die einzelnen Felder, nicht die
    // Hülle.
    final api = apiMit(MockClient((r) async => huelle({'status': 'success', 'data': 'ja'})));
    await expectLater(
      api.belegSenden(fullReceiptId: 'voll-42', an: 'gast@example.com'),
      throwsA(isA<KasseneckHttpError>().having((e) => e.reason, 'reason', 'data-not-object')),
    );
  });

  test('eine unvollständige Erfolgsantwort wirft nicht — die Mail ist draussen', () async {
    final api = apiMit(MockClient((r) async => huelle({'status': 'success', 'data': {}})));

    final erg = await api.belegSenden(fullReceiptId: 'voll-42', an: 'gast@example.com');

    expect(erg.to, 'gast@example.com');
    expect(erg.at, isNull);
    expect(erg.via, isNull);
  });
}
