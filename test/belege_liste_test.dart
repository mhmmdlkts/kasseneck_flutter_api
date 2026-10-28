import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/enums/receipt_type.dart';
import 'package:kasseneck_api/kasseneck_api.dart';

/// `listReceipts` (nur `/v3`): Seiten, Blaettern, Tagessumme, Fehler und die
/// Pruefung der Eingaben vor dem Senden. Der Endpunkt steht noch nicht im
/// Vertrag des npm-Zwillings; die Kurzzeilen folgen der Projektion des
/// Backends (`beleg-liste-core.zusammenfassung`), die volle Ansicht nimmt die
/// Belege des Vertragsfalls `report` (`getReportV2`, dieselbe Form).

const _kopf = {'content-type': 'application/json', 'kasseneck-api-version': 'v3'};

final List<Map<String, dynamic>> _berichtBelege = () {
  final belege = jsonDecode(File('test/fixtures/vertrag/v3/antworten/belege.json').readAsStringSync()) as Map;
  final fall = (belege['cases'] as List).cast<Map<String, dynamic>>().firstWhere((f) => f['name'] == 'report');
  return (((fall['response'] as Map)['data'] as Map)['receipts'] as List).cast<Map<String, dynamic>>();
}();

KasseneckApi _api(http.Client client) => KasseneckApi(
      apiKey: 'kr_test_x',
      cashregisterToken: base64Encode(utf8.encode('KECK-1:secret')),
      httpClient: client,
    );

({MockClient client, List<http.Request> log}) _mock(FutureOr<http.Response> Function(http.Request r, int n) antwort) {
  final log = <http.Request>[];
  return (
    client: MockClient((r) async {
      log.add(r);
      return antwort(r, log.length);
    }),
    log: log,
  );
}

http.Response _erfolg(Map<String, dynamic> daten) =>
    http.Response(jsonEncode({'status': 'success', 'message': '', 'data': daten}), 200, headers: _kopf);

http.Response _fehler(String code) => http.Response(
    jsonEncode({'status': 'error', 'message': 'Der Zeitraum darf höchstens 31 Tage lang sein.', 'code': code, 'data': {'code': code}}),
    200,
    headers: _kopf);

Map<String, dynamic> _params(http.Request r) => (jsonDecode(r.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;

/// Eine Kurzzeile wie vom Server; [ueber] ersetzt einzelne Felder.
Map<String, dynamic> _zeile(String id, {Map<String, dynamic> ueber = const {}}) => {
      'receiptId': id,
      'counter': 2,
      'receiptType': 'standard',
      'zeroKind': null,
      'timeStamp': '2026-10-27T10:15:00',
      'totalCents': 700,
      'grossByRateCents': {'standard': 600, 'reduced1': 0, 'reduced2': 0, 'zero': 100, 'special': 0},
      'paymentMethod': 'creditCard',
      'operator': null,
      'cancellationOf': null,
      'cancellationReason': null,
      'cancellationStatus': 'none',
      'signatureOk': true,
      'customProjectId': null,
      'fullReceiptId': 'f-$id',
      ...ueber,
    };

Map<String, dynamic> _seite(List<Object?> receipts, {String? next, Object? daySummary, bool mitTagessumme = false}) => {
      'receipts': receipts,
      'hasMore': next != null,
      'nextCursor': next,
      if (mitTagessumme) 'daySummary': daySummary,
    };

const _tagessumme = {
  'date': '2026-10-27',
  'receiptCount': 143,
  'revenueCents': 512340,
  'revenueByRate': [
    {'rateBp': 2000, 'grossCents': 401200},
    {'rateBp': 1000, 'grossCents': 111140},
  ],
};

Matcher _anfragefehler([String? teil]) => throwsA(isA<KasseneckValidationError>()
    .having((e) => e.kind, 'kind', 'request')
    .having((e) => e.functionName, 'functionName', 'listReceipts')
    .having((e) => e.reason, 'reason', teil == null ? anything : contains(teil)));

Matcher _antwortfehler(String teil) =>
    throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'response').having((e) => e.reason, 'reason', contains(teil)));

