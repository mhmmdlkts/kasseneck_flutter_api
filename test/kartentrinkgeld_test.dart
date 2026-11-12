import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/register.dart';

/// Kartentrinkgeld an der Kasse (Backend-Spec 2026-11-11-kartentrinkgeld,
/// Stufe 1 bis 3): Zwilling von `test/kartentrinkgeld.test.ts` im npm-Paket
/// 1.37.0. Dieselben drei Stufen wie bei Bar (`business.tipCardKeptMode`,
/// `tipCardKeptByDefault`), der Not-Aus `tipSelfPayout`, die eine Zeile mit
/// Betrag ([tipStatus]), „Mein Trinkgeld“ ([RegisterReceiptClient.getMyTipBalance]
/// gegen den Vertrag), die Zeile „davon Kartentrinkgeld“ und `cardTips` an der
/// Kasse. Die gemeinsamen Faelle mit dem Backend liegen in
/// `stored/card-tip-cases.json`.
Map<String, dynamic> _json(String pfad) =>
    jsonDecode(File('test/fixtures/vertrag/$pfad').readAsStringSync()) as Map<String, dynamic>;

final _faelle = (_json('stored/card-tip-cases.json')['receipts'] as List).cast<Map<String, dynamic>>();
final _surface = (_json('surface.json')['pos'] as Map).cast<String, dynamic>();
final _kataloge = (_json('v3/v3-vokabular.json')['catalogs'] as Map).cast<String, dynamic>();
final _kasse = ((_json('v3/antworten/kasse.json')['endpoints'] as Map)['getMyTipBalance'] as Map)['cases'] as List;

PosBusinessSettings _mit(Map<String, dynamic> b) => PosBusinessSettings.fromJson(b);

/// Trinkgeld eines Mitarbeiters aus der Drahtform der Prueffaelle.
ShiftTip _tip(Map<String, dynamic> t) => ShiftTip(
      registerUserId: t['registerUserId'] as String,
      name: t['name'] as String?,
      receivedImmediatelyCents: t['receivedImmediatelyCents'] as int,
      retainedCents: t['retainedCents'] as int,
      paidOutCents: t['paidOutCents'] as int,
      refundedByEmployeeCents: (t['refundedByEmployeeCents'] as int?) ?? 0,
      cardTipsTakenCents: t['cardTipsTakenCents'] as int?,
      carriedOverCents: (t['carriedOverCents'] as int?) ?? 0,
      openCents: t['openCents'] as int,
    );

Map<String, dynamic> _fall(String name) =>
    _kasse.cast<Map<String, dynamic>>().firstWhere((c) => c['case'] == name);

/// Ruft `getMyTipBalance` mit den Parametern des Falls gegen dessen Antwort.
Future<({TipBalance? ergebnis, Object? fehler, Map<String, dynamic> gesendet})> _rufe(Map<String, dynamic> f) async {
  final anfragen = <http.Request>[];
  final client = RegisterReceiptClient(RegisterTransport(
    idToken: () async => 'id-token',
    sessionId: () async => 'sess-1',
    cashregisterId: 'KASSE1',
    httpClient: MockClient((r) async {
      anfragen.add(r);
      return http.Response.bytes(
        utf8.encode(jsonEncode(f['response'])),
        f['httpStatus'] as int,
        headers: {
          'content-type': 'application/json',
          for (final e in (f['headers'] as Map).cast<String, String>().entries) e.key.toLowerCase(): e.value,
        },
      );
    }),
  ));
  final p = (f['params'] as Map).cast<String, dynamic>();
  TipBalance? ergebnis;
  Object? fehler;
  try {
    ergebnis = await client.getMyTipBalance(drawerId: p['drawerId'] as String?, cashregisterId: p['cashregisterId'] as String?);
  } catch (e) {
    fehler = e;
  }
  expect(anfragen.single.url.toString(), 'https://kasse.kasseneck.at/api/v3/getMyTipBalance');
  final gesendet = ((jsonDecode(anfragen.single.body) as Map)['params'] as Map).cast<String, dynamic>();
  // Die Kasse der Anmeldung legt der Transport bei; nennt der Fall sie nicht, zaehlt sie nicht.
  if (!p.containsKey('cashregisterId')) gesendet.remove('cashregisterId');
  return (ergebnis: ergebnis, fehler: fehler, gesendet: gesendet);
}

