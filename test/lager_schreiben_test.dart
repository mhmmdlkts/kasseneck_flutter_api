import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/inventory.dart';

import 'helpers/lager_anfragen.dart';

/// Lager-API schreiben und reservieren (Backend Stufe 5b, Zwilling von
/// `test/inventory-schreiben.test.ts` im npm-Paket 1.5.0) gegen den
/// Vertrags-Export: die Drahtbeispiele stammen aus `v3/antworten/lager.json`
/// (echte Antworten an einem erfundenen Konto, Baeckerei Kornblum, Standort
/// `haupt`), nichts davon ist hier gebaut.
///
/// Geprueft wird vor allem, was vor dem Senden geschieht: eine schreibende
/// Anfrage ohne gueltigen `idempotencyKey` oder mit einer Zahl, die beim
/// Server anders ankaeme, geht nie hinaus (sonst gaebe es keine sichere
/// Wiederholung bzw. eine falsche Buchung), und eine kaputte Antwort wird ein
/// Antwortfehler, nie ein Ersatzwert.

const _apiKey = 'kr_test_Beispielschluessel0123456789';

Map<String, dynamic> _json(String pfad) => jsonDecode(File(pfad).readAsStringSync()) as Map<String, dynamic>;

final _vokabular = _json('test/fixtures/vertrag/v3/v3-vokabular.json');
final _lager = _json('test/fixtures/vertrag/v3/antworten/lager.json');
final _faelle = (_lager['cases'] as List).cast<Map<String, dynamic>>();

Map<String, dynamic> _fall(String name) => _faelle.firstWhere((c) => c['name'] == name);
Map<String, dynamic> _params(String name) => _kopie(_fall(name)['params'] as Map<String, dynamic>);
Map<String, dynamic> _daten(String name) => _kopie((_fall(name)['response'] as Map)['data'] as Map<String, dynamic>);

/// Tiefe Kopie, damit ein Test die Vertragsdaten nie veraendert.
T _kopie<T>(T wert) => jsonDecode(jsonEncode(wert)) as T;

