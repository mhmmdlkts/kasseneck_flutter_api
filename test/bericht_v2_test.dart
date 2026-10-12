import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/kasseneck_api.dart';

KasseneckApi _api(List<http.Request> log) => KasseneckApi(
      apiKey: 'test-key',
      cashregisterToken: base64Encode(utf8.encode('CASHBOX-9:secret')),
      httpClient: MockClient((r) async {
        log.add(r);
        return http.Response.bytes([37, 80, 68, 70], 200, headers: {'content-type': 'application/pdf', 'kasseneck-api-version': 'v3'});
      }),
    );

Map<String, dynamic> _params(http.Request r) => (jsonDecode(r.body) as Map)['params'] as Map<String, dynamic>;

void main() {
  group('getCashregisterReport', () {
    test('schickt Monat, Tag oder Zeitraum unveraendert', () async {
      final log = <http.Request>[];
      final api = _api(log);
      final pdf = await api.getCashregisterReport(year: 2026, month: 9);
      await api.getCashregisterReport(year: 2026, month: 10, day: 11);
      await api.getCashregisterReport(start: '2026-09-01', end: '2026-09-15');

      expect(pdf, isA<Uint8List>());
      expect(pdf, [37, 80, 68, 70]);
      expect(log.map((r) => r.url.toString()).toSet(), {'https://api.kasseneck.at/v3/getCashregisterReport'});
      expect(log.map(_params), [
        {'year': 2026, 'month': 9},
        {'year': 2026, 'month': 10, 'day': 11},
        {'start': '2026-09-01', 'end': '2026-09-15'},
      ]);
    });

    test('Teil- und Mischformen scheitern vor dem Senden', () async {
      final log = <http.Request>[];
      final api = _api(log);
      final falsch = <Future<Uint8List> Function()>[
        () => api.getCashregisterReport(),
        () => api.getCashregisterReport(year: 2026),
        () => api.getCashregisterReport(month: 9),
        () => api.getCashregisterReport(start: '2026-09-01'),
        () => api.getCashregisterReport(end: '2026-09-15'),
        () => api.getCashregisterReport(year: 2026, month: 9, start: '2026-09-01', end: '2026-09-15'),
        () => api.getCashregisterReport(year: 2026, start: '2026-09-01', end: '2026-09-15'),
        () => api.getCashregisterReport(year: 2026, month: 13),
        () => api.getCashregisterReport(year: 2026, month: 0),
        () => api.getCashregisterReport(year: 2026, month: 9, day: 0),
        () => api.getCashregisterReport(year: 2026, month: 9, day: 32),
        () => api.getCashregisterReport(start: '2026-9-1', end: '2026-09-15'),
        () => api.getCashregisterReport(start: '2026-09-01', end: '15.09.2026'),
      ];
      for (final f in falsch) {
        await expectLater(f(), throwsArgumentError);
      }
      expect(log, isEmpty);
    });
  });
}
