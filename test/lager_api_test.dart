import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/inventory.dart';
import 'package:kasseneck_api/src/aufrufe.dart';
import 'package:kasseneck_api/src/receipt/codes.dart' show anmeldungUndRandCodes;

import 'helpers/lager_anfragen.dart';

/// Die Lager-API (`InventoryClient`, Zwilling von `./inventory` im npm-Paket
/// 1.6.0) gegen den Vertrags-Export des Backends: `v3/antworten/lager.json`
/// (echte Antworten der 32 Endpunkte samt zugestellter Webhook-Ereignisse,
/// erfundenes Konto Baeckerei Kornblum), `v3/v3-vokabular.json` (Kataloge,
/// Schemata) und `surface.json` (Abschnitt `inventory`). Die Faelle folgen
/// `test/inventory.test.ts` im JS-Paket; das Schreiben im Einzelnen steht in
/// `lager_schreiben_test.dart`, die Variantengruppen in
/// `lager_varianten_test.dart`.

const _apiKey = 'kr_test_Beispielschluessel0123456789';

Map<String, dynamic> _json(String pfad) => jsonDecode(File(pfad).readAsStringSync()) as Map<String, dynamic>;

final _vokabular = _json('test/fixtures/vertrag/v3/v3-vokabular.json');
final _lager = _json('test/fixtures/vertrag/v3/antworten/lager.json');
final _faelle = (_lager['cases'] as List).cast<Map<String, dynamic>>();

Map<String, dynamic> _fall(String name) => _faelle.firstWhere((c) => c['name'] == name);
Map<String, dynamic> _daten(String name) => (_fall(name)['response'] as Map)['data'] as Map<String, dynamic>;

/// Tiefe Kopie, damit ein Test die Vertragsdaten nie veraendert.
T _kopie<T>(T wert) => jsonDecode(jsonEncode(wert)) as T;

final Map<String, dynamic> _artikel = _kopie(_daten('get_article')['article'] as Map<String, dynamic>);
final Map<String, dynamic> _bestand = _kopie((_daten('get_stock')['stock'] as List).first as Map<String, dynamic>);
final List<Map<String, dynamic>> _standorte = _kopie(_daten('list_locations')['locations'] as List).cast<Map<String, dynamic>>();
final Map<String, dynamic> _bewegung = _kopie((_daten('list_stock_movements')['movements'] as List).first as Map<String, dynamic>);
final Map<String, dynamic> _webhook = _kopie((_daten('list_webhooks')['webhooks'] as List).first as Map<String, dynamic>);
final Map<String, dynamic> _zustellung =
    _kopie((_daten('list_webhook_deliveries')['deliveries'] as List).first as Map<String, dynamic>);