http.Response _antwort(Object? rumpf) => http.Response.bytes(utf8.encode(jsonEncode(rumpf)), 200,
    headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'});
http.Response _vertrag(String name) => _antwort(_fall(name)['response']);
http.Response _erfolg(Object? data) => _antwort({'status': 'success', 'message': '', 'data': data});

({InventoryClient lager, List<http.Request> anfragen}) _client(List<Object> antworten) {
  final anfragen = <http.Request>[];
  var i = 0;
  final mock = MockClient((request) async {
    anfragen.add(request);
    if (i >= antworten.length) throw StateError('Attrappe: keine Antwort mehr vorbereitet');
    final a = antworten[i++];
    if (a is Exception) throw a;
    return a as http.Response;
  });
  return (lager: InventoryClient(apiKey: _apiKey, httpClient: mock), anfragen: anfragen);
}

Map<String, dynamic> _gesendet(http.Request r) => (jsonDecode(r.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;

final Matcher _antwortfehler = isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'response');
final Matcher _anfragefehler = isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'request');

Future<Object?> _fang(Future<Object?> f) => f.then<Object?>((_) => null, onError: (Object e) => e);

/// Die aeusseren Schluessel eines Schema-Eintrags (ohne `__`).
List<String> _schluessel(Object? schema) => (schema as Map).keys.cast<String>().where((k) => k != '__').toList();

final Map<String, dynamic> _artikel = _daten('create_article')['article'] as Map<String, dynamic>;
final Map<String, dynamic> _reservierung = _daten('create_reservation')['reservation'] as Map<String, dynamic>;

/// Je schreibender Aufruf ein gueltiger Vertragsfall; jeder Endpunkt ausser
/// der Vorschau genau einmal.
const _schreiben = {
  'createArticle': 'create_article',
  'updateArticle': 'update_article',
  'deactivateArticle': 'deactivate_article',
  'receiveGoods': 'receive_goods',
  'transferStock': 'transfer_stock',
  'recordStockLoss': 'record_stock_loss',
  'changeStockCondition': 'change_stock_condition',
  'reverseStockMovement': 'reverse_stock_movement',
  'createReservation': 'create_reservation',
  'extendReservation': 'extend_reservation',
  'releaseReservation': 'release_reservation_partial',
};

Object? _alsJson(Object? ergebnis) => switch (ergebnis) {
      Article a => a.toJson(),
      Reservation r => r.toJson(),
      StockOperation o => o.toJson(),
      GoodsReceiptPreview v => v.toJson(),
      _ => ergebnis,
    };

void main() {
  group('Schreiben', () {
    test('jede gueltige Anfrage des Vertrags geht unveraendert an /v3/<name>, die Antwort liest sich verlustfrei', () async {
      expect(_schreiben, hasLength(11));
      for (final MapEntry(key: name, value: fallName) in _schreiben.entries) {
        expect(_fall(fallName)['endpoint'], name);
        final (:lager, :anfragen) = _client([_vertrag(fallName)]);
        final ergebnis = await schreibAufruf(lager, name, _params(fallName));
        expect(anfragen, hasLength(1), reason: name);
        expect(anfragen.single.url.toString(), 'https://api.kasseneck.at/v3/$name');
        expect(_gesendet(anfragen.single), _params(fallName), reason: '$name: Parameter');
        expect(anfragen.single.headers['Authorization'], 'Bearer $_apiKey');
        final d = _daten(fallName);
        expect(_alsJson(ergebnis), d['article'] ?? d['reservation'] ?? d, reason: name);
      }
    });

    test('ein Netzfehler wird nie von selbst wiederholt: genau eine Anfrage, der Aufrufer entscheidet', () async {
      // Wiederholen darf nur der Aufrufer, mit demselben Schluessel; ein
      // Client, der still nachsendet, waere bei einem neuen Schluessel eine
      // zweite Buchung.
      final (:lager, :anfragen) = _client([http.ClientException('Verbindung abgebrochen')]);
      final e = await _fang(lager.createReservation(reservieren(_params('create_reservation'))));
      expect(anfragen, hasLength(1));
      expect(e, isA<KasseneckHttpError>().having((x) => x.reason, 'reason', KasseneckHttpError.reasonNetwork));
    });
  });

  // ---- idempotencyKey (sicherheitsrelevant: ohne ihn keine sichere Wiederholung) ---------------

  group('idempotencyKey', () {
    test('leer, nur Leerraum oder ueber 120 Zeichen: keine schreibende Anfrage geht hinaus (Rot-Probe je Aufruf)', () async {
      final falsch = ['', '   ', '\t\n', 'x' * (inventoryIdempotencyKeyMax + 1)];
      var geprueft = 0;
      for (final MapEntry(key: name, value: fallName) in _schreiben.entries) {
        for (final schluessel in falsch) {
          final (:lager, :anfragen) = _client([_vertrag(fallName)]);
          final p = {..._params(fallName), 'idempotencyKey': schluessel};
          await expectLater(schreibAufruf(lager, name, p), throwsA(_anfragefehler), reason: '$name mit "$schluessel"');
          expect(anfragen, isEmpty, reason: '$name: mit "$schluessel" gesendet');
          geprueft += 1;
        }
      }
      expect(geprueft, 11 * falsch.length);
    });

    test('120 Zeichen gehen hinaus, unveraendert (nie getrimmt oder gekuerzt)', () async {
      for (final schluessel in ['k' * inventoryIdempotencyKeyMax, ' shop-res-1001 ', 'Bestellung 1001 / Versuch 1']) {
        final (:lager, :anfragen) = _client([_vertrag('create_reservation')]);
        await lager.createReservation(reservieren({..._params('create_reservation'), 'idempotencyKey': schluessel}));
        expect(_gesendet(anfragen.single)['idempotencyKey'], schluessel);
      }
    });

    test('eine Wiederholung sendet dieselbe Anfrage noch einmal und liefert die gespeicherte Antwort', () async {
      expect(_params('create_article_replayed'), _params('create_article'));
      final anfrage = artikelAnlegen(_params('create_article'));
      final (:lager, :anfragen) = _client([_vertrag('create_article'), _vertrag('create_article_replayed')]);
      final a = await lager.createArticle(anfrage);
      final b = await lager.createArticle(anfrage);
      expect(_gesendet(anfragen[1]), _gesendet(anfragen[0]));
      expect(b.toJson(), a.toJson());
      final konflikt = _client([_vertrag('error_create_article_idempotency_conflict')]);
      final e = await _fang(konflikt.lager.createArticle(artikelAnlegen(_params('error_create_article_idempotency_conflict'))));
      expect(isInventoryError(e, 'idempotency_conflict'), isTrue);
      expect((e! as KasseneckApiError).outcome, ErrorOutcome.rejected);
    });

    test('Vorschau: Schluessel freigestellt; wenn da, nur seine Form geprueft', () async {
      final (:lager, :anfragen) = _client([]);
      await expectLater(
          lager.previewGoodsReceipt(vorschau({..._params('receive_goods_dry_run'), 'idempotencyKey': ' '})),
          throwsA(_anfragefehler));
      expect(anfragen, isEmpty);
    });
  });

  // ---- Zahlen in der Anfrage ---------------------------------------------------------

  group('Anfrage', () {
    test('eine Ganzzahl ausserhalb ±(2^53 - 1) geht nie hinaus: der Server rechnet in JavaScript', () async {
      const zuGross = 9007199254740992; // 2^53: kaeme beim Server als dieselbe Zahl wie 2^53 + 1 an
      const kleinste = -9223372036854775808;
      final eingang = _params('receive_goods');
      Map<String, dynamic> pos(Map<String, dynamic> extra) =>
          {...eingang, 'items': [{...(eingang['items'] as List).first as Map<String, dynamic>, ...extra}]};
      final faelle = <String, Future<Object?> Function(InventoryClient)>{
        'quantity 2^53': (l) => l.receiveGoods(wareneingang(pos({'quantity': zuGross}))),
        'totalCents -2^63': (l) => l.receiveGoods(wareneingang(pos({'totalCents': kleinste}))),
        'unitPriceMicros 2^53': (l) => l.receiveGoods(wareneingang(pos({'unitPriceMicros': zuGross}))),
        'landedCostCents 2^53': (l) => l.receiveGoods(wareneingang(pos({'landedCostCents': zuGross}))),
        'landedCosts amountCents': (l) => l.receiveGoods(wareneingang({
              ...eingang,
              'landedCosts': [
                {'type': 'freight', 'amountCents': -zuGross},
              ],
            })),
        'Vorschau quantity': (l) => l.previewGoodsReceipt(vorschau(pos({'quantity': zuGross}))),
        'Umbuchung': (l) => l.transferStock(const TransferStockRequest(
            idempotencyKey: 'k', fromLocationId: 'haupt', toLocationId: 'lieferwagen', items: [StockItem(articleId: 'kipferl', quantity: zuGross)])),
        'Abgang': (l) => l.recordStockLoss(const RecordStockLossRequest(
            idempotencyKey: 'k', reason: 'breakage', items: [StockItem(articleId: 'kipferl', quantity: zuGross)])),
        'Zustand': (l) => l.changeStockCondition(const ChangeStockConditionRequest(
            idempotencyKey: 'k', from: 'sellable', to: 'defective', items: [StockItem(articleId: 'kipferl', quantity: zuGross)])),
        'Reservierung': (l) => l.createReservation(const CreateReservationRequest(
            idempotencyKey: 'k', items: [ReservationItemInput(articleId: 'kipferl', quantity: zuGross)])),
        'Freigabe': (l) => l.releaseReservation(const ReleaseReservationRequest(
            idempotencyKey: 'k', reservationId: 'r1', items: [ReleaseReservationItem(articleId: 'kipferl', quantity: zuGross)])),
        'unitPriceCents': (l) =>
            l.createArticle(const CreateArticleRequest(idempotencyKey: 'k', name: 'Kaisersemmel', unitPriceCents: zuGross)),
        'purchasePriceMicros': (l) =>
            l.createArticle(const CreateArticleRequest(idempotencyKey: 'k', name: 'Kaisersemmel', purchasePriceMicros: zuGross)),
        'minStock': (l) => l.updateArticle(const UpdateArticleRequest(idempotencyKey: 'k', articleId: 'a1', minStock: zuGross)),
        'minStockByLocation': (l) => l.updateArticle(
            const UpdateArticleRequest(idempotencyKey: 'k', articleId: 'a1', minStockByLocation: {'haupt': zuGross})),
      };
      for (final MapEntry(key: grund, value: rufe) in faelle.entries) {
        final (:lager, :anfragen) = _client([]);
        await expectLater(rufe(lager), throwsA(_anfragefehler), reason: grund);
        expect(anfragen, isEmpty, reason: '$grund: gesendet');
      }
      // Die Grenze selbst geht hinaus.
      final (:lager, :anfragen) = _client([_erfolg(_daten('transfer_stock'))]);
      await lager.transferStock(const TransferStockRequest(idempotencyKey: 'k', fromLocationId: 'haupt', toLocationId: 'lieferwagen',
          items: [StockItem(articleId: 'kipferl', quantity: 9007199254740991)]));
      expect(((_gesendet(anfragen.single)['items'] as List).single as Map)['quantity'], 9007199254740991);
    });

    test('Pflichtkennungen, leere Aenderung und leere Freigabeliste gehen nicht hinaus', () async {
      final faelle = <String, Future<Object?> Function(InventoryClient)>{
        'updateArticle ohne Feld': (l) => l.updateArticle(const UpdateArticleRequest(idempotencyKey: 'k', articleId: 'a1')),
        'updateArticle ohne articleId': (l) =>
            l.updateArticle(const UpdateArticleRequest(idempotencyKey: 'k', articleId: '', name: 'x')),
        'deactivateArticle ohne articleId': (l) =>
            l.deactivateArticle(const DeactivateArticleRequest(idempotencyKey: 'k', articleId: ' ')),
        'transferStock ohne Ziel': (l) => l.transferStock(
            const TransferStockRequest(idempotencyKey: 'k', fromLocationId: 'haupt', toLocationId: '', items: [])),
        'transferStock ohne Herkunft': (l) => l.transferStock(
            const TransferStockRequest(idempotencyKey: 'k', fromLocationId: ' ', toLocationId: 'haupt', items: [])),
        'Position ohne articleId': (l) => l.recordStockLoss(const RecordStockLossRequest(
            idempotencyKey: 'k', reason: 'breakage', items: [StockItem(articleId: '', quantity: 1000)])),
        'Wareneingang ohne articleId': (l) => l.receiveGoods(
            const ReceiveGoodsRequest(idempotencyKey: 'k', items: [GoodsReceiptItem(articleId: ' ', quantity: 1000)])),
        'Reservierung ohne articleId': (l) => l.createReservation(
            const CreateReservationRequest(idempotencyKey: 'k', items: [ReservationItemInput(articleId: '', quantity: 1000)])),
        'reverseStockMovement ohne operationId': (l) => l.reverseStockMovement(
            const ReverseStockMovementRequest(idempotencyKey: 'k', operationId: ' ', reason: 'Irrtum')),
        'extendReservation ohne reservationId': (l) => l.extendReservation(
            const ExtendReservationRequest(idempotencyKey: 'k', reservationId: '', expiresInMinutes: 30)),
        'releaseReservation mit leerer Liste': (l) =>
            l.releaseReservation(const ReleaseReservationRequest(idempotencyKey: 'k', reservationId: 'r1', items: [])),
        'releaseReservation ohne reservationId': (l) =>
            l.releaseReservation(const ReleaseReservationRequest(idempotencyKey: 'k', reservationId: '')),
        'getReservation leer': (l) => l.getReservation(''),
      };
      for (final MapEntry(key: grund, value: rufe) in faelle.entries) {
        final (:lager, :anfragen) = _client([]);
        await expectLater(rufe(lager), throwsA(_anfragefehler), reason: grund);
        expect(anfragen, isEmpty, reason: '$grund: gesendet');
      }
    });

    test('Positionen leer: das entscheidet der Server (no_positions), die Anfrage geht hinaus', () async {
      final (:lager, :anfragen) = _client([
        _antwort({'status': 'error', 'message': 'Keine Positionen.', 'code': 'no_positions', 'data': {'code': 'no_positions'}}),
      ]);
      final e = await _fang(lager.recordStockLoss(const RecordStockLossRequest(idempotencyKey: 'k', reason: 'breakage', items: [])));
      expect(_gesendet(anfragen.single)['items'], isEmpty);
      expect(inventoryErrorCode(e), 'no_positions');
    });

    test('clear leert Felder (am Draht null); ein nicht leerbares, unbekanntes oder zugleich gesetztes Feld geht nicht hinaus', () async {
      final (:lager, :anfragen) = _client([_erfolg({'article': _artikel}), _erfolg({'article': _artikel})]);
      await lager.updateArticle(const UpdateArticleRequest(
        idempotencyKey: 'shop-update-1',
        articleId: 'a1',
        minStockByLocation: {'haupt': null, 'lieferwagen': 10000},
        clear: {'unitPriceCents', 'minStock', 'purchasePriceMicros', 'description', 'externalIds'},
      ));
      expect(_gesendet(anfragen[0]), {
        'idempotencyKey': 'shop-update-1',
        'articleId': 'a1',
        'unitPriceCents': null,
        'minStock': null,
        'purchasePriceMicros': null,
        'minStockByLocation': {'haupt': null, 'lieferwagen': 10000},
        'description': null,
        'externalIds': null,
      });
      // clear allein ist eine Aenderung.
      await lager.updateArticle(const UpdateArticleRequest(idempotencyKey: 'k2', articleId: 'a1', clear: {'metadata'}));
      expect(_gesendet(anfragen[1]), {'idempotencyKey': 'k2', 'articleId': 'a1', 'metadata': null});
      for (final (grund, anfrage) in [
        ('name laesst sich nicht leeren', const UpdateArticleRequest(idempotencyKey: 'k', articleId: 'a1', clear: {'name'})),
        ('stockKind auch nicht', const UpdateArticleRequest(idempotencyKey: 'k', articleId: 'a1', clear: {'stockKind'})),
        ('Tippfehler', const UpdateArticleRequest(idempotencyKey: 'k', articleId: 'a1', clear: {'descripton'})),
        (
          'gesetzt und geleert',
          const UpdateArticleRequest(idempotencyKey: 'k', articleId: 'a1', description: 'neu', clear: {'description'})
        ),
      ]) {
        await expectLater(lager.updateArticle(anfrage), throwsA(_anfragefehler), reason: grund);
      }
      expect(anfragen, hasLength(2));
    });

    test('createArticle: was nicht gesetzt ist, geht nicht hinaus (am Draht gleichbedeutend mit null)', () async {
      final (:lager, :anfragen) = _client([_erfolg({'article': _artikel})]);
      await lager.createArticle(const CreateArticleRequest(idempotencyKey: 'shop-artikel-1', name: 'Kaisersemmel'));
      expect(_gesendet(anfragen.single), {'idempotencyKey': 'shop-artikel-1', 'name': 'Kaisersemmel'});
    });

    test('expiresInMinutes: ganze Minuten 5 … 43 200; ausserhalb geht nichts hinaus, die Grenzen schon', () async {
      for (final falsch in [4, 43201, 0, -30]) {
        final (:lager, :anfragen) = _client([]);
        await expectLater(
            lager.extendReservation(ExtendReservationRequest(idempotencyKey: 'k', reservationId: 'r1', expiresInMinutes: falsch)),
            throwsA(_anfragefehler),
            reason: '$falsch');
        await expectLater(
            lager.createReservation(CreateReservationRequest(
                idempotencyKey: 'k', items: const [ReservationItemInput(articleId: 'kipferl', quantity: 1000)], expiresInMinutes: falsch)),
            throwsA(_anfragefehler));
        expect(anfragen, isEmpty);
      }
      final (:lager, :anfragen) = _client([_erfolg({'reservation': _reservierung}), _erfolg({'reservation': _reservierung})]);
      await lager.extendReservation(const ExtendReservationRequest(idempotencyKey: 'k1', reservationId: 'r1', expiresInMinutes: 5));
      await lager.createReservation(const CreateReservationRequest(
          idempotencyKey: 'k2', items: [ReservationItemInput(articleId: 'kipferl', quantity: 1000)], expiresInMinutes: 43200));
      expect([for (final a in anfragen) _gesendet(a)['expiresInMinutes']], [5, 43200]);
    });
  });

  // ---- Wareneingang und Vorschau --------------------------------------------------------

  group('Wareneingang', () {
    test('previewGoodsReceipt: dryRun true an receiveGoods, Schluessel freigestellt; Werte nur mit dem Recht costs', () async {
      final ohne = _params('receive_goods_dry_run');
      final (:lager, :anfragen) = _client([
        _vertrag('receive_goods_dry_run'),
        _vertrag('receive_goods_dry_run_with_costs'),
        _vertrag('receive_goods_dry_run'),
      ]);
      final v1 = await lager.previewGoodsReceipt(vorschau(ohne));
      expect(anfragen[0].url.toString(), 'https://api.kasseneck.at/v3/receiveGoods');
      expect(_gesendet(anfragen[0]), ohne);
      expect(_gesendet(anfragen[0]).containsKey('idempotencyKey'), isFalse);
      expect(v1.toJson(), _daten('receive_goods_dry_run'));
      expect(v1.preview.first.hasValues, isFalse);
      expect(v1.preview.first.toJson().containsKey('baseCents'), isFalse, reason: 'ohne Recht costs fehlen die Werte ganz');
      final v2 = await lager.previewGoodsReceipt(vorschau(ohne));
      expect(v2.toJson(), _daten('receive_goods_dry_run_with_costs'));
      expect(v2.preview.first.unitCostMicros, 1302500);
      expect(v2.preview.first.hasValues, isTrue);
      // Ein mitgesendeter Schluessel geht hinaus, dryRun bleibt true.
      await lager.previewGoodsReceipt(vorschau({...ohne, 'idempotencyKey': 'shop-we-118'}));
      expect(_gesendet(anfragen[2])['idempotencyKey'], 'shop-we-118');
      expect(_gesendet(anfragen[2])['dryRun'], true);
    });

    test('receiveGoods sendet nie dryRun: die Buchung ist keine Vorschau', () async {
      final (:lager, :anfragen) = _client([_vertrag('receive_goods')]);
      final r = await lager.receiveGoods(wareneingang(_params('receive_goods')));
      expect(_gesendet(anfragen.single).containsKey('dryRun'), isFalse);
      expect(r.operationId, 'auto34');
      expect(r.lotIds, hasLength(2));
    });

    test('Vorschau: Bruchzahl in quantity oder einem Wert ist ein Antwortfehler; fehlende preview auch', () async {
      final zeile = (_daten('receive_goods_dry_run_with_costs')['preview'] as List).first as Map<String, dynamic>;
      const anfrage = GoodsReceiptPreviewRequest(items: [GoodsReceiptItem(articleId: 'roggenbrot', quantity: 20000)]);
      for (final kaputt in <Map<String, dynamic>>[
        {'quantity': 1.5},
        {'valueCents': 26.05},
        {'unitCostMicros': '1302500'},
        {'serialNumbers': 'S1'},
        {'articleId': ''},
      ]) {
        final (:lager, anfragen: _) = _client([
          _erfolg({
            'preview': [
              {...zeile, ...kaputt},
            ],
          }),
        ]);
        await expectLater(lager.previewGoodsReceipt(anfrage), throwsA(_antwortfehler), reason: '$kaputt');
      }
      final (:lager, anfragen: _) = _client([_erfolg({})]);
      await expectLater(lager.previewGoodsReceipt(anfrage), throwsA(_antwortfehler));
    });
  });

  // ---- Antwort einer Buchung ------------------------------------------------------------

  group('Buchung', () {
    test('operationId, movementIds, lotIds, warnings; Hinweise aus dem Katalog, keine Fehler', () async {
      final (:lager, anfragen: _) = _client([_vertrag('record_stock_loss')]);
      final r = await lager.recordStockLoss(abgang(_params('record_stock_loss')));
      expect(r.toJson(), _daten('record_stock_loss'));
      expect(r.warnings.single.code, 'below_minimum');
      expect(r.warnings.single.locationId, 'haupt');
      expect(isInventoryWarningCode(r.warnings.single.code), isTrue);
      expect(isInventoryWarningCode('exceeds_stock'), isFalse, reason: 'ein Fehlercode ist kein Hinweis');
      expect(isInventoryWarningCode(null), isFalse);
      for (final w in inventoryWarningCodes) {
        expect(isInventoryWarningCode(w), isTrue, reason: w);
      }
      // Jeder Hinweis im Vertrag stammt aus dem Katalog.
      for (final f in _faelle) {
        final d = (f['response'] as Map)['data'];
        for (final w in (d is Map ? d['warnings'] as List? : null) ?? const []) {
          expect(isInventoryWarningCode((w as Map)['code'] as String?), isTrue, reason: '${f['name']}');
        }
      }
    });

    test('ohne operationId, mit Text statt Kennungsliste oder Hinweis ohne Code ist die Antwort unbrauchbar', () async {
      final gut = _daten('transfer_stock');
      final ohne = Map.of(gut)..remove('operationId');
      for (final kaputt in <Map<String, dynamic>>[
        ohne,
        {...gut, 'operationId': ''},
        {...gut, 'movementIds': 'auto35_0'},
        {
          ...gut,
          'lotIds': [1],
        },
        {...gut, 'warnings': {}},
        {
          ...gut,
          'warnings': [
            {'message': 'x'},
          ],
        },
      ]) {
        final (:lager, anfragen: _) = _client([_erfolg(kaputt)]);
        await expectLater(lager.transferStock(umbuchung(_params('transfer_stock'))), throwsA(_antwortfehler), reason: '$kaputt');
      }
      // Fehlende Listen sind leer, nicht kaputt.
      final (:lager, anfragen: _) = _client([_erfolg({'operationId': 'auto35'})]);
      final r = await lager.transferStock(umbuchung(_params('transfer_stock')));
      expect(r.movementIds, isEmpty);
      expect(r.lotIds, isEmpty);
      expect(r.warnings, isEmpty);
    });

    test('Fehler am Code (exceeds_stock, withdrawal_type_required, already_reversed, invalid_condition …)', () async {
      for (final name in [
        'error_transfer_stock_exceeds_stock',
        'error_record_stock_loss_exceeds_stock',
        'error_record_stock_loss_withdrawal_type_required',
        'error_record_stock_loss_invalid_reason',
        'error_change_stock_condition_invalid_condition',
        'error_reverse_stock_movement_already_reversed',
        'error_reverse_stock_movement_operation_not_found',
        'error_update_article_stock_kind_locked',
        'error_update_article_inactive',
        'error_update_article_not_found',
      ]) {
        final c = _fall(name);
        final (:lager, :anfragen) = _client([_vertrag(name)]);
        final e = await _fang(schreibAufruf(lager, c['endpoint'] as String, _params(name)));
        expect(anfragen, hasLength(1), reason: name);
        expect(e, isA<KasseneckApiError>(), reason: name);
        expect(inventoryErrorCode(e), (c['response'] as Map)['code'], reason: name);
        expect((e! as KasseneckApiError).outcome, ErrorOutcome.rejected, reason: name);
      }
    });
  });

  // ---- Artikel ------------------------------------------------------------------

  group('Artikel', () {
    test('description, stockKind, minStockByLocation kommen an; code_taken nennt Feld und Artikel', () async {
      final (:lager, anfragen: _) = _client([_vertrag('create_article')]);
      final a = await lager.createArticle(artikelAnlegen(_params('create_article')));
      expect(a.description, 'Handgeschlagen, mit Mohn bestreut');
      expect(a.stockKind, 'quantity');
      expect(a.minStockByLocation, {'haupt': 20000});
      expect(a.minStock, isNull, reason: 'Altfeld');
      expect(a.externalIds, {'shop': '1001'});
      final c = _client([_vertrag('error_create_article_code_taken')]);
      final e = await _fang(c.lager.createArticle(artikelAnlegen(_params('error_create_article_code_taken'))));
      expect(isInventoryError(e, 'code_taken'), isTrue);
      expect((e! as KasseneckApiError).details['field'], 'ean');
      expect((e as KasseneckApiError).details['articleId'], 'roggenbrot');
      final x = _client([_vertrag('error_create_article_external_id_taken')]);
      expect(inventoryErrorCode(await _fang(x.lager.createArticle(artikelAnlegen(_params('error_create_article_external_id_taken'))))),
          'external_id_taken');
      final v = _client([_vertrag('error_create_article_validation')]);
      final e2 = await _fang(v.lager.createArticle(artikelAnlegen(_params('error_create_article_validation'))));
      expect([for (final f in inventoryFieldErrors(e2)) f.field], ['ean', 'minStock']);
    });

    test('Einkaufspreis beim Anlegen geht hinaus und kommt mit dem Recht costs zurueck', () async {
      final (:lager, :anfragen) = _client([_vertrag('create_article_with_costs')]);
      final a = await lager.createArticle(artikelAnlegen(_params('create_article_with_costs')));
      expect(_gesendet(anfragen.single)['purchasePriceMicros'], 1150000);
      expect(a.hasPurchasePriceMicros, isTrue);
      expect(a.purchasePriceMicros, 1150000);
    });

    test('ein Server vor Stufe 5b ohne die neuen Felder ergibt description null, stockKind null, minStockByLocation {}', () async {
      final alt = Map.of(_artikel)
        ..remove('description')
        ..remove('stockKind')
        ..remove('minStockByLocation');
      final (:lager, anfragen: _) = _client([_erfolg({'article': alt})]);
      final a = await lager.getArticle('auto29');
      expect(a.description, isNull);
      expect(a.stockKind, isNull);
      expect(a.minStockByLocation, isEmpty);
    });

    test('Bruchzahl, Text oder null im Mindestbestand je Standort ist ein Antwortfehler, nie gerundet', () async {
      for (final kaputt in <Object>[
        {'haupt': 1.5},
        {'haupt': '20000'},
        {'haupt': null},
        [20000],
      ]) {
        final (:lager, anfragen: _) = _client([
          _erfolg({
            'article': {..._artikel, 'minStockByLocation': kaputt},
          }),
        ]);
        await expectLater(lager.getArticle('auto29'), throwsA(_antwortfehler), reason: '$kaputt');
      }
    });
  });

  // ---- Reservierung ---------------------------------------------------------------

  group('Reservierung', () {
    test('Status aus dem Katalog, Positionen in Tausendstel; Lesen, Liste und Iterator', () async {
      final (:lager, :anfragen) = _client([
        _vertrag('get_reservation_redeemed'),
        _vertrag('list_reservations_active'),
        _erfolg({
          'reservations': [_reservierung],
          'nextCursor': 'c1',
        }),
        _erfolg({
          'reservations': [
            {..._reservierung, 'id': 'auto49'},
          ],
          'nextCursor': null,
        }),
      ]);
      final r = await lager.getReservation('auto53');
      expect(_gesendet(anfragen[0]), {'reservationId': 'auto53'});
      expect(r.status, 'redeemed');
      expect(reservationStatuses, contains(r.status));
      expect(r.items.first.toJson(), {'articleId': 'roggenbrot', 'locationId': 'haupt', 'quantity': 1000, 'redeemed': 1000, 'released': 0});
      expect(r.items.first.open, 0);
      final seite = await lager.listReservations(status: 'active');
      expect(_gesendet(anfragen[1]), {'status': 'active'});
      expect(seite.toJson(), _daten('list_reservations_active'));
      expect(seite.reservations.single.items.last.open, 4000, reason: '6000 reserviert, 2000 freigegeben');
      final ids = [for (final x in await lager.iterateReservations(reference: 'Bestellung 1001').toList()) x.id];
      expect(ids, ['auto43', 'auto49']);
      expect(_gesendet(anfragen[3]), {'reference': 'Bestellung 1001', 'cursor': 'c1'});
      await expectLater(lager.listReservations(limit: 201), throwsA(_anfragefehler));
      expect(anfragen, hasLength(4));
    });

    test('iterateReservations: derselbe Cursor zweimal endet mit einem Antwortfehler', () async {
      final (:lager, anfragen: _) = _client([
        _erfolg({
          'reservations': [_reservierung],
          'nextCursor': 'c1',
        }),
        _erfolg({
          'reservations': [_reservierung],
          'nextCursor': 'c1',
        }),
      ]);
      await expectLater(lager.iterateReservations().toList(), throwsA(_antwortfehler));
    });

    test('Bruchzahl, fehlende Menge oder Kennung ist ein Antwortfehler', () async {
      final pos = (_reservierung['items'] as List).first as Map<String, dynamic>;
      final ohneFreigabe = Map.of(pos)..remove('released');
      for (final kaputt in <Map<String, dynamic>>[
        {
          'items': [
            {...pos, 'quantity': 1.5},
          ],
        },
        {
          'items': [ohneFreigabe],
        },
        {
          'items': [
            {...pos, 'locationId': ''},
          ],
        },
        {'items': 'roggenbrot'},
        {'id': ''},
      ]) {
        final (:lager, anfragen: _) = _client([
          _erfolg({
            'reservation': {..._reservierung, ...kaputt},
          }),
        ]);
        await expectLater(lager.getReservation('auto43'), throwsA(_antwortfehler), reason: '$kaputt');
      }
      final (:lager, anfragen: _) = _client([_erfolg({})]);
      await expectLater(lager.getReservation('auto43'), throwsA(_antwortfehler));
    });

    test('insufficient_available nennt die fehlenden Positionen, sonst ist die Liste leer', () async {
      final (:lager, anfragen: _) = _client([
        _vertrag('error_create_reservation_insufficient_available'),
        _vertrag('error_get_reservation_not_found'),
      ]);
      final e = await _fang(lager.createReservation(reservieren(_params('error_create_reservation_insufficient_available'))));
      expect(isInventoryError(e, 'insufficient_available'), isTrue);
      expect([for (final f in inventoryShortfalls(e)) f.toJson()], [
        {'articleId': 'roggenbrot', 'locationId': 'haupt', 'requested': 3000, 'available': 2000},
      ]);
      final anderer = await _fang(lager.getReservation('gibt_es_nicht'));
      expect(isInventoryError(anderer, 'reservation_not_found'), isTrue);
      expect(inventoryShortfalls(anderer), isEmpty);
      expect(inventoryShortfalls(Exception('x')), isEmpty);
      // Ein kaputter Eintrag faellt weg (der Aufruf ist ohnehin gescheitert, nichts reserviert).
      const kaputt = KasseneckApiError('createReservation', 'x', code: 'insufficient_available', details: {
        'details': [
          {'articleId': 'a', 'locationId': 'haupt', 'requested': 1.5, 'available': 0},
          'x',
          {'articleId': 'b', 'locationId': 'haupt', 'requested': 2000, 'available': -1000},
        ],
      });
      expect([for (final f in inventoryShortfalls(kaputt)) f.articleId], ['b']);
      expect(inventoryShortfalls(kaputt).single.available, -1000, reason: 'verfuegbar darf negativ sein');
    });

    test('reservation_not_active am Code; Verlaengern sendet Kennung und Minuten', () async {
      final (:lager, :anfragen) = _client([_vertrag('error_extend_reservation_not_active')]);
      final e = await _fang(lager.extendReservation(verlaengern(_params('error_extend_reservation_not_active'))));
      expect(isInventoryError(e, 'reservation_not_active'), isTrue);
      expect(_gesendet(anfragen.single), _params('error_extend_reservation_not_active'));
    });

    test('Freigabe ohne items gibt alles frei; der Status wird released', () async {
      final (:lager, :anfragen) = _client([_vertrag('release_reservation')]);
      final r = await lager.releaseReservation(freigeben(_params('release_reservation')));
      expect(_gesendet(anfragen.single).containsKey('items'), isFalse);
      expect(r.status, 'released');
      expect(r.items.every((p) => p.open == 0), isTrue);
    });
  });

  // ---- Bewegungen ------------------------------------------------------------------

  group('Bewegungen', () {
    test('reservation mit reservedDelta und stockAfter.reserved; sonst reservedDelta 0 und reserved null', () async {
      final res = _daten('list_stock_movements_reservation');
      final (:lager, anfragen: _) = _client([_erfolg(res), _vertrag('list_stock_movements')]);
      final seite = await lager.listStockMovements(articleId: 'kipferl', type: 'reservation', limit: 3);
      expect([for (final b in seite.movements) b.toJson()], res['movements']);
      expect(seite.movements.first.type, 'reservation');
      expect(seite.movements.first.quantityDelta, 0);
      expect(seite.movements.first.reservedDelta, -3000);
      expect(seite.movements[1].stockAfter!.reserved, 3000);
      final andere = (await lager.listStockMovements()).movements.first;
      expect(andere.reservedDelta, 0);
      expect(andere.stockAfter!.reserved, isNull);
    });

    test('ein Server vor Stufe 5b ohne reservedDelta ergibt 0; Bruchzahl oder null darin ist ein Antwortfehler', () async {
      final b = (_daten('list_stock_movements')['movements'] as List).first as Map<String, dynamic>;
      final alt = Map.of(b)..remove('reservedDelta');
      final (:lager, anfragen: _) = _client([
        _erfolg({
          'movements': [
            {
              ...alt,
              'stockAfter': {'sellable': 4000, 'defective': 0},
            },
          ],
          'nextCursor': null,
        }),
        _erfolg({
          'movements': [
            {...b, 'reservedDelta': 0.5},
          ],
          'nextCursor': null,
        }),
        _erfolg({
          'movements': [
            {...b, 'reservedDelta': null},
          ],
          'nextCursor': null,
        }),
        _erfolg({
          'movements': [
            {
              ...b,
              'stockAfter': {'sellable': 4000, 'defective': 0, 'reserved': 0.5},
            },
          ],
          'nextCursor': null,
        }),
      ]);
      final m = (await lager.listStockMovements()).movements.single;
      expect(m.reservedDelta, 0);
      expect(m.stockAfter!.reserved, isNull);
      await expectLater(lager.listStockMovements(), throwsA(_antwortfehler));
      await expectLater(lager.listStockMovements(), throwsA(_antwortfehler));
      await expectLater(lager.listStockMovements(), throwsA(_antwortfehler));
    });
  });

  // ---- Ereignisse ------------------------------------------------------------------

  group('Ereignisse', () {
    test('reservation.expired|released|redeemed tragen die Reservierung wie getReservation', () {
      final ereignisse =
          (_lager['webhookEvents'] as List).cast<Map<String, dynamic>>().where((e) => (e['event'] as String).startsWith('reservation.'));
      expect(ereignisse.map((e) => e['event']).toSet(), {'reservation.expired', 'reservation.released', 'reservation.redeemed'});
      for (final e in ereignisse) {
        final body = e['body'] as Map<String, dynamic>;
        final ereignis = parseInventoryWebhookEvent(jsonEncode(body));
        expect(ereignis, isA<InventoryReservationEvent>(), reason: e['event'] as String);
        ereignis as InventoryReservationEvent;
        expect(ereignis.type, e['event']);
        expect(ereignis.data.toJson(), body['data']);
        expect(reservationStatuses, contains(ereignis.data.status));
      }
      // Teilfreigabe: das Ereignis kommt, der Status bleibt active.
      expect(
          ereignisse.any((e) => e['event'] == 'reservation.released' && ((e['body'] as Map)['data'] as Map)['status'] == 'active'),
          isTrue,
          reason: 'Teilfreigabe im Vertrag');
      final erstes = ereignisse.first['body'] as Map<String, dynamic>;
      final data = erstes['data'] as Map<String, dynamic>;
      final kaputt = {
        ...erstes,
        'data': {
          ...data,
          'items': [
            {...(data['items'] as List).first as Map<String, dynamic>, 'quantity': 2.5},
          ],
        },
      };
      expect(() => parseInventoryWebhookEvent(jsonEncode(kaputt)), throwsA(_antwortfehler));
    });

    test('die 5b-Antworten im Vertrag tragen jedes Feld ihres Schemas, und das Modell liest es', () async {
      final schemata = _vokabular['schemas'] as Map;
      final (:lager, anfragen: _) = _client([
        _vertrag('create_reservation'),
        _vertrag('transfer_stock'),
        _vertrag('receive_goods_dry_run_with_costs'),
        _vertrag('update_article'),
      ]);
      final r = (await lager.createReservation(reservieren(_params('create_reservation')))).toJson();
      final s = (schemata['createReservation'] as Map)['data']['reservation'] as Map;
      for (final k in _schluessel(s)) {
        expect(r.containsKey(k), isTrue, reason: 'Reservation.$k');
      }
      for (final k in _schluessel((s['items'] as List).first)) {
        expect(((r['items'] as List).first as Map).containsKey(k), isTrue, reason: 'ReservationItem.$k');
      }
      final v = (await lager.transferStock(umbuchung(_params('transfer_stock')))).toJson();
      for (final k in _schluessel((schemata['transferStock'] as Map)['data'])) {
        expect(v.containsKey(k), isTrue, reason: 'StockOperation.$k');
      }
      final p = (await lager.previewGoodsReceipt(vorschau(_params('receive_goods_dry_run_with_costs')))).toJson();
      for (final k in _schluessel(((schemata['receiveGoods'] as Map)['data']['preview'] as List).first)) {
        expect(((p['preview'] as List).first as Map).containsKey(k), isTrue, reason: 'GoodsReceiptPreviewLine.$k');
      }
      final a = (await lager.updateArticle(artikelAendern(_params('update_article')))).toJson();
      for (final k in _schluessel((schemata['updateArticle'] as Map)['data']['article'])) {
        if (k != 'purchasePriceMicros') expect(a.containsKey(k), isTrue, reason: 'Article.$k');
      }
    });
  });
}
