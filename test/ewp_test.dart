import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/src/aufrufe.dart';
import 'package:kasseneck_api/src/v3.dart' show isUnknownOutcomeCall;

/// EWP-Meldung (Einwegpfand-Meldung): getEwpReport, downloadEwpReport und
/// setEwpExtraQuantities gegen eine Attrappe des Servers. Zwilling von
/// `test/ewp.test.ts` im npm-Paket (1.36.0). GTINs sind erfunden und
/// pruefziffernrichtig, Betriebsnamen gibt es hier nicht.

const _kopf = {'content-type': 'application/json', 'kasseneck-api-version': 'v3'};
const _gtinDose = '9012345000011';
const _gtinFlasche = '9012345000028';
const _gtinFremd = '9012345000035';

const _stamm = {
  'barcodeType': 'International',
  'productOrigin': 'Produced in Austria',
  'depositFee': 'D1',
  'producerFee': 'PF1',
  'ecoImpact': 'EFP1',
  'intBarcodeUsage': 'PFI1',
};

Map<String, dynamic> _meldung() => {
      'month': '2026-11',
      'dueDate': '2026-12-05',
      'provisional': false,
      'test': false,
      'lines': [
        {
          'gtin': _gtinDose,
          'name': 'Lager Dose 0,5 l',
          'masterData': _stamm,
          'domestic': 37,
          'foreign': 0,
          'sources': {'register': 3, 'invoices': 24, 'deliveryNotes': 10, 'extra': 0},
        },
        {
          'gtin': _gtinFlasche,
          'name': 'Lager Flasche 0,33 l',
          'domestic': 0,
          'foreign': 2,
          'sources': {'register': 0, 'invoices': 0, 'deliveryNotes': 0, 'extra': 2},
        },
      ],
      'warnings': [
        {'code': 'foreign_not_reportable', 'gtin': _gtinFlasche, 'country': 'DE', 'quantity': 2},
        {'code': 'gtin_not_registered', 'gtin': _gtinFremd, 'quantity': 4},
        {'code': 'master_data_missing', 'gtin': _gtinDose, 'fields': ['ecoImpact']},
        {'code': 'negative_quantity', 'gtin': _gtinDose, 'column': 'domestic', 'amount': -3},
        {'code': 'invalid_posting', 'count': 2},
      ],
      'extraQuantities': [
        {'gtin': _gtinFlasche, 'domestic': 0, 'foreign': 2, 'reason': 'sampling', 'text': null, 'at': 1760000000000, 'by': 'api'},
        {'gtin': _gtinDose, 'domestic': 1, 'foreign': 0, 'reason': 'own_consumption', 'text': 'Fest', 'at': 1760000100000, 'by': 'uidBeispiel1'},
      ],
      'downloadedAt': null,
    };

({KasseneckApi api, List<http.Request> log}) _server(Object? data, {String? token}) {
  final log = <http.Request>[];
  final client = MockClient((r) async {
    log.add(r);
    return http.Response(jsonEncode({'status': 'success', 'message': '', 'data': data}), 200, headers: _kopf);
  });
  return (api: KasseneckApi(apiKey: 'kr_test_Beispielschluessel0123456789', cashregisterToken: token, httpClient: client), log: log);
}

