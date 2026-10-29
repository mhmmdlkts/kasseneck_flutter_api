import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/enums/keck_month.dart';
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/models/report_month.dart';

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

  // Befund 29.10.2026, live gegen die Demo-Kasse: der laufende Monat kam mit
  // HTTP 200 und dieser Huelle zurueck, und bis 11.8.0 gingen ihre 192 Bytes
  // als "PDF" an den Aufrufer.
  group('Ablehnung statt PDF', () {
    const meldung = 'Ungültige Daten: Der Monat ist noch nicht abgeschlossen – Monatsbericht erst ab dem Folgemonat.';
    final abgelehnt = utf8.encode(jsonEncode({
      'status': 'error',
      'message': meldung,
      'data': {'code': 'period_not_closed'},
      'code': 'period_not_closed',
    }));

    final aufrufe = <String, Future<Uint8List?> Function(KasseneckApi api)>{
      'getCashregisterReport': (api) => api.getCashregisterReport(year: 2026, month: 10),
      // ignore: deprecated_member_use_from_same_package
      'downloadReport': (api) => api.downloadMonthlyReport(const ReportMonth(KeckMonth.october, 2026)),
      // ignore: deprecated_member_use_from_same_package
      'downloadDailyReport': (api) => api.downloadDailyReport(DateTime(2026, 10, 29)),
    };

    test('HTTP 200 mit Fehlerhuelle ist ein KasseneckApiError mit Code, gleich welcher Inhaltstyp', () async {
      // Ein Proxy kann den Inhaltstyp verlieren oder falsch setzen; die Bytes entscheiden.
      for (final typ in ['application/json; charset=utf-8', null, 'application/pdf']) {
        for (final MapEntry(key: name, value: los) in aufrufe.entries) {
          await expectLater(
            los(_antwortet(abgelehnt, typ: typ)),
            throwsA(isA<KasseneckApiError>()
                .having((e) => e.code, 'code', 'period_not_closed')
                .having((e) => e.outcome, 'outcome', ErrorOutcome.rejected)
                .having((e) => e.functionName, 'functionName', name)
                .having((e) => e.message, 'message', meldung)),
            reason: '$name, Inhaltstyp $typ',
          );
        }
      }
    });

    test('period_in_future kommt ebenso als Code an', () async {
      final zukunft = utf8.encode(jsonEncode({
        'status': 'error',
        'message': 'Ungültige Daten: Zeitraum liegt in der Zukunft.',
        'data': {'code': 'period_in_future'},
        'code': 'period_in_future',
      }));
      await expectLater(
        _antwortet(zukunft, typ: 'application/json').getCashregisterReport(year: 2027, month: 1),
        throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'period_in_future')),
      );
    });

    test('ein echtes PDF kommt Byte fuer Byte an, auch mit Bytes ueber 0x7F und ohne Inhaltstyp', () async {
      // 0xC3 0x28 ist kein UTF-8: eine Textdeutung wuerde dieses PDF zerstoeren.
      const pdf = [0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x37, 0x0a, 0xC3, 0x28, 0xFF, 0x00, 0x0a];
      for (final typ in ['application/pdf', null, 'application/json']) {
        for (final MapEntry(key: name, value: los) in aufrufe.entries) {
          expect(await los(_antwortet(pdf, typ: typ)), pdf, reason: '$name, Inhaltstyp $typ');
        }
      }
    });

    test('eine Erfolgshuelle ohne PDF ist ein Antwortfehler, kein Bericht', () async {
      final erfolg = utf8.encode(jsonEncode({'status': 'success', 'data': {'irgendwas': true}}));
      for (final MapEntry(key: name, value: los) in aufrufe.entries) {
        await expectLater(
          los(_antwortet(erfolg, typ: 'application/json')),
          throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'response')),
          reason: name,
        );
      }
    });
  });
}

/// Ein Geraete-Client, dessen Server immer mit HTTP 200, Kennzeichen und
/// [rumpf] antwortet.
KasseneckApi _antwortet(List<int> rumpf, {String? typ}) => KasseneckApi(
      apiKey: 'test-key',
      cashregisterToken: base64Encode(utf8.encode('CASHBOX-9:secret')),
      httpClient: MockClient((r) async => http.Response.bytes(rumpf, 200,
          headers: {'content-type': ?typ, 'kasseneck-api-version': 'v3'})),
    );
