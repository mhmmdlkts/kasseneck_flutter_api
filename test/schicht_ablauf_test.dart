import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/models/receipt_grid.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/register.dart';
import 'package:kasseneck_api/src/aufrufe.dart';
import 'package:kasseneck_api/src/v3.dart';

/// Schicht-Ablauf der Kasse (Zwilling von `test/schicht-ablauf.test.ts`, npm
/// 1.28.0): Zwischenzaehlung, Zaehlung vor der Auszahlung, letzte Schicht,
/// Teile des Solls, Trinkgeld-Arten, Spaltenbreite und die Z-Bon-Zeilen dazu.
/// Die Antworten des Servers im Vertrag prueft `kasse_schicht_test.dart`.

Map<String, dynamic> _json(String pfad) => jsonDecode(File(pfad).readAsStringSync()) as Map<String, dynamic>;

({RegisterReceiptClient client, List<http.Request> anfragen}) _kasse(Object? data) {
  final anfragen = <http.Request>[];
  final transport = RegisterTransport(
    idToken: () async => 'id-token',
    sessionId: () async => 'sess-1',
    cashregisterId: 'KASSE1',
    httpClient: MockClient((r) async {
      anfragen.add(r);
      return http.Response.bytes(
        utf8.encode(jsonEncode({'status': 'success', 'message': '', 'data': data})),
        200,
        headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'},
      );
    }),
  );
  return (client: RegisterReceiptClient(transport), anfragen: anfragen);
}

Map<String, dynamic> _params(http.Request r) => (jsonDecode(r.body) as Map)['params'] as Map<String, dynamic>;

final Matcher _anfragefehler = isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'request');
final Matcher _antwortfehler = isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'response');

Map<String, dynamic> get _stand => {
      'drawer': {'id': 'haupt_KASSE1', 'name': 'Hauptlade', 'shiftMode': true, 'cashregisterId': 'KASSE1'},
      'rights': {'shift': true, 'cashMove': true, 'cashView': true, 'drawer': true},
      'tipClaims': [],
      'tips': [],
      'shift': null,
    };

