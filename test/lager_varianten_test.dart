import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/inventory.dart';

import 'helpers/lager_anfragen.dart';

/// Variantengruppen der Lager-API (Backend Stufe 5c, Zwilling von
/// `test/inventory-varianten.test.ts` im npm-Paket 1.6.0) gegen den
/// Vertrags-Export: die Drahtbeispiele stammen aus `v3/antworten/lager.json`
/// (echte Antworten an einem erfundenen Konto, Baeckerei Kornblum, Gruppen
/// „Schürze“ und „Geschirrtuch“), nichts davon ist hier gebaut.
///
/// Geprueft wird vor allem, was vor dem Senden geschieht (ohne gueltigen
/// `idempotencyKey` geht nichts hinaus, die Grenzen der Gruppe entscheidet der
/// Server) und dass eine kaputte Antwort ein Antwortfehler wird, nie ein
/// Ersatzwert. Was im JS-Zwilling erst zur Laufzeit auffaellt (Bruchzahl als
/// Preis, `variants` keine Liste, fehlende Merkmalsabbildung), schliesst hier
/// schon der Typ aus; an seine Stelle tritt der sichere Ganzzahlbereich.

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

Map<String, dynamic> _gesendet(http.Request r) => (jsonDecode(r.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;

final Matcher _antwortfehler = isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'response');
final Matcher _anfragefehler = isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'request');

Future<Object?> _fang(Future<Object?> f) => f.then<Object?>((_) => null, onError: (Object e) => e);

/// Die aeusseren Schluessel eines Schema-Eintrags (ohne `__`).
List<String> _schluessel(Object? schema) => (schema as Map).keys.cast<String>().where((k) => k != '__').toList();

final Map<String, dynamic> _schuerze = _daten('get_variant_group')['variantGroup'] as Map<String, dynamic>;

/// Je schreibender Aufruf die gueltigen Anfragen aus dem Vertrag.
const List<(String, String)> _schreiben = [
  ('createVariantGroup', 'create_variant_group_matrix'),
  ('createVariantGroup', 'create_variant_group_variants'),
  ('updateVariantGroup', 'update_variant_group_values'),
  ('updateVariantGroup', 'update_variant_group_deactivate'),
  ('addVariant', 'add_variant'),
];

Object? _alsJson(Object? ergebnis) => switch (ergebnis) {
      Article a => a.toJson(),
      VariantGroup g => g.toJson(),
      _ => ergebnis,
    };

const _gruppe = CreateVariantGroupRequest(
  idempotencyKey: 'k',
  name: 'Schürze',
  attributes: [VariantAttribute(key: 'farbe', label: 'Farbe', values: ['rot', 'blau'])],
);