void main() {
  group('listReceipts: eine Seite', () {
    test('summary: Aufruf, gesendete Parameter und jede Kurzzeile in Cent', () async {
      final m = _mock((_, _) => _erfolg(_seite([
            _zeile('KECK-1-ID-2', ueber: {
              'payments': [
                {'id': 'p1', 'method': 'creditCard', 'amountCents': 700, 'provider': 'sumup'},
              ],
              'tipCents': 100,
              'operator': {'name': 'Livia Lindmayr'},
              'customProjectId': 'auftrag-4711',
              'cancellationStatus': 'partial',
            }),
            _zeile('KECK-1-ID-3', ueber: {
              'receiptType': 'cancellation',
              'totalCents': -300,
              'grossByRateCents': {'standard': -300, 'reduced1': 0, 'reduced2': 0, 'zero': 0, 'special': 0},
              'paymentMethod': 'cash',
              'cancellationOf': {'receiptId': 'KECK-1-ID-2', 'timeStamp': '2026-10-27T10:15:00'},
              'cancellationReason': 'input_error',
              'signatureOk': false,
            }),
            _zeile('KECK-1-ID-4', ueber: {
              'receiptType': 'zero',
              'zeroKind': 'monthly',
              'totalCents': 0,
              'grossByRateCents': {'standard': 0, 'reduced1': 0, 'reduced2': 0, 'zero': 0, 'special': 0},
              // Ein kuenftiger Wert wird nicht zu "bar" geraten.
              'paymentMethod': 'voucherWallet',
            }),
          ], mitTagessumme: true, daySummary: _tagessumme)));

      final seite = await _api(m.client).listReceipts(date: '2026-10-27');

      final r = m.log.single;
      expect(r.url.toString(), 'https://api.kasseneck.at/v3/listReceipts');
      expect(r.headers['Authorization'], 'Bearer kr_test_x');
      expect(r.headers['cashregister-token'], base64Encode(utf8.encode('KECK-1:secret')));
      expect(_params(r), {'date': '2026-10-27', 'view': 'summary'});

      expect(seite.hasMore, isFalse);
      expect(seite.nextCursor, isNull);
      final [verkauf, storno, nullbeleg] = seite.receipts;
      expect(verkauf.receiptId, 'KECK-1-ID-2');
      expect(verkauf.counter, 2);
      expect(verkauf.receiptType, ReceiptType.standard);
      expect(verkauf.timeStamp, '2026-10-27T10:15:00');
      expect(verkauf.totalCents, 700);
      expect(verkauf.grossByRateCents.standard, 600);
      expect(verkauf.grossByRateCents.zero, 100);
      expect(verkauf.paymentMethod, KeckPaymentMethod.creditCard);
      expect(verkauf.payments!.single.amountCents, 700);
      expect(verkauf.tipCents, 100);
      expect(verkauf.operator!.name, 'Livia Lindmayr');
      expect(verkauf.operator!.uid, isNull);
      expect(verkauf.cancellationStatus, CancellationState.partial);
      expect(verkauf.cancellationOf, isNull);
      expect(verkauf.signatureOk, isTrue);
      expect(verkauf.customProjectId, 'auftrag-4711');
      expect(verkauf.fullReceiptId, 'f-KECK-1-ID-2');

      expect(storno.receiptType, ReceiptType.cancellation);
      expect(storno.totalCents, -300);
      expect(storno.cancellationOf!.receiptId, 'KECK-1-ID-2');
      expect(storno.cancellationOf!.timeStamp, '2026-10-27T10:15:00');
      expect(storno.cancellationReason, 'input_error');
      expect(storno.signatureOk, isFalse);
      expect(storno.payments, isNull, reason: 'payments nur, wenn die Zeile sie traegt');
      expect(storno.tipCents, isNull);

      expect(nullbeleg.zeroKind, 'monthly');
      expect(nullbeleg.paymentMethod, isNull);

      final summe = seite.daySummary!;
      expect(summe.date, '2026-10-27');
      expect(summe.receiptCount, 143);
      expect(summe.revenueCents, 512340);
      expect(summe.revenueByRate, [(rateBp: 2000, grossCents: 401200), (rateBp: 1000, grossCents: 111140)]);
    });

    test('full: die gespeicherten Belege als KasseneckReceipt (Form von getReportV2)', () async {
      final m = _mock((_, _) => _erfolg(_seite(_berichtBelege)));
      final seite = await _api(m.client).listFullReceipts(from: '2026-09-26', to: '2026-09-27T00:00:00', order: 'asc', limit: 500);
      expect(_params(m.log.single), {'from': '2026-09-26', 'to': '2026-09-27T00:00:00', 'limit': 500, 'order': 'asc', 'view': 'full'});
      expect(seite.receipts.map((b) => b.receiptId), _berichtBelege.map((b) => b['receiptId']));
      for (final (i, b) in seite.receipts.indexed) {
        expect(b.fullReceiptId, _berichtBelege[i]['fullReceiptId']);
        expect(b.headerVersionId, _berichtBelege[i]['headerVersionId']);
        // Die Seite traegt keine Kopfdaten des Betriebs.
        expect(b.companyName, '');
      }
      expect(seite.daySummary, isNull);
    });

    test('full: ein unlesbarer Beleg faellt heraus, die Seite nicht (wie getReceipts)', () async {
      final m = _mock((_, _) => _erfolg(_seite([_berichtBelege.first, 'kein Beleg', _berichtBelege.last])));
      final seite = await _api(m.client).listFullReceipts(date: '2026-09-26');
      expect(seite.receipts.map((b) => b.receiptId), [_berichtBelege.first['receiptId'], _berichtBelege.last['receiptId']]);
    });

    test('leere Seite', () async {
      final m = _mock((_, _) => _erfolg(_seite(const [], mitTagessumme: true)));
      final seite = await _api(m.client).listReceipts(date: '2030-01-01');
      expect(seite.receipts, isEmpty);
      expect(seite.hasMore, isFalse);
      expect(seite.daySummary, isNull, reason: 'Tag ohne Statistik: daySummary null');
    });
  });

  group('daySummary nur auf Seite 1', () {
    test('Seite 1 mit date traegt sie, die Folgeseite mit cursor nicht', () async {
      final m = _mock((r, n) => n == 1
          ? _erfolg(_seite([_zeile('KECK-1-ID-9')], next: 'c1', mitTagessumme: true, daySummary: _tagessumme))
          : _erfolg(_seite([_zeile('KECK-1-ID-8')])));
      final api = _api(m.client);
      final erste = await api.listReceipts(date: '2026-10-27', limit: 1);
      final zweite = await api.listReceipts(date: '2026-10-27', limit: 1, cursor: erste.nextCursor);
      expect(erste.daySummary!.receiptCount, 143);
      expect(zweite.daySummary, isNull);
      expect(_params(m.log[1]), {'date': '2026-10-27', 'limit': 1, 'view': 'summary', 'cursor': 'c1'});
    });
  });

  group('listAllReceipts', () {
    test('drei Seiten: Cursor weitergegeben, Fenster, order und view gleich, Seitengroesse 500', () async {
      final seiten = [
        _seite([_zeile('KECK-1-ID-6'), _zeile('KECK-1-ID-5')], next: 'c1', mitTagessumme: true, daySummary: _tagessumme),
        _seite([_zeile('KECK-1-ID-4'), _zeile('KECK-1-ID-3')], next: 'c2'),
        _seite([_zeile('KECK-1-ID-2')]),
      ];
      final m = _mock((_, n) => _erfolg(seiten[n - 1]));
      final alle = await _api(m.client).listAllReceipts(from: '2026-10-01', to: '2026-11-01', order: 'desc').toList();

      expect(alle.map((b) => b.receiptId), ['KECK-1-ID-6', 'KECK-1-ID-5', 'KECK-1-ID-4', 'KECK-1-ID-3', 'KECK-1-ID-2']);
      expect(m.log, hasLength(3));
      const fenster = {'from': '2026-10-01', 'to': '2026-11-01', 'limit': 500, 'order': 'desc', 'view': 'summary'};
      expect(_params(m.log[0]), fenster);
      expect(_params(m.log[1]), {...fenster, 'cursor': 'c1'});
      expect(_params(m.log[2]), {...fenster, 'cursor': 'c2'});
    });

    test('full: zwei Seiten, eigenes limit bleibt', () async {
      final m = _mock((_, n) => n == 1
          ? _erfolg(_seite(_berichtBelege.take(2).toList(), next: 'c1'))
          : _erfolg(_seite(_berichtBelege.skip(2).toList())));
      final alle = await _api(m.client).listAllFullReceipts(date: '2026-09-26', limit: 2).toList();
      expect(alle.map((b) => b.receiptId), _berichtBelege.map((b) => b['receiptId']));
      expect(_params(m.log[0]), {'date': '2026-09-26', 'limit': 2, 'view': 'full'});
      expect(_params(m.log[1]), {'date': '2026-09-26', 'limit': 2, 'view': 'full', 'cursor': 'c1'});
    });

    test('Fehler auf Seite 2: Seite 1 ist geliefert, dann endet der Strom mit dem Code', () async {
      final m = _mock((_, n) => n == 1 ? _erfolg(_seite([_zeile('KECK-1-ID-6')], next: 'c1')) : _fehler('invalid_cursor'));
      final geliefert = <String?>[];
      await expectLater(
        _api(m.client).listAllReceipts(date: '2026-10-27').map((b) => geliefert.add(b.receiptId)).toList(),
        throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'invalid_cursor')),
      );
      expect(geliefert, ['KECK-1-ID-6']);
      expect(m.log, hasLength(2), reason: 'nach dem Fehler keine dritte Seite');
    });

    test('Schutz: nach 100 Seiten Abbruch mit Fehler', () async {
      final m = _mock((_, n) => _erfolg(_seite([_zeile('KECK-1-ID-$n')], next: 'c$n')));
      await expectLater(_api(m.client).listAllReceipts(date: '2026-10-27').toList(), _anfragefehler('100 Seiten'));
      expect(m.log, hasLength(receiptListPagesMax));
      expect(_params(m.log.last)['cursor'], 'c${receiptListPagesMax - 1}');
    });

    test('derselbe nextCursor zweimal endet mit einem Antwortfehler statt einer Schleife', () async {
      final m = _mock((_, _) => _erfolg(_seite([_zeile('KECK-1-ID-1')], next: 'immer-gleich')));
      await expectLater(_api(m.client).listAllReceipts(date: '2026-10-27').toList(), _antwortfehler('nextCursor zweimal'));
      expect(m.log, hasLength(2));
    });

    test('Eingabefehler faellt an der Aufrufstelle, ohne Netzaufruf', () {
      final m = _mock((_, _) => _erfolg(_seite(const [])));
      expect(() => _api(m.client).listAllReceipts(date: '2026-02-30'), _anfragefehler('date'));
      expect(() => _api(m.client).listAllFullReceipts(from: '2026-10-01', to: '2026-11-02'), _anfragefehler('31'));
      expect(m.log, isEmpty);
    });
  });

  group('Fehlercode aus der Huelle', () {
    for (final code in receiptListErrorCodes) {
      test(code, () async {
        final m = _mock((_, _) => _fehler(code));
        await expectLater(
          _api(m.client).listReceipts(date: '2026-10-27'),
          throwsA(isA<KasseneckApiError>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.functionName, 'functionName', 'listReceipts')
              .having((e) => e.message, 'message', startsWith('Der Zeitraum'))
              .having(isOutcomeUnknown, 'isOutcomeUnknown', isFalse)),
        );
      });
    }

    test('Code nur in data.code kommt ebenso an', () async {
      final m = _mock((_, _) => http.Response(
          jsonEncode({'status': 'error', 'message': 'nein', 'data': {'code': 'invalid_cursor'}}), 200,
          headers: _kopf));
      await expectLater(_api(m.client).listFullReceipts(date: '2026-10-27'),
          throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'invalid_cursor')));
    });
  });

  group('Eingaben werden vor dem Senden geprueft', () {
    final faelle = <String, ({String? date, String? from, String? to, int? limit, String? order, String? cursor, String teil})>{
      'kein Zeitfenster': (date: null, from: null, to: null, limit: null, order: null, cursor: null, teil: 'Zeitraum fehlt'),
      'date und from': (date: '2026-10-27', from: '2026-10-27', to: null, limit: null, order: null, cursor: null, teil: 'nicht beides'),
      'date und to': (date: '2026-10-27', from: null, to: '2026-10-28', limit: null, order: null, cursor: null, teil: 'nicht beides'),
      'nur from': (date: null, from: '2026-10-27', to: null, limit: null, order: null, cursor: null, teil: 'Zeitraum fehlt'),
      'nur to': (date: null, from: null, to: '2026-10-27', limit: null, order: null, cursor: null, teil: 'Zeitraum fehlt'),
      'unmoegliches Datum': (date: '2026-02-30', from: null, to: null, limit: null, order: null, cursor: null, teil: 'date'),
      'date mit Uhrzeit': (date: '2026-10-27T00:00:00', from: null, to: null, limit: null, order: null, cursor: null, teil: 'date'),
      'date ohne fuehrende Null': (date: '2026-1-27', from: null, to: null, limit: null, order: null, cursor: null, teil: 'date'),
      'from mit Zone': (date: null, from: '2026-10-01T00:00:00Z', to: '2026-10-02', limit: null, order: null, cursor: null, teil: 'from'),
      'to mit Millisekunden': (date: null, from: '2026-10-01', to: '2026-10-02T00:00:00.000', limit: null, order: null, cursor: null, teil: 'to'),
      'Stunde 24': (date: null, from: '2026-10-01', to: '2026-10-01T24:00:00', limit: null, order: null, cursor: null, teil: 'to'),
      'to gleich from': (date: null, from: '2026-10-01', to: '2026-10-01T00:00:00', limit: null, order: null, cursor: null, teil: 'nach from'),
      'to vor from': (date: null, from: '2026-10-02', to: '2026-10-01', limit: null, order: null, cursor: null, teil: 'nach from'),
      '32 Tage': (date: null, from: '2026-10-01', to: '2026-11-02', limit: null, order: null, cursor: null, teil: '31 Tage'),
      '31 Tage und eine Sekunde': (date: null, from: '2026-10-01T10:00:00', to: '2026-11-01T10:00:01', limit: null, order: null, cursor: null, teil: '31 Tage'),
      'limit 0': (date: '2026-10-27', from: null, to: null, limit: 0, order: null, cursor: null, teil: 'limit'),
      'limit 501': (date: '2026-10-27', from: null, to: null, limit: 501, order: null, cursor: null, teil: 'limit'),
      'order unbekannt': (date: '2026-10-27', from: null, to: null, limit: null, order: 'newest', cursor: null, teil: 'order'),
      'cursor leer': (date: '2026-10-27', from: null, to: null, limit: null, order: null, cursor: '', teil: 'cursor'),
    };
    for (final MapEntry(key: name, value: f) in faelle.entries) {
      test(name, () {
        final m = _mock((_, _) => _erfolg(_seite(const [])));
        final api = _api(m.client);
        expect(() => api.listReceipts(date: f.date, from: f.from, to: f.to, limit: f.limit, order: f.order, cursor: f.cursor),
            _anfragefehler(f.teil));
        expect(() => api.listFullReceipts(date: f.date, from: f.from, to: f.to, limit: f.limit, order: f.order, cursor: f.cursor),
            _anfragefehler(f.teil));
        expect(m.log, isEmpty);
      });
    }

    // Die Grenzen, die gerade noch gehen: 31 Kalendertage auch ueber die
    // Zeitumstellung (25.10.2026, 29.03.2026), Schaltjahr, limit 1 und 500.
    final gueltig = <String, ({String? date, String? from, String? to, int? limit})>{
      'Oktober mit Zeitumstellung, 31 Tage': (date: null, from: '2026-10-01', to: '2026-11-01', limit: null),
      'Maerz mit Zeitumstellung, 31 Tage': (date: null, from: '2026-03-01', to: '2026-04-01', limit: null),
      '31 Tage auf die Sekunde': (date: null, from: '2026-10-01T10:00:00', to: '2026-11-01T10:00:00', limit: null),
      'eine Sekunde': (date: null, from: '2026-10-25T02:59:59', to: '2026-10-25T03:00:00', limit: null),
      'Schalttag': (date: '2028-02-29', from: null, to: null, limit: 1),
      'Tag der Zeitumstellung': (date: '2026-10-25', from: null, to: null, limit: 500),
    };
    for (final MapEntry(key: name, value: f) in gueltig.entries) {
      test('gültig: $name', () async {
        final m = _mock((_, _) => _erfolg(_seite(const [])));
        await _api(m.client).listReceipts(date: f.date, from: f.from, to: f.to, limit: f.limit);
        expect(_params(m.log.single), {'date': ?f.date, 'from': ?f.from, 'to': ?f.to, 'limit': ?f.limit, 'view': 'summary'});
      });
    }
  });

  group('kaputte Antwort wird nicht geraten', () {
    final faelle = <String, (Map<String, dynamic>, String)>{
      'receipts fehlt': ({'hasMore': false, 'nextCursor': null}, 'data.receipts fehlt'),
      'hasMore fehlt': ({'receipts': const [], 'nextCursor': null}, 'data.hasMore'),
      'hasMore ohne Cursor': ({'receipts': const [], 'hasMore': true, 'nextCursor': null}, 'passt nicht'),
      'Cursor ohne hasMore': ({'receipts': const [], 'hasMore': false, 'nextCursor': 'c1'}, 'passt nicht'),
      'Betrag mit Nachkomma': (_seite([_zeile('KECK-1-ID-1', ueber: {'totalCents': 12.5})]), 'receipts[0].totalCents'),
      'Topf fehlt': (
        _seite([
          _zeile('KECK-1-ID-1', ueber: {
            'grossByRateCents': {'standard': 600, 'reduced1': 0, 'reduced2': 0, 'zero': 100},
          }),
        ]),
        'grossByRateCents.special'
      ),
      'Zeile kein Objekt': (_seite(['KECK-1-ID-1']), 'receipts[0] ist kein Objekt'),
      'Tagessumme ohne Zahl': (
        _seite(const [], mitTagessumme: true, daySummary: {..._tagessumme, 'revenueCents': '512340'}),
        'daySummary.revenueCents'
      ),
    };
    for (final MapEntry(key: name, value: (daten, teil)) in faelle.entries) {
      test(name, () async {
        final m = _mock((_, _) => _erfolg(daten));
        await expectLater(_api(m.client).listReceipts(date: '2026-10-27'), _antwortfehler(teil));
      });
    }
  });
}
