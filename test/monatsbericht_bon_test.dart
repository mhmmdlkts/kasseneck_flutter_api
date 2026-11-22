import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/models/receipt_layout.dart';
import 'package:kasseneck_api/printing.dart';

/// Monatsbericht als Bon (Backend-Spec 2026-11-21-monatsbericht-bon): Abruf ueber
/// `getCashregisterReport` mit `format: 'receipt'` und Druck eines fertigen Layouts.

const _kopf = {'content-type': 'application/json', 'kasseneck-api-version': 'v3'};

const _bonAntwort = {
  'status': 'success',
  'data': {
    'layout': {
      'lines': [
        {'kind': 'banner', 'text': 'TESTUMGEBUNG', 'tone': 'warning'},
        {'kind': 'text', 'text': 'MONATSBERICHT', 'align': 'center', 'bold': true},
        {'kind': 'rule', 'char': '='},
        {
          'kind': 'columns',
          'columns': [
            {'text': 'GESAMT Brutto', 'width': 8, 'align': 'left'},
            {'text': '205,00', 'width': 4, 'align': 'right'},
          ],
        },
        {'kind': 'text', 'text': 'Kein Registrierkassenbeleg.', 'align': 'center', 'bold': false},
      ],
      'paperSize': 'mm80',
      'ruleset': 2,
    },
    'reportNumber': '7F3A 91C2',
    'recalculated': false,
    'period': {'year': 2026, 'month': 10},
  },
};

({KasseneckApi api, List<http.Request> log}) _api(FutureOr<http.Response> Function(http.Request) antwort) {
  final log = <http.Request>[];
  final api = KasseneckApi(
    apiKey: 'kr_test_x',
    cashregisterToken: base64Encode(utf8.encode('KECK-1:secret')),
    httpClient: MockClient((r) async {
      log.add(r);
      return antwort(r);
    }),
  );
  return (api: api, log: log);
}

Map<String, dynamic> _params(http.Request r) => (jsonDecode(r.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('getCashregisterReportReceipt', () {
    test('sendet Monat, format receipt und Papierbreite; liest Layout, Pruefnummer, neu berechnet', () async {
      final m = _api((_) => http.Response(jsonEncode(_bonAntwort), 200, headers: _kopf));
      final r = await m.api.getCashregisterReportReceipt(year: 2026, month: 10, paperSize: KeckPaperSize.mm80);
      expect(m.log.single.url.path, endsWith('getCashregisterReport'));
      expect(_params(m.log.single), {'year': 2026, 'month': 10, 'format': 'receipt', 'paperSize': 'mm80'});
      expect(r.reportNumber, '7F3A 91C2');
      expect(r.recalculated, isFalse);
      expect(r.layout.paperSize, 'mm80');
      expect(r.layout.ruleset, 2);
      expect(r.layout.lines, hasLength(5));
      expect(r.layout.lines.first, isA<LayoutBannerLine>());
    });

    test('Vorgabe 58 mm; ohne Pruefnummer ist reportNumber null', () async {
      final antwort = jsonDecode(jsonEncode(_bonAntwort)) as Map<String, dynamic>;
      (antwort['data'] as Map)['reportNumber'] = null;
      (antwort['data'] as Map)['recalculated'] = true;
      final m = _api((_) => http.Response(jsonEncode(antwort), 200, headers: _kopf));
      final r = await m.api.getCashregisterReportReceipt(year: 2026, month: 9);
      expect(_params(m.log.single)['paperSize'], 'mm58');
      expect(r.reportNumber, isNull);
      expect(r.recalculated, isTrue);
    });

    test('ungueltiger Monat wirft vor dem Aufruf', () async {
      final m = _api((_) => http.Response('{}', 200, headers: _kopf));
      expect(() => m.api.getCashregisterReportReceipt(year: 2026, month: 13), throwsArgumentError);
      expect(m.log, isEmpty);
    });

    test('Fehlerhuelle kommt mit Code (laufender Monat)', () async {
      final m = _api((_) => http.Response(
          jsonEncode({'status': 'error', 'message': 'Nur abgeschlossene Monate.', 'code': 'period_not_closed', 'data': {'code': 'period_not_closed'}}),
          200,
          headers: _kopf));
      await expectLater(m.api.getCashregisterReportReceipt(year: 2026, month: 11),
          throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'period_not_closed')));
    });

    test('Antwort ohne Zeilen ist ein Fehler, kein leerer Bon', () async {
      final m = _api((_) => http.Response(
          jsonEncode({'status': 'success', 'data': {'layout': {'lines': [], 'paperSize': 'mm58', 'ruleset': 2}, 'reportNumber': null, 'recalculated': false}}),
          200,
          headers: _kopf));
      await expectLater(m.api.getCashregisterReportReceipt(year: 2026, month: 10), throwsA(isA<FormatException>()));
    });
  });

  group('KeckPrinterService.getPaperFromLayout', () {
    test('mit brandMark: Kasseneck-Zeichen am Ende (Bytes und myPOS-Blatt laenger)', () async {
      final layout = ReceiptLayout.fromJson((_bonAntwort['data'] as Map)['layout'])!;
      final ohne = await KeckPrinterService.getPaperFromLayout(layout, KeckPaperSize.mm58);
      final mit = await KeckPrinterService.getPaperFromLayout(layout, KeckPaperSize.mm58, brandMark: true);
      expect(mit.bytes.expand((e) => e).length, greaterThan(ohne.bytes.expand((e) => e).length + 100));
      expect(mit.myPosPaper.commands.length, greaterThan(ohne.myPosPaper.commands.length));
    });

    test('fertiges Layout ergibt ESC/POS-Bytes und ein myPOS-Blatt', () async {
      final layout = ReceiptLayout.fromJson((_bonAntwort['data'] as Map)['layout'])!;
      for (final papier in KeckPaperSize.values) {
        final paper = await KeckPrinterService.getPaperFromLayout(layout, papier);
        expect(paper.bytes.expand((e) => e).length, greaterThan(100), reason: papier.name);
        expect(paper.myPosPaper.commands, isNotEmpty, reason: papier.name);
      }
    });
  });
}