void main() {
  // ---- Vertrag ------------------------------------------------------------------

  group('Vertrag', () {
    test('jede gueltige Anfrage des Vertrags geht unveraendert an /v3/<name>, die Antwort liest sich verlustfrei', () async {
      for (final (name, fallName) in _schreiben) {
        expect(_fall(fallName)['endpoint'], name);
        final (:lager, :anfragen) = _client([_vertrag(fallName)]);
        final ergebnis = await schreibAufruf(lager, name, _params(fallName));
        expect(anfragen, hasLength(1), reason: fallName);
        expect(anfragen.single.url.toString(), 'https://api.kasseneck.at/v3/$name');
        expect(_gesendet(anfragen.single), _params(fallName), reason: '$fallName: Parameter');
        expect(anfragen.single.headers['Authorization'], 'Bearer $_apiKey');
        final d = _daten(fallName);
        expect(_alsJson(ergebnis), d['variantGroup'] ?? d['article'], reason: fallName);
      }
    });

    test('Lesen, Liste und Iterator; listVariantGroups nimmt active, updatedSince (ISO UTC), limit, cursor', () async {
      final (:lager, :anfragen) = _client([
        _vertrag('get_variant_group'),
        _vertrag('list_variant_groups'),
        _erfolg({'variantGroups': [_schuerze], 'nextCursor': 'c1'}),
        _erfolg({
          'variantGroups': [
            {..._schuerze, 'id': 'auto99'}
          ],
          'nextCursor': null,
        }),
      ]);
      final g = await lager.getVariantGroup('auto61');
      expect(_gesendet(anfragen[0]), {'variantGroupId': 'auto61'});
      expect(g.toJson(), _schuerze);
      final seite = await lager.listVariantGroups();
      expect(_gesendet(anfragen[1]), isEmpty);
      expect(seite.toJson(), _daten('list_variant_groups'));
      expect([for (final x in seite.variantGroups) x.active], [true, false]);
      final ids = [
        await for (final x in lager.iterateVariantGroups(active: true, updatedSince: DateTime.utc(2026, 10, 6, 8), limit: 1)) x.id
      ];
      expect(ids, ['auto61', 'auto99']);
      expect(_gesendet(anfragen[2]), {'active': true, 'updatedSince': '2026-10-06T08:00:00.000Z', 'limit': 1});
      expect(_gesendet(anfragen[3]), {'active': true, 'updatedSince': '2026-10-06T08:00:00.000Z', 'limit': 1, 'cursor': 'c1'});
      for (final falsch in [0, 201]) {
        expect(await _fang(lager.listVariantGroups(limit: falsch)), _anfragefehler, reason: '$falsch');
      }
      expect(await _fang(lager.listVariantGroups(cursor: ' ')), _anfragefehler);
      expect(await _fang(lager.getVariantGroup('')), _anfragefehler);
      expect(await _fang(lager.getVariantGroup('  ')), _anfragefehler);
      expect(anfragen, hasLength(4));
    });

    test('iterateVariantGroups: derselbe Cursor zweimal endet mit einem Antwortfehler statt einer Endlosschleife', () async {
      final (:lager, anfragen: _) = _client([
        _erfolg({'variantGroups': [_schuerze], 'nextCursor': 'c1'}),
        _erfolg({'variantGroups': [_schuerze], 'nextCursor': 'c1'}),
      ]);
      expect(await _fang(lager.iterateVariantGroups().toList()), _antwortfehler);
    });

    test('listArticles(variantGroupId:) liest die Varianten als Artikel; variantAttributes nach Schluessel sortiert', () async {
      final c = _fall('list_articles_by_variant_group');
      final (:lager, :anfragen) = _client([_vertrag('list_articles_by_variant_group')]);
      final seite = await lager.listArticles(variantGroupId: 'auto61', limit: 3);
      expect(_gesendet(anfragen.single), c['params']);
      expect([for (final a in seite.articles) a.toJson()], _daten('list_articles_by_variant_group')['articles']);
      expect(seite.nextCursor, _daten('list_articles_by_variant_group')['nextCursor']);
      expect(seite.articles, isNotEmpty);
      for (final a in seite.articles) {
        expect(a.variantGroupId, 'auto61');
        final schluessel = a.variantAttributes!.keys.toList();
        expect(schluessel, [...schluessel]..sort(), reason: '${a.id}: Schluessel sortiert');
      }
      // Die Gruppe nennt die Merkmale in ihrer eigenen Reihenfolge (Groesse vor Farbe).
      expect([for (final m in _schuerze['attributes'] as List) (m as Map)['key']], ['groesse', 'farbe']);
      expect(seite.articles.first.name, 'Schürze S rot', reason: 'Standardname in Merkmalsreihenfolge');
    });

    test('jedes Feld der Gruppen-Schemata kommt im gelesenen Modell an', () async {
      final (:lager, anfragen: _) = _client([_vertrag('get_variant_group')]);
      final g = (await lager.getVariantGroup('auto61')).toJson();
      final schemata = _vokabular['schemas'] as Map;
      for (final name in ['createVariantGroup', 'updateVariantGroup', 'getVariantGroup']) {
        for (final k in _schluessel(((schemata[name] as Map)['data'] as Map)['variantGroup'])) {
          expect(g.containsKey(k), isTrue, reason: '$name: VariantGroup.$k');
        }
      }
      expect(_schluessel((schemata['listVariantGroups'] as Map)['data'])..sort(), ['nextCursor', 'variantGroups']);
      for (final k in ['key', 'label', 'values']) {
        expect(((g['attributes'] as List).first as Map).containsKey(k), isTrue, reason: 'VariantAttribute.$k');
      }
      for (final k in ['articleId', 'variantAttributes']) {
        expect(((g['variants'] as List).first as Map).containsKey(k), isTrue, reason: 'VariantGroupMember.$k');
      }
      expect((((schemata['addVariant'] as Map)['data'] as Map)['article'] as Map)['__'], 'artikel',
          reason: 'addVariant antwortet mit dem Artikel wie createArticle');
    });
  });

  // ---- idempotencyKey (ohne ihn keine sichere Wiederholung) ----------------------

  group('idempotencyKey', () {
    test('leer (= fehlt), nur Leerraum oder ueber 120 Zeichen: keine Variantenanfrage geht hinaus', () async {
      final falsch = ['', '   ', 'x' * (inventoryIdempotencyKeyMax + 1)];
      var geprueft = 0;
      for (final (name, fallName) in _schreiben) {
        for (final schluessel in falsch) {
          final (:lager, :anfragen) = _client([_vertrag(fallName)]);
          final p = {..._params(fallName), 'idempotencyKey': schluessel};
          expect(await _fang(schreibAufruf(lager, name, p)), _anfragefehler, reason: '$name mit "$schluessel"');
          expect(anfragen, isEmpty, reason: '$name: mit "$schluessel" gesendet');
          geprueft += 1;
        }
      }
      expect(geprueft, _schreiben.length * falsch.length);
      // Genau 120 Zeichen gehen hinaus: die Grenze ist eingeschlossen.
      final (:lager, :anfragen) = _client([_vertrag('add_variant')]);
      await schreibAufruf(lager, 'addVariant', {..._params('add_variant'), 'idempotencyKey': 'x' * inventoryIdempotencyKeyMax});
      expect(anfragen, hasLength(1));
    });

    test('eine Wiederholung sendet dieselbe Anfrage noch einmal und liefert die gespeicherte Antwort', () async {
      expect(_params('add_variant_replayed'), _params('add_variant'));
      final (:lager, :anfragen) = _client([_vertrag('add_variant'), _vertrag('add_variant_replayed')]);
      final anfrage = varianteErgaenzen(_params('add_variant'));
      final a = await lager.addVariant(anfrage);
      final b = await lager.addVariant(anfrage);
      expect(_gesendet(anfragen[0]), _gesendet(anfragen[1]));
      expect(a.toJson(), b.toJson());
      expect(a.variantGroupId, 'auto69');
      expect(a.variantAttributes, {'farbe': 'grün'});
    });
  });

  // ---- Pruefung vor dem Senden ------------------------------------------------------

  group('Anfrage', () {
    test('was ohne Netz sicher falsch ist, geht nie hinaus', () async {
      const rot = VariantInput(variantAttributes: {'farbe': 'rot'});
      final faelle = <String, Future<Object?> Function(InventoryClient l)>{
        'createMatrix true mit variants': (l) => l.createVariantGroup(CreateVariantGroupRequest(
            idempotencyKey: 'k', name: _gruppe.name, attributes: _gruppe.attributes, createMatrix: true, variants: const [rot])),
        'createMatrix true mit leeren variants': (l) => l.createVariantGroup(CreateVariantGroupRequest(
            idempotencyKey: 'k', name: _gruppe.name, attributes: _gruppe.attributes, createMatrix: true, variants: const [])),
        'variants[1].unitPriceCents ausserhalb 2^53': (l) => l.createVariantGroup(CreateVariantGroupRequest(
            idempotencyKey: 'k',
            name: _gruppe.name,
            attributes: _gruppe.attributes,
            variants: const [rot, VariantInput(variantAttributes: {'farbe': 'blau'}, unitPriceCents: 9007199254740992)])),
        'defaults.unitPriceCents ausserhalb 2^53': (l) => l.createVariantGroup(CreateVariantGroupRequest(
            idempotencyKey: 'k',
            name: _gruppe.name,
            attributes: _gruppe.attributes,
            defaults: const VariantGroupDefaultsInput(unitPriceCents: -9007199254740992))),
        'defaults.clear mit fremdem Feld': (l) => l.createVariantGroup(CreateVariantGroupRequest(
            idempotencyKey: 'k',
            name: _gruppe.name,
            attributes: _gruppe.attributes,
            defaults: const VariantGroupDefaultsInput(clear: {'name'}))),
        'addVariant ohne variantGroupId': (l) =>
            l.addVariant(const AddVariantRequest(idempotencyKey: 'k', variantGroupId: '', variantAttributes: {'farbe': 'rot'})),
        'addVariant mit leerer variantGroupId': (l) =>
            l.addVariant(const AddVariantRequest(idempotencyKey: 'k', variantGroupId: ' ', variantAttributes: {'farbe': 'rot'})),
        'addVariant minStockByLocation ausserhalb 2^53': (l) => l.addVariant(const AddVariantRequest(
            idempotencyKey: 'k',
            variantGroupId: 'auto69',
            variantAttributes: {'farbe': 'rot'},
            minStockByLocation: {'haupt': 9007199254740992})),
        'updateVariantGroup ohne Feld': (l) =>
            l.updateVariantGroup(const UpdateVariantGroupRequest(idempotencyKey: 'k', variantGroupId: 'auto61')),
        'updateVariantGroup ohne variantGroupId': (l) =>
            l.updateVariantGroup(const UpdateVariantGroupRequest(idempotencyKey: 'k', variantGroupId: '', name: 'Schürze')),
        'updateVariantGroup active true': (l) =>
            l.updateVariantGroup(const UpdateVariantGroupRequest(idempotencyKey: 'k', variantGroupId: 'auto61', active: true)),
        'updateVariantGroup active false mit Name': (l) => l.updateVariantGroup(const UpdateVariantGroupRequest(
            idempotencyKey: 'k', variantGroupId: 'auto61', active: false, name: 'Schürze alt')),
        'updateVariantGroup active false mit addAttributeValues': (l) => l.updateVariantGroup(const UpdateVariantGroupRequest(
            idempotencyKey: 'k',
            variantGroupId: 'auto61',
            active: false,
            addAttributeValues: {
              'groesse': ['XL']
            })),
        'updateVariantGroup active false mit clearDefaults': (l) => l.updateVariantGroup(const UpdateVariantGroupRequest(
            idempotencyKey: 'k', variantGroupId: 'auto61', active: false, clearDefaults: true)),
        'updateVariantGroup defaults und clearDefaults': (l) => l.updateVariantGroup(const UpdateVariantGroupRequest(
            idempotencyKey: 'k',
            variantGroupId: 'auto61',
            defaults: VariantGroupDefaultsInput(unitPriceCents: 2590),
            clearDefaults: true)),
        'updateVariantGroup defaults.unitPriceCents gesetzt und geleert': (l) => l.updateVariantGroup(
            const UpdateVariantGroupRequest(
                idempotencyKey: 'k',
                variantGroupId: 'auto61',
                defaults: VariantGroupDefaultsInput(unitPriceCents: 2590, clear: {'unitPriceCents'}))),
      };
      for (final MapEntry(key: grund, value: rufe) in faelle.entries) {
        final (:lager, :anfragen) = _client([]);
        expect(await _fang(rufe(lager)), _anfragefehler, reason: grund);
        expect(anfragen, isEmpty, reason: '$grund: gesendet');
      }
    });

    test('die Fehlermeldung nennt die Stelle in variants', () async {
      final (:lager, anfragen: _) = _client([]);
      final e = await _fang(lager.createVariantGroup(CreateVariantGroupRequest(
        idempotencyKey: 'k',
        name: _gruppe.name,
        attributes: _gruppe.attributes,
        variants: const [
          VariantInput(variantAttributes: {'farbe': 'rot'}),
          VariantInput(variantAttributes: {'farbe': 'blau'}, unitPriceCents: 9007199254740992),
        ],
      )));
      expect(e, isA<KasseneckValidationError>().having((x) => x.reason, 'reason', contains('variants[1].unitPriceCents')));
    });

    test('die Grenzen der Gruppe prueft der Server; vier Merkmale, 31 Werte und eine Matrix ueber 100 gehen hinaus', () async {
      List<String> werte(int n) => [for (var i = 1; i <= n; i++) 'W$i'];
      final merkmale = [for (final key in ['a', 'b', 'c', 'd']) VariantAttribute(key: key, label: key.toUpperCase(), values: werte(4))];
      final fehler = _antwort({
        'status': 'error',
        'message': 'Bitte Eingaben prüfen.',
        'data': {
          'code': 'validation',
          'errors': [
            {'field': 'attributes', 'message': 'Liste mit 1 bis 3 Merkmalen.'}
          ],
        },
        'code': 'validation',
      });
      final (:lager, :anfragen) = _client([fehler, fehler, fehler]);
      final versuche = [
        () => lager.createVariantGroup(
            CreateVariantGroupRequest(idempotencyKey: 'k1', name: 'Servietten', attributes: merkmale, createMatrix: true)),
        () => lager.createVariantGroup(CreateVariantGroupRequest(
            idempotencyKey: 'k2', name: 'Servietten', attributes: [VariantAttribute(key: 'reihe', label: 'Reihe', values: werte(31))])),
        () => lager.updateVariantGroup(UpdateVariantGroupRequest(
            idempotencyKey: 'k3', variantGroupId: 'auto61', addAttributeValues: {'groesse': werte(40)})),
      ];
      for (final v in versuche) {
        expect(isInventoryError(await _fang(v()), 'validation'), isTrue);
      }
      expect(anfragen, hasLength(3), reason: 'keine Grenze vor dem Senden');
      expect(_gesendet(anfragen[0])['attributes'], hasLength(4));
      expect(4 * 4 * 4 * 4, greaterThan(variantMatrixMax));
      expect(4, greaterThan(variantAttributesMax));
      expect(31, greaterThan(variantValuesMax));
    });

    test('clear und clearDefaults gehen als null hinaus; createMatrix ohne variants und createMatrix false mit variants gehen', () async {
      final g = _erfolg({'variantGroup': _schuerze});
      final (:lager, :anfragen) = _client([g, g, g, g, _erfolg({'article': _daten('add_variant')['article']})]);
      await lager.updateVariantGroup(const UpdateVariantGroupRequest(
        idempotencyKey: 'shop-gruppe-3001-v',
        variantGroupId: 'auto61',
        defaults: VariantGroupDefaultsInput(stockTracked: true, clear: {'unitPriceCents'}),
      ));
      expect(_gesendet(anfragen[0]), {
        'idempotencyKey': 'shop-gruppe-3001-v',
        'variantGroupId': 'auto61',
        'defaults': {'unitPriceCents': null, 'stockTracked': true},
      });
      await lager.updateVariantGroup(
          const UpdateVariantGroupRequest(idempotencyKey: 'shop-gruppe-3001-w', variantGroupId: 'auto61', clearDefaults: true));
      expect(_gesendet(anfragen[1]), {'idempotencyKey': 'shop-gruppe-3001-w', 'variantGroupId': 'auto61', 'defaults': null});
      await lager.createVariantGroup(gruppeAnlegen(_params('create_variant_group_matrix')));
      expect(_gesendet(anfragen[2]), _params('create_variant_group_matrix'));
      final mitFalse = {..._params('create_variant_group_variants'), 'createMatrix': false};
      await lager.createVariantGroup(gruppeAnlegen(mitFalse));
      expect(_gesendet(anfragen[3]), mitFalse, reason: 'nur createMatrix true schliesst variants aus');
      await lager.addVariant(const AddVariantRequest(
          idempotencyKey: 'shop-variante-1', variantGroupId: 'auto69', variantAttributes: {'farbe': 'grün'}));
      expect(_gesendet(anfragen[4]), {'idempotencyKey': 'shop-variante-1', 'variantGroupId': 'auto69', 'variantAttributes': {'farbe': 'grün'}});
    });

    test('active: false allein geht hinaus (Stilllegen), jede Wiederholung ebenso', () async {
      final (:lager, :anfragen) = _client([_vertrag('update_variant_group_deactivate'), _vertrag('update_variant_group_deactivate')]);
      final anfrage = gruppeAendern(_params('update_variant_group_deactivate'));
      expect(anfrage.active, isFalse);
      final a = await lager.updateVariantGroup(anfrage);
      final b = await lager.updateVariantGroup(anfrage);
      expect(a.active, isFalse);
      expect(a.toJson(), b.toJson());
      expect(_gesendet(anfragen[0]), {'idempotencyKey': 'shop-gruppe-3002-aus', 'variantGroupId': 'auto69', 'active': false});
    });
  });

  // ---- Antwort ------------------------------------------------------------------

  group('Antwort', () {
    test('Bruchzahl im Vorgabepreis, fehlende Listen, Variante ohne Kennung oder Werte, die keine Texte sind, sind Antwortfehler', () async {
      final kaputte = <Map<String, Object?>>[
        {'defaults': {'unitPriceCents': 2490.5}},
        {'defaults': {'unitPriceCents': '2490'}},
        {'defaults': {'vatRate': '20'}},
        {'defaults': {'stockTracked': 'ja'}},
        {'defaults': {'unit': 7}},
        {'defaults': {'groupId': false}},
        {'defaults': [2490]},
        {'attributes': null},
        {'attributes': {}},
        {'variants': null},
        {
          'variants': [
            {'variantAttributes': {'farbe': 'rot'}}
          ]
        },
        {
          'attributes': [
            {'key': 'groesse', 'label': 'Größe', 'values': 'S'}
          ]
        },
        {
          'attributes': [
            {'key': 'groesse', 'label': 'Größe', 'values': ['S', 2]}
          ]
        },
        {
          'attributes': [
            {'label': 'Größe', 'values': ['S']}
          ]
        },
        {'attributes': ['groesse']},
        {'id': ''},
      ];
      for (final kaputt in kaputte) {
        final (:lager, anfragen: _) = _client([
          _erfolg({'variantGroup': {..._schuerze, ...kaputt}})
        ]);
        expect(await _fang(lager.getVariantGroup('auto61')), _antwortfehler, reason: jsonEncode(kaputt));
      }
      expect(await _fang(_client([_erfolg({})]).lager.getVariantGroup('auto61')), _antwortfehler);
      expect(await _fang(_client([_erfolg({'variantGroups': {}})]).lager.listVariantGroups()), _antwortfehler);
      expect(await _fang(_client([_erfolg({'variantGroups': [_schuerze], 'nextCursor': 7})]).lager.listVariantGroups()),
          _antwortfehler);
    });

    test('fehlende Vorgaben sind leer, nur gesendete Vorgaben stehen im Modell; null gilt als nicht gesendet', () async {
      final (:lager, anfragen: _) = _client([
        _erfolg({'variantGroup': {..._schuerze}..remove('defaults')}),
        _erfolg({
          'variantGroup': {
            ..._schuerze,
            'defaults': {'unitPriceCents': 2490, 'unit': null, 'groupId': 'textil'}
          }
        }),
        _erfolg({
          'variantGroup': {
            ..._schuerze,
            'defaults': {'unitPriceCents': 2490.0}
          }
        }),
      ]);
      expect((await lager.getVariantGroup('auto61')).defaults.toJson(), isEmpty);
      final g = await lager.getVariantGroup('auto61');
      expect(g.defaults.toJson(), {'unitPriceCents': 2490, 'groupId': 'textil'});
      expect(g.defaults.unit, isNull);
      // Wie im JS-Zwilling: 2490.0 ist eine Ganzzahl (JSON kennt keinen Unterschied).
      expect((await lager.getVariantGroup('auto61')).defaults.unitPriceCents, 2490);
    });

    test('die gelesenen Listen sind unveraenderlich', () async {
      final (:lager, anfragen: _) = _client([_vertrag('get_variant_group')]);
      final g = await lager.getVariantGroup('auto61');
      expect(() => g.attributes.add(const VariantAttribute(key: 'x', label: 'X', values: ['1'])), throwsUnsupportedError);
      expect(() => g.attributes.first.values.add('XXL'), throwsUnsupportedError);
      expect(() => g.variants.first.variantAttributes['farbe'] = 'gelb', throwsUnsupportedError);
    });
  });

  // ---- Fehler ------------------------------------------------------------------

  group('Fehler', () {
    test('variant_already_exists nennt Feld und bestehende Variante, invalid_variant_attributes die Feldfehler', () async {
      final e = await _fang(schreibAufruf(
          _client([_vertrag('error_add_variant_exists')]).lager, 'addVariant', _params('error_add_variant_exists')));
      expect(isInventoryError(e, 'variant_already_exists'), isTrue);
      expect((e! as KasseneckApiError).details['articleId'], 'auto70');
      expect((e as KasseneckApiError).details['field'], 'variantAttributes');
      final e2 = await _fang(schreibAufruf(_client([_vertrag('error_add_variant_invalid_attributes')]).lager, 'addVariant',
          _params('error_add_variant_invalid_attributes')));
      expect(isInventoryError(e2, 'invalid_variant_attributes'), isTrue);
      expect((e2! as KasseneckApiError).details['field'], 'variantAttributes.farbe');
      expect([for (final f in inventoryFieldErrors(e2)) f.field], ['variantAttributes.farbe']);
    });

    test('too_many_positions traegt das Feld (variants), variant_group_inactive und variant_group_not_found am Code', () async {
      final zuViel = _params('error_create_variant_group_too_many_positions');
      expect((zuViel['variants'] as List).length, lessThanOrEqualTo(variantMatrixMax), reason: 'nicht die Grenze, das Schreibbudget');
      final e = await _fang(schreibAufruf(
          _client([_vertrag('error_create_variant_group_too_many_positions')]).lager, 'createVariantGroup', zuViel));
      expect(isInventoryError(e, 'too_many_positions'), isTrue);
      expect((e! as KasseneckApiError).details['field'], 'variants');
      for (final (fallName, endpunkt) in [
        ('error_add_variant_group_inactive', 'addVariant'),
        ('error_get_variant_group_not_found', 'getVariantGroup'),
      ]) {
        final f = await _fang(schreibAufruf(_client([_vertrag(fallName)]).lager, endpunkt, _params(fallName)));
        expect(inventoryErrorCode(f), (_fall(fallName)['response'] as Map)['code'], reason: fallName);
      }
      const limit = KasseneckApiError('addVariant', 'Höchstens 250 aktive Varianten je Variantengruppe.', code: 'variant_limit');
      expect(isInventoryError(limit, 'variant_limit'), isTrue);
    });
  });

  // ---- Ereignisse ------------------------------------------------------------------

  group('Ereignisse', () {
    final ereignisse = (_lager['webhookEvents'] as List)
        .cast<Map<String, dynamic>>()
        .where((e) => (e['event'] as String).startsWith('variant_group.'))
        .toList();

    test('variant_group.created|updated tragen die Gruppe wie getVariantGroup', () {
      expect(inventoryWebhookEvents.sublist(inventoryWebhookEvents.length - 2), ['variant_group.created', 'variant_group.updated']);
      expect({for (final e in ereignisse) e['event']}, {'variant_group.created', 'variant_group.updated'});
      for (final e in ereignisse) {
        final body = e['body'] as Map<String, dynamic>;
        final ereignis = parseInventoryWebhookEvent(jsonEncode(body));
        expect(ereignis, isA<InventoryVariantGroupEvent>(), reason: e['event'] as String);
        expect(ereignis!.type, e['event']);
        expect((ereignis as InventoryVariantGroupEvent).data.toJson(), body['data']);
      }
      // Stilllegen der Gruppe: genau ein variant_group.updated mit active false und eingefrorener Liste.
      final still =
          ereignisse.where((e) => e['event'] == 'variant_group.updated' && ((e['body'] as Map)['data'] as Map)['active'] == false);
      expect(still, hasLength(1));
      expect((((still.single['body'] as Map)['data'] as Map)['variants'] as List), hasLength(3));
      final erstes = _kopie(ereignisse.first['body'] as Map<String, dynamic>);
      final kaputt = {
        ...erstes,
        'data': {
          ...erstes['data'] as Map,
          'defaults': {'unitPriceCents': 24.9}
        }
      };
      expect(() => parseInventoryWebhookEvent(jsonEncode(kaputt)), throwsA(_antwortfehler));
    });

    test('zwei Zustellungen derselben Gruppe ordnet updatedAt, nicht die Ankunft', () {
      final gelesen = [
        for (final e in ereignisse.where((e) => ((e['body'] as Map)['data'] as Map)['id'] == 'auto69'))
          parseInventoryWebhookEvent(jsonEncode(e['body']))! as InventoryVariantGroupEvent,
      ];
      expect(gelesen.length, greaterThan(1));
      // Spaet zugestellt zuerst: der Empfaenger behaelt den Stand mit dem neuesten updatedAt.
      final stand = <String, VariantGroup>{};
      for (final e in gelesen.reversed) {
        final alt = stand[e.data.id];
        if (alt == null || (e.data.updatedAt ?? '').compareTo(alt.updatedAt ?? '') > 0) stand[e.data.id] = e.data;
      }
      expect(stand['auto69']!.active, isFalse);
      expect(stand['auto69']!.updatedAt, '2026-10-06T08:02:50.000Z');
    });
  });
}
