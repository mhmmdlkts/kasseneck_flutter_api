import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/models/receipt_grid.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/register.dart';

/// Rabatt-Vorlagen (`business.discountPresets`) und Rabatte auf dem Z-Bon,
/// Zwilling von `rabatt-vorlagen.test.ts` (npm 1.31.0). Die Pruefaelle
/// `discount-preset-cases.json` sind byte-gleich mit dem Backend; `innen` ist die
/// gespeicherte Form (art/prozentBp/betragCents), `aussen` die Drahtform.
Map<String, dynamic> _json(String pfad) => jsonDecode(File(pfad).readAsStringSync()) as Map<String, dynamic>;

final _faelle = _json('test/fixtures/vertrag/discount-preset-cases.json');
final _golden = _json('test/fixtures/kasse/rabatte-z-bon.json');
final _kasse = (_json('test/fixtures/vertrag/v3/antworten/kasse.json')['endpoints'] as Map).cast<String, dynamic>();

const _art = {'prozent': 'percent', 'betrag': 'amount'};
const _feld = {'art': 'kind', 'prozentBp': 'percentBp', 'betragCents': 'amountCents'};

/// Gespeicherte Vorlage -> Drahtform (Schluessel und Art); alles Fremde bleibt.
Object? _draht(Object? v) => v is! Map
    ? v
    : {for (final e in v.entries) _feld[e.key] ?? e.key: e.key == 'art' ? (_art[e.value] ?? e.value) : e.value};
Object? _drahtListe(Object? l) => l is List ? [for (final v in l) _draht(v)] : l;

List<Map<String, dynamic>> _liste(String abschnitt) => (_faelle[abschnitt] as List).cast<Map<String, dynamic>>();

PosBusinessSettings _betrieb(Map<String, dynamic> aussen) => PosBusinessSettings.fromJson(aussen);

List<Map<String, dynamic>> _json2(List<PosDiscountPreset> l) => [for (final v in l) v.toJson()];

/// Der Z-Bon der Vertragsantwort mit Rabatten.
Future<ShiftSummaryReceipt> _zBon(Object? discounts) async {
  final fall = ((_kasse['closeMyShift'] as Map)['cases'] as List).cast<Map<String, dynamic>>().firstWhere((f) => f['case'] == 'success_manager');
  final antwort = jsonDecode(jsonEncode(fall['response'])) as Map<String, dynamic>;
  final bon = (antwort['data'] as Map)['receipt'] as Map<String, dynamic>;
  if (discounts != null) bon['discounts'] = discounts;
  final transport = RegisterTransport(
    idToken: () async => 'id-token',
    sessionId: () async => 'sess-1',
    cashregisterId: 'KASSE1',
    httpClient: MockClient((_) async => http.Response.bytes(utf8.encode(jsonEncode(antwort)), 200, headers: {
          'content-type': 'application/json',
          for (final e in (fall['headers'] as Map).cast<String, String>().entries) e.key.toLowerCase(): e.value,
        })),
  );
  return (await RegisterReceiptClient(transport).closeMyShift(idempotencyKey: 'k', shiftId: 's', countedCents: 0)).receipt!;
}

Map<String, dynamic> _darstellung(ShiftSummaryReceipt bon) {
  final layout = shiftReceiptLayout(bon);
  return {'lines': layout.toJson()['lines'], 'grid32': ReceiptGrid.render(layout, charsPerLine: 32).toText()};
}