void main() {
  test('Einstellungen: Karten-Stufe und Vorbelegung optional wie bei Bar, Not-Aus optional, Katalog wie der Vertrag', () {
    expect(posBusinessOptionalChoices, contains('tipCardKeptMode'));
    expect(posBusinessOptionalFields, containsAll(['tipCardKeptByDefault', 'tipSelfPayout']));
    expect(posBusinessOptionalFields, _surface['posBusinessOptionalFields']);
    expect(posBusinessOptionalChoices, _surface['posBusinessOptionalChoices']);
    final standard = const PosBusinessSettings().toJson();
    for (final k in ['tipCardKeptMode', 'tipCardKeptByDefault', 'tipSelfPayout']) {
      expect(standard.containsKey(k), isFalse, reason: k);
    }
    final werte = [for (final m in PosTipKeptMode.values) m.value];
    expect(posBusinessValues['tipCardKeptMode'], werte);
    expect(_surface['tipCardKeptMode'], werte);
    final katalog = _kataloge['KASSE_BETRIEB_WERTE.tipCardKeptMode'] as Map;
    expect(werte, katalog.values.toList());
    expect(legacyValues['tipCardKeptMode'], {for (final e in katalog.entries) e.key as String: e.value as String});
    // Lesen: fehlend = ask, aus, an; deutsche Altwerte kommen nicht ins Modell.
    expect(posTipCardKeptMode(const PosBusinessSettings()), PosTipKeptMode.ask);
    expect(posTipCardKeptMode(_mit({'tipCardKeptMode': 'never'})), PosTipKeptMode.never);
    final alt = _mit({'tipCardKeptMode': 'immer'});
    expect(alt.tipCardKeptMode, isNull);
    expect(alt.toJson().containsKey('tipCardKeptMode'), isFalse);
    // Ein unbekannter Wert eines neueren Servers bleibt woertlich erhalten, die Stufe gilt als ask.
    final neu = _mit({'tipCardKeptMode': 'sometimes'});
    expect(posTipCardKeptMode(neu), PosTipKeptMode.ask);
    expect(neu.unknownValues['tipCardKeptMode'], 'sometimes');
    expect(posTipCardKeptByDefault(const PosBusinessSettings()), isFalse);
    expect(posTipCardKeptByDefault(_mit({'tipCardKeptByDefault': true})), isTrue);
    expect(posTipCardKeptByDefault(_mit({'tipCardKeptByDefault': 'ja'})), isFalse);
    expect(posTipSelfPayout(const PosBusinessSettings()), isTrue);
    expect(posTipSelfPayout(_mit({'tipSelfPayout': false})), isFalse);
    expect(posTipSelfPayout(null), isTrue);
    // Gelesen wie gesendet, ohne Wert fehlt das Feld.
    final alle = _mit({'tipCardKeptMode': 'always', 'tipCardKeptByDefault': true, 'tipSelfPayout': false});
    expect(alle.toJson(), containsPair('tipCardKeptMode', 'always'));
    expect(alle.toJson(), containsPair('tipCardKeptByDefault', true));
    expect(alle.toJson(), containsPair('tipSelfPayout', false));
  });

  test('merge: Karten-Stufe setzen und mit null entfernen; Schalter nur als Wahrheitswert', () {
    final b = const PosBusinessSettings().merge({'tipCardKeptMode': 'never', 'tipSelfPayout': false});
    expect(b.tipCardKeptMode, PosTipKeptMode.never);
    expect(b.tipSelfPayout, isFalse);
    expect(b.merge({'theme': 'night'}).tipCardKeptMode, PosTipKeptMode.never);
    expect(b.merge({'tipCardKeptMode': null}).tipCardKeptMode, isNull);
    expect(b.merge({'tipSelfPayout': null}).tipSelfPayout, isNull);
    expect(() => b.merge({'tipCardKeptMode': 3}), throwsArgumentError);
    expect(() => b.merge({'tipCardKeptByDefault': 'ja'}), throwsArgumentError);
  });

  test('saveBusiness: Karten-Stufe nur mit einem Wert des Katalogs, Schalter nur als Wahrheitswert', () async {
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
                'data': {
                  'business': {'tipCardKeptMode': 'never', 'tipCardKeptByDefault': true, 'tipSelfPayout': false},
                },
              }),
              200,
              headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'});
        }),
      ),
      deviceId: 'GERAET1',
    );
    final b = await client.saveBusiness({'tipCardKeptMode': 'never', 'tipCardKeptByDefault': true, 'tipSelfPayout': false});
    expect((posTipCardKeptMode(b), posTipCardKeptByDefault(b), posTipSelfPayout(b)), (PosTipKeptMode.never, true, false));
    expect(jsonDecode(log.single.body)['params']['business'],
        {'tipCardKeptMode': 'never', 'tipCardKeptByDefault': true, 'tipSelfPayout': false});
    await expectLater(client.saveBusiness({'tipCardKeptMode': 'nie'}), throwsA(isA<KasseneckValidationError>()));
    await expectLater(client.saveBusiness({'tipCardKeptMode': 'sometimes'}), throwsA(isA<KasseneckValidationError>()));
    await expectLater(client.saveBusiness({'tipSelfPayout': 'aus'}), throwsA(isA<KasseneckValidationError>()));
    expect(log, hasLength(1));
  });

  test('tipKeptFor je Zahlart: bar wie bisher (ohne drittes Argument), Karte nach der Karten-Stufe', () {
    final b = _mit({'tipKeptMode': 'always', 'tipKeptByDefault': false, 'tipCardKeptMode': 'ask', 'tipCardKeptByDefault': true});
    // Bar: unveraendert (die Bar-Stufe), auch mit ausdruecklichem cash.
    expect(tipKeptFor(b), (showSwitch: false, kept: true));
    expect(tipKeptFor(b, null, TipPaymentKind.cash), (showSwitch: false, kept: true));
    // Karte: Schalter, vorbelegt aus tipCardKeptByDefault, die Wahl gewinnt.
    expect(tipKeptFor(b, null, TipPaymentKind.card), (showSwitch: true, kept: true));
    expect(tipKeptFor(b, false, TipPaymentKind.card), (showSwitch: true, kept: false));
    // Karte always/never: kein Schalter, Wahl und Vorbelegung zaehlen nicht.
    for (final wahl in <bool?>[null, true, false]) {
      expect(tipKeptFor(_mit({'tipCardKeptMode': 'always', 'tipCardKeptByDefault': false}), wahl, TipPaymentKind.card),
          (showSwitch: false, kept: true));
      expect(tipKeptFor(_mit({'tipCardKeptMode': 'never', 'tipCardKeptByDefault': true}), wahl, TipPaymentKind.card),
          (showSwitch: false, kept: false));
    }
    // Rot-Probe: die Karten-Stufe aendert nichts an Bar und umgekehrt.
    expect(tipKeptFor(_mit({'tipCardKeptMode': 'always'})), (showSwitch: true, kept: false));
    expect(tipKeptFor(_mit({'tipKeptMode': 'always'}), null, TipPaymentKind.card), (showSwitch: true, kept: false));
    expect(tipKeptFor(_mit({'tipKeptByDefault': true}), null, TipPaymentKind.card), (showSwitch: true, kept: false));
    expect(tipKeptFor(null, null, TipPaymentKind.card), (showSwitch: true, kept: false));
    expect([for (final k in TipPaymentKind.values) k.value], ['cash', 'card']);
  });

  test('tipStatus: die eine Zeile je Zahlart und Ergebnis, mit Betrag; einzeilig', () {
    expect(tipStatus(TipPaymentKind.cash, true), (status: TipStatusKind.kept, key: 'tip.line_cash_kept'));
    expect(tipStatus(TipPaymentKind.cash, false), (status: TipStatusKind.open, key: 'tip.line_cash_open'));
    expect(tipStatus(TipPaymentKind.card, true), (status: TipStatusKind.kept, key: 'tip.line_card_kept'));
    expect(tipStatus(TipPaymentKind.card, false), (status: TipStatusKind.open, key: 'tip.line_card_open'));
    expect([for (final s in TipStatusKind.values) s.value], ['kept', 'open']);
    String zeile(TipPaymentKind m, bool k) => labelText(tipStatus(m, k).key, {'amount': '5,00 €'});
    expect(zeile(TipPaymentKind.cash, true), '5,00 € gleich einstecken');
    expect(zeile(TipPaymentKind.cash, false), '5,00 € in der Lade lassen');
    expect(zeile(TipPaymentKind.card, true), '5,00 € aus der Lade nehmen');
    expect(zeile(TipPaymentKind.card, false), '5,00 € später auszahlen');
    for (final k in [
      'tip.line_cash_kept', 'tip.line_cash_open', 'tip.line_card_kept', 'tip.line_card_open', 'done.tip_open',
      'cancellation.tip_deducted', 'my_tips.overpaid',
    ]) {
      expect(labelText(k, {'amount': '1', 'open': '2', 'name': 'Livia'}), isNot(contains('\n')), reason: k);
    }
    expect(labelText('cancellation.tip_deducted', {'amount': '5,00 €', 'name': 'Livia Lindmayr'}),
        '5,00 € Trinkgeld werden vom Guthaben von Livia Lindmayr abgezogen');
    expect(labelText('my_tips.nothing_open'), 'Nichts offen');
    expect(labelText('shift_receipt.tip_card_taken'), 'davon Kartentrinkgeld');
    expect(messageText('tip.card_kept_setting_hint'), contains('bar aus der Lade'));
    // F1 an der Kasse: gleich behalten nur mit offener Schicht und bekanntem, ausreichendem Soll -- sonst offen.
    expect(
        messageText('tip.card_kept_setting_hint'),
        endsWith('nur bei offener Schicht, mit genug Bargeld in der Lade und für Mitarbeiter, die den Kassenstand sehen – '
            'sonst bleibt es offen.'));
  });

  test('shiftTipLines: „davon Kartentrinkgeld“ nach „genommen“, nur ungleich 0; Soll-Teil card_tips_taken', () {
    final z = shiftTipLines(const ShiftTip(
      registerUserId: 'ru_livia',
      name: 'Livia Lindmayr',
      receivedImmediatelyCents: 500,
      retainedCents: 0,
      paidOutCents: 500,
      cardTipsTakenCents: 500,
      openCents: 0,
    ));
    expect([for (final x in z) (x.key, x.cents)], [
      ('shift_receipt.tip_earned', 500),
      ('shift_receipt.tip_paid_out', 500),
      ('shift_receipt.tip_card_taken', 500),
    ]);
    expect(z[2].text, 'davon Kartentrinkgeld');
    // Ohne das Feld (Server vor 1.37.0, bar) keine Zeile -- wie bisher.
    expect(
        [
          for (final x in shiftTipLines(const ShiftTip(
              registerUserId: 'ru_livia', name: 'L', receivedImmediatelyCents: 500, retainedCents: 0, paidOutCents: 500, openCents: 0)))
            x.key,
        ],
        ['shift_receipt.tip_earned', 'shift_receipt.tip_paid_out']);
    // Mit 0 ebenso keine Zeile; die Zahl geht trotzdem verlustfrei zurueck.
    const null0 = ShiftTipTotals(
        registerUserId: 'ru_livia', receivedImmediatelyCents: 500, retainedCents: 0, paidOutCents: 500, cardTipsTakenCents: 0);
    expect([for (final x in shiftTipLines(null0)) x.key], isNot(contains('shift_receipt.tip_card_taken')));
    expect(null0.toJson()['cardTipsTakenCents'], 0);
    expect(expectedPartKeys, contains('card_tips_taken'));
    expect(expectedPartKeys, _surface['expectedPartKeys']);
    expect(labelText('shift.part_card_tips_taken'), 'Kartentrinkgeld bar genommen');
    expect(tipClaimScopes, (_kataloge['TRINKGELD_ANSPRUCH'] as Map).values.toList());
    expect(tipClaimScopes, _surface['tipClaimScopes']);
    expect(posErrorCodes, contains('not_a_person_login'));
  });

  test('Prueffaelle (Vertrag mit dem Backend): Zeilen und Zeile je Beleg', () {
    expect(_faelle.length, greaterThanOrEqualTo(6));
    for (final f in _faelle) {
      final name = f['name'] as String;
      for (final t in (f['tips'] as Map).values) {
        final zeilen = shiftTipLines(_tip((t as Map).cast<String, dynamic>()));
        expect([for (final z in zeilen) [z.key, z.cents]], f['tipLines'], reason: name);
      }
      final s = f['tipStatus'] as Map?;
      if (s != null) {
        final r = tipStatus(TipPaymentKind.values.byName(s['method'] as String), s['kept'] as bool);
        expect({'status': r.status.value, 'key': r.key}, {'status': s['status'], 'key': s['key']}, reason: name);
      }
    }
  });

  group('getMyTipBalance gegen den Vertrag', () {
    test('Erfolgsfaelle: Modell wie gesendet (offen je Lade, andere Laden, je Person)', () async {
      final erfolg = _kasse.cast<Map<String, dynamic>>().where((c) => (c['response'] as Map)['status'] == 'success').toList();
      expect(erfolg.length, greaterThanOrEqualTo(3));
      for (final f in erfolg) {
        final lauf = await _rufe(f);
        expect(lauf.fehler, isNull, reason: '${f['case']}: ${lauf.fehler}');
        expect(lauf.gesendet, f['params'], reason: f['case'] as String);
        expect(lauf.ergebnis!.toJson(), (f['response'] as Map)['data'], reason: f['case'] as String);
      }
      final andere = (await _rufe(_fall('success_cashier_other_drawer'))).ergebnis!;
      expect(andere.claimScope, 'per_drawer');
      expect([for (final l in andere.otherDrawers) l.toJson()], [
        {'drawerId': 'lade_bar', 'name': 'Bar', 'openCents': 150},
      ]);
      final person = (await _rufe(_fall('success_cashier_per_person'))).ergebnis!;
      expect((person.claimScope, person.openCents, person.otherDrawers.length), ('per_person', 550, 0));
    });

    test('Fehler am Code: Inhaber not_a_person_login, Lade unbekannt, fremde Kasse', () async {
      for (final (name, code) in [
        ('owner', 'not_a_person_login'),
        ('drawer_unknown', 'drawer_not_found'),
        ('foreign_cashregister', 'cashregister_not_assigned'),
      ]) {
        final lauf = await _rufe(_fall(name));
        expect(lauf.fehler, isA<KasseneckApiError>().having((e) => e.code, 'code', code), reason: name);
        expect(isPosError(lauf.fehler, code), isTrue, reason: name);
      }
    });

    test('unlesbare Antwort ist ein Fehler, nie ein Stand mit 0', () async {
      final f = jsonDecode(jsonEncode(_fall('success_cashier'))) as Map<String, dynamic>;
      ((f['response'] as Map)['data'] as Map)['openCents'] = 'viel';
      final lauf = await _rufe(f);
      expect(lauf.ergebnis, isNull);
      expect(
          lauf.fehler,
          isA<KasseneckValidationError>()
              .having((e) => e.kind, 'kind', 'response')
              .having((e) => e.toString(), 'Meldung', contains('openCents')));
    });

    test('ohne Lade gilt die Hauptlade der Kasse; ein leeres drawerId gilt wie keines', () async {
      final lauf = await _rufe({
        ..._fall('success_cashier'),
        'params': <String, dynamic>{'drawerId': ''},
      });
      expect(lauf.gesendet, isEmpty);
    });
  });

  test('Stufe 3: Anspruchs-Modus je Lade / je Person mit Beschriftung je Wert (Kundenbereich), Satz ohne Auszahl-Recht', () {
    // Jeder Wert des Katalogs hat genau eine Beschriftung -- eine neue Stufe ohne Wort waere hier rot.
    expect(tipClaimScopeLabels.keys.toSet(), tipClaimScopes.toSet());
    expect([for (final s in tipClaimScopes) labelText(tipClaimScopeLabels[s]!)], ['Je Kassenlade', 'Je Person (alle Kassenladen)']);
    expect(labelText('tip_claim_scope.title'), 'Offenes Trinkgeld zählt');
    expect(messageText('tip_claim_scope.hint'), matches(RegExp(r'^Je Kassenlade: .+ Je Person: .+\.$')));
    expect(messageText('my_tips.payout_not_allowed'), 'Auszahlen nur mit dem Recht „Schicht“.');
    // Die Karten-Stufe nimmt dieselben Woerter wie Bar (eine Zuordnung, keine zweite Liste).
    expect([for (final m in PosTipKeptMode.values) labelText(tipKeptModeLabels[m.value]!)],
        ['Jedes Mal fragen', 'Immer gleich behalten', 'Immer offen lassen']);
  });

  test('listRegisterUsersForDevice: cardTips nur bei true; ohne Feld, mit false oder Muell bleibt es aus', () async {
    Future<RegisterCashregisterState?> lies(Map<String, dynamic> kasse) async {
      final mock = MockClient((request) async => http.Response.bytes(
            utf8.encode(jsonEncode({
              'status': 'success',
              'message': '',
              'data': {'loginMode': 'pin', 'users': [], 'cashregister': kasse},
            })),
            200,
            headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'},
          ));
      return (await RegisterClient(httpClient: mock).listRegisterUsersForDevice(ownerUid: 'o', deviceId: 'd', deviceSecret: 's'))
          .cashregister;
    }

    expect((await lies({'ready': true, 'cardTips': true}))!.cardTips, isTrue);
    for (final wert in <Object?>[false, 'true', 1, null]) {
      expect((await lies({'ready': true, 'cardTips': wert}))!.cardTips, isFalse, reason: '$wert');
    }
    expect((await lies({'ready': true}))!.cardTips, isFalse);
  });
}
