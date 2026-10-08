import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/register.dart';

/// Inventur zaehlen an der Kasse (seit 10.7), Zwilling von `pos/inventur.ts`
/// im npm-Paket 1.8.0: `parseQuantityMilli` gegen die gemeinsamen Prueffaelle
/// des Vertrags, die fuenf Aufrufe des Kassenwegs gegen
/// `v3/antworten/kasse.json` (dass jeder Fall mit seinen Parametern hinausgeht
/// und sein Code ankommt, prueft `kasse_v3_test.dart`) und der Ausgang nach
/// einem Zeitlimit.

Map<String, dynamic> _json(String pfad) => jsonDecode(File(pfad).readAsStringSync()) as Map<String, dynamic>;

final _endpunkte = _json('test/fixtures/vertrag/v3/antworten/kasse.json')['endpoints'] as Map<String, dynamic>;

const _inventur = [
  'listMyStocktakes',
  'listMyStocktakeItems',
  'listMyStocktakeCounts',
  'recordMyStocktakeCount',
  'voidMyStocktakeCount',
];

Iterable<Map<String, dynamic>> _faelle(String endpunkt) => ((_endpunkte[endpunkt] as Map)['cases'] as List)
    .cast<Map<String, dynamic>>()
    .where((f) => f['method'] == 'POST' && f['params'] is Map && !(f['params'] as Map).containsKey(r'$body'));

/// Ohne `null`-Werte, rekursiv (fehlt und `null` sind im Modell gleich).
Object? _ohneNull(Object? w) => switch (w) {
  Map m => {
    for (final e in m.entries)
      if (e.value != null) e.key: _ohneNull(e.value),
  },
  List l => [for (final x in l) _ohneNull(x)],
  _ => w,
};

({RegisterReceiptClient client, List<http.Request> anfragen}) _kasse(
  Future<http.Response> Function(http.Request r) antwort, {
  Duration? timeout,
}) {
  final anfragen = <http.Request>[];
  final transport = RegisterTransport(
    idToken: () async => 'id-token',
    sessionId: () async => 'sess-1',
    cashregisterId: 'KASSE1',
    httpClient: MockClient((r) {
      anfragen.add(r);
      return antwort(r);
    }),
    timeout: timeout,
  );
  return (client: RegisterReceiptClient(transport), anfragen: anfragen);
}

http.Response _antwort(Map<String, dynamic> fall) => http.Response.bytes(
  utf8.encode(jsonEncode(fall['response'])),
  fall['httpStatus'] as int,
  headers: {
    'content-type': 'application/json',
    for (final e in (fall['headers'] as Map).cast<String, String>().entries) e.key.toLowerCase(): e.value,
  },
);

String _s(Object? v) => v is String ? v : '';

Future<Object?> _rufe(RegisterReceiptClient c, String endpunkt, Map<String, dynamic> p) => switch (endpunkt) {
  'listMyStocktakes' => c.listMyStocktakes(locationId: p['locationId'] as String?, status: p['status'] as String?),
  'listMyStocktakeItems' => c.listMyStocktakeItems(
    stocktakeId: _s(p['stocktakeId']),
    openOnly: p['openOnly'] as bool?,
    limit: p['limit'] as int?,
    cursor: p['cursor'] as String?,
  ),
  'listMyStocktakeCounts' => c.listMyStocktakeCounts(
    stocktakeId: _s(p['stocktakeId']),
    articleId: p['articleId'] as String?,
    ownOnly: p['ownOnly'] as bool?,
    limit: p['limit'] as int?,
    cursor: p['cursor'] as String?,
  ),
  'recordMyStocktakeCount' => c.recordMyStocktakeCount(
    idempotencyKey: _s(p['idempotencyKey']),
    stocktakeId: _s(p['stocktakeId']),
    articleId: _s(p['articleId']),
    quantity: p['quantity'] as int,
    condition: p['condition'] as String?,
    note: p['note'] as String?,
    cashregisterId: p['cashregisterId'] as String?,
  ),
  'voidMyStocktakeCount' => c.voidMyStocktakeCount(
    idempotencyKey: _s(p['idempotencyKey']),
    stocktakeId: _s(p['stocktakeId']),
    countId: _s(p['countId']),
    reason: _s(p['reason']),
  ),
  _ => throw StateError(endpunkt),
};

