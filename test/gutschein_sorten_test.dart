import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/enums/receipt_type.dart';
import 'package:kasseneck_api/kasseneck_api.dart' as wurzel;
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/register.dart';
import 'package:kasseneck_api/src/receipt/due.dart';

/// Gutscheine Stufe 4b: Gutschein-Sorten an der Kasse. Die Kasse bekommt die
/// verkaufbaren Sorten aus `getKasseSettings` (`vouchers.types[]`), verkauft
/// einen Wertgutschein nur noch ueber eine Sorte (`typeId`) und rechnet den
/// Zahlbetrag mit Art und Satz der Sorte. Zwilling von
/// `test/gutschein-sorten.test.ts` im npm-Paket (1.17.0).
final _v3 = Directory('test/fixtures/vertrag/v3');

Map<String, dynamic> _json(String pfad) => jsonDecode(File('${_v3.path}/$pfad').readAsStringSync()) as Map<String, dynamic>;

final _kasse = (_json('antworten/kasse.json')['endpoints'] as Map).cast<String, dynamic>();
final _vokabular = _json('v3-vokabular.json');
final _surface = jsonDecode(File('test/fixtures/vertrag/surface.json').readAsStringSync()) as Map<String, dynamic>;

Map<String, dynamic> _fall(String endpunkt, String name) => ((_kasse[endpunkt] as Map)['cases'] as List)
    .cast<Map<String, dynamic>>()
    .firstWhere((f) => f['case'] == name);

Map<String, dynamic> _kopie(Map<String, dynamic> m) => jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

/// Antwort des Servers auf einen Mehrzweck-Verkauf ueber eine Sorte (Kassenweg).
final _verkaufAntwort = ((_json('antworten/kasse-belege.json')['cases'] as List).cast<Map<String, dynamic>>()
    .firstWhere((f) => f['name'] == 'sale_multi_purpose_voucher'))['response'] as Map<String, dynamic>;

/// Eine stimmige Sorte in der Drahtform; [aendern] setzt einzelne Felder,
/// [weg] loescht welche.
Map<String, dynamic> sorte([Map<String, Object?> aendern = const {}, Set<String> weg = const {}]) {
  final s = <String, dynamic>{
    'id': 'vt_geschenk',
    'name': 'Geschenkgutschein',
    'kind': 'multi_purpose',
    'vatRateBp': null,
    'amount': {'mode': 'free'},
    'validity': {'pattern': 'unlimited'},
    'payout': 'allowed',
    'label': {
      'layout': 'a',
      'size': '40x30',
      'fields': {'qr': true, 'value': true, 'designation': true},
      'freeText': <String>[],
    },
    'order': 0,
    'active': true,
    'soldCount': 0,
    ...aendern,
  };
  for (final k in weg) {
    s.remove(k);
  }
  return s;
}

const _standard = {
  'layout': 'a',
  'size': '40x30',
  'fields': {'logo': true, 'qr': true, 'business': true, 'value': true, 'validity': true, 'checkPage': true, 'designation': true},
  'freeText': <String>[],
};

Map<String, dynamic> block([Map<String, Object?> aendern = const {}]) => {
      'sale': false,
      'typeSale': true,
      'valueVoucherType': null,
      'vatRateBp': null,
      'labelDefault': _standard,
      'types': [sorte()],
      'serviceArticles': false,
      ...aendern,
    };

/// Der Block ohne das alte Feld `label` (Kassen vor 1.17): das Paket liest es nicht.
Map<String, dynamic> ohneAltesEtikett(Map<String, dynamic> b) => {...b}..remove('label');

