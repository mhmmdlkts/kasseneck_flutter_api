import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/register.dart';

/// `reportMyRegisterClient` (Zwilling von npm 1.39.0): die Fälle des
/// Vertrags-Exports durch den Client, dazu die Prüfung vor dem Senden.

final _faelle =
    ((jsonDecode(File('test/fixtures/vertrag/v3/antworten/kasse.json').readAsStringSync())
            as Map<String, dynamic>)['endpoints']['reportMyRegisterClient']['cases']
        as List)
        .cast<Map<String, dynamic>>();

const _geheimnis = 'EXAMPLE-GEHEIM-0123456789abcdef';
const _kennung = '1.39.0/2026-11-13T18:20Z';

RegisterClient _client(Map<String, dynamic> fall, List<http.Request> log) => RegisterClient(
  httpClient: MockClient((request) async {
    log.add(request);
    return http.Response.bytes(
      utf8.encode(jsonEncode(fall['response'])),
      fall['httpStatus'] as int,
      headers: {
        'content-type': 'application/json',
        for (final e in (fall['headers'] as Map).cast<String, String>().entries) e.key.toLowerCase(): e.value,
      },
    );
  }),
);

Future<ReportedRegisterClient> _melden(
  RegisterClient c, {
  String ownerUid = 'kw_betrieb1',
  String deviceId = 'dev_pin',
  String secret = _geheimnis,
  String app = _kennung,
}) => c.reportMyRegisterClient(ownerUid: ownerUid, deviceId: deviceId, deviceSecret: secret, app: app);

void main() {
  group('reportMyRegisterClient', () {
    test('jeder Erfolgsfall sendet genau Ausweis und Kennung und liest written', () async {
      var gelaufen = 0;
      for (final fall in _faelle.where((f) => f['response']['status'] == 'success')) {
        final log = <http.Request>[];
        final p = (fall['params'] as Map).cast<String, dynamic>();
        final r = await _melden(
          _client(fall, log),
          ownerUid: p['ownerUid'],
          deviceId: p['deviceId'],
          secret: p['deviceSecret'],
          app: p['app'],
        );
        expect(r, ReportedRegisterClient(written: fall['response']['data']['written'] as bool), reason: fall['case']);
        expect(log, hasLength(1));
        expect(log.single.url.path, '/api/v3/reportMyRegisterClient');
        expect((jsonDecode(log.single.body) as Map)['params'], p, reason: fall['case']);
        gelaufen++;
      }
      expect(gelaufen, greaterThanOrEqualTo(1));
    });

    test('Unbrauchbares wird vor dem Senden abgewiesen, ohne Wert in der Meldung', () async {
      final log = <http.Request>[];
      final c = _client(_faelle.first, log);
      final falsche = <Future<Object?> Function()>[
        () => _melden(c, ownerUid: ''),
        () => _melden(c, deviceId: ' '),
        () => _melden(c, secret: ''),
        () => _melden(c, app: ''),
        () => _melden(c, app: '  '),
      ];
      for (final f in falsche) {
        await expectLater(
          f(),
          throwsA(
            isA<KasseneckValidationError>().having((e) => e.toString().contains(_geheimnis), 'ohne Geheimnis', isFalse),
          ),
        );
      }
      expect(log, isEmpty);
    });

    test('eine Antwort ohne written ist ein Antwortfehler', () async {
      final leer = {
        ..._faelle.first,
        'response': {'status': 'success', 'message': '', 'data': <String, dynamic>{}},
      };
      await expectLater(_melden(_client(leer, [])), throwsA(isA<KasseneckValidationError>()));
    });
  });
}
