import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/register.dart' show RegisterUserPerms;

/// Pfand & Leergut: die Vorschau-Rechnung gegen dieselben Pruefaelle wie der
/// Server und das npm-Paket (`deposit-cases.json`), dazu Leser und Hilfen.
/// Zwilling von `test/pfand-vorschau.test.ts` und `test/pfand.test.ts`.

final _datei = jsonDecode(File('test/fixtures/vertrag/deposit-cases.json').readAsStringSync()) as Map<String, dynamic>;
final _faelle = (_datei['cases'] as List).cast<Map<String, dynamic>>();

Map<String, dynamic> _map(Object? w) => (w as Map).cast<String, dynamic>();

DepositPreviewInput _eingabe(Map<String, dynamic> i) {
  final kasse = i['cashRegister'];
  return DepositPreviewInput(
    auto: i['auto'] == true,
    articles: {for (final e in _map(i['articles']).entries) e.key: PosArticle.fromJson(_map(e.value))},
    groups: {for (final e in _map(i['groups']).entries) e.key: ArticleGroup.fromJson(_map(e.value))},
    depositTypes: {for (final e in _map(i['depositTypes']).entries) e.key: DepositType.fromJson(e.value)!},
    day: i['day'] as String,
    onPremises: i['onPremises'] == true,
    cashRegister: kasse == null ? null : CashRegisterDeposit.fromJson(kasse),
    smallBusiness: i['smallBusiness'] == true,
    mayReturn: i['mayReturn'] != false,
  );
}