/// Der Kassenweg mit einer Attrappe, die immer [antwort] liefert und mitschreibt.
({RegisterReceiptClient kasse, List<http.Request> log}) _weg(Map<String, dynamic> antwort) {
  final log = <http.Request>[];
  final client = MockClient((r) async {
    log.add(r);
    return http.Response.bytes(utf8.encode(jsonEncode(antwort)), 200,
        headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'});
  });
  final transport = RegisterTransport(
    idToken: () async => 'id-token',
    sessionId: () async => 'sess-1',
    cashregisterId: 'KASSE1',
    httpClient: client,
  );
  return (kasse: RegisterReceiptClient(transport), log: log);
}

Map<String, dynamic> _params(http.Request r) => (jsonDecode(r.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;

const _zahlung = [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 5000)];

/// Verkauft ueber den Kassenweg; liefert den Fehler (nichts darf hinausgehen) oder `null`.
Future<Object?> _fehlerBeimVerkauf(List<KeckVoucher> vouchers, {List<KasseneckItem> items = const []}) async {
  final w = _weg({'status': 'error', 'message': 'darf nicht gesendet werden'});
  try {
    await w.kasse.sell(items: items, payments: _zahlung, vouchers: vouchers);
  } catch (e) {
    expect(w.log, isEmpty, reason: 'nichts geht hinaus');
    return e;
  }
  return null;
}

Map<String, int> toepfe([Map<String, int> werte = const {}]) => {
      'amountRateStandard': 0,
      'amountRateReduced1': 0,
      'amountRateReduced2': 0,
      'amountRateZero': 0,
      'amountRateSpecial': 0,
      'amountRatOthers': 0,
      ...werte,
    };

Map<String, Object?> alsMap(ReceiptDueBreakdown e) => {
      'dueCents': e.dueCents,
      'counterDeltaCents': e.counterDeltaCents,
      'valueVoucherFlowCents': e.valueVoucherFlowCents,
      'bucketsCents': e.bucketsCents,
    };

Matcher wirft(String code) => throwsA(isA<ReceiptDueError>()
    .having((e) => e.reason, 'reason', 'invalid_voucher')
    .having((e) => e.voucherErrorCode, 'voucherErrorCode', code));

KeckVoucher wunsch(Map<String, dynamic> json) => KeckVoucher.fromJson(json);

const _mehrzweck = VoucherDueType(id: 'vt_mz', kind: VoucherType.multiPurpose, amount: VoucherTypeAmount.free());
const _einzweck = VoucherDueType(id: 'vt_ez10', kind: VoucherType.singlePurpose, vatRateBp: 1000, amount: VoucherTypeAmount.free());
const _fix = VoucherDueType(id: 'vt_fix50', kind: VoucherType.singlePurpose, vatRateBp: 2000, amount: VoucherTypeAmount.fixed(5000));
const _sorten = [_mehrzweck, _einzweck, _fix];

void main() {
  group('Einstellungen: Block vouchers mit Sorten', () {
    test('der Vertragsfall owner_with_voucher_type liest jede Sorte mit allen Feldern', () {
      final draht = _kopie(_fall('getKasseSettings', 'owner_with_voucher_type'))['response']['data']['vouchers'] as Map<String, dynamic>;
      final s = PosVoucherSettings.fromJson(draht);
      expect([s.sale, s.typeSale, s.serviceArticles, s.valueVoucherType, s.vatRateBp], [false, false, false, null, null]);
      expect(s.labelDefault?.toJson(), draht['labelDefault']);
      expect(s.types, hasLength(1));
      final t = s.types.single;
      final roh = (draht['types'] as List).single as Map<String, dynamic>;
      expect([t.id, t.name, t.kind, t.vatRateBp, t.order, t.active, t.soldCount],
          ['sorte_geschenk50', 'Geschenkgutschein 50 €', VoucherType.singlePurpose, 2000, 0, true, 2]);
      expect(t.amount, const VoucherTypeAmount.fixed(5000));
      expect([t.amount.mode, t.amount.cents], [VoucherAmountMode.fixed, 5000]);
      expect(t.validity, const VoucherTypeValidity.years(3));
      expect([t.validity.pattern, t.validity.years], [VoucherTypeValidityPattern.years, 3]);
      expect(t.payout, VoucherPayout.allowed);
      expect(t.label?.toJson(), roh['label']);
      expect([t.label?.size, t.label?.layout, t.label?.rotation], ['50x80', 'b', 90]);
      expect(t.label?.fields, {'qr': true, 'value': true, 'validity': true, 'designation': true});
      expect(t.label?.freeText, isEmpty);
      // Gelesen und zurueckgeschrieben ergibt sich der Block selbst (ohne das alte Feld `label`).
      expect(s.toJson(), ohneAltesEtikett(draht));
      // Eine Kopie, kein Verweis auf die Antwort: wer die Antwort danach aendert, aendert die Sorte nicht.
      ((roh['label'] as Map)['fields'] as Map)['qr'] = false;
      roh['label']['size'] = '1x1';
      (draht['labelDefault'] as Map)['size'] = '1x1';
      expect([t.label?.size, t.label?.fields['qr'], s.labelDefault?.size], ['50x80', true, '40x30']);
    });

    test('ein Block eines aelteren Servers (nur sale, Art, Satz) liest die neuen Felder als aus', () {
      final s = PosVoucherSettings.fromJson({'sale': true, 'valueVoucherType': 'single_purpose', 'vatRateBp': 2000});
      expect([s.sale, s.valueVoucherType, s.vatRateBp], [true, VoucherType.singlePurpose, 2000]);
      expect([s.typeSale, s.types, s.serviceArticles, s.labelDefault], [false, isEmpty, false, isNull]);
      expect(s.toJson(), {
        'sale': true,
        'valueVoucherType': 'single_purpose',
        'vatRateBp': 2000,
        'typeSale': false,
        'types': <Object?>[],
        'serviceArticles': false,
        'labelDefault': null,
      });
    });

    test('stimmiger Block mit Sorten geht durch (Mehrzweck ohne Satz, Einzweck mit Satz, fix, Jahre, Auszahlung nie)', () {
      for (final b in [
        block(),
        block({
          'types': [
            sorte({'kind': 'single_purpose', 'vatRateBp': 1000, 'amount': {'mode': 'fixed', 'cents': 2000}, 'validity': {'pattern': 'years', 'years': 1}}),
          ],
        }),
        block({'types': [sorte({'payout': 'never'})]}),
        block({'types': [sorte({'validity': {'pattern': 'years', 'years': 30}, 'amount': {'mode': 'fixed', 'cents': 1000000}, 'order': -3})]}),
      ]) {
        expect(PosVoucherSettings.fromJson(b).toJson(), b, reason: jsonEncode(b));
      }
    });

    test('eine unstimmige Sorte faellt weg, die anderen bleiben (geschlossen im Zweifel)', () {
      final kaputt = <Object?>[
        sorte({}, {'id'}), sorte({'id': ''}), sorte({'id': '__intern__'}), sorte({'id': 'a b'}), sorte({'id': 7}),
        sorte({'id': 'x' * 129}),
        sorte({}, {'name'}), sorte({'name': '  '}), sorte({'name': 5}),
        sorte({'kind': 'service'}), sorte({'kind': 'promotion'}), sorte({'kind': 'mehrzweck'}),
        sorte({'vatRateBp': 2000}),
        sorte({'kind': 'single_purpose', 'vatRateBp': null}), sorte({'kind': 'single_purpose', 'vatRateBp': 0}),
        sorte({'kind': 'single_purpose', 'vatRateBp': 10.5}),
        sorte({}, {'amount'}), sorte({'amount': {'mode': 'fix', 'cents': 100}}), sorte({'amount': {'mode': 'fixed'}}),
        sorte({'amount': {'mode': 'fixed', 'cents': 0}}), sorte({'amount': {'mode': 'fixed', 'cents': 99}}),
        sorte({'amount': {'mode': 'fixed', 'cents': 1000001}}), sorte({'amount': {'mode': 'fixed', 'cents': 120.5}}),
        sorte({'amount': 'frei'}),
        sorte({}, {'validity'}), sorte({'validity': {'pattern': '1+3'}}), sorte({'validity': {'pattern': 'years'}}),
        sorte({'validity': {'pattern': 'years', 'years': 0}}), sorte({'validity': {'pattern': 'years', 'years': 31}}),
        sorte({'validity': {'pattern': 'years', 'years': 2.5}}),
        sorte({}, {'payout'}), sorte({'payout': 'sometimes'}),
        // Auszahlung nie nur zusammen mit unbefristet (Regel des Servers).
        sorte({'payout': 'never', 'validity': {'pattern': 'years', 'years': 2}}),
        sorte({'order': 1.5}), sorte({'order': '1'}),
        sorte({'active': false}), sorte({}, {'active'}),
        sorte({'soldCount': -1}), sorte({'soldCount': 'viele'}),
        'sorte', null, <Object?>[], 3,
      ];
      for (final k in kaputt) {
        final gut = sorte({'id': 'vt_gut'});
        final s = PosVoucherSettings.fromJson(block({'types': [k, gut]}));
        expect([for (final t in s.types) t.toJson()], [gut], reason: jsonEncode(k));
        expect(s.typeSale, isTrue, reason: jsonEncode(k));
      }
    });

    test('fehlende Reihenfolge oder Verkaufszahl gelten als 0, eine unbrauchbare Vorlage als keine', () {
      final s = PosVoucherSettings.fromJson(block({'types': [sorte({'label': 'gross'}, {'order', 'soldCount'})]}));
      expect([s.types.single.order, s.types.single.soldCount, s.types.single.label], [0, 0, isNull]);
      for (final vorlage in [null, <Object?>[], {'size': 40, 'layout': 'a'}, {'size': '40x30'}, {'layout': 'a'}]) {
        expect(PosVoucherSettings.fromJson(block({'types': [sorte({'label': vorlage})]})).types.single.label, isNull,
            reason: jsonEncode(vorlage));
      }
      expect(PosVoucherSettings.fromJson(block({'types': [sorte({}, {'label'})]})).types.single.label, isNull);
    });

    test('dieselbe Kennung zweimal: die erste gilt', () {
      final erste = sorte({'name': 'Erste'});
      final s = PosVoucherSettings.fromJson(block({'types': [erste, sorte({'name': 'Zweite'})]}));
      expect([for (final t in s.types) t.toJson()], [erste]);
    });

    test('typeSale nur mit einer verkaufbaren Sorte oder freigegebenen Leistungsartikeln', () {
      expect(PosVoucherSettings.fromJson(block({'types': [sorte({'kind': 'x'})]})).typeSale, isFalse);
      expect(PosVoucherSettings.fromJson(block({'types': <Object?>[]})).typeSale, isFalse);
      final leistung = PosVoucherSettings.fromJson(block({'types': <Object?>[], 'serviceArticles': true}));
      expect([leistung.typeSale, leistung.serviceArticles], [true, true]);
      // Schalter aus: nie, auch mit Sorten.
      expect(PosVoucherSettings.fromJson(block({'typeSale': false})).typeSale, isFalse);
      // Fehlt der Schalter (aelterer Server), ist er aus.
      expect(PosVoucherSettings.fromJson({...block()}..remove('typeSale')).typeSale, isFalse);
    });

    test('ein unstimmiges Feld des Blocks schliesst den ganzen Block', () {
      for (final f in [
        block({'typeSale': 'ja'}),
        block({'types': 'alle'}),
        block({'types': {'a': 1}}),
        block({'serviceArticles': 1}),
        block({'sale': 'nein'}),
        block({'valueVoucherType': 'x'}),
      ]) {
        expect(PosVoucherSettings.fromJson(f), PosVoucherSettings.off, reason: jsonEncode(f));
      }
      // Eine unbrauchbare Standardvorlage schliesst nicht: ein Verkauf scheitert nie an der Vorlage.
      final ohneVorlage = PosVoucherSettings.fromJson(block({'labelDefault': 'standard'}));
      expect([ohneVorlage.labelDefault, ohneVorlage.typeSale, ohneVorlage.types.length], [isNull, true, 1]);
    });

    test('ein gelesener Block liest sich wieder gleich (die Kasse legt den Stand ab und liest ihn wieder)', () {
      for (final b in [
        _fall('getKasseSettings', 'owner_with_voucher_type')['response']['data']['vouchers'] as Map<String, dynamic>,
        block({'types': [sorte({}, {'label', 'order', 'soldCount'})], 'labelDefault': null}),
        const {'sale': false, 'valueVoucherType': null, 'vatRateBp': null},
      ]) {
        final einmal = PosVoucherSettings.fromJson(b);
        expect(PosVoucherSettings.fromJson(jsonDecode(jsonEncode(einmal.toJson()))), einmal);
        expect(PosVoucherSettings.fromJson(jsonDecode(jsonEncode(einmal.toJson()))).hashCode, einmal.hashCode);
        expect(PosSettings.fromJson({'vouchers': einmal.toJson()}).vouchers, einmal);
      }
      // Gleichheit schaut in die Sorten: eine andere Sorte ist ein anderer Stand.
      expect(PosVoucherSettings.fromJson(block()), isNot(PosVoucherSettings.fromJson(block({'types': [sorte({'name': 'Anders'})]}))));
      expect(PosVoucherSettings.fromJson(block()),
          isNot(PosVoucherSettings.fromJson(block({'labelDefault': {..._standard, 'size': '50x80'}}))));
    });

    test('das alte Feld label (Kassen vor 1.17) liest das Paket nicht', () {
      final draht = _fall('getKasseSettings', 'owner')['response']['data']['vouchers'] as Map<String, dynamic>;
      expect(draht['label'], isNotNull, reason: 'der Vertrag traegt das alte Feld');
      expect(PosVoucherSettings.fromJson(draht).toJson().containsKey('label'), isFalse);
    });

    test('die Wertemengen der Sorte sind die Kataloge des Vokabulars und der Oberflaeche', () {
      List<String> katalog(String name) => ((_vokabular['catalogs'] as Map)[name] as Map).values.cast<String>().toList();
      final pos = _surface['pos'] as Map<String, dynamic>;
      // Eine Sorte ist Mehrzweck oder Einzweck; Leistung und Aktion sind keine Sorte.
      expect(voucherTypeKinds, ['multi_purpose', 'single_purpose']);
      expect(katalog('GUTSCHEIN_ART'), containsAll(voucherTypeKinds));
      expect(voucherTypeKinds, pos['voucherTypeKinds']);
      expect(voucherAmountModes, katalog('GUTSCHEIN_BETRAG_MODUS'));
      expect(voucherAmountModes, pos['voucherAmountModes']);
      expect(voucherTypeValidityPatterns, katalog('GUTSCHEIN_SORTE_MUSTER'));
      expect(voucherTypeValidityPatterns, pos['voucherTypeValidityPatterns']);
      expect(voucherPayouts, katalog('GUTSCHEIN_AUSZAHLUNG'));
      expect(voucherPayouts, pos['voucherPayouts']);
      for (final m in VoucherAmountMode.values) {
        expect(VoucherAmountMode.fromWire(m.wire), m);
      }
      for (final p in VoucherTypeValidityPattern.values) {
        expect(VoucherTypeValidityPattern.fromWire(p.wire), p);
      }
      for (final p in VoucherPayout.values) {
        expect(VoucherPayout.fromWire(p.wire), p);
      }
      expect([VoucherAmountMode.fromWire('fix'), VoucherTypeValidityPattern.fromWire('1+3'), VoucherPayout.fromWire('nie')],
          everyElement(isNull));
    });
  });

  group('checkVoucher: Sortenname, Auszahlung, Jahre', () {
    Map<String, dynamic> pruefung() => _kopie(_fall('checkVoucher', 'success_cashier')['response'] as Map<String, dynamic>);
    Future<VoucherCheck> mit(void Function(Map<String, dynamic> data) aendern) {
      final antwort = pruefung();
      aendern(antwort['data'] as Map<String, dynamic>);
      return _weg(antwort).kasse.checkVoucher('B1KK5EQ57DHP');
    }

    test('Sortenname, Auszahlung und Jahre einer Sorte werden gelesen', () async {
      final v = await mit((d) => d
        ..['typeName'] = 'Geschenkgutschein'
        ..['payout'] = 'never'
        ..['validity'] = {
          'pattern': '1+3',
          'redeemableYears': 3,
          'redeemableUntil': '2029-09-20',
          'refundableUntil': '2032-09-20',
          'validUntil': null,
        });
      expect([v.typeName, v.payout], ['Geschenkgutschein', VoucherPayout.never]);
      // Jedes N geht als `1+3` mit den Daten der Sorte hinaus (Nachtrag E1), N steht in redeemableYears.
      expect(v.validity, const VoucherValidity(pattern: '1+3', redeemableYears: 3, redeemableUntil: '2029-09-20', refundableUntil: '2032-09-20'));
      expect(v.validity, isNot(const VoucherValidity(pattern: '1+3', redeemableUntil: '2029-09-20', refundableUntil: '2032-09-20')));
      // Ein Gutschein ohne Sorte (Stufe 4 und aelter): die Felder fehlen.
      final alt = await mit((_) {});
      expect([alt.typeName, alt.payout, alt.validity?.redeemableYears], everyElement(isNull));
    });

    test('eine unbekannte Auszahlungs-Angabe gilt als never, ein kaputtes Feld ist ein Lesefehler', () async {
      for (final wert in ['sometimes', 1, true]) {
        expect((await mit((d) => d['payout'] = wert)).payout, VoucherPayout.never, reason: '$wert');
      }
      expect((await mit((d) => d['payout'] = 'allowed')).payout, VoucherPayout.allowed);
      expect((await mit((d) => d['payout'] = null)).payout, isNull);
      final lesefehler = throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'response'));
      for (final aendern in <void Function(Map<String, dynamic>)>[
        (d) => d['typeName'] = 5,
        (d) => d['typeName'] = '',
        (d) => (d['validity'] as Map)['redeemableYears'] = 2.5,
        (d) => (d['validity'] as Map)['redeemableYears'] = 0,
        (d) => (d['validity'] as Map)['redeemableYears'] = '3',
        // Das innere Muster `years` geht nie hinaus (Nachtrag E1): es bleibt ein Lesefehler.
        (d) => d['validity'] = {'pattern': 'years', 'redeemableYears': 3},
      ]) {
        await expectLater(mit(aendern), lesefehler);
      }
      expect(voucherValidityPatterns, ['unlimited', '1+3', 'custom']);
    });
  });

  group('Artikel als Leistungsgutschein', () {
    test('serviceVoucher nur bei true, sonst false; der Zwischenspeicher behaelt es', () {
      expect(PosArticle.fromJson({'id': 'art_mani', 'name': 'Maniküre', 'serviceVoucher': true}).serviceVoucher, isTrue);
      for (final w in [null, false, 'true', 1]) {
        expect(PosArticle.fromJson({'id': 'art_mani', 'name': 'Maniküre', 'serviceVoucher': w}).serviceVoucher, isFalse, reason: '$w');
      }
      expect(PosArticle.fromJson(const {'id': 'art_mani', 'name': 'Maniküre'}).serviceVoucher, isFalse);
      final a = PosArticle.fromJson({'id': 'art_mani', 'name': 'Maniküre', 'serviceVoucher': true});
      expect(a.toJson()['serviceVoucher'], isTrue);
      expect(PosArticle.fromJson(a.toJson()).serviceVoucher, isTrue);
      expect(PosArticle.fields, contains('serviceVoucher'));
      // Der Vokabular-Eintrag des Servers (gutscheinLeistung) heisst nach aussen so.
      final artikel = ((((_vokabular['schemas'] as Map)['listMyArticles'] as Map)['data'] as Map)['articles'] as List).single as Map;
      expect(artikel['serviceVoucher'], 'gutscheinLeistung');
    });
  });

  group('Wunsch: Verkauf ueber eine Sorte', () {
    test('ein Wertgutschein geht mit typeId hinaus, mit oder ohne Art', () async {
      for (final roh in [
        {'action': 'sell', 'type': 'multi_purpose', 'typeId': 'vt_geschenk', 'amountCents': 5000},
        {'action': 'sell', 'typeId': 'vt_geschenk', 'amountCents': 5000},
      ]) {
        final v = wunsch(roh);
        expect([v.isNewForm, v.isValid, v.serverFields], [true, true, isEmpty], reason: jsonEncode(roh));
        expect(v.toPayload(), roh);
        expect(KeckVoucher.fromJson(v.toJson()).toPayload(), roh, reason: 'gespeichert und wieder gelesen');
        final w = _weg(_verkaufAntwort);
        final beleg = await w.kasse.sell(items: const [], payments: _zahlung, vouchers: [v]);
        expect(_params(w.log.single)['vouchers'], [roh]);
        expect(beleg.vouchers!.single.typeName, 'Geschenkgutschein');
      }
      // Der Weg ueber den Konstruktor: mit Art und Sorte.
      final gebaut = KeckVoucher(action: VoucherAction.sell, type: VoucherType.singlePurpose, typeId: 'vt_ez20', amountCents: 5000);
      expect(gebaut.toPayload(), {'action': 'sell', 'type': 'single_purpose', 'typeId': 'vt_ez20', 'amountCents': 5000});
      expect(gebaut.isValid, isTrue);
    });

    test('ohne Art steht die Art nirgends still: hasType ist false, type wirft, nie Rabatt', () {
      final v = wunsch({'action': 'sell', 'typeId': 'vt_mz', 'amountCents': 5000});
      expect(v.hasType, isFalse);
      expect(() => v.type, throwsStateError);
      expect(v.toJson().containsKey('type'), isFalse);
      expect(v.toPayload().containsKey('type'), isFalse);
      expect(v.receiptText, 'Gutschein');
      // Mit Art bleibt alles wie bisher.
      final mitArt = wunsch({'action': 'sell', 'type': 'single_purpose', 'typeId': 'vt_ez20', 'amountCents': 5000});
      expect([mitArt.hasType, mitArt.type], [true, VoucherType.singlePurpose]);
    });

    test('eine unbekannte Art an einem Verkauf wird nie still zum Rabatt; sonst wie bisher', () {
      final unbekannt = wunsch({'action': 'sell', 'type': 'gift', 'typeId': 'vt_mz', 'amountCents': 5000});
      expect([unbekannt.hasType, unbekannt.isNewForm, unbekannt.isValid], [false, false, false]);
      // Geschrieben wird sie zurueck, wie sie kam.
      expect(unbekannt.toJson()['type'], 'gift');
      expect(unbekannt.toPayload()['type'], 'gift');
      expect(KeckVoucher.fromJson(unbekannt.toJson()).toJson(), unbekannt.toJson());
      // Ohne Sorte und ohne Art ist ein Verkauf ebenfalls kein Rabatt (und nicht sendbar).
      final ohneAlles = wunsch({'action': 'sell', 'amountCents': 5000});
      expect([ohneAlles.hasType, ohneAlles.isNewForm, ohneAlles.isValid], [false, false, false]);
      // Einloesung mit unbekannter Art: der alte Rueckfall bleibt (Altbelege).
      expect(wunsch({'action': 'redeem', 'type': 'gift', 'valueCents': 100}).type, VoucherType.promo);
    });

    test('ein Wertgutschein ohne Sorte geht nicht hinaus (voucher_type_required)', () async {
      for (final type in [VoucherType.multiPurpose, VoucherType.singlePurpose]) {
        final v = KeckVoucher(action: VoucherAction.sell, type: type, amountCents: 5000);
        expect(v.isValid, isFalse, reason: type.wire);
        expect(await _fehlerBeimVerkauf([v]),
            isA<KasseneckValidationError>().having((e) => e.reason, 'reason', startsWith('voucher_type_required')),
            reason: type.wire);
      }
    });

    test('typeId nur am Wert-Verkauf, in der Form des Servers; Sortenname und Auszahlung setzt nur der Server', () {
      final schlecht = <Map<String, dynamic>>[
        {'action': 'sell', 'typeId': '', 'amountCents': 100},
        {'action': 'sell', 'typeId': 'a b', 'amountCents': 100},
        {'action': 'sell', 'typeId': 'x' * 129, 'amountCents': 100},
        {'action': 'sell', 'typeId': 'vt_1'},
        {'action': 'sell', 'typeId': 'vt_1', 'amountCents': 0},
        {'action': 'sell', 'typeId': 'vt_1', 'type': 'service', 'articleId': 'a', 'quantity': 1},
        {'action': 'sell', 'typeId': 'vt_1', 'type': 'promotion'},
        {'action': 'sell', 'typeId': 'vt_1', 'amountCents': 100, 'articleId': 'a'},
        {'action': 'sell', 'typeId': 'vt_1', 'amountCents': 100, 'reason': 'x'},
        {'action': 'redeem', 'type': 'multi_purpose', 'typeId': 'vt_1', 'code': 'C', 'amountCents': 1},
        {'action': 'payout', 'type': 'multi_purpose', 'typeId': 'vt_1', 'code': 'C', 'amountCents': 1, 'reason': 'x'},
        {'action': 'sell', 'typeId': 'vt_1', 'amountCents': 100, 'typeName': 'Geschenkgutschein'},
        {'action': 'sell', 'typeId': 'vt_1', 'amountCents': 100, 'payout': 'allowed'},
      ];
      for (final g in schlecht) {
        expect(wunsch(g).isValid, isFalse, reason: jsonEncode(g));
      }
      // Eine reservierte Kennung ist der Form nach gueltig; der Server kennt sie nicht (voucher_type_not_found).
      expect(wunsch({'action': 'sell', 'typeId': '__intern__', 'amountCents': 100}).isValid, isTrue);
      expect(wunsch({'action': 'sell', 'typeId': 'x' * 128, 'amountCents': 100}).isValid, isTrue);
      expect(wunsch({'action': 'sell', 'typeId': 'vt_1', 'amountCents': 100, 'typeName': 'G'}).serverFields, ['typeName']);
      expect(wunsch({'action': 'sell', 'typeId': 'vt_1', 'amountCents': 100, 'payout': 'never'}).serverFields, ['payout']);
    });

    test('Sortenname und Auszahlung am Wunsch werden vor dem Senden abgewiesen', () async {
      for (final feld in [
        {'typeName': 'Geschenkgutschein'},
        {'payout': 'allowed'},
      ]) {
        expect(await _fehlerBeimVerkauf([wunsch({'action': 'sell', 'typeId': 'vt_1', 'amountCents': 5000, ...feld})]),
            isA<KasseneckValidationError>().having((e) => e.reason, 'reason', startsWith('voucher_invalid')));
      }
    });

    test('eine Sorte an einem Altform-Gutschein oder an einer Einloesung geht nicht hinaus', () async {
      final posi = [KasseneckItem(name: 'a', quantity: 1, priceCents: 5000, vat: VatRate.vat20)];
      for (final g in [
        KeckVoucher(action: VoucherAction.sell, type: VoucherType.value, valueCents: 100, typeId: 'vt_1'),
        KeckVoucher(action: VoucherAction.redeem, type: VoucherType.value, valueCents: 100, code: 'WG-1', typeId: 'vt_1'),
        KeckVoucher(action: VoucherAction.redeem, type: VoucherType.multiPurpose, code: 'DTD5-9ECF-5KNZ', amountCents: 100, typeId: 'vt_1'),
      ]) {
        expect(await _fehlerBeimVerkauf([g], items: posi),
            isA<KasseneckValidationError>().having((e) => e.reason, 'reason', startsWith('voucher_invalid')),
            reason: jsonEncode(g.toPayload()));
      }
      // Am gelesenen Beleg bleibt der Mehrzweck-Verkauf (type value) mit Sorte gueltig: er zaehlt im 0-%-Satz des Bons.
      expect(
          wunsch({
            'action': 'sell', 'type': 'value', 'valueCents': 5000, 'typeId': 'vt_mz', 'typeName': 'Geschenkgutschein',
            'payout': 'allowed', 'voucherId': 'g1', 'codeSuffix': 'NNNY',
          }).isValid,
          isTrue);
    });

    test('Beleg lesen: Sorte, Sortenname und Auszahlung bleiben erhalten und schreiben sich zurueck', () {
      final eintrag = {
        'action': 'sell', 'type': 'value', 'voucherType': 'multi_purpose', 'value': 50, 'valueCents': 5000,
        'name': 'Geschenkgutschein (Mehrzweckgutschein)', 'typeId': 'vt_mz', 'typeName': 'Geschenkgutschein', 'payout': 'allowed',
        'code': '····-····-NNNY', 'codeSuffix': 'NNNY', 'voucherId': 'auto4',
      };
      final g = KeckVoucher.fromJson(eintrag);
      expect([g.typeId, g.typeName, g.payout, g.hasType, g.type], ['vt_mz', 'Geschenkgutschein', 'allowed', true, VoucherType.value]);
      for (final zurueck in [g.toJson(), g.toPayload()]) {
        for (final k in ['typeId', 'typeName', 'payout']) {
          expect(zurueck[k], eintrag[k], reason: k);
        }
      }
      // Ein unbekannter Auszahlungswert bleibt wie er kam (ein Beleg scheitert nie am Gutschein).
      expect(KeckVoucher.fromJson({...eintrag, 'payout': 'later'}).toJson()['payout'], 'later');
      // Ein Altbeleg ohne Sorte bleibt schlank.
      final alt = KeckVoucher.fromJson(const {'action': 'redeem', 'type': 'value', 'valueCents': 500, 'code': 'WG-1'});
      expect([alt.typeId, alt.typeName, alt.payout], everyElement(isNull));
      for (final k in ['typeId', 'typeName', 'payout']) {
        expect(alt.toJson().containsKey(k), isFalse, reason: k);
      }
    });
  });

  group('Zahlbetrag: Art und Satz aus der Sorte', () {
    test('Mehrzweck-Sorte als Wertgutschein-Fluss (vor dem Stichtag), ab dem Stichtag im 0-%-Topf', () {
      for (final v in [
        wunsch({'action': 'sell', 'typeId': 'vt_mz', 'amountCents': 5000}),
        wunsch({'action': 'sell', 'type': 'multi_purpose', 'typeId': 'vt_mz', 'amountCents': 5000}),
      ]) {
        expect(alsMap(receiptDueBreakdown(const [], [v], ReceiptType.standard, voucherTypes: _sorten)), {
          'dueCents': 5000,
          'counterDeltaCents': 0,
          'valueVoucherFlowCents': 5000,
          'bucketsCents': toepfe(),
        });
        expect(
            alsMap(receiptDueBreakdown(const [], [v], ReceiptType.standard,
                voucherTypes: _sorten, zeroRateBucketFrom: '2026-10-01', today: '2026-10-27')),
            {
              'dueCents': 5000,
              'counterDeltaCents': 5000,
              'valueVoucherFlowCents': 0,
              'bucketsCents': toepfe({'amountRateZero': 5000}),
            });
      }
    });

    test('Einzweck-Sorte als Position im Satz der Sorte, Kleinunternehmer zu 0 %; die Sorte schlaegt die alte Einstellung', () {
      final v = [wunsch({'action': 'sell', 'typeId': 'vt_ez10', 'amountCents': 5000})];
      expect(alsMap(receiptDueBreakdown(const [], v, ReceiptType.standard, voucherTypes: _sorten)), {
        'dueCents': 5000,
        'counterDeltaCents': 5000,
        'valueVoucherFlowCents': 0,
        'bucketsCents': toepfe({'amountRateReduced1': 5000}),
      });
      expect(receiptDueBreakdown(const [], v, ReceiptType.standard, voucherTypes: _sorten, smallBusiness: true).bucketsCents,
          toepfe({'amountRateZero': 5000}));
      expect(
          receiptDueBreakdown(const [], v, ReceiptType.standard,
                  voucherTypes: _sorten,
                  voucherSettings: const PosVoucherSettings(sale: true, valueVoucherType: VoucherType.multiPurpose, vatRateBp: null))
              .bucketsCents,
          toepfe({'amountRateReduced1': 5000}));
    });

    test('die Sorten der Einstellung gehen unveraendert in den Zahlbetrag (PosVoucherType ist eine VoucherDueType)', () {
      final s = PosVoucherSettings.fromJson(_fall('getKasseSettings', 'owner_with_voucher_type')['response']['data']['vouchers']);
      final v = [wunsch({'action': 'sell', 'typeId': 'sorte_geschenk50', 'amountCents': 5000})];
      expect(receiptDueBreakdown(const [], v, ReceiptType.standard, voucherTypes: s.types).bucketsCents,
          toepfe({'amountRateStandard': 5000}));
      expect(() => receiptDueCents(const [], [wunsch({'action': 'sell', 'typeId': 'sorte_geschenk50', 'amountCents': 4000})],
          ReceiptType.standard, voucherTypes: s.types), wirft('voucher_amount_mismatch'));
    });

    // Eine andere Art am Wunsch als an der Sorte heisst: die Kasse hat eine alte Sicht (Sorte umgestellt) – wie beim
    // Server voucher_amount_mismatch, die Kasse laedt die Sorten neu.
    test('Fixbetrag und Art muessen zur Sorte passen, sonst voucher_amount_mismatch', () {
      expect(receiptDueCents(const [], [wunsch({'action': 'sell', 'typeId': 'vt_fix50', 'amountCents': 5000})], ReceiptType.standard,
          voucherTypes: _sorten), 5000);
      expect(() => receiptDueCents(const [], [wunsch({'action': 'sell', 'typeId': 'vt_fix50', 'amountCents': 4999})], ReceiptType.standard,
          voucherTypes: _sorten), wirft('voucher_amount_mismatch'));
      expect(() => receiptDueCents(const [], [wunsch({'action': 'sell', 'type': 'multi_purpose', 'typeId': 'vt_ez10', 'amountCents': 5000})],
          ReceiptType.standard, voucherTypes: _sorten), wirft('voucher_amount_mismatch'));
    });

    test('eine unstimmige Sorte verkauft der Server nicht (voucher_type_not_found)', () {
      final v = [wunsch({'action': 'sell', 'typeId': 'vt_x', 'amountCents': 5000})];
      for (final t in const [
        VoucherDueType(id: 'vt_x', kind: VoucherType.singlePurpose, amount: VoucherTypeAmount.free()),
        VoucherDueType(id: 'vt_x', kind: VoucherType.singlePurpose, vatRateBp: 0, amount: VoucherTypeAmount.free()),
        VoucherDueType(id: 'vt_x', kind: VoucherType.multiPurpose, vatRateBp: 2000, amount: VoucherTypeAmount.free()),
        VoucherDueType(id: 'vt_x', kind: VoucherType.singlePurpose, vatRateBp: 2000, amount: VoucherTypeAmount.fixed(50)),
        VoucherDueType(id: 'vt_x', kind: VoucherType.singlePurpose, vatRateBp: 2000, amount: VoucherTypeAmount.fixed(1000001)),
        VoucherDueType(id: 'vt_x', kind: VoucherType.service, vatRateBp: 2000, amount: VoucherTypeAmount.free()),
      ]) {
        expect(() => receiptDueCents(const [], v, ReceiptType.standard, voucherTypes: [t]), wirft('voucher_type_not_found'),
            reason: '${t.kind} ${t.vatRateBp} ${t.amount.cents}');
      }
    });

    test('eine Sorte, die die Kasse nicht hat, ist voucher_type_not_found (auch eine reservierte)', () {
      expect(() => receiptDueCents(const [], [wunsch({'action': 'sell', 'typeId': 'vt_weg', 'amountCents': 5000})], ReceiptType.standard,
          voucherTypes: _sorten), wirft('voucher_type_not_found'));
      expect(() => receiptDueCents(const [], [wunsch({'action': 'sell', 'typeId': 'vt_mz', 'amountCents': 5000})], ReceiptType.standard),
          wirft('voucher_type_not_found'));
      expect(() => receiptDueCents(const [], [wunsch({'action': 'sell', 'typeId': '__intern__', 'amountCents': 5000})], ReceiptType.standard,
          voucherTypes: const [VoucherDueType(id: '__intern__', kind: VoucherType.multiPurpose, amount: VoucherTypeAmount.free())]),
          wirft('voucher_type_not_found'));
    });

    test('ein Wert-Verkauf ohne Sorte ist voucher_type_required, ohne alte Einstellung oder mit einer ohne Art', () {
      // So liest die Kasse den Block jedes Servers ab Stufe 4b: valueVoucherType ist immer null.
      final ausVertrag = PosVoucherSettings.fromJson(_fall('getKasseSettings', 'owner_with_voucher_type')['response']['data']['vouchers']);
      expect(ausVertrag.valueVoucherType, isNull);
      for (final type in [VoucherType.multiPurpose, VoucherType.singlePurpose]) {
        final v = [KeckVoucher(action: VoucherAction.sell, type: type, amountCents: 5000)];
        expect(() => receiptDueCents(const [], v, ReceiptType.standard, voucherTypes: _sorten), wirft('voucher_type_required'));
        expect(() => receiptDueCents(const [], v, ReceiptType.standard), wirft('voucher_type_required'));
        expect(() => receiptDueCents(const [], v, ReceiptType.standard, voucherSettings: PosVoucherSettings.off), wirft('voucher_type_required'));
        expect(() => receiptDueCents(const [], v, ReceiptType.standard, voucherSettings: ausVertrag), wirft('voucher_type_required'));
      }
    });

    test('Aufrufer bis 11.7 mit einer Einstellung mit Art rechnen den Verkauf ohne Sorte wie bisher', () {
      expect(
          receiptDueBreakdown(const [], [KeckVoucher(action: VoucherAction.sell, type: VoucherType.singlePurpose, amountCents: 5000)],
                  ReceiptType.standard,
                  voucherSettings: const PosVoucherSettings(sale: true, valueVoucherType: VoucherType.singlePurpose, vatRateBp: 1000))
              .bucketsCents,
          toepfe({'amountRateReduced1': 5000}));
      expect(
          receiptDueCents(const [], [KeckVoucher(action: VoucherAction.sell, type: VoucherType.multiPurpose, amountCents: 5000)],
              ReceiptType.standard,
              voucherSettings: const PosVoucherSettings(sale: false, valueVoucherType: VoucherType.multiPurpose, vatRateBp: null)),
          5000);
    });

    test('Auszahlung eines Gutscheins mit Auszahlung nie ist voucher_payout_not_allowed, auch abgelaufen', () {
      const code = 'DTD1-NKT1-8CN5';
      final v = [KeckVoucher(action: VoucherAction.payout, type: VoucherType.multiPurpose, code: code, amountCents: 1000, reason: 'Kulanz')];
      VoucherCheck check({VoucherStatus status = VoucherStatus.active, VoucherPayout? payout}) =>
          VoucherCheck(type: VoucherType.multiPurpose, status: status, codeSuffix: '8CN5', balanceCents: 3000, payout: payout);
      expect(receiptDueCents(const [], v, ReceiptType.standard, voucherInfo: [VoucherDueInfo(code: code, check: check(payout: VoucherPayout.allowed))]),
          -1000);
      expect(receiptDueCents(const [], v, ReceiptType.standard, voucherInfo: [VoucherDueInfo(code: code, check: check())]), -1000);
      expect(() => receiptDueCents(const [], v, ReceiptType.standard,
          voucherInfo: [VoucherDueInfo(code: code, check: check(payout: VoucherPayout.never))]), wirft('voucher_payout_not_allowed'));
      expect(() => receiptDueCents(const [], v, ReceiptType.standard,
              voucherInfo: [VoucherDueInfo(code: code, check: check(status: VoucherStatus.expired, payout: VoucherPayout.never))]),
          wirft('voucher_payout_not_allowed'));
    });

    test('ein Leistungsartikel ohne Freigabe ist voucher_service_not_allowed; ohne Angabe wie bisher', () {
      final v = [KeckVoucher(action: VoucherAction.sell, type: VoucherType.service, articleId: 'art_mani', quantity: 2)];
      expect(receiptDueCents(const [], v, ReceiptType.standard,
          voucherArticles: const [VoucherDueArticle(id: 'art_mani', priceCents: 3500, vatRateBp: 2000, serviceVoucher: true)]), 7000);
      expect(receiptDueCents(const [], v, ReceiptType.standard,
          voucherArticles: const [VoucherDueArticle(id: 'art_mani', priceCents: 3500, vatRateBp: 2000)]), 7000);
      expect(() => receiptDueCents(const [], v, ReceiptType.standard,
              voucherArticles: const [VoucherDueArticle(id: 'art_mani', priceCents: 3500, vatRateBp: 2000, serviceVoucher: false)]),
          wirft('voucher_service_not_allowed'));
    });

    test('die Wurzel exportiert VoucherDueType; die Vorbelegung nimmt die Sorten wie der Zahlbetrag', () {
      expect(const wurzel.VoucherDueType(id: 'a', kind: VoucherType.multiPurpose, amount: VoucherTypeAmount.free()), isA<VoucherDueType>());
      const check = VoucherCheck(type: VoucherType.multiPurpose, status: VoucherStatus.active, codeSuffix: '5KNZ', balanceCents: 5000);
      final items = [KasseneckItem(name: 'Kaffee', quantity: 1, priceCents: 320, vat: VatRate.vat20)];
      expect(voucherRedeemMaxCents(items, check, voucherTypes: _sorten), 320);
      expect(wurzel.voucherRedeemMaxCentsForLines([ReceiptDueLine(quantity: 1, priceCents: 320, vatRate: 20)], check, voucherTypes: _sorten), 320);
    });
  });

  group('Woerter', () {
    test('Reiter, Kacheln und Fehlersaetze der Gutschein-Sorten mit genau diesem Text', () {
      expect(labelText('voucher.tab'), 'Gutscheine');
      expect(labelText('voucher.enter_amount'), 'Betrag eingeben');
      expect(labelText('voucher.service_tile'), 'Leistungsgutschein');
      expect(labelText('voucher.kind_multi_short'), 'Mehrzweck');
      expect(labelText('voucher.kind_single_short', {'rate': '20'}), 'Einzweck 20 %');
      const saetze = {
        'voucher_type_required': 'Bitte eine Gutschein-Sorte wählen.',
        'voucher_type_not_found': 'Diese Gutschein-Sorte gibt es nicht mehr. Die Kasse lädt die Sorten neu.',
        'voucher_amount_mismatch': 'Die Gutschein-Sorte hat sich geändert. Die Kasse lädt die Sorten neu.',
        'voucher_service_not_allowed': 'Dieser Artikel ist nicht als Leistungsgutschein freigegeben.',
        'voucher_payout_not_allowed': 'Dieser Gutschein kann nicht ausgezahlt werden.',
      };
      for (final MapEntry(key: code, value: satz) in saetze.entries) {
        final key = voucherErrorMessage(code);
        expect(key, 'voucher_error.${code.replaceFirst('voucher_', '')}', reason: code);
        expect(messageText(key!), satz, reason: code);
      }
      // Codes nur des Kundenbereichs (Sorten pflegen) sind keine Kassen-Codes.
      for (final code in ['invalid_voucher_type', 'voucher_type_in_use', 'too_many_voucher_types']) {
        expect(voucherErrorMessage(code), isNull, reason: code);
      }
    });

    // Eine Verkaufszeile, die nach dem Neuladen der Sorten nicht mehr passt, sperrt das Kassieren mit einem eigenen Satz
    // der Kasse – der Satz zur Absage des Servers sagt „Die Kasse laedt die Sorten neu“, das ist dann vorbei.
    test('Satz fuer eine Verkaufszeile mit geaenderter Sorte', () {
      expect(messageText('voucher.type_changed'),
          'Diese Gutschein-Sorte hat sich geändert. Bitte die Zeile entfernen und die Kachel neu antippen.');
      expect(messageText('voucher.type_changed'), isNot(messageText('voucher_error.amount_mismatch')));
    });
  });
}