void main() {
  group('Vertrag und Katalog', () {
    test('die Faelle sind die des Backends (Abschnitte und Anzahl)', () {
      expect(_faelle.keys.toList(), ['hinweis', 'wirksam', 'chipText', 'spiegelung', 'pruefung', 'bonBlock']);
      expect(_liste('wirksam').length, greaterThanOrEqualTo(5));
      expect(_liste('chipText').length, greaterThanOrEqualTo(9));
      expect(_liste('spiegelung').length, greaterThanOrEqualTo(5));
      expect(_liste('pruefung').length, greaterThanOrEqualTo(27));
      expect(_liste('bonBlock').length, greaterThanOrEqualTo(4));
    });

    test('Arten, Grenzen und Fehlercode wie im Backend und in surface.json', () {
      final pos = (_json('test/fixtures/vertrag/surface.json')['pos'] as Map);
      expect([for (final k in PosDiscountPresetKind.values) k.value], pos['discountPresetKind']);
      expect(posBusinessOptionalLists, pos['posBusinessOptionalLists']);
      expect(discountPresetsMax, 5);
      expect(invalidDiscountPreset, 'invalid_discount_preset');
      expect(posErrorCodes, contains(invalidDiscountPreset));
    });
  });

  group('wirksame Vorlagen', () {
    for (final f in _liste('wirksam')) {
      test('${f['name']}', () {
        final aussen = (f['aussen'] as Map).cast<String, dynamic>();
        final erwartet = f['erwartetAussen'] as List;
        final stand = _betrieb(aussen);
        final hat = aussen.containsKey('discountPresets') || aussen.containsKey('discountChips');
        // Vorlagen ueberstimmen die Standard-Chips, ohne Vorlagen gilt discountChips.
        final soll = hat ? erwartet : _json2(posDiscountPresets(const PosBusinessSettings()));
        expect(_json2(posDiscountPresets(stand)), soll);
        if (aussen.containsKey('discountPresets')) {
          expect(stand.discountPresets, isNotNull);
        } else {
          expect(stand.discountPresets, isNull);
        }
      });
    }
  });

  group('Chip-Text', () {
    for (final f in _liste('chipText')) {
      test('${f['chip']}', () {
        final v = _betrieb({'discountPresets': [f['vorlageAussen']]}).discountPresets!.single;
        expect(discountPresetChipText(v), f['chip']);
      });
    }
  });

  group('Spiegelung nach discountChips', () {
    for (final f in _liste('spiegelung')) {
      test('${f['name']}', () {
        final liste = _betrieb({'discountPresets': _drahtListe(f['vorlagen'])}).discountPresets!;
        expect(discountChipsFromPresets(liste), f['rabattChips']);
      });
    }
  });

  group('Pruefung', () {
    for (final f in _liste('pruefung')) {
      test('${f['name']}', () {
        final r = checkDiscountPresets(_drahtListe(f['eingabe']));
        expect(r.ok, f['ok']);
        if (r.ok) {
          expect(_json2(r.value), _drahtListe(f['wert']));
        } else {
          expect(r.code, f['code']);
          expect(
            [for (final e in r.errors) {'index': e.index, 'feld': e.field, 'meldung': e.message}],
            [
              for (final e in (f['fehler'] as List).cast<Map<String, dynamic>>())
                {'index': e['index'], 'feld': e['feld'] == null ? null : (_feld[e['feld']] ?? e['feld']), 'meldung': e['meldung']},
            ],
          );
        }
      });
    }

    test('Eindeutigkeit ohne Rolle von Gross und Klein, auch mit Umlauten', () {
      Map<String, dynamic> eins(String name) => {'name': name, 'kind': 'amount', 'amountCents': 100};
      expect(checkDiscountPresets([eins('Stammkunde'), eins('STAMMKUNDE')]).ok, isFalse);
      expect(checkDiscountPresets([eins('Ärger'), eins('ärger')]).ok, isFalse);
      expect(checkDiscountPresets([eins('Stammkunde'), eins('Stammkunden')]).ok, isTrue);
      // Getrimmt verglichen.
      expect(checkDiscountPresets([eins('Stammkunde'), eins(' stammkunde ')]).ok, isFalse);
    });

    test('Fehlersaetze sind die Saetze des Katalogs', () {
      for (final g in DiscountPresetReason.values) {
        expect(messageText(discountPresetMessages[g]!), isNotEmpty);
      }
      expect(labelText('discount_presets.title'), 'Rabatt-Vorlagen');
      expect(labelText('shift_receipt.discounts'), 'Rabatte');
      expect(messageText('discount.preset_over_total'), 'Der Rabatt ist höher als der Betrag, auf den er gilt.');
    });
  });

  group('Leser und Schreiben', () {
    test('unbekannte Art und Teilformen fallen weg, die Liste bleibt', () {
      final s = _betrieb({
        'discountPresets': [
          {'name': 'A', 'kind': 'percent', 'percentBp': 500},
          {'name': 'B', 'kind': 'staffel', 'percentBp': 500},
          {'name': 'C', 'kind': 'amount'},
          {'name': 'D', 'kind': 'amount', 'amountCents': 1.5},
          'x',
          null,
          {'kind': 'amount', 'amountCents': 5},
          {'name': 'E', 'kind': 'amount', 'amountCents': 250},
        ],
      });
      expect(_json2(s.discountPresets!), [
        {'name': 'A', 'kind': 'percent', 'percentBp': 500},
        {'name': 'E', 'kind': 'amount', 'amountCents': 250},
      ]);
      // Keine Liste: das Feld fehlt, die Chips gelten. Leere Liste bleibt (keine Chips).
      expect(_betrieb({'discountPresets': 'x'}).discountPresets, isNull);
      expect(_betrieb({'discountPresets': <Object>[]}).discountPresets, isEmpty);
      // Ein Konto ohne das Feld: Standard unveraendert, kein Schluessel in toJson.
      expect(const PosBusinessSettings().toJson().containsKey('discountPresets'), isFalse);
    });

    test('Rundreise: toJson gibt die Liste wie gelesen aus, merge setzt und entfernt sie', () {
      final s = _betrieb({
        'discountPresets': [
          {'name': 'Stammkunde', 'kind': 'amount', 'amountCents': 500},
        ],
      });
      expect(s.toJson()['discountPresets'], [
        {'name': 'Stammkunde', 'kind': 'amount', 'amountCents': 500},
      ]);
      final neu = const PosBusinessSettings().merge({
        'discountPresets': [
          {'name': 'A', 'kind': 'percent', 'percentBp': 1000},
        ],
      });
      expect(_json2(neu.discountPresets!), [
        {'name': 'A', 'kind': 'percent', 'percentBp': 1000},
      ]);
      expect(neu.merge({'discountPresets': null}).discountPresets, isNull);
      expect(() => const PosBusinessSettings().merge({'discountPresets': 'x'}), throwsArgumentError);
    });

    test('nur geaenderte Vorlagen gehen als ganze Liste, die Pruefung laeuft vor dem Senden', () async {
      final vorher = const PosBusinessSettings().toJson();
      final nachher = const PosBusinessSettings().merge({
        'discountPresets': [
          {'name': 'Stammkunde', 'kind': 'amount', 'amountCents': 500},
        ],
      }).toJson();
      final aenderung = posSettingsChanges(vorher, nachher);
      expect(aenderung, {
        'discountPresets': [
          {'name': 'Stammkunde', 'kind': 'amount', 'amountCents': 500},
        ],
      });
      final log = <http.Request>[];
      final client = PosSettingsClient(
        RegisterTransport(
          idToken: () async => 'tok',
          sessionId: () async => 'sess',
          cashregisterId: 'KASSE1',
          httpClient: MockClient((r) async {
            log.add(r);
            return http.Response(
              jsonEncode({
                'status': 'success',
                'data': {'business': nachher},
              }),
              200,
              headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'},
            );
          }),
        ),
        deviceId: 'GERAET1',
      );
      final stand = await client.saveBusiness(aenderung);
      expect(log, hasLength(1));
      expect(jsonDecode(log.single.body)['params']['business'], aenderung);
      expect(_json2(stand.discountPresets!), [
        {'name': 'Stammkunde', 'kind': 'amount', 'amountCents': 500},
      ]);
      // Ungueltig: wirft vor dem Senden, mit Vorlage, Feld, Satz und Code.
      await expectLater(
        client.saveBusiness({
          'discountPresets': [
            {'name': 'A', 'kind': 'percent', 'percentBp': 1005},
          ],
        }),
        throwsA(isA<KasseneckValidationError>().having(
            (e) => e.reason, 'reason', matches(RegExp(r'discountPresets\[0\]\.percentBp: Prozent zwischen 0,1 und 100.*invalid_discount_preset')))),
      );
      await expectLater(client.saveBusiness({'discountPresets': 'x'}), throwsA(isA<KasseneckValidationError>()));
      expect(log, hasLength(1));
    });
  });

  group('Rabatte auf dem Z-Bon', () {
    for (final f in _liste('bonBlock')) {
      test('bonBlock: ${f['name']}', () {
        final lines = discountBlockLines([
          for (final r in (f['rabatte'] as List).cast<Map<String, dynamic>>())
            ShiftDiscount(name: r['name'] as String, cents: r['cents'] as int, count: r['anzahl'] as int),
        ]);
        expect([for (final z in lines) {'label': z.label, 'cents': z.cents}], f['zeilen']);
      });
    }

    test('ein voll stornierter Name (Betrag 0) entfaellt, auch die Summe zaehlt ihn nicht', () {
      expect(
        discountBlockLines(const [ShiftDiscount(name: 'A', cents: 0, count: 2), ShiftDiscount(name: 'B', cents: 300, count: 1)]),
        [const DiscountBlockLine(label: 'B (1×)', cents: -300)],
      );
      expect(discountBlockLines(const [ShiftDiscount(name: 'A', cents: 0, count: 2)]), isEmpty);
    });

    test('ohne Rabatte byte-gleich (Feld fehlt, null, leere Liste)', () async {
      final basis = jsonEncode(shiftReceiptLayout(await _zBon(null)).toJson());
      for (final wert in [null, <Object>[]]) {
        expect(jsonEncode(shiftReceiptLayout(await _zBon(wert)).toJson()), basis);
      }
    });

    test('Block „Rabatte“ nach dem Unbar-Block, vor den Zaehlern, wie der Golden', () async {
      final faelle = {
        'eins': [
          {'name': 'Stammkunde', 'cents': 500, 'count': 1},
        ],
        'mehrere': [
          {'name': 'Mitarbeiter-Rabatt', 'cents': 1200, 'count': 3},
          {'name': 'Stammkunde', 'cents': 500, 'count': 1},
        ],
        'unbenannt': [
          {'name': '', 'cents': 100, 'count': 2},
          {'name': 'Stammkunde', 'cents': 50, 'count': 1},
        ],
      };
      for (final e in faelle.entries) {
        final golden = _golden[e.key] as Map<String, dynamic>;
        final bon = await _zBon(e.value);
        expect(bon.discounts!.map((r) => r.toJson()).toList(), golden['discounts'], reason: e.key);
        final d = _darstellung(bon);
        expect(d['lines'], golden['lines'], reason: '${e.key}: Zeilenmodell');
        expect(d['grid32'], golden['grid32'], reason: '${e.key}: Raster 32');
      }
      // Der Block steht vor „Belege“ und enthaelt die Summe nur ab zwei Eintraegen.
      final text = _darstellung(await _zBon(faelle['mehrere']))['grid32'] as String;
      expect(text.indexOf('Rabatte'), lessThan(text.indexOf('Belege')));
      expect(_darstellung(await _zBon(faelle['eins']))['grid32'], isNot(contains('Rabatte gesamt')));
      expect(jsonEncode(_darstellung(await _zBon(faelle['mehrere']))['lines']), contains('Mitarbeiter-Rabatt (3×)'));
    });

    test('Laufstand: discounts wird gelesen und ausgegeben, fehlt = null', () {
      const mit = ShiftRunningTotals(
        cashSalesCents: 0,
        cashCancellationsCents: 0,
        nonCashByMethod: [],
        receiptCount: 0,
        cancellationCount: 0,
        cashInCents: 0,
        cashOutCents: 0,
        tips: [],
        openingsWithoutSale: 0,
        discounts: [ShiftDiscount(name: 'A', cents: 5, count: 1)],
      );
      expect(mit.toJson()['discounts'], [
        {'name': 'A', 'cents': 5, 'count': 1},
      ]);
    });

    test('ein kaputter Eintrag ist ein Antwortfehler', () async {
      await expectLater(_zBon([
        {'name': 'Stammkunde', 'cents': 1.5, 'count': 1},
      ]), throwsA(anything));
    });
  });
}