void main() {
  test('Pruefaelle: Vorschau liefert genau die Zeilen bzw. den Code des Servers', () {
    expect(_faelle.length, 32);
    for (final f in _faelle) {
      final i = _map(f['input']);
      final r = withDepositLines(i['items'] as List, _eingabe(i));
      final soll = _map(f['expected']);
      if (soll.containsKey('code')) {
        expect(r.ok, isFalse, reason: f['name'] as String);
        expect(r.code, soll['code'], reason: f['name'] as String);
      } else {
        expect(r.code, isNull, reason: '${f['name']}');
        expect(r.items, soll['items'], reason: f['name'] as String);
      }
    }
  });

  test('Pruefaelle: die Eingabe bleibt unveraendert', () {
    for (final f in _faelle) {
      final i = _map(f['input']);
      final vorher = jsonEncode(i);
      withDepositLines(i['items'] as List, _eingabe(i));
      expect(jsonEncode(i), vorher, reason: f['name'] as String);
    }
  });

  test('ohne Pfand und Leergut kommen die Positionen unveraendert zurueck (dieselben Objekte)', () {
    final i = _map(_faelle.firstWhere((f) => (f['name'] as String).startsWith('Unbekannter Artikel und Trinkgeld'))['input']);
    final items = i['items'] as List;
    final r = withDepositLines(items, _eingabe(i));
    expect(r.ok, isTrue);
    expect(r.items, items);
    for (var n = 0; n < items.length; n++) {
      expect(identical(r.items![n], items[n]), isTrue);
    }
  });

  test('Leergutzeile: dieselbe wie in der Vorschau, als Position', () {
    final faelle = _faelle.where((f) => ((f['input'] as Map)['items'] as List).any((i) => i is Map && i['kind'] == 'deposit_return') && (f['expected'] as Map).containsKey('items'));
    expect(faelle.length, greaterThanOrEqualTo(4));
    for (final f in faelle) {
      final i = _map(f['input']);
      final arten = _map(i['depositTypes']);
      for (final it in (i['items'] as List).whereType<Map>()) {
        if (it['kind'] != 'deposit_return') continue;
        final art = DepositType.fromJson(arten[it['depositTypeId']])!;
        final codes = it['codes'] == null ? null : {for (final e in _map(it['codes']).entries) e.key: e.value as int};
        final z = depositReturnLine(art, it['quantity'] as int, day: i['day'] as String, smallBusiness: i['smallBusiness'] == true, codes: codes);
        final soll = ((f['expected'] as Map)['items'] as List).cast<Map>().firstWhere((e) => e['kind'] == 'deposit_return' && e['depositTypeId'] == it['depositTypeId']);
        expect(z.priceCents, soll['unitPriceCents'], reason: f['name'] as String);
        expect(z.quantity, soll['quantity'], reason: f['name'] as String);
        expect(z.name, soll['name'], reason: f['name'] as String);
        expect(z.vat.rate, soll['vat'], reason: f['name'] as String);
        expect(z.ean, soll['ean'], reason: f['name'] as String);
        expect(z.codes, soll['codes'], reason: f['name'] as String);
        expect(z.kind, 'deposit_return');
        expect(z.isDepositReturn, isTrue);
        expect(z.depositKind, art.kind);
      }
    }
  });

  test('Leergutzeile: unmoegliche Eingabe wirft', () {
    final art = DepositType(
        id: 'x', kind: 'single_use', name: 'Pfand X', amounts: const [DepositAmount(from: '2025-01-01', cents: 25)], used: true);
    expect(() => depositReturnLine(art, 0, day: '2026-11-07', smallBusiness: false), throwsStateError);
    expect(() => depositReturnLine(art, 2, day: '2024-12-31', smallBusiness: false), throwsStateError);
    // Mehrweg ohne Rueckgabesatz (nie ausgegeben) rechnet nicht.
    final mehrweg = DepositType(id: 'm', kind: 'reusable', name: 'Pfand M', amounts: const [DepositAmount(from: '2025-01-01', cents: 25)], used: true);
    expect(() => depositReturnLine(mehrweg, 1, day: '2026-11-07', smallBusiness: false), throwsStateError);
    expect(depositReturnLine(mehrweg, 1, day: '2026-11-07', smallBusiness: true).vat.rate, 0);
  });

  test('depositsFor: Artikel vor Gruppe, leer = kein Pfand, null = Gruppe, Fremdgutschein nie', () {
    const g = [DepositEntry(depositTypeId: 'g', quantity: 1)];
    const a = [DepositEntry(depositTypeId: 'a', quantity: 2)];
    PosArticle artikel({List<DepositEntry>? deposits, ArticleExternalVoucher? fremd}) =>
        PosArticle(id: 'x', name: 'X', unit: 'piece', visible: true, sort: 0, active: true, deposits: deposits, externalVoucher: fremd);
    const gruppe = ArticleGroup(id: 'g', name: 'G', color: '#000000', sort: 0, deposits: g);
    expect(depositsFor(artikel(deposits: a), gruppe), a);
    expect(depositsFor(artikel(deposits: const []), gruppe), isEmpty);
    expect(depositsFor(artikel(), gruppe), g);
    expect(depositsFor(artikel(), null), isEmpty);
    expect(depositsFor(null, gruppe), isEmpty);
    expect(depositsFor(artikel(deposits: a, fremd: ArticleExternalVoucher.multiPurpose), gruppe), isEmpty);
    expect(depositsFor(artikel(fremd: ArticleExternalVoucher.singlePurpose), gruppe), isEmpty);
  });

  test('depositAmountOn: letzter Eintrag mit from <= Tag, sonst null', () {
    const t = DepositType(id: 't', kind: 'single_use', name: 'T', amounts: [DepositAmount(from: '2025-01-01', cents: 25), DepositAmount(from: '2026-07-01', cents: 30)]);
    expect(depositAmountOn(t, '2024-12-31'), isNull);
    expect(depositAmountOn(t, '2025-01-01'), 25);
    expect(depositAmountOn(t, '2026-06-30'), 25);
    expect(depositAmountOn(t, '2026-07-01'), 30);
    expect(depositAmountOn(const DepositType(id: 'e', kind: 'single_use', name: 'E'), '2026-07-01'), isNull);
  });

  test('viennaDay: Wiener Tag, nicht der UTC-Tag (Sommer- und Winterzeit)', () {
    int utc(int j, int m, int t, int h, int mi, int s) => DateTime.utc(j, m, t, h, mi, s).millisecondsSinceEpoch;
    // Sommerzeit (UTC+2): 22:00 UTC ist schon 00:00 am Folgetag.
    expect(viennaDay(utc(2026, 7, 14, 21, 59, 59)), '2026-07-14');
    expect(viennaDay(utc(2026, 7, 14, 22, 0, 0)), '2026-07-15');
    // Winterzeit (UTC+1): 23:00 UTC ist 00:00 am Folgetag.
    expect(viennaDay(utc(2026, 11, 7, 22, 59, 59)), '2026-11-07');
    expect(viennaDay(utc(2026, 11, 7, 23, 0, 0)), '2026-11-08');
    // Jahreswechsel und Umstellungstage.
    expect(viennaDay(utc(2026, 12, 31, 23, 0, 0)), '2027-01-01');
    expect(viennaDay(utc(2026, 3, 29, 0, 30, 0)), '2026-03-29');
    expect(viennaDay(utc(2026, 10, 24, 22, 0, 0)), '2026-10-25');
  });

  group('Leser', () {
    test('Block deposit: kein Objekt -> null, unlesbare Pfandart faellt weg', () {
      expect(DepositSettings.fromJson(null), isNull);
      expect(DepositSettings.fromJson('x'), isNull);
      final s = DepositSettings.fromJson({
        'singleUse': true,
        'reusable': false,
        'depositTypes': [
          {'id': 'einweg', 'kind': 'single_use', 'name': 'Pfand Einweg', 'type': 'can', 'amounts': [{'from': '2025-01-01', 'cents': 25}, {'from': 1}], 'returnRate': 0, 'used': true},
          {'id': 'kaputt', 'kind': 'irgendwas'},
          {'kind': 'reusable'},
          5,
        ],
      })!;
      expect(s.singleUse, isTrue);
      expect(s.reusable, isFalse);
      expect(s.depositTypes.length, 1);
      final a = s.depositTypes.single;
      expect(a.type, isNull, reason: 'Gebindetyp ausserhalb des Katalogs');
      expect(a.amounts.length, 1);
      expect(a.returnRate, 0);
      expect(a.used, isTrue);
      expect(a.active, isTrue);
      expect(DepositSettings.fromJson(s.toJson())!.toJson(), s.toJson());
    });

    test('Pfandliste: keine Liste -> null, leer bleibt leer, unlesbare Eintraege fallen weg', () {
      expect(DepositEntry.listFromJson(null), isNull);
      expect(DepositEntry.listFromJson('x'), isNull);
      expect(DepositEntry.listFromJson(const []), isEmpty);
      final l = DepositEntry.listFromJson([
        {'depositTypeId': 'kiste', 'quantity': 1},
        {'depositTypeId': 'flasche', 'quantity': 20, 'gtin': '9012345001025', 'ownFilling': true},
        {'depositTypeId': '', 'quantity': 1},
        {'depositTypeId': 'x', 'quantity': 0},
        {'depositTypeId': 'x', 'quantity': 1.5},
      ])!;
      expect(l.map((e) => e.depositTypeId), ['kiste', 'flasche']);
      expect(l.last.gtin, '9012345001025');
      expect(l.last.ownFilling, isTrue);
    });

    test('Artikel und Gruppe lesen und schreiben deposits', () {
      final a = PosArticle.fromJson({'id': 'a', 'name': 'Cola', 'deposits': [{'depositTypeId': 'einweg', 'quantity': 1}]});
      expect(a.deposits!.single.depositTypeId, 'einweg');
      expect(PosArticle.fromJson(a.toJson()).deposits!.single.quantity, 1);
      expect(PosArticle.fromJson({'id': 'a'}).deposits, isNull);
      expect(PosArticle.fromJson({'id': 'a', 'deposits': []}).deposits, isEmpty);
      final g = ArticleGroup.fromJson({'id': 'g', 'deposits': [{'depositTypeId': 'kiste', 'quantity': 2}]});
      expect(g.deposits!.single.quantity, 2);
      expect(ArticleGroup.fromJson(g.toJson()).deposits!.single.quantity, 2);
      expect(ArticleGroup.fromJson({'id': 'g'}).deposits, isNull);
    });

    test('Pfand-Angaben der Kasse: unbrauchbar -> null, Vorgaben und Stelle', () {
      expect(CashRegisterDeposit.fromJson(null), isNull);
      expect(CashRegisterDeposit.fromJson({'returns': 'sometimes', 'onPremisesDefault': 'ask'}), isNull);
      expect(CashRegisterDeposit.fromJson({'returns': 'here', 'onPremisesDefault': 'maybe'}), isNull);
      final k = CashRegisterDeposit.fromJson({
        'returns': 'shared',
        'onPremisesDefault': 'takeaway',
        'usualQuantity': 0,
        'sharedReturnPoint': {'name': 'Sammelstelle Kornblum', 'address': 'Hauptplatz 1, 4020 Linz'},
      })!;
      expect(k.usualQuantity, 1);
      expect(k.sharedReturnPoint!.name, 'Sammelstelle Kornblum');
      expect(CashRegisterDeposit.fromJson({'returns': 'here', 'onPremisesDefault': 'ask', 'usualQuantity': 24})!.usualQuantity, 24);
      expect(CashRegisterDeposit.fromJson({'returns': 'here', 'onPremisesDefault': 'ask', 'sharedReturnPoint': {'address': 'x'}})!.sharedReturnPoint, isNull);
    });

    test('PosSettings: der Block deposit fehlt, solange er nicht kommt', () {
      expect(PosSettings.fromJson({'business': const {}, 'device': const {}}).deposit, isNull);
      expect(const PosSettings.standard().deposit, isNull);
      expect(PosSettings.fromJson({'business': const {}, 'device': const {}}).toJson().containsKey('deposit'), isFalse);
      final s = PosSettings.fromJson({'business': const {}, 'device': const {}, 'deposit': {'singleUse': true, 'reusable': true, 'depositTypes': const []}});
      expect(s.deposit!.singleUse, isTrue);
      expect(PosSettings.fromJson(s.toJson()).deposit!.reusable, isTrue);
    });
  });

  group('Recht depositReturn', () {
    test('fehlt = erteilt, nur ein ausdrueckliches false sperrt, ohne Rechte nein', () {
      expect(depositReturnOf(null), isFalse);
      expect(depositReturnOf(RegisterUserPerms.fromJson(const {})), isTrue);
      expect(depositReturnOf(RegisterUserPerms.fromJson(const {'depositReturn': true})), isTrue);
      expect(depositReturnOf(RegisterUserPerms.fromJson(const {'depositReturn': false})), isFalse);
      expect(depositReturnOf(RegisterUserPerms.fromJson(const {'depositReturn': 'ja'})), isFalse);
    });

    test('landet nicht im Auffangbecken', () {
      final p = RegisterUserPerms.fromJson(const {'depositReturn': true, 'etwasNeues': true});
      expect(p.other.containsKey('depositReturn'), isFalse);
      expect(p.other['etwasNeues'], isTrue);
      expect(p['depositReturn'], isTrue);
    });
  });
}