void main() {
  group('recordMyShiftCount', () {
    test('sendet Schicht, Betrag, Stueckelung, Kommentar und Schluessel; liest count', () async {
      final (:client, :anfragen) = _kasse({'count': {'expectedCents': 29400, 'countedCents': 29000, 'differenceCents': -400}});
      final r = await client.recordMyShiftCount(
        idempotencyKey: 'zz-1',
        shiftId: 'haupt_KASSE1_s2',
        countedCents: 29000,
        denominations: {'20000': 1, '5000': 1, '2000': 2},
        comment: 'Kassensturz',
      );
      expect((r.expectedCents, r.countedCents, r.differenceCents), (29400, 29000, -400));
      expect(_params(anfragen.single), {
        'idempotencyKey': 'zz-1',
        'shiftId': 'haupt_KASSE1_s2',
        'countedCents': 29000,
        'denominations': {'20000': 1, '5000': 1, '2000': 2},
        'comment': 'Kassensturz',
        'cashregisterId': 'KASSE1',
      });
      expect(anfragen.single.url.path, endsWith('/recordMyShiftCount'));
    });

    test('gehoert zu den Kassen-Aufrufen und ist ein Aufruf mit Wirkung; 0 ist ein gueltiger Betrag', () async {
      expect(Aufrufe.alle, contains('recordMyShiftCount'));
      expect(unknownOutcomeCalls, contains('recordMyShiftCount'));
      final (:client, :anfragen) = _kasse({'count': {'expectedCents': 0, 'countedCents': 0, 'differenceCents': 0}});
      await client.recordMyShiftCount(idempotencyKey: 'k', shiftId: 's1', countedCents: 0);
      expect(_params(anfragen.single)['countedCents'], 0);
    });

    test('fehlende Kennung, fehlender Schluessel und krummer Betrag werfen vor dem Senden', () async {
      final (:client, :anfragen) = _kasse({});
      final faelle = <Future<Object?> Function()>[
        () => client.recordMyShiftCount(idempotencyKey: 'k', shiftId: '', countedCents: 100),
        () => client.recordMyShiftCount(idempotencyKey: '', shiftId: 's1', countedCents: 100),
        () => client.recordMyShiftCount(idempotencyKey: 'k', shiftId: 's1', countedCents: 9007199254740992),
      ];
      for (final f in faelle) {
        await expectLater(f(), throwsA(_anfragefehler));
      }
      expect(anfragen, isEmpty);
    });

    test('eine Antwort ohne Ganzzahl ist ein Antwortfehler, nie 0', () async {
      final (:client, anfragen: _) = _kasse({'count': {'expectedCents': '29400', 'countedCents': 29000, 'differenceCents': -400}});
      await expectLater(client.recordMyShiftCount(idempotencyKey: 'k', shiftId: 's1', countedCents: 29000), throwsA(_antwortfehler));
      final (client: ohne, anfragen: _) = _kasse(<String, dynamic>{});
      await expectLater(ohne.recordMyShiftCount(idempotencyKey: 'k', shiftId: 's1', countedCents: 1), throwsA(_antwortfehler));
    });
  });

  group('closeMyShift: countedBeforePayout', () {
    test('geht nur als true hinaus', () async {
      final (:client, :anfragen) = _kasse({'status': 'recount'});
      await client.closeMyShift(idempotencyKey: 'k', shiftId: 's1', countedCents: 100, countedBeforePayout: true);
      await client.closeMyShift(idempotencyKey: 'k', shiftId: 's1', countedCents: 100);
      expect(_params(anfragen[0])['countedBeforePayout'], isTrue);
      expect(_params(anfragen[1]).containsKey('countedBeforePayout'), isFalse);
    });
  });

  group('Kassenstand', () {
    test('lastShift: Nummer, Zeit und Name; ohne Namen null; null bleibt null; fehlt bleibt fehlend', () async {
      final mit = await _kasse({..._stand, 'lastShift': {'number': 7, 'closedAt': '2026-09-25T20:00:00.000Z', 'closedByName': 'Anna Chef'}})
          .client
          .getMyDrawerState();
      expect((mit.lastShift!.number, mit.lastShift!.closedAt, mit.lastShift!.closedByName), (7, '2026-09-25T20:00:00.000Z', 'Anna Chef'));
      final ohneName =
          await _kasse({..._stand, 'lastShift': {'number': 7, 'closedAt': '2026-09-25T20:00:00.000Z', 'closedByName': null}}).client.getMyDrawerState();
      expect(ohneName.lastShift!.closedByName, isNull);
      final keine = await _kasse({..._stand, 'lastShift': null}).client.getMyDrawerState();
      expect(keine.lastShift, isNull);
      expect(keine.toJson().containsKey('lastShift'), isTrue);
      final fehlt = await _kasse(_stand).client.getMyDrawerState();
      expect(fehlt.toJson().containsKey('lastShift'), isFalse);
    });

    test('lastShift ohne Zeit oder mit krummer Nummer: Antwort kaputt', () async {
      for (final kaputt in [
        {'number': 7, 'closedByName': 'x'},
        {'number': '7', 'closedAt': '2026-09-25T20:00:00.000Z', 'closedByName': null},
      ]) {
        await expectLater(_kasse({..._stand, 'lastShift': kaputt}).client.getMyDrawerState(), throwsA(_antwortfehler));
      }
    });

    test('Teile des Solls, Trinkgeld in der Lade und Zwischenzaehlungen werden gelesen, fehlend bleibt fehlend', () async {
      final offen = {
        'id': 'haupt_KASSE1_s2', 'drawerId': 'haupt_KASSE1', 'number': 2, 'status': 'open',
        'openingCounted': false,
        'expectedParts': [
          {'key': 'opening', 'cents': 15000},
          {'key': 'cash_sales', 'cents': 9400},
          {'key': 'interim_difference', 'cents': -200},
          {'key': 'kuenftig', 'cents': 5},
        ],
        'cashTipsInDrawerCents': 400,
        'interimCounts': 1,
        'interimDifferenceCents': -200,
      };
      final s = (await _kasse({..._stand, 'shift': offen}).client.getMyDrawerState()).shift!;
      expect(s.openingCounted, isFalse);
      expect([for (final t in s.expectedParts!) (t.key, t.cents)], [('opening', 15000), ('cash_sales', 9400), ('interim_difference', -200), ('kuenftig', 5)]);
      expect((s.cashTipsInDrawerCents, s.interimCounts, s.interimDifferenceCents), (400, 1, -200));
      expect(s.toJson()['expectedParts'], offen['expectedParts']);
      final knapp = (await _kasse({..._stand, 'shift': {'id': 'x_s1', 'drawerId': 'x', 'number': 1, 'status': 'open'}}).client.getMyDrawerState()).shift!;
      expect((knapp.openingCounted, knapp.expectedParts, knapp.interimCounts, knapp.differenceParts, knapp.countedBeforePayoutCents),
          (null, null, null, null, null));
      for (final k in ['openingCounted', 'expectedParts', 'cashTipsInDrawerCents', 'interimCounts', 'interimDifferenceCents', 'differenceParts', 'countedBeforePayoutCents']) {
        expect(knapp.toJson().containsKey(k), isFalse, reason: k);
      }
    });

    test('interim_difference ist eine Bewegungsart des Servers, keine von Hand', () {
      expect(movementTypes, contains('interim_difference'));
      expect(manualMovementTypes, isNot(contains('interim_difference')));
      expect(expectedPartKeys, ['opening', 'cash_sales', 'cash_tips', 'cancellations', 'cash_in', 'cash_out', 'interim_difference']);
      expect(differencePartTypes, ['interim', 'closing']);
    });
  });

  group('Z-Bon des Ablaufs (shift-ablauf-cases.json)', () {
    final faelle = (_json('test/fixtures/vertrag/shift-ablauf-cases.json')['cases'] as Map).cast<String, Map<String, dynamic>>();
    final vorlage = jsonDecode(File('test/fixtures/vertrag/v3/antworten/kasse.json').readAsStringSync()) as Map<String, dynamic>;
    final erfolg = (((vorlage['endpoints'] as Map)['closeMyShift'] as Map)['cases'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((f) => f['case'] == 'success_manager');

    Future<ShiftSummaryReceipt> bon(Map<String, dynamic> receipt) async {
      final fall = jsonDecode(jsonEncode(erfolg)) as Map<String, dynamic>;
      ((fall['response'] as Map)['data'] as Map<String, dynamic>)['receipt'] = receipt;
      final (:client, anfragen: _) = _kasse((fall['response'] as Map)['data']);
      return (await client.closeMyShift(idempotencyKey: 'k', shiftId: 's', countedCents: 0)).receipt!;
    }

    for (final e in faelle.entries) {
      test('${e.key}: Zeichen fuer Zeichen wie im npm-Paket', () async {
        final layout = shiftReceiptLayout(await bon(e.value['receipt'] as Map<String, dynamic>), paperSize: PosPaperSize.mm58);
        expect(ReceiptGrid.render(layout, charsPerLine: 32).toText(), e.value['grid32'], reason: '32');
        final breit = shiftReceiptLayout(await bon(e.value['receipt'] as Map<String, dynamic>), paperSize: PosPaperSize.mm80);
        expect(ReceiptGrid.render(breit, charsPerLine: 48).toText(), e.value['grid48'], reason: '48');
      });
    }

    test('ohne die neuen Felder bleibt der Bon wie bisher: keine der neuen Zeilen', () async {
      final roh = jsonDecode(jsonEncode(faelle['z-bon-ablauf']!['receipt'])) as Map<String, dynamic>;
      for (final k in ['openingCounted', 'interimDifferenceCents', 'differenceParts', 'countedBeforePayoutCents', 'countedBeforePayoutDenominations']) {
        roh.remove(k);
      }
      final text = ReceiptGrid.render(shiftReceiptLayout(await bon(roh), paperSize: PosPaperSize.mm80), charsPerLine: 48).toText();
      expect(text, isNot(matches(RegExp('nicht gezählt|Zwischenzählung|davon'))));
      expect(text, isNot(contains('Gezählt')) , reason: 'ohne countedBeforePayout kein „Gezaehlt“ vor dem Ist');
    });

    test('eine Zwischenzaehlung ohne Differenz faellt in den Teilen weg, der Abschluss bleibt', () async {
      final roh = jsonDecode(jsonEncode(faelle['z-bon-ablauf']!['receipt'])) as Map<String, dynamic>;
      roh['differenceParts'] = [
        {'type': 'interim', 'cents': 0, 'at': '2026-09-26T13:30:00.000Z'},
        {'type': 'closing', 'cents': 0, 'at': null},
      ];
      final text = ReceiptGrid.render(shiftReceiptLayout(await bon(roh), paperSize: PosPaperSize.mm80), charsPerLine: 48).toText();
      expect(text, isNot(contains('davon Zwischenzählung')));
      expect(text, matches(RegExp(r'^davon Abschluss +0,00$', multiLine: true)));
    });
  });

  group('Einstellungen: Trinkgeld-Arten, Start, Spaltenbreite', () {
    test('ohne Angabe keine Standardwerte; wirksam: alle drei Arten, Start Prozent, Breite mittel', () {
      const standard = PosSettings.standard();
      expect(standard.business.toJson().containsKey('tipKinds'), isFalse);
      expect(standard.business.toJson().containsKey('tipStart'), isFalse);
      expect(standard.device.toJson().containsKey('cartWidth'), isFalse);
      expect(posTipKinds(standard.business), PosTipKind.values);
      expect(posTipStart(standard.business), PosTipKind.percent);
      expect(posCartWidth(standard.device), PosCartWidth.medium);
      expect(posTipKinds(null), PosTipKind.values);
      expect(PosTipKind.values.map((k) => k.value), ['percent', 'round_up', 'total']);
      expect(PosCartWidth.values.map((k) => k.value), ['narrow', 'medium', 'wide']);
    });

    test('gespeicherte Werte werden gelesen und gehen unveraendert wieder hinaus', () {
      final b = PosBusinessSettings.fromJson({'tipKinds': ['round_up', 'total'], 'tipStart': 'round_up'});
      expect(b.tipKinds, [PosTipKind.roundUp, PosTipKind.total]);
      expect(b.tipStart, PosTipKind.roundUp);
      expect(b.toJson()['tipKinds'], ['round_up', 'total']);
      expect(b.toJson()['tipStart'], 'round_up');
      expect(PosDeviceSettings.fromJson({'cartWidth': 'wide'}).cartWidth, PosCartWidth.wide);
      expect(PosDeviceSettings.fromJson({'cartWidth': 'wide'}).toJson()['cartWidth'], 'wide');
    });

    test('falsche Form und Werte der inneren Form 0.x kommen nicht herein', () {
      final schlecht = PosBusinessSettings.fromJson({'tipKinds': <String>[], 'tipStart': 5});
      expect((schlecht.tipKinds, schlecht.tipStart), (null, null));
      expect(schlecht.unknownValues, isEmpty);
      expect(PosBusinessSettings.fromJson({'tipKinds': ['prozent']}).tipKinds, isNull);
      expect(PosBusinessSettings.fromJson({'tipStart': 'aufrunden'}).tipStart, isNull);
      expect(PosDeviceSettings.fromJson({'cartWidth': 'breit'}).cartWidth, isNull);
      expect(PosBusinessSettings.fromJson({'tipKinds': ['prozent']}).unknownValues, isEmpty);
    });

    test('der Start liegt immer unter den angebotenen Arten', () {
      PosBusinessSettings b(List<String> arten, [String? start]) => PosBusinessSettings.fromJson({'tipKinds': arten, 'tipStart': ?start});
      expect(posTipStart(b(['round_up', 'total'], 'total')), PosTipKind.total);
      expect(posTipStart(b(['percent', 'total'], 'round_up')), PosTipKind.percent);
      expect(posTipStart(b(['round_up', 'total'])), PosTipKind.roundUp);
      expect(posTipStart(b(['total'], 'percent')), PosTipKind.total);
    });

    test('ein neuer Wert des Servers bleibt stehen und wird gemeldet; nur Geaendertes geht hinaus', () {
      final stand = PosSettings.fromJson({
        'business': {'tipKinds': ['percent', 'voucher'], 'tipStart': 'round_up'},
        'device': {'cartWidth': 'huge'},
      });
      expect(stand.business.tipKinds, isNull);
      expect(stand.business.tipStart, PosTipKind.roundUp);
      expect(stand.business.toJson()['tipKinds'], ['percent', 'voucher'], reason: 'unveraendert zurueck');
      expect(stand.device.toJson()['cartWidth'], 'huge');
      expect(unknownPosSettingValues(stand), ['business.tipKinds', 'device.cartWidth']);
      final vorher = PosBusinessSettings.fromJson({'tipKinds': ['percent', 'round_up', 'total']});
      final nachher = vorher.merge({'tipKinds': ['percent']});
      expect(posSettingsChanges(vorher.toJson(), nachher.toJson()), {'tipKinds': ['percent']});
    });

    test('merge: Optionales bleibt beim Mischen, wird ersetzt oder mit null entfernt; Unsinn wirft', () {
      final b = PosBusinessSettings.fromJson({'tipKinds': ['percent', 'total'], 'tipStart': 'total'});
      expect(b.merge({'clock': false}).tipKinds, [PosTipKind.percent, PosTipKind.total]);
      expect(b.merge({'tipStart': 'percent'}).tipStart, PosTipKind.percent);
      expect(b.merge({'tipKinds': null}).tipKinds, isNull);
      expect(() => b.merge({'tipKinds': 'percent'}), throwsArgumentError);
      expect(() => b.merge({'tipKinds': ['prozent']}), throwsArgumentError);
      expect(() => b.merge({'tipStart': 5}), throwsArgumentError);
      final d = PosDeviceSettings.fromJson({'cartWidth': 'narrow'});
      expect(d.merge({'touch': true}).cartWidth, PosCartWidth.narrow);
      expect(d.merge({'cartWidth': 'wide'}).cartWidth, PosCartWidth.wide);
      expect(() => d.merge({'cartWidth': 'schmal'}), throwsArgumentError);
    });

    test('Listen und Wertemengen am Vertrag (surface.json)', () {
      final s = _json('test/fixtures/vertrag/surface.json')['pos'] as Map<String, dynamic>;
      expect(posBusinessOptionalChoices, s['posBusinessOptionalChoices']);
      expect(posDeviceOptionalChoices, s['posDeviceOptionalChoices']);
      expect(posBusinessValues['tipKinds'], ['percent', 'round_up', 'total']);
      expect(posBusinessValues['tipStart'], ['percent', 'round_up', 'total']);
      expect(posDeviceValues['cartWidth'], ['narrow', 'medium', 'wide']);
    });

    test('saveBusiness: tipKinds und tipStart gehen hinaus; ausserhalb, leere Liste, Dublette, falscher Typ werfen vor dem Senden', () async {
      final (:client, :anfragen) = _kasse({
        'business': {...const PosBusinessSettings().toJson(), 'tipKinds': ['percent', 'round_up'], 'tipStart': 'percent', 'tipMode': 'both'},
      });
      final einstellungen = PosSettingsClient(client.transport, deviceId: 'dev_1');
      final stand = await einstellungen.saveBusiness({'tipKinds': ['percent', 'round_up'], 'tipStart': 'percent'});
      expect(_params(anfragen.single)['business'], {'tipKinds': ['percent', 'round_up'], 'tipStart': 'percent'});
      expect(stand.tipKinds, [PosTipKind.percent, PosTipKind.roundUp]);
      for (final schlecht in <Map<String, dynamic>>[
        {'tipKinds': <String>[]},
        {'tipKinds': ['percent', 'percent']},
        {'tipKinds': ['prozent']},
        {'tipKinds': 'percent'},
        {'tipStart': 'prozent'},
        {'tipStart': 'half'},
        {'tipStart': null, 'tipKinds': null},
      ]) {
        await expectLater(einstellungen.saveBusiness(schlecht), throwsA(_anfragefehler), reason: '$schlecht');
      }
      expect(anfragen, hasLength(1));
    });

    test('saveDevice: cartWidth geht hinaus, ein fremder Wert wirft', () async {
      final (:client, :anfragen) = _kasse({'device': {...const PosDeviceSettings().toJson(), 'cartWidth': 'narrow'}});
      final einstellungen = PosSettingsClient(client.transport, deviceId: 'dev_1');
      final stand = await einstellungen.saveDevice({'cartWidth': 'narrow'});
      expect(_params(anfragen.single)['device'], {'cartWidth': 'narrow'});
      expect(stand.cartWidth, PosCartWidth.narrow);
      await expectLater(einstellungen.saveDevice({'cartWidth': 'schmal'}), throwsA(_anfragefehler));
      expect(anfragen, hasLength(1));
    });
  });
}
