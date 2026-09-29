import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/receipt_layout.dart';

/// Gespeichertes Zeilenmodell (Form 0.x/9.x oder 1.0) -> Form `/v3`, gegen
/// echte Ausgaben: die 40 Goldens, wie 0.31.0 sie festgeschrieben hat
/// (`test/fixtures/vor-1.0/layouts-0.31.json`, byteweise aus dem npm-Repo,
/// dort von `scripts/layouts-vor-1.0.mjs` aus git e4b2887 gezogen), und
/// dieselben Goldens heute (`expected/*.lines.json` im Vertrag). Zwilling von
/// `test/stored-layout.test.ts` (Richtung `fromStoredLayout`).

final _alt = jsonDecode(File('test/fixtures/vor-1.0/layouts-0.31.json').readAsStringSync()) as Map<String, dynamic>;
final _paare = (_alt['pairs'] as List).cast<Map<String, dynamic>>();

Map<String, dynamic> _golden(String pfad) =>
    jsonDecode(File('test/fixtures/vertrag/$pfad').readAsStringSync()) as Map<String, dynamic>;

void main() {
  test('Golden-Paare: die 40 Zeilenmodelle von 0.31.0, byteweise wie im npm-Repo, jedes mit einem heutigen Golden', () {
    expect(sha256.convert(File('test/fixtures/vor-1.0/layouts-0.31.json').readAsBytesSync()).toString(),
        'a92202a7db8b5c03a2d3c819a85259919c448434a164509c5b453b9cab40f2b1');
    expect(_alt['version'], '0.31.0');
    expect(_alt['ref'], 'e4b2887');
    expect(_paare, hasLength(40));
    // Die Paare tragen wirklich die innere Form, sonst pruefte der Vergleich nichts.
    for (final p in _paare) {
      final layout = p['layout'] as Map<String, dynamic>;
      expect(layout.containsKey('regelwerk') && !layout.containsKey('ruleset'), isTrue, reason: '${p['before']}');
      expect(File('test/fixtures/vertrag/${p['after']}').existsSync(), isTrue, reason: '${p['after']}');
    }
    final toene = {
      for (final p in _paare)
        for (final z in ((p['layout'] as Map)['lines'] as List).cast<Map>())
          if (z['ton'] != null) z['ton'],
    };
    expect(toene, {'belegart', 'warnung'});
  });

  test('storedLayoutJson: jedes 0.31-Zeilenmodell ergibt genau das heutige Golden, auch in der Reihenfolge', () {
    for (final p in _paare) {
      final neu = _golden(p['after'] as String);
      final gelesen = storedLayoutJson(p['layout']);
      expect(gelesen, neu, reason: '${p['after']}');
      expect(jsonEncode(gelesen), jsonEncode(neu), reason: '${p['after']} (Reihenfolge)');
      // Die Form 1.0 geht unveraendert durch.
      expect(jsonEncode(storedLayoutJson(neu)), jsonEncode(neu), reason: '${p['after']} (Form 1.0)');
      // Und der Leser macht daraus dasselbe Zeilenmodell wie aus dem Golden.
      expect(ReceiptLayout.fromJson(gelesen)!.toJson(), ReceiptLayout.fromJson(neu)!.toJson(), reason: '${p['after']}');
    }
  });

  test('storedLayoutJson: Unlesbares und halb Lesbares wird null, ein unbekannter Ton bleibt woertlich', () {
    const zeile = {'kind': 'text', 'text': 'X', 'align': 'left', 'bold': false};
    for (final roh in <Object?>[
      null, 'x', 42, const <Object>[], const <String, Object>{}, const {'lines': 'x'},
      // halb lesbar: leere Zeilen, eine Zeile kein Objekt, kein paperSize
      const {'lines': <Object>[], 'paperSize': 'mm80', 'regelwerk': 2},
      const {'lines': [zeile, 'kaputt'], 'paperSize': 'mm80', 'regelwerk': 2},
      const {'lines': [zeile, null], 'paperSize': 'mm80', 'regelwerk': 2},
      const {'lines': [zeile], 'regelwerk': 2},
      const {'lines': [zeile], 'paperSize': '', 'regelwerk': 2},
    ]) {
      expect(storedLayoutJson(roh), isNull, reason: jsonEncode(roh));
    }
    const fremd = {
      'lines': [
        {'kind': 'banner', 'text': 'X', 'ton': 'neu'},
      ],
      'paperSize': 'mm80',
      'regelwerk': 2,
    };
    expect(jsonEncode(storedLayoutJson(fremd)),
        jsonEncode({'lines': [{'kind': 'banner', 'text': 'X', 'tone': 'neu'}], 'paperSize': 'mm80', 'ruleset': 2}));
    // Beide Namen: der englische gewinnt, an seiner Stelle.
    expect(
        jsonEncode(storedLayoutJson({
          'regelwerk': 1,
          'ruleset': 2,
          'paperSize': 'mm80',
          'lines': [
            {'kind': 'banner', 'text': 'X', 'ton': 'warnung', 'tone': 'receipt_type'},
          ],
        })),
        jsonEncode({
          'ruleset': 2,
          'paperSize': 'mm80',
          'lines': [
            {'kind': 'banner', 'text': 'X', 'tone': 'receipt_type'},
          ],
        }));
    // Die Eingabe bleibt unberuehrt.
    final vorher = jsonEncode(_paare.first['layout']);
    storedLayoutJson(_paare.first['layout']);
    expect(jsonEncode(_paare.first['layout']), vorher);
  });

  test('ein halb lesbares Layout im gespeicherten Beleg faellt weg, und der Neubau traegt wieder TESTKASSE', () {
    // Ein echter Beleg aus dem Vertrag (/v3, Kassenweg), gespeichert mit toJson, als Testkasse.
    final faelle = (_golden('v3/antworten/kasse-belege.json')['cases'] as List).cast<Map<String, dynamic>>();
    final antwort = faelle.firstWhere((f) => f['name'] == 'get_zero_receipt')['response'] as Map<String, dynamic>;
    final daten = <String, dynamic>{
      ...KasseneckReceipt.fromJson(antwort['data'] as Map<String, dynamic>).toJson(),
      'testCashregister': true,
    };
    const zeile = {'kind': 'text', 'text': 'X', 'align': 'left', 'bold': false};
    for (final halb in <Object>[
      const {'lines': <Object>[], 'paperSize': 'mm80', 'regelwerk': 2},
      const {'lines': [zeile, 'kaputt'], 'paperSize': 'mm80', 'regelwerk': 2},
      const {'lines': [zeile], 'regelwerk': 2},
    ]) {
      final migriert = migrateStoredReceiptJson({...daten, 'layout': halb});
      expect(migriert.containsKey('layout'), isFalse, reason: jsonEncode(halb));
      final gelesen = KasseneckReceipt.fromJson(migriert);
      final druck = receiptLayoutFromResult(gelesen);
      expect(druck.fromServer, isFalse, reason: jsonEncode(halb));
      expect(druck.paperSize, KeckPaperSize.mm58);
      expect(gelesen.testCashregister, isTrue);
    }
    // Ein ganzes Layout bleibt und gewinnt.
    final ganz = _golden(_paare.first['after'] as String);
    final mit = KasseneckReceipt.fromJson(migrateStoredReceiptJson({...daten, 'layout': ganz}));
    expect(receiptLayoutFromResult(mit).fromServer, isTrue);
  });
}
