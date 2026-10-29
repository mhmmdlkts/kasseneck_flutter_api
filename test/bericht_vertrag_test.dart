import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/src/v3.dart' show readPdfBody;

/// `antworten/berichte.json` aus dem Backend-Vertrag (ueber npm 1.17.1):
/// `getCashregisterReport` als Binaerweg, erzeugt aus dem echten Handler. Die
/// Datei kommt als PDF, jede Ablehnung mit HTTP 200 als Huelle. Bis 11.8.0
/// reichte dieses Paket die Huelle als PDF durch (Befund 29.10.2026).
/// Zwilling von `test/v3-berichte-vertrag.test.ts` im npm-Paket.
final List<Map<String, dynamic>> _faelle =
    ((jsonDecode(File('test/fixtures/vertrag/v3/antworten/berichte.json').readAsStringSync()) as Map)['cases'] as List)
        .cast<Map<String, dynamic>>();

/// Die Bytes einer Datei des Vertrags: ihr Anfang, dann Bytes, die kein UTF-8 sind.
Uint8List _dateiBytes(Map<String, dynamic> f) =>
    Uint8List.fromList([...utf8.encode('${(f['file'] as Map)['startsWith']}1.7\n'), 0xC3, 0x28, 0xFF, 0x00, 0x0A]);

http.Response _antwort(Map<String, dynamic> f) => http.Response.bytes(
      f['file'] != null ? _dateiBytes(f) : utf8.encode(jsonEncode(f['response'])),
      f['httpStatus'] as int,
      headers: {for (final e in (f['headers'] as Map).entries) (e.key as String).toLowerCase(): e.value as String},
    );

Matcher _ablehnung(Map<String, dynamic> f) => isA<KasseneckApiError>()
    .having((e) => e.code, 'code', (f['response'] as Map)['code'])
    .having((e) => e.outcome, 'outcome', ErrorOutcome.rejected)
    .having((e) => e.functionName, 'functionName', 'getCashregisterReport')
    .having((e) => e.message, 'message', (f['response'] as Map)['message']);

void main() {
  test('Datei und Ablehnung sind beide im Vertrag', () {
    // Sonst liefen die Tests unten leer und blieben gruen.
    expect(_faelle.where((f) => f['file'] != null), isNotEmpty);
    expect(_faelle.where((f) => f['response'] is Map && (f['response'] as Map)['status'] == 'error'), isNotEmpty);
    for (final f in _faelle) {
      expect(f['endpoint'], 'getCashregisterReport', reason: f['name'] as String);
    }
  });

  test('readPdfBody: die Datei kommt Byte fuer Byte an, jede Ablehnung mit HTTP 200 ist ein Fehler mit Code', () {
    for (final f in _faelle) {
      final name = f['name'] as String;
      if (f['file'] != null) {
        expect(readPdfBody('getCashregisterReport', _antwort(f)), _dateiBytes(f), reason: name);
      } else {
        expect(f['httpStatus'], 200, reason: name);
        expect(() => readPdfBody('getCashregisterReport', _antwort(f)), throwsA(_ablehnung(f)), reason: name);
      }
    }
  });

  test('getCashregisterReport ueber den ganzen Weg; die Mischform scheitert schon vor dem Senden', () async {
    for (final f in _faelle) {
      final name = f['name'] as String;
      final p = f['params'] as Map<String, dynamic>;
      var gesendet = 0;
      final api = KasseneckApi(
        apiKey: 'k',
        cashregisterToken: base64Encode(utf8.encode('C:s')),
        httpClient: MockClient((_) async {
          gesendet++;
          return _antwort(f);
        }),
      );
      final los = api.getCashregisterReport(
          year: p['year'] as int?, month: p['month'] as int?, day: p['day'] as int?,
          start: p['start'] as String?, end: p['end'] as String?);
      if (name == 'error_invalid_period') {
        await expectLater(los, throwsArgumentError, reason: name);
        expect(gesendet, 0, reason: name);
      } else if (f['file'] != null) {
        expect(await los, _dateiBytes(f), reason: name);
      } else {
        await expectLater(los, throwsA(_ablehnung(f)), reason: name);
      }
    }
  });
}
