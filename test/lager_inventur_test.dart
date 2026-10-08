import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/inventory.dart';

import 'helpers/lager_anfragen.dart';

/// Die Inventur der Lager-API (`InventoryClient`, Zwilling von
/// `src/inventory/inventur.ts` im npm-Paket 1.8.0) gegen den Vertrags-Export
/// `v3/antworten/lager.json` (erfundenes Konto Baeckerei Kornblum). Dass jeder
/// Fall durch den Client laeuft und die Parameter wie aufgezeichnet hinausgehen,
/// prueft `lager_api_test.dart`; hier stehen das Lesen der Modelle, das
/// Protokoll als Datei oder Link und die Pruefungen vor dem Senden.

const _apiKey = 'kr_test_Beispielschluessel0123456789';

Map<String, dynamic> _json(String pfad) => jsonDecode(File(pfad).readAsStringSync()) as Map<String, dynamic>;

final _faelle = (_json('test/fixtures/vertrag/v3/antworten/lager.json')['cases'] as List).cast<Map<String, dynamic>>();

Map<String, dynamic> _fall(String name) => _faelle.firstWhere((c) => c['name'] == name);
Map<String, dynamic> _daten(String name) => (_fall(name)['response'] as Map)['data'] as Map<String, dynamic>;

/// Tiefe Kopie, damit ein Test die Vertragsdaten nie veraendert.
T _kopie<T>(T wert) => jsonDecode(jsonEncode(wert)) as T;

/// Ohne `null`-Werte, rekursiv: ein Feld, das der Server mit `null` sendet,
/// und eines, das er weglaesst, sind im Modell beide `null`.
Object? _ohneNull(Object? w) => switch (w) {
  Map m => {
    for (final e in m.entries)
      if (e.value != null) e.key: _ohneNull(e.value),
  },
  List l => [for (final x in l) _ohneNull(x)],
  _ => w,
};

const _kennzeichen = {'kasseneck-api-version': 'v3'};

http.Response _antwort(Object? rumpf, {int status = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode(rumpf)),
  status,
  headers: {'content-type': 'application/json', ..._kennzeichen},
);
http.Response _erfolg(Object? data) => _antwort({'status': 'success', 'message': '', 'data': data});

({InventoryClient lager, List<http.Request> anfragen}) _client(List<http.Response> antworten) {
  final anfragen = <http.Request>[];
  var i = 0;
  final mock = MockClient((request) async {
    anfragen.add(request);
    if (i >= antworten.length) throw StateError('Attrappe: keine Antwort mehr vorbereitet');
    return antworten[i++];
  });
  return (lager: InventoryClient(apiKey: _apiKey, httpClient: mock), anfragen: anfragen);
}

Map<String, dynamic> _params(http.Request r) =>
    (jsonDecode(r.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;

final Matcher _antwortfehler = isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'response');
final Matcher _anfragefehler = isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'request');

/// Ein Kopf, wie `getStocktake` ihn in der Zaehlung sendet.
Map<String, dynamic> get _kopf => _kopie(_daten('get_stocktake_counting')['stocktake'] as Map<String, dynamic>);

/// Eine Position, wie die Liste sie nach dem Abschluss mit Werten sendet.
Map<String, dynamic> get _position =>
    _kopie((_daten('list_stocktake_items_closed_with_costs')['items'] as List).first as Map<String, dynamic>);

/// Eine Zaehlung, wie die Liste sie sendet.
Map<String, dynamic> get _zaehlung =>
    _kopie((_daten('list_stocktake_counts')['counts'] as List).last as Map<String, dynamic>);

Uint8List _pdf() => Uint8List.fromList([...utf8.encode('%PDF-1.7\n'), 0, 1, 2, 3, ...utf8.encode('%%EOF')]);