Map<String, dynamic> _params(http.Request r) => (jsonDecode(r.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;

void main() {
  test('Zusatzmenge ohne Zeitpunkt bleibt lesbar (at null), wie npm', () {
    final z = EwpExtraQuantity.fromJson({'gtin': '9012345000011', 'domestic': -12, 'foreign': 0, 'reason': 'return', 'text': null});
    expect(z.at, isNull);
    expect(z.domestic, -12);
    final mitZeit = EwpExtraQuantity.fromJson({'gtin': '9012345000011', 'domestic': 6, 'foreign': 0, 'reason': 'own_consumption', 'at': 1794297739537});
    expect(mitZeit.at, 1794297739537);
  });

  test('getEwpReport ruft /v3/getEwpReport mit { month } und liest die Meldung', () async {
    final (:api, :log) = _server(_meldung());
    final bericht = await api.getEwpReport(month: '2026-11');
    expect(log, hasLength(1));
    expect(log.single.url.path, endsWith('/v3/getEwpReport'));
    expect(_params(log.single), {'month': '2026-11'});
    expect(bericht.month, '2026-11');
    expect(bericht.dueDate, '2026-12-05');
    expect(bericht.provisional, isFalse);
    expect(bericht.test, isFalse);
    expect(bericht.downloadedAt, isNull);
    expect(bericht.lines, hasLength(2));
    expect(bericht.lines[0].gtin, _gtinDose);
    expect(bericht.lines[0].domestic, 37);
    expect(bericht.lines[0].masterData!.ecoImpact, 'EFP1');
    expect(bericht.lines[0].sources.deliveryNotes, 10);
    expect(bericht.lines[0].sources.invoices, 24);
    expect(bericht.lines[1].masterData, isNull);
    expect(bericht.lines[1].foreign, 2);
    expect(bericht.extraQuantities[0].by, 'api');
    expect(bericht.extraQuantities[0].text, isNull);
    expect(bericht.extraQuantities[1].text, 'Fest');
    expect(bericht.extraQuantities[1].at, 1760000100000);
  });

  test('Warnungen tragen je Code ihre Angaben', () async {
    final (:api, log: _) = _server(_meldung());
    final bericht = await api.getEwpReport(month: '2026-11');
    EwpWarning nach(String code) => bericht.warnings.firstWhere((w) => w.code == code);
    final fremd = nach('foreign_not_reportable');
    expect([fremd.gtin, fremd.country, fremd.quantity], [_gtinFlasche, 'DE', 2]);
    expect(nach('gtin_not_registered').quantity, 4);
    expect(nach('master_data_missing').fields, ['ecoImpact']);
    final negativ = nach('negative_quantity');
    expect([negativ.column, negativ.amount], ['domestic', -3]);
    expect(nach('invalid_posting').count, 2);
    expect(bericht.warnings.map((w) => w.code).toList(), [
      'foreign_not_reportable', 'gtin_not_registered', 'master_data_missing', 'negative_quantity', 'invalid_posting',
    ]);
    expect(bericht.warnings.every((w) => ewpWarningCodes.contains(w.code)), isTrue);
  });

  test('downloadEwpReport sendet format csv und liefert { csv, filename, contentType }', () async {
    final (:api, :log) = _server({'csv': 'Kopf\r\nZeile\r\n', 'filename': 'EWP-Meldung-2026-11.csv', 'contentType': 'text/csv; charset=utf-8'});
    final datei = await api.downloadEwpReport(month: '2026-11');
    expect(log.single.url.path, endsWith('/v3/getEwpReport'));
    expect(_params(log.single), {'month': '2026-11', 'format': 'csv'});
    expect(datei.csv, 'Kopf\r\nZeile\r\n');
    expect(datei.filename, 'EWP-Meldung-2026-11.csv');
    expect(datei.contentType, 'text/csv; charset=utf-8');
  });

  test('setEwpExtraQuantities sendet die Liste und liefert die neue Meldung', () async {
    final (:api, :log) = _server(_meldung());
    final bericht = await api.setEwpExtraQuantities(month: '2026-11', extraQuantities: const [
      EwpExtraQuantityInput(gtin: _gtinDose, domestic: 1, foreign: 0, reason: 'own_consumption', text: 'Fest'),
      EwpExtraQuantityInput(gtin: _gtinFlasche, domestic: 0, foreign: 2, reason: 'sampling'),
    ]);
    expect(log.single.url.path, endsWith('/v3/setEwpExtraQuantities'));
    expect(_params(log.single), {
      'month': '2026-11',
      'extraQuantities': [
        {'gtin': _gtinDose, 'domestic': 1, 'foreign': 0, 'reason': 'own_consumption', 'text': 'Fest'},
        {'gtin': _gtinFlasche, 'domestic': 0, 'foreign': 2, 'reason': 'sampling'},
      ],
    });
    expect(bericht.extraQuantities, hasLength(2));
  });

  test('eine leere Liste leert die Zusatzmengen (wird gesendet, nicht weggelassen)', () async {
    final (:api, :log) = _server({..._meldung(), 'extraQuantities': <Object>[]});
    final bericht = await api.setEwpExtraQuantities(month: '2026-11', extraQuantities: const []);
    expect(_params(log.single), {'month': '2026-11', 'extraQuantities': <Object>[]});
    expect(bericht.extraQuantities, isEmpty);
  });

  group('unlesbare Antwort -> KasseneckValidationError (response)', () {
    final unlesbar = <Object?>[
      'text',
      <Object?>[],
      <String, dynamic>{},
      {..._meldung(), 'lines': 'x'},
      {..._meldung(), 'warnings': null},
      {..._meldung(), 'extraQuantities': <String, dynamic>{}},
      {..._meldung(), 'month': 7},
      {..._meldung(), 'lines': [5]},
    ];
    for (final data in unlesbar) {
      test('Meldung: ${jsonEncode(data).substring(0, jsonEncode(data).length.clamp(0, 40))}', () async {
        for (final aufruf in <Future<Object?> Function(KasseneckApi)>[
          (a) => a.getEwpReport(month: '2026-11'),
          (a) => a.setEwpExtraQuantities(month: '2026-11', extraQuantities: const []),
        ]) {
          final (:api, log: _) = _server(data);
          // data ist kein Objekt: schon die Huelle meldet es als Antwortfehler des Transports.
          await expectLater(
            aufruf(api),
            throwsA(anyOf(
              isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'response'),
              isA<KasseneckHttpError>(),
            )),
          );
        }
      });
    }

    for (final data in <Object?>[
      <String, dynamic>{},
      {'csv': 7, 'filename': 'a.csv', 'contentType': 'text/csv'},
      {'csv': 'x', 'filename': null, 'contentType': 'text/csv'},
      {'csv': 'x', 'filename': 'a.csv'},
    ]) {
      test('CSV: ${jsonEncode(data)}', () async {
        final (:api, log: _) = _server(data);
        await expectLater(
          api.downloadEwpReport(month: '2026-11'),
          throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'response')),
        );
      });
    }
  });

  test('ein leerer Monat wirft vor dem Senden (request)', () async {
    final (:api, :log) = _server(_meldung());
    for (final aufruf in <Future<Object?> Function()>[
      () => api.getEwpReport(month: ''),
      () => api.downloadEwpReport(month: ''),
      () => api.setEwpExtraQuantities(month: '', extraQuantities: const []),
    ]) {
      await expectLater(aufruf(), throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'request')));
    }
    expect(log, isEmpty);
  });

  test('Serverfehler (kein Abfueller) kommt als KasseneckApiError mit Code', () async {
    final client = MockClient((_) async => http.Response(
        jsonEncode({'status': 'error', 'message': 'Nur fuer Abfueller', 'code': 'filler_role_required', 'data': {'code': 'filler_role_required'}}),
        200,
        headers: _kopf));
    final api = KasseneckApi(apiKey: 'kr_test_x', httpClient: client);
    await expectLater(
      api.getEwpReport(month: '2026-11'),
      throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'filler_role_required')),
    );
  });

  test('ewpReasons: die neun Gruende in der Reihenfolge des Backends, jeder ein Wert des Vokabulars', () {
    expect(ewpReasons, [
      'own_consumption', 'sampling', 'donation', 'theft', 'free_goods', 'stocktake', 'return', 'external_system', 'other',
    ]);
    final vokabular = jsonDecode(File('test/fixtures/vertrag/v3/v3-vokabular.json').readAsStringSync()) as Map<String, dynamic>;
    final schema = (vokabular['schemas'] as Map<String, dynamic>)['setEwpExtraQuantities'] as Map<String, dynamic>;
    final werte = ((schema['paramWerte'] as Map<String, dynamic>)['extraQuantities[].reason'] as Map<String, dynamic>).values.toList();
    expect([...ewpReasons]..sort(), [...werte]..sort());
  });

  test('EwpWarning.code: die fuenf Werte des Vokabulars, in dessen Reihenfolge', () {
    final vokabular = jsonDecode(File('test/fixtures/vertrag/v3/v3-vokabular.json').readAsStringSync()) as Map<String, dynamic>;
    final schema = (vokabular['schemas'] as Map<String, dynamic>)['getEwpReport'] as Map<String, dynamic>;
    final werte = ((schema['werte'] as Map<String, dynamic>)['warnings[].code'] as Map<String, dynamic>).values.toList();
    expect(ewpWarningCodes, werte);
    expect(ewpWarningCodes, hasLength(5));
  });

  test('Einordnung: beide Aufrufe bekannt, wiederholbar, nicht "Ausgang unklar"', () {
    for (final n in [Aufrufe.getEwpReport, Aufrufe.setEwpExtraQuantities]) {
      expect(Aufrufe.alle, contains(n));
      expect(isUnknownOutcomeCall(n), isFalse, reason: n);
    }
    final surface = jsonDecode(File('test/fixtures/vertrag/surface.json').readAsStringSync()) as Map<String, dynamic>;
    final oeffentlich = ((surface['calls'] as Map<String, dynamic>)['public'] as List).cast<String>();
    expect(oeffentlich, containsAll(['getEwpReport', 'setEwpExtraQuantities']));
  });

  test('nur API-Schluessel, keine Kasse: keine Kopfzeile cashregister-token', () async {
    final (:api, :log) = _server(_meldung());
    await api.getEwpReport(month: '2026-11');
    expect(log.single.headers['Authorization'], startsWith('Bearer kr_test_'));
    expect(log.single.headers.keys.map((k) => k.toLowerCase()), isNot(contains('cashregister-token')));
  });
}