http.Response _antwort(Object? rumpf, {int status = 200}) => http.Response.bytes(utf8.encode(jsonEncode(rumpf)), status,
    headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'});
http.Response _erfolg(Object? data) => _antwort({'status': 'success', 'message': '', 'data': data});
http.Response _fehler(String message, Map<String, dynamic> data) =>
    _antwort({'status': 'error', 'message': message, 'data': data, 'code': data['code']});

({InventoryClient lager, List<http.Request> anfragen}) _client(List<http.Response> antworten, {String? baseUrl}) {
  final anfragen = <http.Request>[];
  var i = 0;
  final mock = MockClient((request) async {
    anfragen.add(request);
    if (i >= antworten.length) throw StateError('Attrappe: keine Antwort mehr vorbereitet');
    return antworten[i++];
  });
  return (lager: InventoryClient(apiKey: _apiKey, httpClient: mock, baseUrl: baseUrl), anfragen: anfragen);
}

Map<String, dynamic> _params(http.Request r) => (jsonDecode(r.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;

final Matcher _antwortfehler = isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'response');
final Matcher _anfragefehler = isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'request');

/// Die aeusseren Schluessel eines Schema-Eintrags (ohne `__`).
List<String> _schluessel(Object? schema) => (schema as Map).keys.cast<String>().where((k) => k != '__').toList();

Future<List<T>> _alle<T>(Stream<T> s) => s.toList();

/// Testvektor des Backends (functions/test/unit/webhook-core.test.js), wie im JS-Paket.
const _vektorSecret = 'whsec_test';
const _vektorT = 1700000000;
const _vektorBody = '{"id":"evt_1","type":"webhook.test"}';
const _vektorHex = '684fbc8999ff13aa332102c10e23ad56af8cb3b34c5d3bcba8bf53317e5f6c33';
DateTime _um(int sek) => DateTime.fromMillisecondsSinceEpoch(sek * 1000, isUtc: true);

String _huelle(String type, Object? data, {bool test = false}) => jsonEncode({
      'id': 'evt_Beispiel',
      'type': type,
      'createdAt': 1791274500000,
      'accountId': 'konto_kornblum',
      if (test) 'test': true,
      'data': data,
    });

const Map<String, dynamic> _stockChanged = {
  'articleId': 'beispiel_roggenbrot',
  'locationId': 'haupt',
  'onHand': 12000,
  'reserved': 0,
  'available': 12000,
  'defective': 0,
  'sequence': 42,
  'updatedAt': '2026-10-06T08:15:00.000Z',
  'cause': 'sale',
  'movementId': 'beispiel_bewegung_1',
};
const Map<String, dynamic> _unterMindest = {'articleId': 'beispiel_roggenbrot', 'locationId': 'haupt', 'available': 4000, 'minStock': 5000};

void main() {
  // ---- Vertrag ----------------------------------------------------------------

  group('Vertrag', () {
    final surface = _json('test/fixtures/vertrag/surface.json');

    test('surface.json inventory: jede Liste gibt es hier, Wert fuer Wert und in der Reihenfolge, und keine mehr', () {
      final listen = surface['inventory'] as Map<String, dynamic>;
      final hier = <String, List<String>>{
        'inventoryEndpoints': inventoryEndpoints,
        'inventoryErrorCodes': inventoryErrorCodes,
        'inventoryRequestErrorCodes': inventoryRequestErrorCodes,
        'inventoryWarningCodes': inventoryWarningCodes,
        'inventoryWebhookEnvelopeFields': inventoryWebhookEnvelopeFields,
        'inventoryWebhookEvents': inventoryWebhookEvents,
        'landedCostAllocations': landedCostAllocations,
        'landedCostTypes': landedCostTypes,
        'locationTypes': locationTypes,
        'reservationStatuses': reservationStatuses,
        'stockChangeCauses': stockChangeCauses,
        'stockConditions': stockConditions,
        'stockKinds': stockKinds,
        'stockLossReasons': stockLossReasons,
        'stockMovementSources': stockMovementSources,
        'stockMovementTypes': stockMovementTypes,
        'webhookDeliveryStatuses': webhookDeliveryStatuses,
        'withdrawalTypes': withdrawalTypes,
      };
      expect(hier.keys.toSet(), listen.keys.toSet());
      for (final e in hier.entries) {
        expect(e.value, listen[e.key], reason: 'inventory.${e.key}');
      }
    });

    test('inventoryEndpoints: die 32 Endpunkte (5a, 5b und 5c) in endpoints.public, in Vertragsreihenfolge, alle in Aufrufe.alle', () {
      final namen = (_vokabular['names'] as Map).cast<String, String>();
      final oeffentlich = [for (final n in (_vokabular['endpoints'] as Map)['public'] as List) namen[n] ?? n as String];
      final start = oeffentlich.indexOf('getArticle');
      expect(start, greaterThan(0));
      expect(inventoryEndpoints, oeffentlich.sublist(start, start + 32));
      expect(inventoryEndpoints, hasLength(32));
      expect(inventoryEndpoints[13], 'listWebhookDeliveries');
      expect(inventoryEndpoints[26], 'listReservations');
      expect(inventoryEndpoints.last, 'addVariant');
      for (final name in inventoryEndpoints) {
        expect(Aufrufe.alle, contains(name));
        expect((_vokabular['schemas'] as Map)[name], isNotNull, reason: '$name: kein Schema im Vertrag');
      }
    });

    test('die Wertlisten sind die Kataloge des Vertrags (aussen, in Katalogreihenfolge)', () {
      List<String> werte(String k) => ((_vokabular['catalogs'] as Map)[k] as Map).values.cast<String>().toList();
      expect(locationTypes, werte('STANDORT_TYP'));
      expect(stockMovementTypes, werte('BEWEGUNG_ART'));
      expect(stockMovementSources, werte('BEWEGUNG_QUELLE'));
      expect(stockConditions, werte('LAGER_ZUSTAND'));
      expect(stockChangeCauses, werte('LAGER_URSACHE'));
      expect(webhookDeliveryStatuses, werte('ZUSTELLUNG'));
      expect(stockLossReasons, werte('LAGER_ABGANG_GRUND'));
      expect(withdrawalTypes, werte('LAGER_ENTNAHME_ART'));
      expect(landedCostTypes, werte('LAGER_NEBENKOSTEN_ART'));
      expect(landedCostAllocations, werte('LAGER_VERTEILUNG'));
      expect(reservationStatuses, werte('RESERVIERUNG_STATUS'));
      expect(inventoryWarningCodes, (_vokabular['warningCodes'] as Map)['inventory']);
      expect(stockMovementTypes, containsAll(['goods_receipt', 'takeover']));
      expect(stockMovementTypes, isNot(contains('receipt')));
      expect(stockMovementTypes.last, 'reservation', reason: 'neue Bewegungsart hinten (gespeicherte Reihenfolgen bleiben gueltig)');
      // Die Schemata verweisen wirklich auf diese Kataloge.
      final schemata = _vokabular['schemas'] as Map;
      expect((schemata['recordStockLoss'] as Map)['paramWerte'], {
        'reason': {r'$catalog': 'LAGER_ABGANG_GRUND'},
        'withdrawalType': {r'$catalog': 'LAGER_ENTNAHME_ART'},
        'condition': {r'$catalog': 'LAGER_ZUSTAND'},
      });
      expect((schemata['receiveGoods'] as Map)['paramWerte'], {
        'allocation': {r'$catalog': 'LAGER_VERTEILUNG'},
        'landedCosts[].type': {r'$catalog': 'LAGER_NEBENKOSTEN_ART'},
      });
      expect((schemata['listReservations'] as Map)['paramWerte'], {
        'status': {r'$catalog': 'RESERVIERUNG_STATUS'},
      });
      // stockKind ist kein Katalog des Vokabulars: jeder Artikel im Vertrag traegt einen Wert aus stockKinds.
      final arten = <Object?>{
        for (final c in _faelle)
          if ((c['response'] as Map)['data'] case final Map d)
            for (final a in [d['article'], ...(d['articles'] as List? ?? const [])])
              if (a is Map) a['stockKind'],
      };
      expect(arten, contains('quantity'));
      expect(stockKinds, containsAll(arten));
    });

    test('inventoryWebhookEvents sind genau die Konto-Ereignisse des Vertrags, in der Reihenfolge von listWebhooks', () {
      final imVertrag =
          (_vokabular['events'] as Map).keys.cast<String>().where((e) => RegExp(r'^(stock|article|reservation|variant_group)\.').hasMatch(e));
      expect(inventoryWebhookEvents.toSet(), imVertrag.toSet());
      expect(inventoryWebhookEvents, _daten('list_webhooks')['events']);
      // Angehaengt wird hinten: 5b die Reservierung, 5c die Variantengruppen.
      expect(inventoryWebhookEvents.sublist(5, 8), ['reservation.expired', 'reservation.released', 'reservation.redeemed']);
      expect(inventoryWebhookEvents.sublist(inventoryWebhookEvents.length - 2),
          ['variant_group.created', 'variant_group.updated']);
      expect(inventoryWebhookEnvelopeFields, ['id', 'type', 'createdAt', 'accountId', 'test', 'data']);
    });

    test('inventoryErrorCodes: der Katalog errorCodes.inventory ohne Anmeldungscode; 5a vorn, 5b und 5c hinten', () {
      final alle = ((_vokabular['errorCodes'] as Map)['all'] as List).cast<String>().toSet();
      expect(inventoryErrorCodes.where((c) => !alle.contains(c)), isEmpty);
      final katalog = ((_vokabular['errorCodes'] as Map)['inventory'] as List).cast<String>();
      final vertrag = katalog.where((c) => c != 'register_user_not_allowed').toList();
      expect(inventoryErrorCodes.toSet(), vertrag.toSet());
      // Angehaengt wird hinten: die 12 Codes aus 10.3 stehen unveraendert vorn.
      expect(inventoryErrorCodes.sublist(0, 12), [
        'validation', 'invalid_cursor', 'article_not_found', 'webhook_not_found', 'webhook_limit', 'invalid_webhook_url',
        'event_not_subscribed', 'webhook_inactive', 'inventory_api_not_enabled', 'module_inactive', 'rate_limited',
        'server_error',
      ]);
      expect(inventoryErrorCodes.sublist(12), vertrag.sublist(vertrag.indexOf('server_error') + 1));
      // 5c haengt hinter 5b an (die Reihenfolge der Codes aus 10.4 bleibt).
      expect(inventoryErrorCodes.sublist(inventoryErrorCodes.length - 6), [
        'reservation_not_active', 'variant_group_not_found', 'variant_already_exists', 'invalid_variant_attributes',
        'variant_group_inactive', 'variant_limit',
      ]);
      // Hinweise sind nie Fehler.
      for (final w in inventoryWarningCodes) {
        expect(inventoryErrorCodes, isNot(contains(w)), reason: w);
      }
      // Jeder Fehlercode, den ein Vertragsfall zeigt, ist ein Lager-Code.
      for (final c in _faelle) {
        final r = c['response'] as Map;
        if (r['status'] == 'error') expect(isInventoryErrorCode(r['code'] as String?), isTrue, reason: '${c['name']}');
      }
    });

    test('inventoryRequestErrorCodes = Anmeldung und Rand ohne den Katalog, dahinter route_missing', () {
      expect(inventoryRequestErrorCodes, [
        ...anmeldungUndRandCodes.where((c) => !inventoryErrorCodes.contains(c)),
        'route_missing',
      ]);
      for (final c in ['api_not_approved', 'unauthorized', 'register_user_not_allowed', 'dialect_mismatch', 'route_missing', 'article_not_found']) {
        expect(isInventoryErrorCode(c), isTrue, reason: c);
      }
      expect(isInventoryErrorCode('brand_new_code_2027'), isFalse);
      expect(isInventoryErrorCode(null), isFalse);
    });

    test('Konstanten wie im JS-Paket', () {
      expect(webhookSignatureHeader, 'X-Kasseneck-Signature');
      expect(webhookEventHeader, 'X-Kasseneck-Event');
      expect(webhookDeliveryHeader, 'X-Kasseneck-Delivery');
      expect(webhookToleranceSec, 300);
      expect(inventoryWebhookLimit, 5);
      expect(inventoryListLimitMax, 200);
      expect(inventoryIdempotencyKeyMax, 120);
      expect(reservationMinutesMin, 5);
      expect(reservationMinutesMax, 43200);
      expect(variantAttributesMax, 3);
      expect(variantValuesMax, 30);
      expect(variantMatrixMax, 100);
      expect(variantGroupActiveMax, 250);
      expect(kInventoryBaseUrl, 'https://api.kasseneck.at/v3');
    });
  });

  // ---- Vertragsfaelle ----------------------------------------------------------

  group('antworten/lager.json', () {
    Future<Object?> rufe(InventoryClient l, String endpunkt, Map<String, dynamic> p) {
      DateTime? zeit(String k) => p[k] == null ? null : DateTime.parse(p[k] as String);
      List<String>? liste(String k) => (p[k] as List?)?.cast<String>();
      switch (endpunkt) {
        case 'getArticle':
          return l.getArticle(p['articleId'] as String);
        case 'listArticles':
          return l.listArticles(
            updatedSince: zeit('updatedSince'),
            groupId: p['groupId'] as String?,
            variantGroupId: p['variantGroupId'] as String?,
            active: p['active'] as bool?,
            stockTracked: p['stockTracked'] as bool?,
            limit: p['limit'] as int?,
            cursor: p['cursor'] as String?,
          );
        case 'lookupArticleByCode':
          return l.lookupArticleByCode(
              code: p['code'] as String?, externalSystem: p['externalSystem'] as String?, externalId: p['externalId'] as String?);
        case 'listLocations':
          return l.listLocations();
        case 'getStock':
          return l.getStock(p['articleId'] as String);
        case 'listStock':
          return l.listStock(
            locationId: p['locationId'] as String?,
            articleId: p['articleId'] as String?,
            belowMinimum: p['belowMinimum'] as bool?,
            changedSince: zeit('changedSince'),
            limit: p['limit'] as int?,
            cursor: p['cursor'] as String?,
          );
        case 'listStockMovements':
          return l.listStockMovements(
            articleId: p['articleId'] as String?,
            locationId: p['locationId'] as String?,
            from: zeit('from'),
            to: zeit('to'),
            type: p['type'] as String?,
            source: p['source'] as String?,
            limit: p['limit'] as int?,
            cursor: p['cursor'] as String?,
          );
        case 'createWebhook':
          return l.createWebhook(url: p['url'] as String, events: liste('events')!, description: p['description'] as String?);
        case 'updateWebhook':
          return l.updateWebhook(p['webhookId'] as String,
              url: p['url'] as String?, events: liste('events'), active: p['active'] as bool?, description: p['description'] as String?);
        case 'deleteWebhook':
          return l.deleteWebhook(p['webhookId'] as String);
        case 'listWebhooks':
          return l.listWebhooks();
        case 'sendWebhookTest':
          return l.sendWebhookTest(p['webhookId'] as String, p['event'] as String);
        case 'rotateWebhookSecret':
          return l.rotateWebhookSecret(p['webhookId'] as String);
        case 'listWebhookDeliveries':
          return l.listWebhookDeliveries(webhookId: p['webhookId'] as String?, limit: p['limit'] as int?);
        default:
          // Die schreibenden Aufrufe baut die Drahtform-Bruecke aus
          // helpers/lager_anfragen.dart (dieselbe, die lager_schreiben_test.dart nutzt).
          return schreibAufruf(l, endpunkt, p);
      }
    }

    /// Die Faelle, die der Client schon vor dem Senden abweist (sicher falsch
    /// ohne Netz): genau diese, keiner mehr – wie `VOR_DEM_SENDEN` im JS-Paket.
    const vorDemSenden = {
      'error_list_articles_validation': 'limit 500 liegt ueber 200',
      'error_create_article_idempotency_key_required': 'idempotencyKey fehlt',
      'error_create_reservation_validation': 'expiresInMinutes 2 liegt unter 5',
      'error_create_variant_group_validation': 'createMatrix true zusammen mit variants',
    };

    /// Faelle, die sich in Dart gar nicht bauen lassen: der Typ `int` schliesst
    /// die Bruchzahl schon beim Schreiben der Anfrage aus. Im JS-Paket weist
    /// der Client sie vor dem Senden ab.
    const nichtBaubar = {
      'error_receive_goods_validation': 'quantity 1.5 ist keine Ganzzahl (Tausendstel)',
    };

    test('jeder Endpunkt kommt vor, jeder Fall laeuft durch den Client', () async {
      expect(_faelle.map((c) => c['endpoint']).toSet(), inventoryEndpoints.toSet());
      var gesendet = 0;
      final abgewiesen = <String>[];
      for (final c in _faelle) {
        if (nichtBaubar.containsKey(c['name'])) {
          // Belegt, dass der Fall wirklich eine Bruchzahl traegt (und nicht still mitlaeuft).
          final mengen = [for (final p in (c['params'] as Map)['items'] as List) (p as Map)['quantity']];
          expect(mengen.any((m) => m is double && m != m.truncateToDouble()), isTrue, reason: '${c['name']}');
          continue;
        }
        final kopf = (c['headers'] as Map).cast<String, String>();
        final antwort = http.Response.bytes(utf8.encode(jsonEncode(c['response'])), c['httpStatus'] as int,
            headers: {'content-type': 'application/json', for (final e in kopf.entries) e.key.toLowerCase(): e.value});
        final (:lager, :anfragen) = _client([antwort]);
        final antwortRumpf = c['response'] as Map<String, dynamic>;
        Object? ergebnis;
        Object? fehler;
        try {
          ergebnis = await rufe(lager, c['endpoint'] as String, c['params'] as Map<String, dynamic>);
        } catch (e) {
          fehler = e;
        }
        if (anfragen.isEmpty) {
          // Der Client hat die Anfrage selbst abgewiesen: nur bei Fehlerfaellen erlaubt.
          expect(antwortRumpf['status'], 'error', reason: '${c['name']}: Erfolgsfall nicht gesendet');
          expect(fehler, _anfragefehler, reason: c['name'] as String);
          abgewiesen.add(c['name'] as String);
          continue;
        }
        gesendet += 1;
        expect(anfragen.single.url.toString(), 'https://api.kasseneck.at${c['path']}', reason: c['name'] as String);
        expect(_params(anfragen.single), c['params'], reason: '${c['name']}: Parameter');
        expect(anfragen.single.headers['Authorization'], 'Bearer $_apiKey');
        expect(anfragen.single.headers.containsKey('cashregister-token'), isFalse);
        if (antwortRumpf['status'] == 'error') {
          expect(inventoryErrorCode(fehler), antwortRumpf['code'], reason: c['name'] as String);
          if (antwortRumpf['code'] == 'rate_limited') {
            expect(inventoryRetryAfterSec(fehler), (antwortRumpf['data'] as Map)['retryAfterSec']);
          }
        } else {
          expect(fehler, isNull, reason: '${c['name']}: $fehler');
          expect(ergebnis, isNotNull, reason: c['name'] as String);
        }
      }
      expect(abgewiesen.toSet(), vorDemSenden.keys.toSet(), reason: 'vor dem Senden abgewiesen');
      expect(gesendet, _faelle.length - abgewiesen.length - nichtBaubar.length);
    });

    test('Erfolgsantworten lesen sich verlustfrei: toJson ist der Draht', () async {
      final (:lager, anfragen: _) = _client([
        _antwort(_fall('get_article_with_costs')['response']),
        _antwort(_fall('list_locations')['response']),
        _antwort(_fall('list_stock_with_costs')['response']),
        _antwort(_fall('list_stock_movements_with_costs')['response']),
        _antwort(_fall('list_webhooks')['response']),
        _antwort(_fall('list_webhook_deliveries')['response']),
        _antwort(_fall('send_webhook_test')['response']),
        _antwort(_fall('create_webhook')['response']),
      ]);
      expect((await lager.getArticle('roggenbrot')).toJson(), _daten('get_article_with_costs')['article']);
      final orte = await lager.listLocations();
      final soll = [for (final s in _daten('list_locations')['locations'] as List) {...(s as Map<String, dynamic>), 'virtual': false}];
      expect([for (final o in orte) o.toJson()], soll);
      final seite = await lager.listStock(articleId: 'roggenbrot');
      expect([for (final z in seite.stock) z.toJson()], _daten('list_stock_with_costs')['stock']);
      expect(seite.values!.single.stockValueCents, 480);
      expect(seite.values!.single.averageCostMicros, 1200000);
      expect(seite.nextCursor, isNull);
      final bewegungen = await lager.listStockMovements(articleId: 'roggenbrot', limit: 1);
      expect([for (final b in bewegungen.movements) b.toJson()], _daten('list_stock_movements_with_costs')['movements']);
      expect(bewegungen.nextCursor, _daten('list_stock_movements_with_costs')['nextCursor']);
      final liste = await lager.listWebhooks();
      expect([for (final w in liste.webhooks) w.toJson()], _daten('list_webhooks')['webhooks']);
      expect(liste.events, inventoryWebhookEvents);
      expect(liste.webhooks.single.consecutiveFailures, 0);
      final zustellungen = await lager.listWebhookDeliveries();
      expect([for (final z in zustellungen) z.toJson()], _daten('list_webhook_deliveries')['deliveries']);
      final probe = await lager.sendWebhookTest('3pJJwmZZjQTW', 'stock.below_minimum');
      expect(probe.toJson(), _daten('send_webhook_test'));
      final neu = await lager.createWebhook(url: 'https://shop.baeckerei-kornblum.at/kasseneck-webhook', events: ['stock.changed']);
      expect(neu.secret, _daten('create_webhook')['secret']);
      expect(neu.webhook.toJson(), _daten('create_webhook')['webhook']);
    });

    test('jedes Feld der Schemata kommt im gelesenen Modell an', () async {
      final schemata = _vokabular['schemas'] as Map;
      final (:lager, anfragen: _) = _client([
        _erfolg({'article': {..._artikel, 'purchasePriceMicros': 1234500}}),
        _erfolg({'stock': [_bestand]}),
        _erfolg({'locations': _standorte}),
        _erfolg({
          'movements': [
            {
              ..._bewegung,
              'valueDeltaCents': -90,
              'consumedValueCents': 90,
              'lots': [{...((_bewegung['lots'] as List).first as Map), 'valueCents': 90}],
            }
          ],
          'nextCursor': null,
        }),
        _erfolg({'webhooks': [_webhook], 'events': inventoryWebhookEvents}),
        _erfolg({'deliveries': [_zustellung]}),
      ]);
      final artikel = (await lager.getArticle('roggenbrot')).toJson();
      for (final k in _schluessel((schemata['getArticle'] as Map)['data']['article'])) {
        expect(artikel.containsKey(k), isTrue, reason: 'Article.$k');
      }
      for (final k in ((_vokabular['articleFields'] as Map)['outer'] as List).cast<String>()) {
        if (_artikel.containsKey(k)) expect(artikel.containsKey(k), isTrue, reason: 'Article.$k');
      }
      final bestand = (await lager.getStock('roggenbrot')).stock.first.toJson();
      for (final k in _schluessel(((schemata['getStock'] as Map)['data']['stock'] as List).first)) {
        expect(bestand.containsKey(k), isTrue, reason: 'StockLevel.$k');
      }
      final orte = await lager.listLocations();
      final s = ((schemata['listLocations'] as Map)['data']['locations'] as List).first as Map;
      final mitAdresse = orte.firstWhere((o) => o.address != null).toJson();
      for (final k in _schluessel(s)) {
        expect(mitAdresse.containsKey(k), isTrue, reason: 'Location.$k');
      }
      for (final k in _schluessel(s['address'])) {
        expect((mitAdresse['address'] as Map).containsKey(k), isTrue, reason: 'Location.address.$k');
      }
      final b = (await lager.listStockMovements()).movements.first.toJson();
      final m = ((schemata['listStockMovements'] as Map)['data']['movements'] as List).first as Map;
      for (final k in _schluessel(m)) {
        expect(b.containsKey(k), isTrue, reason: 'StockMovement.$k');
      }
      for (final k in _schluessel(m['stockAfter'])) {
        expect((b['stockAfter'] as Map).containsKey(k), isTrue, reason: 'StockMovement.stockAfter.$k');
      }
      for (final k in _schluessel(m['source'])) {
        expect((b['source'] as Map).containsKey(k), isTrue, reason: 'StockMovement.source.$k');
      }
      for (final k in _schluessel((m['lots'] as List).first)) {
        expect(((b['lots'] as List).first as Map).containsKey(k), isTrue, reason: 'StockMovement.lots.$k');
      }
      final w = (await lager.listWebhooks()).webhooks.first.toJson();
      for (final k in _schluessel(((schemata['listWebhooks'] as Map)['data']['webhooks'] as List).first)) {
        expect(w.containsKey(k), isTrue, reason: 'InventoryWebhook.$k');
      }
      final z = (await lager.listWebhookDeliveries()).first.toJson();
      for (final k in _schluessel(((schemata['listWebhookDeliveries'] as Map)['data']['deliveries'] as List).first)) {
        expect(z.containsKey(k), isTrue, reason: 'InventoryWebhookDelivery.$k');
      }
    });

    test('jedes zugestellte Ereignis liest sich typisiert, data verlustfrei', () {
      final ereignisse = (_lager['webhookEvents'] as List).cast<Map<String, dynamic>>();
      expect(ereignisse.map((e) => e['event']).toSet(), inventoryWebhookEvents.toSet());
      for (final e in ereignisse.where((e) => RegExp(r'^(reservation|variant_group)\.').hasMatch(e['event'] as String))) {
        final body = e['body'] as Map;
        for (final k in _schluessel(((_vokabular['events'] as Map)[e['event']] as Map)['data'])) {
          expect((body['data'] as Map).containsKey(k), isTrue, reason: '${e['event']}.$k');
        }
      }
      for (final e in ereignisse) {
        final body = e['body'] as Map<String, dynamic>;
        final ereignis = parseInventoryWebhookEvent(jsonEncode(body));
        expect(ereignis, isNotNull, reason: e['event'] as String);
        expect(ereignis!.type, e['event']);
        expect(ereignis.id, body['id']);
        expect(ereignis.accountId, body['accountId']);
        expect(ereignis.createdAt, body['createdAt']);
        expect(ereignis.test, isFalse);
        final data = switch (ereignis) {
          InventoryStockChangedEvent(:final data) => data.toJson(),
          InventoryStockBelowMinimumEvent(:final data) => data.toJson(),
          InventoryArticleEvent(:final data) => data.toJson(),
          InventoryReservationEvent(:final data) => data.toJson(),
          InventoryVariantGroupEvent(:final data) => data.toJson(),
        };
        expect(data, body['data'], reason: e['event'] as String);
        if (ereignis is InventoryStockChangedEvent) expect(stockChangeCauses, contains(ereignis.data.cause));
        if (ereignis is InventoryStockBelowMinimumEvent) {
          expect(ereignis.data.available, lessThan(ereignis.data.minStock));
        }
      }
    });
  });

  // ---- Anmeldung und Basis -------------------------------------------------------

  group('Anmeldung', () {
    test('Bearer des Kontoschluessels; Partner-Schluessel und Kassen-Token abgewiesen, ohne den Wert zu nennen', () {
      expect(() => InventoryClient(apiKey: ' '), throwsA(_anfragefehler));
      for (final falsch in ['pk_live_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345', 'cb_live_ZmFsc2NoZXJUb2tlbg']) {
        expect(
            () => InventoryClient(apiKey: falsch),
            throwsA(isA<KasseneckValidationError>()
                .having((e) => e.kind, 'kind', 'request')
                .having((e) => e.toString(), 'Meldung', isNot(contains(falsch)))));
      }
    });

    test('baseUrl abweichend erlaubt (eigener Proxy auf /v3), sonst Anfragefehler', () async {
      final (:lager, :anfragen) = _client([_erfolg({'locations': []})], baseUrl: 'https://proxy.example.com/kasseneck/v3');
      expect(await lager.listLocations(), isEmpty);
      expect(anfragen.single.url.toString(), 'https://proxy.example.com/kasseneck/v3/listLocations');
      expect(() => InventoryClient(apiKey: _apiKey, baseUrl: 'https://proxy.example.com/kasseneck'), throwsA(_anfragefehler));
    });
  });

  // ---- Artikel -------------------------------------------------------------------

  group('Artikel', () {
    test('getArticle: POST an api.kasseneck.at/v3/getArticle; ohne Kosten-Recht kein purchasePriceMicros', () async {
      final (:lager, :anfragen) = _client([_erfolg({'article': _artikel})]);
      final a = await lager.getArticle('roggenbrot');
      expect(anfragen.single.url.toString(), 'https://api.kasseneck.at/v3/getArticle');
      expect(_params(anfragen.single), {'articleId': 'roggenbrot'});
      expect(a.toJson(), _artikel);
      expect(a.stockLocationIds, ['haupt']);
      // Das Feld fehlt ganz (nicht null): ohne Recht `costs` sendet der Server es nicht.
      expect(a.hasPurchasePriceMicros, isFalse);
      expect(a.toJson().containsKey('purchasePriceMicros'), isFalse);
    });

    test('purchasePriceMicros, externalIds, metadata und Varianten kommen durch, wenn der Server sie sendet', () async {
      final mehr = {
        ..._artikel,
        'externalIds': {'shop': '4711'},
        'metadata': {'farbe': 'dunkel'},
        'variantGroupId': 'vg1',
        'variantAttributes': {'size': 'L'},
        'purchasePriceMicros': 1234500,
      };
      final (:lager, anfragen: _) = _client([
        _erfolg({'article': mehr}),
        _erfolg({'article': {..._artikel, 'purchasePriceMicros': null}}),
      ]);
      final a = await lager.getArticle('roggenbrot');
      expect(a.toJson(), mehr);
      expect(a.purchasePriceMicros, 1234500);
      expect(a.externalIds, {'shop': '4711'});
      final ohne = await lager.getArticle('roggenbrot');
      expect(ohne.hasPurchasePriceMicros, isTrue);
      expect(ohne.purchasePriceMicros, isNull);
    });

    test('Bruchzahl als Preis, Mindestbestand oder Einkaufspreis ist ein Antwortfehler, nie gerundet', () async {
      for (final kaputt in <Map<String, dynamic>>[
        {'unitPriceCents': 4.5},
        {'minStock': 2.5},
        {'purchasePriceMicros': 10.25},
        {'id': ''},
        {'stockLocationIds': 'haupt'},
        {'vatRate': '10'},
      ]) {
        final (:lager, anfragen: _) = _client([_erfolg({'article': {..._artikel, ...kaputt}})]);
        await expectLater(lager.getArticle('roggenbrot'), throwsA(_antwortfehler), reason: '$kaputt');
      }
      final (:lager, anfragen: _) = _client([_erfolg({})]);
      await expectLater(lager.getArticle('roggenbrot'), throwsA(_antwortfehler));
    });

    test('eine ganzzahlige Kommazahl (4000.0) gilt wie im JS-Zwilling als Ganzzahl', () async {
      final (:lager, anfragen: _) = _client([_erfolg({'article': {..._artikel, 'minStock': 5000.0}})]);
      final a = await lager.getArticle('roggenbrot');
      expect(a.minStock, 5000);
      expect(a.minStock, isA<int>());
    });

    test('getArticle: leere Kennung geht nicht raus', () async {
      final (:lager, :anfragen) = _client([]);
      await expectLater(lager.getArticle(''), throwsA(_anfragefehler));
      await expectLater(lager.getArticle('   '), throwsA(_anfragefehler));
      expect(anfragen, isEmpty);
    });

    test('listArticles: Filter und Cursor gehen unveraendert hinaus, DateTime als ISO UTC mit Millisekunden', () async {
      final (:lager, :anfragen) = _client([_erfolg({'articles': [_artikel], 'nextCursor': 'eyJ6ZWl0IjoxfQ'})]);
      final seite = await lager.listArticles(
          updatedSince: DateTime.parse('2026-10-06T08:00:00.123456+02:00'), active: true, limit: 1);
      expect(_params(anfragen.single), {'updatedSince': '2026-10-06T06:00:00.123Z', 'active': true, 'limit': 1});
      expect(seite.nextCursor, 'eyJ6ZWl0IjoxfQ');
      expect([for (final a in seite.articles) a.toJson()], [_artikel]);
    });

    test('listArticles: limit ausserhalb 1–200 oder leerer Cursor geht nicht raus', () async {
      final (:lager, :anfragen) = _client([]);
      for (final limit in [0, 201, -1]) {
        await expectLater(lager.listArticles(limit: limit), throwsA(_anfragefehler), reason: '$limit');
      }
      await expectLater(lager.listArticles(cursor: ''), throwsA(_anfragefehler));
      await expectLater(lager.listArticles(limit: 1, cursor: ' '), throwsA(_anfragefehler));
      expect(anfragen, isEmpty);
    });

    test('listArticles: nextCursor fehlt = null, leerer Text oder Zahl ist ein Antwortfehler', () async {
      final (:lager, anfragen: _) = _client([
        _erfolg({'articles': []}),
        _erfolg({'articles': [], 'nextCursor': ''}),
        _erfolg({'articles': [], 'nextCursor': 7}),
        _erfolg({'articles': 'keine'}),
      ]);
      expect((await lager.listArticles()).nextCursor, isNull);
      await expectLater(lager.listArticles(), throwsA(_antwortfehler));
      await expectLater(lager.listArticles(), throwsA(_antwortfehler));
      await expectLater(lager.listArticles(), throwsA(_antwortfehler));
    });

    test('iterateArticles: folgt nextCursor bis null, der Filter bleibt auf jeder Seite', () async {
      final zweiter = {..._artikel, 'id': 'semmel', 'name': 'Semmel'};
      final (:lager, :anfragen) = _client([
        _erfolg({'articles': [_artikel], 'nextCursor': 'c1'}),
        _erfolg({'articles': [], 'nextCursor': 'c2'}),
        _erfolg({'articles': [zweiter], 'nextCursor': null}),
      ]);
      final ids = [for (final a in await _alle(lager.iterateArticles(updatedSince: DateTime.utc(2026, 10)))) a.id];
      expect(ids, ['roggenbrot', 'semmel']);
      expect(anfragen.map(_params).toList(), [
        {'updatedSince': '2026-10-01T00:00:00.000Z'},
        {'updatedSince': '2026-10-01T00:00:00.000Z', 'cursor': 'c1'},
        {'updatedSince': '2026-10-01T00:00:00.000Z', 'cursor': 'c2'},
      ]);
    });

    test('iterateArticles: nennt die erste Antwort den Startcursor wieder, endet es mit einem Antwortfehler', () async {
      final (:lager, :anfragen) = _client([_erfolg({'articles': [_artikel], 'nextCursor': 'c0'})]);
      await expectLater(_alle(lager.iterateArticles(cursor: 'c0')), throwsA(_antwortfehler));
      expect(anfragen, hasLength(1));
      expect(_params(anfragen.single), {'cursor': 'c0'});
    });

    test('iterateArticles: derselbe Cursor zweimal ist ein Antwortfehler statt einer Endlosschleife', () async {
      final (:lager, :anfragen) = _client([
        _erfolg({'articles': [_artikel], 'nextCursor': 'c1'}),
        _erfolg({'articles': [_artikel], 'nextCursor': 'c1'}),
      ]);
      await expectLater(_alle(lager.iterateArticles()), throwsA(_antwortfehler));
      expect(anfragen, hasLength(2));
    });

    test('iterateArticles: ein ungueltiges limit geht nicht raus', () async {
      final (:lager, :anfragen) = _client([]);
      await expectLater(_alle(lager.iterateArticles(limit: 0)), throwsA(_anfragefehler));
      expect(anfragen, isEmpty);
    });

    test('lookupArticleByCode: per code oder per externalSystem mit externalId', () async {
      final (:lager, :anfragen) = _client([_erfolg({'article': _artikel}), _erfolg({'article': _artikel})]);
      await lager.lookupArticleByCode(code: '9001234567896');
      await lager.lookupArticleByCode(externalSystem: 'shop', externalId: '4711');
      expect(anfragen.map(_params).toList(), [
        {'code': '9001234567896'},
        {'externalSystem': 'shop', 'externalId': '4711'},
      ]);
      expect(anfragen.every((a) => a.url.path.endsWith('/v3/lookupArticleByCode')), isTrue);
    });

    test('lookupArticleByCode: unvollstaendige oder doppelte Kennung geht nicht raus', () async {
      final (:lager, :anfragen) = _client([]);
      await expectLater(lager.lookupArticleByCode(), throwsA(_anfragefehler));
      await expectLater(lager.lookupArticleByCode(code: ''), throwsA(_anfragefehler));
      await expectLater(lager.lookupArticleByCode(externalSystem: 'shop'), throwsA(_anfragefehler));
      await expectLater(lager.lookupArticleByCode(externalId: '4711'), throwsA(_anfragefehler));
      await expectLater(lager.lookupArticleByCode(externalSystem: 'shop', externalId: ' '), throwsA(_anfragefehler));
      await expectLater(
          lager.lookupArticleByCode(code: 'A', externalSystem: 'shop', externalId: '1'), throwsA(_anfragefehler));
      expect(anfragen, isEmpty);
    });
  });

  // ---- Standorte und Bestand -------------------------------------------------------

  group('Standorte und Bestand', () {
    test('listLocations: Typen aus dem Katalog, Adresse oder null, virtual nur bei true', () async {
      final (:lager, :anfragen) = _client([
        _erfolg({
          'locations': [
            ..._standorte,
            {'id': 'x', 'name': 'Neu', 'type': 'spaceship', 'active': true},
            {'id': 'haupt2', 'name': 'Hauptstandort', 'type': 'store', 'address': {'street': '', 'zip': null}, 'virtual': true},
          ]
        }),
      ]);
      final l = await lager.listLocations();
      expect(_params(anfragen.single), isEmpty);
      for (final (i, s) in _standorte.indexed) {
        expect(l[i].toJson(), {...s, 'virtual': false});
      }
      expect(l[_standorte.length].type, isNull, reason: 'ein unbekannter Typ wird null, nicht geraten');
      expect(l.last.virtual, isTrue);
      expect(l.last.address, isNull, reason: 'eine Adresse ohne einen einzigen Teil ist keine');
      expect(l.firstWhere((o) => o.id == 'lieferwagen').licensePlate, 'S-123AB');
    });

    test('getStock: Zeilen je Standort, available darf negativ sein; values null ohne Kosten-Recht, Liste mit', () async {
      final minus = {..._bestand, 'locationId': 'lieferwagen', 'onHand': 1000, 'reserved': 3000, 'available': -2000, 'sequence': 7};
      final werte = [
        {'articleId': 'roggenbrot', 'stockValueCents': 2700, 'averageCostMicros': 225000}
      ];
      final (:lager, :anfragen) = _client([
        _erfolg({'stock': [_bestand, minus]}),
        _erfolg({'stock': [_bestand], 'values': werte}),
      ]);
      final ohne = await lager.getStock('roggenbrot');
      expect(_params(anfragen.first), {'articleId': 'roggenbrot'});
      expect([for (final z in ohne.stock) z.toJson()], [_bestand, minus]);
      expect(ohne.stock.last.available, -2000);
      expect(ohne.values, isNull);
      final mit = await lager.getStock('roggenbrot');
      expect(mit.values, hasLength(1));
      expect(mit.values!.single.articleId, 'roggenbrot');
      expect(mit.values!.single.stockValueCents, 2700);
      expect(mit.values!.single.averageCostMicros, 225000);
    });

    test('getStock: Bruchzahl, fehlende Menge oder Text statt Zahl ist ein Antwortfehler, nie 0', () async {
      for (final kaputt in <Map<String, dynamic>>[
        {'onHand': 1.5},
        {'reserved': null},
        {'available': '10000'},
        {'sequence': 1.1},
        {'defective': 9007199254740993},
        {'locationId': ''},
      ]) {
        final (:lager, anfragen: _) = _client([_erfolg({'stock': [{..._bestand, ...kaputt}]})]);
        await expectLater(lager.getStock('roggenbrot'), throwsA(_antwortfehler), reason: '$kaputt');
      }
      final ohneMenge = Map.of(_bestand)..remove('onHand');
      final (:lager, anfragen: _) = _client([
        _erfolg({'stock': [ohneMenge]}),
        _erfolg({'stock': [_bestand], 'values': [{'articleId': 'roggenbrot', 'stockValueCents': 1.5}]}),
      ]);
      await expectLater(lager.getStock('roggenbrot'), throwsA(_antwortfehler));
      await expectLater(lager.getStock('roggenbrot'), throwsA(_antwortfehler));
    });

    test('listStock und iterateStock: Filter, changedSince als DateTime, Seiten bis nextCursor null', () async {
      final (:lager, :anfragen) = _client([
        _erfolg({'stock': [_bestand], 'nextCursor': 'c1'}),
        _erfolg({'stock': [{..._bestand, 'locationId': 'lager1'}], 'nextCursor': null}),
        _erfolg({'stock': [_bestand], 'nextCursor': null, 'values': []}),
      ]);
      final orte = [
        for (final z in await _alle(lager.iterateStock(articleId: 'roggenbrot', changedSince: DateTime.utc(2026, 10, 6, 8))))
          z.locationId
      ];
      expect(orte, ['haupt', 'lager1']);
      expect(_params(anfragen[1]), {'articleId': 'roggenbrot', 'changedSince': '2026-10-06T08:00:00.000Z', 'cursor': 'c1'});
      final seite = await lager.listStock(belowMinimum: true);
      expect(_params(anfragen[2]), {'belowMinimum': true});
      expect(seite.values, isEmpty);
      expect(seite.nextCursor, isNull);
    });

    test('iterateStock: derselbe Cursor zweimal endet mit einem Antwortfehler', () async {
      final (:lager, anfragen: _) = _client([
        _erfolg({'stock': [_bestand], 'nextCursor': 'c1'}),
        _erfolg({'stock': [_bestand], 'nextCursor': 'c1'}),
      ]);
      await expectLater(_alle(lager.iterateStock()), throwsA(_antwortfehler));
    });

    test('listStockMovements: Filter type/source englisch wie gesendet, Wertfelder nur wenn vorhanden', () async {
      final mitWert = {
        ..._bewegung,
        'valueDeltaCents': -90,
        'consumedValueCents': 90,
        'lots': [{...((_bewegung['lots'] as List).first as Map), 'valueCents': 90}],
      };
      final (:lager, :anfragen) = _client([
        _erfolg({'movements': [_bewegung], 'nextCursor': 'c1'}),
        _erfolg({'movements': [mitWert], 'nextCursor': null}),
      ]);
      final seite = await lager.listStockMovements(
          articleId: 'roggenbrot', type: 'sale', source: 'receipt', from: DateTime.utc(2026, 10), to: DateTime.utc(2026, 10, 6));
      expect(_params(anfragen[0]), {
        'articleId': 'roggenbrot',
        'type': 'sale',
        'source': 'receipt',
        'from': '2026-10-01T00:00:00.000Z',
        'to': '2026-10-06T00:00:00.000Z',
      });
      expect([for (final b in seite.movements) b.toJson()], [_bewegung]);
      expect(seite.movements.single.hasValueDeltaCents, isFalse);
      final zweite = await lager.listStockMovements(articleId: 'roggenbrot', cursor: 'c1');
      expect([for (final b in zweite.movements) b.toJson()], [mitWert]);
      expect(zweite.movements.single.valueDeltaCents, -90);
      expect(zweite.movements.single.lots.single.valueCents, 90);
      expect(_params(anfragen[1]), {'articleId': 'roggenbrot', 'cursor': 'c1'});
    });

    test('listStockMovements: Wareneingang heisst goods_receipt, Uebernahme takeover', () async {
      final (:lager, anfragen: _) = _client([_antwort(_fall('list_stock_movements_goods_receipt')['response'])]);
      final seite = await lager.listStockMovements(locationId: 'haupt', type: 'goods_receipt', source: 'panel');
      expect(seite.movements, isNotEmpty);
      expect(seite.movements.every((b) => b.type == 'goods_receipt'), isTrue);
    });

    test('iterateStockMovements: alle Seiten', () async {
      final (:lager, anfragen: _) = _client([
        _erfolg({'movements': [_bewegung], 'nextCursor': 'c1'}),
        _erfolg({'movements': [{..._bewegung, 'id': 'bw2'}], 'nextCursor': null}),
      ]);
      final ids = [for (final b in await _alle(lager.iterateStockMovements())) b.id];
      expect(ids, [_bewegung['id'], 'bw2']);
    });

    test('listStockMovements: Bruchzahl in quantityDelta, stockAfter oder einem Los ist ein Antwortfehler', () async {
      final los = (_bewegung['lots'] as List).first as Map;
      for (final kaputt in <Map<String, dynamic>>[
        {'quantityDelta': -1.5},
        {'stockAfter': {'sellable': 0.5, 'defective': 0}},
        {'lots': [{...los, 'quantity': 0.1}]},
        {'lots': 'keine'},
        {'id': null},
      ]) {
        final (:lager, anfragen: _) = _client([_erfolg({'movements': [{..._bewegung, ...kaputt}], 'nextCursor': null})]);
        await expectLater(lager.listStockMovements(), throwsA(_antwortfehler), reason: '$kaputt');
      }
    });
  });

  // ---- Fehler -----------------------------------------------------------------------

  group('Fehler', () {
    Future<Object?> fang(Future<Object?> f) async {
      try {
        await f;
      } catch (e) {
        return e;
      }
      fail('kein Fehler');
    }

    test('rate_limited traegt retryAfterSec; die uebrigen Codes am Code', () async {
      final (:lager, anfragen: _) = _client([
        _fehler('Zu viele Anfragen – bitte später erneut versuchen.', {'code': 'rate_limited', 'retryAfterSec': 3}),
        _fehler('Die Lager-API ist für dieses Konto nicht freigeschaltet.', {'code': 'inventory_api_not_enabled'}),
        _fehler('Modul inaktiv', {'code': 'module_inactive'}),
        _fehler('Artikel nicht gefunden.', {'code': 'article_not_found'}),
        _fehler('Der Blätter-Zeiger ist ungültig.', {'code': 'invalid_cursor'}),
        _fehler('Zu viele Anfragen.', {'code': 'rate_limited'}),
      ]);
      final e1 = await fang(lager.getStock('roggenbrot'));
      expect(e1, isA<KasseneckApiError>());
      expect(isInventoryError(e1, 'rate_limited'), isTrue);
      expect(isInventoryError(e1), isTrue);
      expect(isInventoryError(e1, 'article_not_found'), isFalse);
      expect(inventoryRetryAfterSec(e1), 3);
      expect((e1 as KasseneckApiError).outcome, ErrorOutcome.rejected);
      expect(inventoryErrorCode(await fang(lager.listArticles())), 'inventory_api_not_enabled');
      expect(inventoryErrorCode(await fang(lager.listLocations())), 'module_inactive');
      final e4 = await fang(lager.getArticle('weg'));
      expect(isInventoryError(e4, 'article_not_found'), isTrue);
      expect(inventoryRetryAfterSec(e4), isNull);
      expect(inventoryErrorCode(await fang(lager.listStock(cursor: 'kaputt'))), 'invalid_cursor');
      expect(inventoryRetryAfterSec(await fang(lager.listStock())), isNull, reason: 'ohne Angabe keine Wartezeit');
    });

    test('inventoryRetryAfterSec: nur eine nicht negative Zahl; fremde Codes sind keine Lager-Fehler', () {
      KasseneckApiError mit(Object? wert) =>
          KasseneckApiError('getStock', 'x', code: 'rate_limited', details: {'code': 'rate_limited', 'retryAfterSec': wert});
      expect(inventoryRetryAfterSec(mit(-1)), isNull);
      expect(inventoryRetryAfterSec(mit('3')), isNull);
      expect(inventoryRetryAfterSec(mit(2.5)), 3, reason: 'aufrunden: frueher fragen hiesse wieder rate_limited');
      expect(inventoryRetryAfterSec(mit(0)), 0);
      expect(isInventoryError(const KasseneckApiError('getStock', 'x', code: 'brand_new_code_2027')), isFalse);
      expect(isInventoryError(Exception('x')), isFalse);
      expect(inventoryErrorCode(null), isNull);
    });

    test('validation liefert die Feldfehler', () async {
      final (:lager, anfragen: _) = _client([
        _fehler('Bitte Eingaben prüfen.', {
          'code': 'validation',
          'errors': [
            {'field': 'limit', 'message': 'Limit muss eine ganze Zahl von 1 bis 200 sein.'},
            {'field': 3, 'message': 'kaputt'},
          ]
        }),
      ]);
      final e = await fang(lager.listStockMovements(type: 'sale'));
      expect(inventoryFieldErrors(e), [(field: 'limit', message: 'Limit muss eine ganze Zahl von 1 bis 200 sein.')]);
      expect(inventoryFieldErrors(Exception('x')), isEmpty);
    });
  });

  // ---- Webhooks verwalten -------------------------------------------------------------

  group('Webhooks verwalten', () {
    test('createWebhook: Secret genau einmal in der Antwort; ohne Secret ist die Antwort unbrauchbar', () async {
      final (:lager, :anfragen) = _client([
        _erfolg({'webhook': _webhook, 'secret': 'whsec_Beispiel0123456789'}),
        _erfolg({'webhook': _webhook}),
      ]);
      final r = await lager.createWebhook(
          url: 'https://shop.example.com/kasseneck-webhook', events: ['stock.changed', 'stock.below_minimum'], description: 'Shop');
      expect(anfragen.first.url.toString(), 'https://api.kasseneck.at/v3/createWebhook');
      expect(_params(anfragen.first), {
        'url': 'https://shop.example.com/kasseneck-webhook',
        'events': ['stock.changed', 'stock.below_minimum'],
        'description': 'Shop',
      });
      expect(r.secret, 'whsec_Beispiel0123456789');
      expect(r.webhook.toJson(), _webhook);
      await expectLater(
          lager.createWebhook(url: 'https://shop.example.com/x', events: ['stock.changed']), throwsA(_antwortfehler));
      expect(_params(anfragen.last).containsKey('description'), isFalse);
    });

    test('createWebhook: ohne url oder ohne Ereignis geht nichts raus', () async {
      final (:lager, :anfragen) = _client([]);
      await expectLater(lager.createWebhook(url: '', events: ['stock.changed']), throwsA(_anfragefehler));
      await expectLater(lager.createWebhook(url: 'https://shop.example.com/x', events: []), throwsA(_anfragefehler));
      expect(anfragen, isEmpty);
    });

    test('updateWebhook: flache Parameter neben webhookId; removeDescription sendet null; leere Aenderung geht nicht raus', () async {
      final (:lager, :anfragen) = _client([
        _erfolg({'webhook': {..._webhook, 'active': false, 'description': null}}),
      ]);
      final w = await lager.updateWebhook('wh1', active: false, removeDescription: true);
      expect(_params(anfragen.single), {'webhookId': 'wh1', 'active': false, 'description': null});
      expect(w.active, isFalse);
      expect(w.description, isNull);
      await expectLater(lager.updateWebhook('wh1'), throwsA(_anfragefehler));
      await expectLater(lager.updateWebhook('', active: true), throwsA(_anfragefehler));
      await expectLater(lager.updateWebhook('wh1', description: 'x', removeDescription: true), throwsA(_anfragefehler));
      expect(anfragen, hasLength(1));
    });

    test('deleteWebhook, listWebhooks, rotateWebhookSecret, sendWebhookTest, listWebhookDeliveries', () async {
      final (:lager, :anfragen) = _client([
        _erfolg({'webhookId': 'wh1', 'deleted': true}),
        _erfolg({
          'webhooks': [_webhook, {..._webhook, 'id': 'wh2', 'lastDelivery': null}],
          'events': inventoryWebhookEvents,
        }),
        _erfolg({'webhook': _webhook, 'secret': 'whsec_Neu0123456789'}),
        _erfolg(_daten('send_webhook_test')),
        _erfolg({'deliveries': [_zustellung]}),
      ]);
      final geloescht = await lager.deleteWebhook('wh1');
      expect(geloescht.webhookId, 'wh1');
      expect(geloescht.deleted, isTrue);
      final liste = await lager.listWebhooks();
      expect(liste.events, inventoryWebhookEvents);
      expect(liste.webhooks[1].lastDelivery, isNull);
      expect(liste.webhooks[0].lastDelivery!.status, 'delivered');
      expect((await lager.rotateWebhookSecret('wh1')).secret, 'whsec_Neu0123456789');
      final probe = await lager.sendWebhookTest('wh1', 'stock.changed');
      expect(probe.toJson(), _daten('send_webhook_test'));
      expect(probe.deliveries.single.deliveryId, isNotEmpty);
      final zustellungen = await lager.listWebhookDeliveries(webhookId: 'wh1', limit: 20);
      expect([for (final z in zustellungen) z.toJson()], [_zustellung]);
      expect(webhookDeliveryStatuses, contains(zustellungen.single.status));
      expect(anfragen.map((a) => a.url.pathSegments.last).toList(),
          ['deleteWebhook', 'listWebhooks', 'rotateWebhookSecret', 'sendWebhookTest', 'listWebhookDeliveries']);
      expect(anfragen.map(_params).toList(), [
        {'webhookId': 'wh1'},
        <String, dynamic>{},
        {'webhookId': 'wh1'},
        {'webhookId': 'wh1', 'event': 'stock.changed'},
        {'webhookId': 'wh1', 'limit': 20},
      ]);
    });

    test('deleteWebhook: ohne Kennung in der Antwort gilt die gesendete, deleted nur bei true', () async {
      final (:lager, anfragen: _) = _client([_erfolg({})]);
      final r = await lager.deleteWebhook('wh1');
      expect(r.webhookId, 'wh1');
      expect(r.deleted, isFalse);
    });

    test('Antwort ohne Kennung ist unbrauchbar; limit der Zustellungen 1–200; leeres Ereignis geht nicht raus', () async {
      final (:lager, :anfragen) = _client([
        _erfolg({'webhooks': [{..._webhook, 'id': ''}], 'events': []}),
        _erfolg({'deliveries': [{..._zustellung, 'deliveryId': null}]}),
      ]);
      await expectLater(lager.listWebhooks(), throwsA(_antwortfehler));
      await expectLater(lager.listWebhookDeliveries(limit: 0), throwsA(_anfragefehler));
      await expectLater(lager.listWebhookDeliveries(limit: 201), throwsA(_anfragefehler));
      await expectLater(lager.listWebhookDeliveries(webhookId: ''), throwsA(_anfragefehler));
      await expectLater(lager.sendWebhookTest('wh1', ''), throwsA(_anfragefehler));
      await expectLater(lager.sendWebhookTest('', 'stock.changed'), throwsA(_anfragefehler));
      await expectLater(lager.rotateWebhookSecret(''), throwsA(_anfragefehler));
      await expectLater(lager.deleteWebhook(''), throwsA(_anfragefehler));
      expect(anfragen, hasLength(1));
      await expectLater(lager.listWebhookDeliveries(), throwsA(_antwortfehler));
    });
  });

  // ---- Signatur -----------------------------------------------------------------------

  group('verifyInventoryWebhookSignature', () {
    const kopf = 't=$_vektorT,v1=$_vektorHex';

    test('Testvektor des Backends (t=1700000000) ist gueltig, als Text und als Bytes', () {
      // Der Vektor selbst: HMAC-SHA256 ueber "<t>.<Rumpf>".
      expect(Hmac(sha256, utf8.encode(_vektorSecret)).convert(utf8.encode('$_vektorT.$_vektorBody')).toString(), _vektorHex);
      expect(verifyInventoryWebhookSignature(_vektorSecret, kopf, _vektorBody, now: _um(_vektorT)), isTrue);
      expect(verifyInventoryWebhookSignature(_vektorSecret, kopf, Uint8List.fromList(utf8.encode(_vektorBody)), now: _um(_vektorT)),
          isTrue);
      expect(verifyInventoryWebhookSignature(_vektorSecret, kopf, utf8.encode(_vektorBody), now: _um(_vektorT)), isTrue);
      // Ein zweiter v1-Anteil (Schluesselwechsel) stoert nicht, gleich an welcher Stelle.
      expect(
          verifyInventoryWebhookSignature(_vektorSecret, 't=$_vektorT,v1=${'0' * 64},v1=$_vektorHex', _vektorBody, now: _um(_vektorT)),
          isTrue);
      expect(verifyInventoryWebhookSignature(_vektorSecret, 'v1=$_vektorHex, t=$_vektorT', _vektorBody, now: _um(_vektorT)), isTrue);
      expect(verifyInventoryWebhookSignature(_vektorSecret, kopf.replaceFirst(_vektorHex, _vektorHex.toUpperCase()), _vektorBody,
          now: _um(_vektorT)), isTrue);
    });

    test('falscher Schluessel, veraenderter Rumpf, kaputter Kopf: nein, nie ein Wurf (Rot-Probe)', () {
      final jetzt = _um(_vektorT);
      expect(verifyInventoryWebhookSignature('whsec_anders', kopf, _vektorBody, now: jetzt), isFalse);
      expect(verifyInventoryWebhookSignature(_vektorSecret, kopf, '$_vektorBody ', now: jetzt), isFalse);
      expect(
          verifyInventoryWebhookSignature(
              _vektorSecret, kopf, const JsonEncoder.withIndent(' ').convert(jsonDecode(_vektorBody)), now: jetzt),
          isFalse);
      for (final schlecht in <String?>[
        '',
        '   ',
        'unsinn',
        't=abc,v1=$_vektorHex',
        'v1=$_vektorHex',
        't=$_vektorT',
        't=$_vektorT,v1=zz',
        't=$_vektorT,v1=${_vektorHex.substring(1)}',
        't=$_vektorT,v1=${_vektorHex.substring(0, 62)}',
        't=$_vektorT,v1=',
        't=1e9,v1=$_vektorHex',
        't=+$_vektorT,v1=$_vektorHex',
        't=1234567890123456,v1=$_vektorHex',
        't=$_vektorT\n,v1=$_vektorHex x',
        null,
      ]) {
        expect(verifyInventoryWebhookSignature(_vektorSecret, schlecht, _vektorBody, now: jetzt), isFalse, reason: '$schlecht');
      }
      expect(verifyInventoryWebhookSignature('', kopf, _vektorBody, now: jetzt), isFalse);
      expect(verifyInventoryWebhookSignature(null, kopf, _vektorBody, now: jetzt), isFalse);
      expect(verifyInventoryWebhookSignature(42, kopf, _vektorBody, now: jetzt), isFalse);
      expect(verifyInventoryWebhookSignature(_vektorSecret, kopf, null, now: jetzt), isFalse);
      expect(verifyInventoryWebhookSignature(_vektorSecret, kopf, {'id': 'evt_1'}, now: jetzt), isFalse);
      expect(verifyInventoryWebhookSignature(_vektorSecret, kopf, [300, -1], now: jetzt), isFalse);
      // Eine Ausnahme im Inneren ist eine Ablehnung, nie ein Ja und nie ein Wurf.
      final wirft = Iterable<String>.generate(1, (_) => throw StateError('kaputt'));
      expect(verifyInventoryWebhookSignature(wirft, kopf, _vektorBody, now: jetzt), isFalse);
      final wirftSpaeter = Iterable<String>.generate(2, (i) => i == 0 ? _vektorSecret : throw StateError('kaputt'));
      expect(verifyInventoryWebhookSignature(wirftSpaeter, 't=$_vektorT,v1=${'0' * 64}', _vektorBody, now: jetzt), isFalse);
    });

    test('Secret als Liste (Schluesselwechsel) prueft mit dem zweiten Schluessel', () {
      final jetzt = _um(_vektorT);
      expect(verifyInventoryWebhookSignature(['whsec_alt', _vektorSecret], kopf, _vektorBody, now: jetzt), isTrue);
      expect(verifyInventoryWebhookSignature(['whsec_alt', 'whsec_anders'], kopf, _vektorBody, now: jetzt), isFalse);
      expect(verifyInventoryWebhookSignature(<String>[], kopf, _vektorBody, now: jetzt), isFalse);
      expect(verifyInventoryWebhookSignature(['', _vektorSecret], kopf, _vektorBody, now: jetzt), isTrue);
    });

    test('Zeitfenster 300 s in beide Richtungen, toleranceSec setzbar (Rot-Probe)', () {
      bool pruefe(int sek, [int? toleranz]) => toleranz == null
          ? verifyInventoryWebhookSignature(_vektorSecret, kopf, _vektorBody, now: _um(sek))
          : verifyInventoryWebhookSignature(_vektorSecret, kopf, _vektorBody, now: _um(sek), toleranceSec: toleranz);
      expect(pruefe(_vektorT + 300), isTrue);
      expect(pruefe(_vektorT - 300), isTrue);
      expect(pruefe(_vektorT + 301), isFalse);
      expect(pruefe(_vektorT - 301), isFalse);
      expect(pruefe(_vektorT + 600, 600), isTrue);
      expect(pruefe(_vektorT + 61, 60), isFalse);
      // Bruchteile einer Sekunde zaehlen wie im JS-Zwilling abgerundet.
      expect(
          verifyInventoryWebhookSignature(_vektorSecret, kopf, _vektorBody,
              now: DateTime.fromMillisecondsSinceEpoch((_vektorT + 300) * 1000 + 999, isUtc: true)),
          isTrue);
      // Ohne `now` gilt die Systemuhr: der Vektor von 2023 ist laengst abgelaufen.
      expect(verifyInventoryWebhookSignature(_vektorSecret, kopf, _vektorBody), isFalse);
    });

    test('Shop-Ablauf: Signatur pruefen, dann Ereignis lesen, Stand nur bei groesserer sequence uebernehmen', () {
      const secret = 'whsec_Beispiel0123456789';
      const t = 1791274510;
      final body = _huelle('stock.changed', _stockChanged);
      final v1 = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode('$t.$body')).toString();
      final stand = <String, int>{'beispiel_roggenbrot/haupt': 41};
      expect(verifyInventoryWebhookSignature(secret, 't=$t,v1=$v1', body, now: _um(t + 2)), isTrue);
      final e = parseInventoryWebhookEvent(body);
      if (e is! InventoryStockChangedEvent) fail('kein stock.changed');
      final schluessel = '${e.data.articleId}/${e.data.locationId}';
      if (e.data.sequence > (stand[schluessel] ?? -1)) stand[schluessel] = e.data.sequence;
      expect(stand[schluessel], 42);
    });
  });

  // ---- Ereignisse -----------------------------------------------------------------------

  group('parseInventoryWebhookEvent', () {
    test('stock.changed typisiert, Huelle mit accountId, test nur bei true', () {
      final e = parseInventoryWebhookEvent(_huelle('stock.changed', _stockChanged));
      expect(e, isA<InventoryStockChangedEvent>());
      e as InventoryStockChangedEvent;
      expect(e.type, 'stock.changed');
      expect(e.accountId, 'konto_kornblum');
      expect(e.createdAt, 1791274500000);
      expect(e.test, isFalse);
      expect(e.data.toJson(), _stockChanged);
      expect(e.data.cause, 'sale');
      expect(e.data.movementId, 'beispiel_bewegung_1');
      for (final k in _schluessel(((_vokabular['events'] as Map)['stock.changed'] as Map)['data'])) {
        expect(e.data.toJson().containsKey(k), isTrue, reason: 'stock.changed.$k');
      }
      final probe = parseInventoryWebhookEvent(
          utf8.encode(_huelle('stock.changed', {..._stockChanged, 'movementId': null, 'cause': 'other'}, test: true)));
      expect(probe!.test, isTrue);
      expect((probe as InventoryStockChangedEvent).data.movementId, isNull);
      final nichtWahr = parseInventoryWebhookEvent(_huelle('stock.changed', _stockChanged).replaceFirst('"data"', '"test":"true","data"'));
      expect(nichtWahr!.test, isFalse, reason: 'nur ein ausdrueckliches true ist eine Probe');
    });

    test('stock.below_minimum und article.* (Artikel wie getArticle)', () {
      final u = parseInventoryWebhookEvent(_huelle('stock.below_minimum', _unterMindest));
      expect(u, isA<InventoryStockBelowMinimumEvent>());
      expect((u as InventoryStockBelowMinimumEvent).data.toJson(), _unterMindest);
      for (final art in ['article.created', 'article.updated', 'article.deactivated']) {
        final a = parseInventoryWebhookEvent(_huelle(art, {..._artikel, 'active': art != 'article.deactivated'}));
        expect(a, isA<InventoryArticleEvent>(), reason: art);
        expect(a!.type, art);
        expect((a as InventoryArticleEvent).data.id, 'roggenbrot');
        expect(a.data.active, art != 'article.deactivated');
      }
    });

    test('unbekannter Typ ist null (2xx antworten und uebergehen), kaputter Rumpf wirft', () {
      // Seit 10.5 kennt das Paket variant_group.*; ein Ereignis einer spaeteren Stufe bleibt null.
      expect(parseInventoryWebhookEvent(_huelle('price_list.updated', {'priceListId': 'pl1'})), isNull);
      final ohneSequence = Map.of(_stockChanged)..remove('sequence');
      for (final kaputt in <Object?>[
        '',
        'kein json',
        '[]',
        '{"type":"stock.changed"}',
        jsonEncode({'id': 'evt_1', 'type': 'stock.changed', 'createdAt': 1, 'data': _stockChanged}),
        jsonEncode({'id': 'evt_1', 'type': 'stock.changed', 'createdAt': '1', 'accountId': 'k', 'data': _stockChanged}),
        jsonEncode({'id': 'evt_1', 'type': 'stock.changed', 'createdAt': 1, 'accountId': 'k'}),
        _huelle('stock.changed', {..._stockChanged, 'onHand': 1.5}),
        _huelle('stock.changed', ohneSequence),
        _huelle('stock.changed', {..._stockChanged, 'cause': ''}),
        _huelle('stock.below_minimum', {..._unterMindest, 'minStock': '5000'}),
        _huelle('article.updated', {..._artikel, 'id': ''}),
        null,
        42,
      ]) {
        expect(() => parseInventoryWebhookEvent(kaputt), throwsA(_antwortfehler), reason: '$kaputt');
      }
    });
  });
}