Object? _modell(Object? ergebnis) => switch (ergebnis) {
  List<Stocktake> l => {
    'stocktakes': [for (final s in l) s.toJson()],
  },
  StocktakeItemPage s => s.toJson(),
  StocktakeCountPage s => s.toJson(),
  StocktakeCountResult s => s.toJson(),
  _ => throw StateError('unbekanntes Ergebnis $ergebnis'),
};

final Matcher _anfragefehler = isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'request');

void main() {
  group('parseQuantityMilli', () {
    final faelle = (_json('test/fixtures/vertrag/stocktake-quantity-cases.json')['cases'] as List)
        .cast<Map<String, dynamic>>();

    QuantityRule? regel(Object? w) => switch (w) {
      null => null,
      'piece' => QuantityRule.piece,
      'decimal' => QuantityRule.decimal,
      _ => throw StateError('Regel $w'),
    };

    test('die gemeinsamen Prueffaelle des Vertrags, 1:1 wie im npm-Paket', () {
      // 50 Faelle in 1.8.0; weniger hiesse, die Datei waere nicht die gezogene.
      expect(faelle, hasLength(50));
      for (final f in faelle) {
        final text = f['text'] as String;
        final unit = f['unit'] as String?;
        expect(
          parseQuantityMilli(text, unit, rule: regel(f['rule'])),
          f['expected'],
          reason: '"$text" $unit rule ${f['rule']}',
        );
      }
    });

    test('ohne Regel gilt die Vorgabe der Einheit, mit Regel schlaegt sie die Einheit', () {
      expect(parseQuantityMilli('2,5', 'Stk'), isNull);
      expect(parseQuantityMilli('2,5', 'Stk', rule: QuantityRule.decimal), 2500);
      expect(parseQuantityMilli('0,5', 'kg'), 500);
      expect(parseQuantityMilli('0,5', 'kg', rule: QuantityRule.piece), isNull);
      // Die Drei-Ziffern-Regel gilt bei jeder Einheit und jeder Regel.
      for (final r in [null, QuantityRule.piece, QuantityRule.decimal]) {
        for (final u in [null, 'Stk', 'kg', 'l', 'g']) {
          expect(parseQuantityMilli('1.000', u, rule: r), isNull, reason: '$u $r');
          expect(parseQuantityMilli('12.500', u, rule: r), isNull, reason: '$u $r');
        }
      }
      expect(parseQuantityMilli('1,000', 'kg'), 1000);
      expect(parseQuantityMilli('0.500', 'kg'), 500);
    });

    test('ohne Gleitkomma und ohne Ueberlauf: lange Ziffernfolgen werden null, nie eine falsche Zahl', () {
      expect(parseQuantityMilli('9007199254740', 'Stk'), 9007199254740000);
      expect(parseQuantityMilli('9007199254740,991', 'kg'), 9007199254740991);
      expect(parseQuantityMilli('9007199254740,992', 'kg'), isNull);
      expect(parseQuantityMilli('9' * 30, 'Stk'), isNull);
      expect(parseQuantityMilli('0,1', 'kg'), 100);
      expect(parseQuantityMilli('0,3', 'kg'), 300, reason: '0.1 + 0.2 waere in Gleitkomma schief');
      expect(parseQuantityMilli(' 12 ', 'Stk'), 12000, reason: 'Leerraum aussen wie String.trim in JS');
      expect(parseQuantityMilli('１２', 'Stk'), isNull, reason: 'nur ASCII-Ziffern');
    });

    test('Leerraum genau wie String.prototype.trim in JS (eigener Fall, nicht in der gemeinsamen Datei)', () {
      // U+0085 (NEL) entfernt Dart-trim, JS-trim nicht: im JS-Zwilling ist das null.
      expect(parseQuantityMilli('\u00851', 'Stk'), isNull);
      expect(parseQuantityMilli('1\u0085', 'Stk'), isNull);
      // Was JS-trim entfernt, entfernt auch dieser Weg.
      for (final z in [
        '\t',
        '\n',
        '\v',
        '\f',
        '\r',
        ' ',
        '\u00a0',
        '\u1680',
        '\u2000',
        '\u200a',
        '\u2028',
        '\u2029',
        '\u202f',
        '\u205f',
        '\u3000',
        '\ufeff',
      ]) {
        expect(parseQuantityMilli('${z}12$z', 'Stk'), 12000, reason: 'U+${z.codeUnitAt(0).toRadixString(16)}');
      }
      // Kein Leerraum fuer JS: U+200B (Zero Width Space) bleibt stehen.
      expect(parseQuantityMilli('\u200b12', 'Stk'), isNull);
    });
  });

  group('Vertrag kasse.json', () {
    test('jede Erfolgsantwort der fuenf Aufrufe liest sich verlustfrei', () async {
      var gelesen = 0;
      for (final endpunkt in _inventur) {
        for (final fall in _faelle(endpunkt).where((f) => (f['response'] as Map)['status'] == 'success')) {
          final (:client, anfragen: _) = _kasse((_) async => _antwort(fall));
          final ergebnis = await _rufe(client, endpunkt, fall['params'] as Map<String, dynamic>);
          expect(
            _ohneNull(_modell(ergebnis)),
            _ohneNull((fall['response'] as Map)['data']),
            reason: '$endpunkt/${fall['case']}',
          );
          gelesen++;
        }
      }
      expect(gelesen, greaterThanOrEqualTo(20));
    });

    test('vor dem Senden abgewiesen werden genau diese Faelle (wie im npm-Paket)', () async {
      final abgewiesen = <String>{};
      for (final endpunkt in _inventur) {
        for (final fall in _faelle(endpunkt)) {
          final (:client, :anfragen) = _kasse((_) async => _antwort(fall));
          try {
            await _rufe(client, endpunkt, fall['params'] as Map<String, dynamic>);
          } on KasseneckValidationError catch (e) {
            if (e.kind == 'request' && anfragen.isEmpty) abgewiesen.add('$endpunkt/${fall['case']}');
          } on Object {
            // Fehler des Servers: hier nicht Thema.
          }
        }
      }
      expect(abgewiesen, {
        'listMyStocktakeItems/data_missing',
        'listMyStocktakeCounts/data_missing',
        'recordMyStocktakeCount/data_missing',
        'recordMyStocktakeCount/key_missing',
        'voidMyStocktakeCount/data_missing',
        'voidMyStocktakeCount/key_missing',
        'voidMyStocktakeCount/reason_missing',
      });
    });

    test('Fehler kommen mit ihrem Code an und stehen in posErrorCodes', () async {
      for (final endpunkt in _inventur) {
        for (final fall in _faelle(endpunkt).where((f) => (f['response'] as Map)['status'] == 'error')) {
          final code = (fall['response'] as Map)['code'] ?? ((fall['response'] as Map)['data'] as Map?)?['code'];
          final (:client, :anfragen) = _kasse((_) async => _antwort(fall));
          Object? fehler;
          try {
            await _rufe(client, endpunkt, fall['params'] as Map<String, dynamic>);
          } catch (e) {
            fehler = e;
          }
          if (anfragen.isEmpty) continue; // vorab abgewiesen, siehe oben
          expect(isPosError(fehler, code as String), isTrue, reason: '$endpunkt/${fall['case']}: $code');
        }
      }
      for (final c in ['stocktake_not_open', 'article_not_in_scope', 'count_already_voided', 'too_many_counts']) {
        expect(posErrorCodes, contains(c));
      }
    });
  });

  group('Senden', () {
    final zaehlung = _faelle('recordMyStocktakeCount').firstWhere((f) => f['case'] == 'success_manager');

    test(
      'recordMyStocktakeCount: Kasse der Anmeldung, eine ausdrueckliche ersetzt sie; Seriennummern wie gegeben',
      () async {
        final (:client, :anfragen) = _kasse((_) async => _antwort(zaehlung));
        await client.recordMyStocktakeCount(
          idempotencyKey: 'k-kipferl-1',
          stocktakeId: 'inv_laden',
          articleId: 'art_kuchen',
          quantity: 0,
        );
        final ohne = (jsonDecode(anfragen.last.body) as Map)['params'] as Map;
        expect(ohne['cashregisterId'], 'KASSE1');
        expect(ohne['quantity'], 0, reason: '0 = leer gezaehlt, geht hinaus');
        expect(ohne.containsKey('serialNumbers'), isFalse, reason: 'keine erfundene leere Liste');
        await client.recordMyStocktakeCount(
          idempotencyKey: 'k-kipferl-2',
          stocktakeId: 'inv_laden',
          articleId: 'art_kuchen',
          quantity: 2000,
          serialNumbers: ['SN-1', 'SN-2'],
          cashregisterId: 'KASSE2',
        );
        final mit = (jsonDecode(anfragen.last.body) as Map)['params'] as Map;
        expect(mit['cashregisterId'], 'KASSE2');
        expect(mit['serialNumbers'], ['SN-1', 'SN-2']);
        expect(anfragen.last.url.toString(), 'https://kasse.kasseneck.at/api/v3/recordMyStocktakeCount');
      },
    );

    test('vor dem Senden: leere Kasse, leere Kennungen, ungueltiger Schluessel', () async {
      final (:client, :anfragen) = _kasse((_) async => _antwort(zaehlung));
      await expectLater(
        client.recordMyStocktakeCount(
          idempotencyKey: 'k',
          stocktakeId: 'inv_laden',
          articleId: 'art_kuchen',
          quantity: 1000,
          cashregisterId: ' ',
        ),
        throwsA(_anfragefehler),
      );
      await expectLater(
        client.recordMyStocktakeCount(
          idempotencyKey: 'x' * 121,
          stocktakeId: 'inv_laden',
          articleId: 'art_kuchen',
          quantity: 1000,
        ),
        throwsA(_anfragefehler),
      );
      await expectLater(
        client.voidMyStocktakeCount(idempotencyKey: 'k', stocktakeId: 'inv_laden', countId: ' ', reason: 'doppelt'),
        throwsA(_anfragefehler),
      );
      await expectLater(client.listMyStocktakeItems(stocktakeId: ''), throwsA(_anfragefehler));
      expect(anfragen, isEmpty);
    });

    test('listMyStocktakes: ein leerer Standort gilt wie keiner', () async {
      final fall = _faelle('listMyStocktakes').firstWhere((f) => f['case'] == 'success_manager');
      final (:client, :anfragen) = _kasse((_) async => _antwort(fall));
      await client.listMyStocktakes(locationId: '');
      final p = (jsonDecode(anfragen.single.body) as Map)['params'] as Map;
      expect(p.containsKey('locationId'), isFalse);
    });

    test('nach einem Zeitlimit: Zaehlen und Stornieren unklar, Lesen abgelehnt', () async {
      Future<Object?> fehler(Future<Object?> Function(RegisterReceiptClient c) aufruf) async {
        final (:client, anfragen: _) = _kasse(
          (_) => Completer<http.Response>().future,
          timeout: const Duration(milliseconds: 20),
        );
        try {
          await aufruf(client);
        } catch (e) {
          return e;
        }
        return null;
      }

      expect(
        isOutcomeUnknown(
          await fehler(
            (c) => c.recordMyStocktakeCount(
              idempotencyKey: 'k',
              stocktakeId: 'inv_laden',
              articleId: 'art_kuchen',
              quantity: 1000,
            ),
          ),
        ),
        isTrue,
      );
      expect(
        isOutcomeUnknown(
          await fehler(
            (c) => c.voidMyStocktakeCount(
              idempotencyKey: 'k',
              stocktakeId: 'inv_laden',
              countId: 'zk1',
              reason: 'doppelt',
            ),
          ),
        ),
        isTrue,
      );
      for (final lesen in <Future<Object?> Function(RegisterReceiptClient)>[
        (c) => c.listMyStocktakes(),
        (c) => c.listMyStocktakeItems(stocktakeId: 'inv_laden'),
        (c) => c.listMyStocktakeCounts(stocktakeId: 'inv_laden'),
      ]) {
        final f = await fehler(lesen);
        expect(f, isA<KasseneckHttpError>().having((e) => e.outcome, 'outcome', ErrorOutcome.rejected));
      }
    });
  });

  test('Texte des Zaehlbildschirms aus dem Katalog, gefuellt wie in der Web-Kasse', () {
    expect(messageText('stocktake.counted', {'name': 'Kornspitz', 'quantity': '37 Stk'}), 'Kornspitz: 37 Stk gezählt.');
    expect(labelText('stocktake.progress', {'counted': 3, 'total': 12}), '3 von 12 gezählt');
    expect(labelText('stocktake.resend'), 'Erneut senden');
    expect(messageText('stocktake.quantity_invalid'), contains('drei Nachkommastellen'));
  });
}