void main() {
  group('Vertrag: jede Erfolgsantwort liest sich verlustfrei', () {
    // Welcher Teil von `data` ist das Modell, je Endpunkt.
    Object? modell(String endpunkt, Object? ergebnis) => switch (ergebnis) {
      Stocktake s => {'stocktake': s.toJson()},
      StocktakePage s => s.toJson(),
      StocktakeItemPage s => s.toJson(),
      StocktakeCountPage s => s.toJson(),
      StocktakeCountResult s => s.toJson(),
      CloseStocktakeResult s => {
        'stocktake': s.stocktake.toJson(),
        if (s.warnings.isNotEmpty) 'warnings': [for (final w in s.warnings) w.toJson()],
      },
      StocktakePdfLink s => {'download': s.download.toJson()},
      _ => throw StateError('$endpunkt: unbekanntes Ergebnis $ergebnis'),
    };

    test('jeder Inventur-Fall des Exports, Feld fuer Feld', () async {
      var gelesen = 0;
      for (final c in _faelle) {
        final endpunkt = c['endpoint'] as String;
        if (!endpunkt.contains('tocktake') || (c['response'] as Map)['status'] != 'success') continue;
        final (:lager, anfragen: _) = _client([_antwort(c['response'])]);
        final ergebnis = await schreibAufruf(lager, endpunkt, _kopie(c['params'] as Map<String, dynamic>));
        expect(
          _ohneNull(modell(endpunkt, ergebnis)),
          _ohneNull((c['response'] as Map)['data']),
          reason: c['name'] as String,
        );
        gelesen++;
      }
      // Alle 23 Erfolgsfaelle der zwoelf Endpunkte (ohne die sieben Fehlerfaelle).
      expect(gelesen, 23);
    });

    test('blind: vor der Pruefung kein Soll, keine Differenz, kein pruefen', () async {
      final (:lager, anfragen: _) = _client([
        _antwort(_fall('list_stocktake_items_counting')['response']),
        _antwort(_fall('list_stocktake_items_review')['response']),
        _antwort(_fall('list_stocktake_items_not_blind')['response']),
      ]);
      final zaehlung = (await lager.listStocktakeItems(stocktakeId: 'auto78')).items.single;
      expect([
        zaehlung.expectedQuantity,
        zaehlung.differenceQuantity,
        zaehlung.needsCheck,
        zaehlung.checkReasons,
      ], everyElement(isNull));
      expect(zaehlung.bookStockNow, isNull);
      final pruefung = (await lager.listStocktakeItems(stocktakeId: 'auto78')).items.single;
      expect([pruefung.expectedQuantity, pruefung.differenceQuantity, pruefung.needsCheck], [24000, -12000, true]);
      expect(pruefung.checkReasons, ['far_from_key_date']);
      final offen = (await lager.listStocktakeItems(stocktakeId: 'auto81')).items.single;
      expect(offen.bookStockNow, 3000);
      expect([offen.counted, offen.quantity, offen.expectedQuantity], [false, null, null]);
    });

    test('Kopf: Fortschritt nur aus getStocktake, Ergebnis erst nach dem Abschluss, Werte nur mit costs', () async {
      final (:lager, anfragen: _) = _client([
        _antwort(_fall('get_stocktake_counting')['response']),
        _antwort(_fall('close_stocktake')['response']),
        _antwort(_fall('get_stocktake_closed')['response']),
        _antwort(_fall('get_stocktake_closed_with_costs')['response']),
      ]);
      final zaehlung = await lager.getStocktake('auto78');
      expect(zaehlung.status, 'counting');
      expect(zaehlung.progress!.counted, isA<int>());
      expect([
        zaehlung.totals,
        zaehlung.warnings,
        zaehlung.seal,
        zaehlung.checksum,
        zaehlung.pdf,
      ], everyElement(isNull));
      final schluss = await lager.closeStocktake(
        const CloseStocktakeRequest(idempotencyKey: 'k', stocktakeId: 'auto78'),
      );
      expect(schluss.stocktake.status, 'closing');
      // Die Abschluss-Antwort zaehlt nicht: unbekannt ist nicht „keine“.
      expect(schluss.stocktake.progress!.counted, isNull);
      expect(schluss.stocktake.closing!.parts, isNull);
      expect(schluss.warnings, isEmpty);
      final ohneWerte = await lager.getStocktake('auto78');
      expect(ohneWerte.totals!.differenceValueCents, isNull);
      expect(ohneWerte.pdf!.valuesSha256, isNull);
      expect(ohneWerte.pdf!.quantitiesSha256, isNotNull);
      final mitWerten = await lager.getStocktake('auto78');
      expect([mitWerten.totals!.differenceValueCents, mitWerten.totals!.inventoryValueCents], [-122, 856]);
      expect(mitWerten.warnings, isEmpty);
      expect(mitWerten.seal!.verified, isTrue);
      expect(mitWerten.inventoryAsOf, 'count_date');
    });

    test('Zaehlen und Stornieren: die Position kommt ohne Seriennummern (null, nicht leer)', () async {
      final (:lager, anfragen: _) = _client([
        _antwort(_fall('record_stocktake_count')['response']),
        _antwort(_fall('list_stocktake_items_counting')['response']),
      ]);
      final r = await lager.recordStocktakeCount(
        zaehlung(_fall('record_stocktake_count')['params'] as Map<String, dynamic>),
      );
      expect(r.item.serialNumbers, isNull);
      expect(r.item.toJson().containsKey('serialNumbers'), isFalse);
      expect(r.count.serialNumbers, isEmpty);
      expect([r.count.quantity, r.item.quantity, r.item.counts], [12000, 12000, 1]);
      final liste = await lager.listStocktakeItems(stocktakeId: 'auto78');
      expect(liste.items.single.serialNumbers, isEmpty);
    });

    test('stocktake_location_busy nennt die offene Inventur, andere Fehler nicht', () async {
      final (:lager, anfragen: _) = _client([
        _antwort(_fall('error_create_stocktake_location_busy')['response']),
        _antwort(_fall('error_get_stocktake_not_found')['response']),
      ]);
      Object? fehler;
      try {
        await lager.createStocktake(
          inventurAnlegen(_fall('error_create_stocktake_location_busy')['params'] as Map<String, dynamic>),
        );
      } catch (e) {
        fehler = e;
      }
      expect(inventoryErrorCode(fehler), 'stocktake_location_busy');
      expect(inventoryBusyStocktakeId(fehler), 'auto78');
      Object? anderer;
      try {
        await lager.getStocktake('gibt_es_nicht');
      } catch (e) {
        anderer = e;
      }
      expect(inventoryErrorCode(anderer), 'stocktake_not_found');
      expect(inventoryBusyStocktakeId(anderer), isNull);
      expect(
        inventoryBusyStocktakeId(const KasseneckApiError('createStocktake', 'x', code: 'stocktake_location_busy')),
        isNull,
        reason: 'ohne Kennung keine erfundene',
      );
      expect(inventoryBusyStocktakeId(Exception('stocktake_location_busy')), isNull);
    });
  });

  group('Inventurprotokoll: Datei oder Link', () {
    test('bis 9 MiB die Datei selbst, unveraendert', () async {
      final datei = _pdf();
      final (:lager, :anfragen) = _client([
        http.Response.bytes(datei, 200, headers: {'content-type': 'application/pdf', ..._kennzeichen}),
      ]);
      final protokoll = await lager.getStocktakePdf('auto78');
      expect(protokoll, isA<StocktakePdfFile>().having((p) => p.kind, 'kind', 'pdf'));
      expect((protokoll as StocktakePdfFile).pdf, datei);
      expect(anfragen.single.url.toString(), 'https://api.kasseneck.at/v3/getStocktakePdf');
      expect(_params(anfragen.single), {'stocktakeId': 'auto78'});
    });

    test('darueber der signierte Link aus dem Vertrag', () async {
      final (:lager, anfragen: _) = _client([_antwort(_fall('get_stocktake_pdf_download')['response'])]);
      final protokoll = await lager.getStocktakePdf('auto78');
      final link = (protokoll as StocktakePdfLink).download;
      expect(protokoll.kind, 'download');
      expect(link.toJson(), _daten('get_stocktake_pdf_download')['download']);
      expect(link.sizeBytes, 44);
    });

    test('ein Fachfehler bleibt ein Fachfehler (stocktake_not_closed), Ausgang abgelehnt', () async {
      final (:lager, anfragen: _) = _client([_antwort(_fall('error_get_stocktake_pdf_not_closed')['response'])]);
      await expectLater(
        lager.getStocktakePdf('auto81'),
        throwsA(
          isA<KasseneckApiError>()
              .having((e) => e.code, 'code', 'stocktake_not_closed')
              .having((e) => e.outcome, 'outcome', ErrorOutcome.rejected),
        ),
      );
    });

    test('Erfolg ohne Link, Link ohne Pruefsumme oder mit gebrochener Groesse: Antwortfehler', () async {
      final link = _kopie(_daten('get_stocktake_pdf_download')['download'] as Map<String, dynamic>);
      for (final data in [
        <String, dynamic>{},
        {'download': null},
        {'download': 'https://example.invalid/x.pdf'},
        {
          'download': {...link}..remove('sha256'),
        },
        {
          'download': {...link}..remove('url'),
        },
        {
          'download': {...link, 'sizeBytes': 44.5},
        },
        {
          'download': {...link, 'expiresAt': ''},
        },
      ]) {
        final (:lager, anfragen: _) = _client([_erfolg(data)]);
        await expectLater(lager.getStocktakePdf('auto78'), throwsA(_antwortfehler), reason: '$data');
      }
    });

    test('weder PDF noch JSON: unlesbar wie auf dem JSON-Weg, abgelehnt (Lesen)', () async {
      for (final (rumpf, grund) in [('', 'empty-body'), ('kein json', 'not-json'), ('{"data":{}}', 'missing-status')]) {
        final (:lager, anfragen: _) = _client([
          http.Response.bytes(utf8.encode(rumpf), 200, headers: {'content-type': 'application/json', ..._kennzeichen}),
        ]);
        await expectLater(
          lager.getStocktakePdf('auto78'),
          throwsA(
            isA<KasseneckHttpError>()
                .having((e) => e.reason, 'reason', grund)
                .having((e) => e.outcome, 'outcome', ErrorOutcome.rejected),
          ),
          reason: grund,
        );
      }
    });

    test('der Transport selbst: callPdfOrData liefert Datei oder Nutzlast', () async {
      final datei = _pdf();
      final weg = InventoryTransport(
        apiKey: _apiKey,
        httpClient: MockClient(
          (r) async => r.url.path.endsWith('/a')
              ? http.Response.bytes(datei, 200, headers: {'content-type': 'application/pdf', ..._kennzeichen})
              : _erfolg({'download': 'x'}),
        ),
      );
      expect(await weg.callPdfOrData('a', const {}), isA<PdfOrDataFile>().having((p) => p.pdf, 'pdf', datei));
      expect(
        await weg.callPdfOrData('b', const {}),
        isA<PdfOrDataPayload>().having((p) => p.data, 'data', {'download': 'x'}),
      );
      // Ein leeres stocktakeId geht nie hinaus.
      final (:lager, :anfragen) = _client(const []);
      await expectLater(lager.getStocktakePdf(' '), throwsA(_anfragefehler));
      expect(anfragen, isEmpty);
    });
  });

  group('Antwort streng gelesen', () {
    Future<Object?> lies(Map<String, dynamic> data, Future<Object?> Function(InventoryClient l) aufruf) async {
      final (:lager, anfragen: _) = _client([_erfolg(data)]);
      try {
        return await aufruf(lager);
      } catch (e) {
        return e;
      }
    }

    Future<Object?> position(Map<String, dynamic> p) => lies({
      'items': [p],
      'nextCursor': null,
    }, (l) => l.listStocktakeItems(stocktakeId: 'auto78'));
    Future<Object?> kopf(Map<String, dynamic> k) => lies({'stocktake': k}, (l) => l.getStocktake('auto78'));
    Future<Object?> zaehlung(Map<String, dynamic> z) => lies({
      'counts': [z],
      'nextCursor': null,
    }, (l) => l.listStocktakeCounts(stocktakeId: 'auto78'));

    test('Position: gezaehlt ohne Menge, ohne countedBy, kaputte Zaehler und Bruchzahlen sind Antwortfehler', () async {
      expect(await position(_position), isA<StocktakeItemPage>());
      expect(await position({..._position, 'quantity': null}), _antwortfehler, reason: 'counted: true ohne Menge');
      expect(await position({..._position}..remove('countedBy')), _antwortfehler);
      expect(await position({..._position, 'countedBy': 'api'}), _antwortfehler);
      expect(
        await position({
          ..._position,
          'countedBy': [null],
        }),
        _antwortfehler,
        reason: 'ein Eintrag null ist nicht „niemand“',
      );
      expect(
        await position({
          ..._position,
          'countedBy': ['api'],
        }),
        _antwortfehler,
      );
      expect(await position({..._position}..remove('counted')), _antwortfehler, reason: 'fehlt ist nicht ungezaehlt');
      expect(await position({..._position, 'round': 1.5}), _antwortfehler);
      expect(await position({..._position, 'counts': null}), _antwortfehler);
      expect(await position({..._position, 'expectedQuantity': 24000.5}), _antwortfehler);
      expect(await position({..._position, 'serialNumbers': 'SN1'}), _antwortfehler);
      expect(
        await position({
          ..._position,
          'notBooked': {'quantity': 1000},
        }),
        _antwortfehler,
        reason: 'Grund ohne Code',
      );
      expect(
        await position({
          ..._position,
          'inventory': {'countedOn': '2026-10-06'},
        }),
        _antwortfehler,
      );
      expect(await position({..._position}..remove('articleId')), _antwortfehler);
      // Ungezaehlt ohne Menge ist kein Fehler; 12000.0 ist eine Ganzzahl (JSON kennt keinen Unterschied).
      final ungezaehlt = await position({..._position, 'counted': false, 'quantity': null}) as StocktakeItemPage;
      expect(ungezaehlt.items.single.quantity, isNull);
      final ganz = await position({..._position, 'quantity': 21000.0}) as StocktakeItemPage;
      expect(ganz.items.single.quantity, 21000);
    });

    test('Akteure: null oder fehlend ergibt null, ein Nicht-Objekt ist ein Antwortfehler', () async {
      final ohne = await kopf({..._kopf}..remove('createdBy')) as Stocktake;
      expect(ohne.createdBy, isNull);
      final leer = await kopf({..._kopf, 'createdBy': null}) as Stocktake;
      expect(leer.createdBy, isNull);
      expect(await kopf({..._kopf, 'createdBy': 'owner'}), _antwortfehler);
      expect(
        await kopf({
          ..._kopf,
          'review': {'startedBy': 7, 'complete': false},
        }),
        _antwortfehler,
      );
      expect(
        await zaehlung({
          ..._zaehlung,
          'countedBy': ['api'],
        }),
        _antwortfehler,
      );
      final gut = await kopf(_kopf) as Stocktake;
      expect(gut.createdBy!.type, 'api');
    });

    test('Kopf: Pflichtzahlen ganz, Unterobjekte Objekt oder null, blind nur mit ausdruecklichem false aus', () async {
      expect(
        await kopf({
          ..._kopf,
          'progress': {'items': 1.5},
        }),
        _antwortfehler,
      );
      expect(
        await kopf({
          ..._kopf,
          'progress': {'recountOpen': false},
        }),
        _antwortfehler,
        reason: 'items fehlt',
      );
      expect(await kopf({..._kopf, 'closing': 'closing'}), _antwortfehler);
      expect(
        await kopf({
          ..._kopf,
          'scope': {'type': 'groups', 'groupIds': 'gebaeck'},
        }),
        _antwortfehler,
      );
      expect(await kopf({..._kopf, 'warnings': {}}), _antwortfehler);
      expect(
        await kopf({
          ..._kopf,
          'warnings': [
            {'code': 'not_booked'},
          ],
        }),
        _antwortfehler,
        reason: 'Hinweis ohne Zahl',
      );
      expect(await kopf({..._kopf}..remove('id')), _antwortfehler);
      expect((await kopf({..._kopf}..remove('blind')) as Stocktake).blind, isTrue);
      expect((await kopf({..._kopf, 'blind': 'nein'}) as Stocktake).blind, isTrue);
      expect((await kopf({..._kopf, 'blind': false}) as Stocktake).blind, isFalse);
      // Ein unbekannter Stand bleibt als Text stehen.
      expect((await kopf({..._kopf, 'status': 'archived'}) as Stocktake).status, 'archived');
    });

    test('Zaehlung: Seriennummern sind zugesagt, Menge ganz', () async {
      expect(await zaehlung({..._zaehlung}..remove('serialNumbers')), _antwortfehler);
      expect(await zaehlung({..._zaehlung, 'quantity': 0.5}), _antwortfehler);
      expect(await zaehlung({..._zaehlung}..remove('round')), _antwortfehler);
      expect(await zaehlung({..._zaehlung, 'voided': 'ja'}), _antwortfehler);
      final gut = await zaehlung(_zaehlung) as StocktakeCountPage;
      expect(gut.counts.single.voided, isNull);
    });

    test('closeStocktake: Hinweise aus der Antwort (recount_uncounted), fehlende Liste = keine', () async {
      final (:lager, anfragen: _) = _client([
        _erfolg({
          'stocktake': _kopf,
          'warnings': [
            {'code': 'recount_uncounted', 'items': 2, 'message': 'Zwei Positionen wurden nicht nachgezählt.'},
          ],
        }),
        _erfolg({'stocktake': _kopf}),
        _erfolg({'stocktake': _kopf, 'warnings': 'keine'}),
      ]);
      const anfrage = CloseStocktakeRequest(idempotencyKey: 'k', stocktakeId: 'auto78', uncountedAsZero: true);
      final r = await lager.closeStocktake(anfrage);
      expect(r.warnings.single.code, 'recount_uncounted');
      expect(r.warnings.single.items, 2);
      expect(isInventoryWarningCode(r.warnings.single.code), isTrue);
      expect((await lager.closeStocktake(anfrage)).warnings, isEmpty);
      await expectLater(lager.closeStocktake(anfrage), throwsA(_antwortfehler));
    });
  });

  group('vor dem Senden', () {
    Future<void> abgewiesen(Future<Object?> Function(InventoryClient l) aufruf, String grund) async {
      final (:lager, :anfragen) = _client(const []);
      await expectLater(aufruf(lager), throwsA(_anfragefehler), reason: grund);
      expect(anfragen, isEmpty, reason: grund);
    }

    test('nur, was ohne Netz sicher falsch ist', () async {
      const scope = StocktakeScopeInput(type: 'all');
      await abgewiesen(
        (l) => l.createStocktake(
          const CreateStocktakeRequest(idempotencyKey: '', locationId: 'haupt', scope: scope, type: 'perpetual'),
        ),
        'ohne Schluessel',
      );
      await abgewiesen(
        (l) => l.createStocktake(
          CreateStocktakeRequest(idempotencyKey: 'x' * 121, locationId: 'haupt', scope: scope, type: 'perpetual'),
        ),
        'Schluessel ueber 120 Zeichen',
      );
      await abgewiesen(
        (l) => l.createStocktake(
          const CreateStocktakeRequest(idempotencyKey: 'k', locationId: ' ', scope: scope, type: 'perpetual'),
        ),
        'ohne Standort',
      );
      await abgewiesen(
        (l) => l.recordStocktakeCount(
          const RecordStocktakeCountRequest(idempotencyKey: 'k', stocktakeId: '', articleId: 'kipferl', quantity: 1000),
        ),
        'ohne stocktakeId',
      );
      await abgewiesen(
        (l) => l.recordStocktakeCount(
          const RecordStocktakeCountRequest(idempotencyKey: 'k', stocktakeId: 'auto78', articleId: '', quantity: 1000),
        ),
        'ohne articleId',
      );
      await abgewiesen(
        (l) => l.recordStocktakeCount(
          const RecordStocktakeCountRequest(
            idempotencyKey: 'k',
            stocktakeId: 'auto78',
            articleId: 'kipferl',
            quantity: 9007199254740992,
          ),
        ),
        'Menge ausserhalb des sicheren Bereichs',
      );
      await abgewiesen(
        (l) => l.voidStocktakeCount(
          const VoidStocktakeCountRequest(idempotencyKey: 'k', stocktakeId: 'auto78', countId: 'z1', reason: '  '),
        ),
        'Storno ohne Grund',
      );
      await abgewiesen(
        (l) => l.voidStocktakeCount(
          const VoidStocktakeCountRequest(idempotencyKey: 'k', stocktakeId: 'auto78', countId: '', reason: 'doppelt'),
        ),
        'Storno ohne countId',
      );
      await abgewiesen(
        (l) => l.recountStocktake(
          const RecountStocktakeRequest(idempotencyKey: 'k', stocktakeId: 'auto78', items: [], reason: 'Kiste fehlt'),
        ),
        'Nachzaehlen ohne Positionen',
      );
      await abgewiesen(
        (l) => l.recountStocktake(
          const RecountStocktakeRequest(
            idempotencyKey: 'k',
            stocktakeId: 'auto78',
            items: [StocktakeRecountItem(articleId: '')],
            reason: 'Kiste fehlt',
          ),
        ),
        'Nachzaehlen ohne articleId',
      );
      await abgewiesen(
        (l) => l.recountStocktake(
          const RecountStocktakeRequest(
            idempotencyKey: 'k',
            stocktakeId: 'auto78',
            items: [StocktakeRecountItem(articleId: 'kipferl')],
            reason: '',
          ),
        ),
        'Nachzaehlen ohne Grund',
      );
      await abgewiesen(
        (l) => l.cancelStocktake(const CancelStocktakeRequest(idempotencyKey: 'k', stocktakeId: 'auto78', reason: '')),
        'Abbruch ohne Grund',
      );
      await abgewiesen(
        (l) => l.reviewStocktake(const ReviewStocktakeRequest(idempotencyKey: 'k', stocktakeId: '')),
        'Pruefen ohne stocktakeId',
      );
      await abgewiesen(
        (l) => l.closeStocktake(const CloseStocktakeRequest(idempotencyKey: ' ', stocktakeId: 'auto78')),
        'Abschluss mit leerem Schluessel',
      );
      await abgewiesen((l) => l.listStocktakes(limit: 0), 'limit 0');
      await abgewiesen((l) => l.listStocktakeItems(stocktakeId: 'auto78', limit: 201), 'limit 201');
      await abgewiesen((l) => l.listStocktakeCounts(stocktakeId: ''), 'Zaehlungen ohne stocktakeId');
      await abgewiesen((l) => l.getStocktake(''), 'getStocktake ohne Kennung');
    });

    test('eine negative Menge geht hinaus: der Server meldet invalid_quantity', () async {
      final (:lager, :anfragen) = _client([
        _antwort({
          'status': 'error',
          'message': 'Ungültige Menge.',
          'data': {'code': 'invalid_quantity'},
          'code': 'invalid_quantity',
        }),
      ]);
      await expectLater(
        lager.recordStocktakeCount(
          const RecordStocktakeCountRequest(
            idempotencyKey: 'k',
            stocktakeId: 'auto78',
            articleId: 'kipferl',
            quantity: -1000,
          ),
        ),
        throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'invalid_quantity')),
      );
      expect(_params(anfragen.single)['quantity'], -1000);
    });

    test('Anfragen in Drahtform: ohne null, Liste und Umfang wie gesendet', () async {
      const anlegen = CreateStocktakeRequest(
        idempotencyKey: 'shop-inventur-haupt-1',
        locationId: 'haupt',
        scope: StocktakeScopeInput(type: 'articles', articleIds: ['roggenbrot']),
        type: 'perpetual',
        blind: false,
      );
      expect(anlegen.toJson(), {
        'idempotencyKey': 'shop-inventur-haupt-1',
        'locationId': 'haupt',
        'scope': {
          'type': 'articles',
          'articleIds': ['roggenbrot'],
        },
        'type': 'perpetual',
        'blind': false,
      });
      const zaehlen = RecordStocktakeCountRequest(
        idempotencyKey: 'k',
        stocktakeId: 'auto78',
        articleId: 'kipferl',
        quantity: 2000,
        serialNumbers: ['SN-1', 'SN-2'],
        condition: 'defective',
      );
      expect(zaehlen.toJson(), {
        'idempotencyKey': 'k',
        'stocktakeId': 'auto78',
        'articleId': 'kipferl',
        'condition': 'defective',
        'quantity': 2000,
        'serialNumbers': ['SN-1', 'SN-2'],
      });
      expect(const CloseStocktakeRequest(idempotencyKey: 'k', stocktakeId: 'auto78').toJson(), {
        'idempotencyKey': 'k',
        'stocktakeId': 'auto78',
      });
    });
  });

  group('Listen', () {
    test('iterateStocktakeItems folgt nextCursor, derselbe Cursor zweimal ist ein Antwortfehler', () async {
      final eine = _position;
      final (:lager, :anfragen) = _client([
        _erfolg({
          'items': [eine],
          'nextCursor': 'c1',
        }),
        _erfolg({
          'items': [eine],
          'nextCursor': null,
        }),
      ]);
      final alle = await lager.iterateStocktakeItems(stocktakeId: 'auto78', openOnly: true).toList();
      expect(alle, hasLength(2));
      expect(_params(anfragen[0]), {'stocktakeId': 'auto78', 'openOnly': true});
      expect(_params(anfragen[1]), {'stocktakeId': 'auto78', 'openOnly': true, 'cursor': 'c1'});

      final (lager: kreis, anfragen: _) = _client([
        _erfolg({
          'counts': [_zaehlung],
          'nextCursor': 'c1',
        }),
        _erfolg({
          'counts': [_zaehlung],
          'nextCursor': 'c1',
        }),
      ]);
      await expectLater(kreis.iterateStocktakeCounts(stocktakeId: 'auto78').toList(), throwsA(_antwortfehler));
    });

    test('listStocktakes sendet updatedSince wie toISOString, Filter nur wenn gesetzt', () async {
      final (:lager, :anfragen) = _client([
        _antwort(_fall('list_stocktakes')['response']),
        _antwort(_fall('list_stocktakes')['response']),
      ]);
      await lager.listStocktakes();
      expect(_params(anfragen[0]), isEmpty);
      final seite = await lager.listStocktakes(
        status: 'counting',
        locationId: 'haupt',
        updatedSince: DateTime.utc(2026, 10, 6, 8, 3, 4, 5, 6),
        limit: 10,
      );
      expect(_params(anfragen[1]), {
        'status': 'counting',
        'locationId': 'haupt',
        'updatedSince': '2026-10-06T08:03:04.005Z',
        'limit': 10,
      });
      expect(seite.stocktakes, isNotEmpty);
    });
  });

  test('Kataloge und Grenzen wie im JS-Zwilling', () {
    expect(stocktakeStatuses, ['creating', 'counting', 'review', 'closing', 'closed', 'cancelled']);
    expect([stocktakeItemsMax, stocktakeRecountItemsMax, stocktakeCountsPerItemMax], [5000, 200, 200]);
    expect(inventoryWarningCodes.sublist(inventoryWarningCodes.length - 4), [
      'defect_capped',
      'uncounted_items',
      'not_booked',
      'recount_uncounted',
    ]);
    expect(inventoryErrorCodes.last, 'stocktake_not_closed');
  });
}
