import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/kasseneck_api.dart' show KasseneckApi;
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/register.dart';

/// Gutscheine der neuen Form an der Kasse gegen den Vertrags-Export
/// (`v3/antworten/kasse.json`, `kasse-belege.json`, `belege.json`): pruefen,
/// Etikett nachdrucken, Rechte, Einstellung, Belege lesen und Wuensche senden.
/// Zwilling von `pos-gutschein.test.ts`, `register-rechte.test.ts` und
/// `voucher-neue-form.test.ts` im npm-Paket.
final _v3 = Directory('test/fixtures/vertrag/v3');

Map<String, dynamic> _json(String pfad) => jsonDecode(File('${_v3.path}/$pfad').readAsStringSync()) as Map<String, dynamic>;

final _kasse = (_json('antworten/kasse.json')['endpoints'] as Map).cast<String, dynamic>();
final _surface = jsonDecode(File('test/fixtures/vertrag/surface.json').readAsStringSync()) as Map<String, dynamic>;
List<Map<String, dynamic>> _faelle(String datei) => (_json('antworten/$datei')['cases'] as List).cast<Map<String, dynamic>>();
final _belege = _faelle('belege.json');
final _kasseBelege = _faelle('kasse-belege.json');
final _storno = _faelle('storno.json');

Map<String, dynamic> _fall(String endpunkt, String name) => ((_kasse[endpunkt] as Map)['cases'] as List)
    .cast<Map<String, dynamic>>()
    .firstWhere((f) => f['case'] == name);

Map<String, dynamic> _kopie(Map<String, dynamic> m) => jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

/// Die Felder der Gutschein-Sorten (11.8.0) ohne Angabe: kein Sortenverkauf, keine Sorten, keine Vorlage.
const _ohneSorten = {'typeSale': false, 'types': <Object?>[], 'serviceArticles': false, 'labelDefault': null};

/// Der Kassenweg mit einer Attrappe, die immer [antwort] liefert und die
/// Anfragen mitschreibt.
({RegisterReceiptClient kasse, RegisterTransport transport, List<http.Request> log}) _weg(Map<String, dynamic> antwort,
    {int status = 200}) {
  final log = <http.Request>[];
  final client = MockClient((r) async {
    log.add(r);
    return http.Response.bytes(utf8.encode(jsonEncode(antwort)), status,
        headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'});
  });
  final transport = RegisterTransport(
    idToken: () async => 'id-token',
    sessionId: () async => 'sess-1',
    cashregisterId: 'KASSE1',
    httpClient: client,
  );
  return (kasse: RegisterReceiptClient(transport), transport: transport, log: log);
}

Map<String, dynamic> _params(http.Request r) => (jsonDecode(r.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;

void main() {
  group('checkVoucher', () {
    test('sendet den normalisierten Code und liest das Modell ohne null-Felder', () async {
      final w = _weg(_fall('checkVoucher', 'success_cashier')['response'] as Map<String, dynamic>);
      final v = await w.kasse.checkVoucher('b1kk-5eq5-7dhp');
      expect(w.log.single.url.toString(), 'https://kasse.kasseneck.at/api/v3/checkVoucher');
      expect(_params(w.log.single)['code'], 'B1KK5EQ57DHP');
      expect([v.type, v.status, v.codeSuffix, v.balanceCents, v.faceValueCents], [VoucherType.multiPurpose, VoucherStatus.active, '7DHP', 3200, 5000]);
      expect(v.validity, const VoucherValidity(pattern: '1+3', redeemableUntil: '2027-09-20', refundableUntil: '2030-09-20'));
      expect([v.quantity, v.remainingQuantity, v.vatRateBp, v.article, v.discountCents, v.discountPercentBp, v.exempt], everyElement(isNull));
    });

    test('Leistungsgutschein mit Artikel und Stueckzahl; die Funktion wie die Methode', () async {
      final w = _weg(_fall('checkVoucher', 'success_service')['response'] as Map<String, dynamic>);
      final v = await checkVoucher(w.transport, 'B1KK5EQ57DJG');
      expect(v.type, VoucherType.service);
      expect([v.quantity, v.remainingQuantity], [3, 2]);
      expect(v.article, const VoucherArticle(id: 'art_mani', name: 'Manikuere', vatRateBp: 2000, priceCents: 3500));
      expect(v.validity, const VoucherValidity(pattern: 'unlimited'));
    });

    test('Fehler tragen ihren Code; ein falsches Pruefzeichen geht nie ueber das Netz', () async {
      final f = _fall('checkVoucher', 'unknown');
      final w = _weg(f['response'] as Map<String, dynamic>);
      await expectLater(w.kasse.checkVoucher(f['params']['code'] as String),
          throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'voucher_not_found')));
      expect(_fall('checkVoucher', 'check_digit_wrong')['response']['code'], 'voucher_invalid_code');
      final lokal = _weg(_fall('checkVoucher', 'success_cashier')['response'] as Map<String, dynamic>);
      for (final falsch in ['B1KK5EQ57DH0', '', 'B1KK-5EQ5', 'B1KK5EQ57DHP!']) {
        await expectLater(lokal.kasse.checkVoucher(falsch),
            throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'request').having((e) => e.reason, 'reason', isNot(contains('B1KK')))));
      }
      expect(lokal.log, isEmpty);
    });

    test('unbekannte Art oder Stand, keine ganze Zahl: ein Lesefehler, nie still', () async {
      for (final (feld, wert) in [('status', 'frozen'), ('type', 'value'), ('balanceCents', 3.5), ('codeSuffix', null)]) {
        final antwort = _kopie(_fall('checkVoucher', 'success_cashier')['response'] as Map<String, dynamic>);
        (antwort['data'] as Map)[feld] = wert;
        await expectLater(_weg(antwort).kasse.checkVoucher('B1KK5EQ57DHP'),
            throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'response')), reason: '$feld = $wert');
      }
    });

    test('exempt (befreit verkauft) als Wahrheitswert; null fehlt; alles andere ist ein Lesefehler', () async {
      Future<VoucherCheck> mit(Object? wert) {
        final antwort = _kopie(_fall('checkVoucher', 'success_cashier')['response'] as Map<String, dynamic>);
        (antwort['data'] as Map)['exempt'] = wert;
        return _weg(antwort).kasse.checkVoucher('B1KK5EQ57DHP');
      }

      expect((await mit(true)).exempt, isTrue);
      expect((await mit(false)).exempt, isFalse);
      expect((await mit(null)).exempt, isNull);
      await expectLater(mit('ja'), throwsA(isA<KasseneckValidationError>()));
      final f = _fall('checkVoucher', 'success_exempt');
      final r = await _weg(f['response'] as Map<String, dynamic>).kasse.checkVoucher(f['params']['code'] as String);
      expect([r.exempt, r.balanceCents, r.vatRateBp], [true, 4000, 0]);
    });

    test('ein Servertext, der den Code wiederholt, erreicht den Fehler nie im Klartext', () async {
      final antwort = _kopie(_fall('checkVoucher', 'unknown')['response'] as Map<String, dynamic>);
      antwort['message'] = 'Gutschein B1KK5EQ57DKJ (B1KK-5EQ5-7DKJ) gibt es nicht.';
      Object? fehler;
      try {
        await _weg(antwort).kasse.checkVoucher('b1kk-5eq5-7dkj');
      } catch (e) {
        fehler = e;
      }
      expect(fehler, isA<KasseneckApiError>().having((e) => e.code, 'code', 'voucher_not_found'));
      final text = '${(fehler as KasseneckApiError).message} $fehler';
      expect(text, isNot(contains('B1KK5EQ57DKJ')));
      expect(text, isNot(contains('B1KK-5EQ5-7DKJ')));
      expect(text, contains('****'));
    });
  });

  group('Servertext von createReceipt nennt den Code nie (beide Wege)', () {
    const fehlerCode = 'voucher_not_found';
    final item = KasseneckItem(name: 'Blumenstrauss', quantity: 1, priceCents: 2240, vat: VatRate.vat20);
    const zahlung = [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 490)];

    KeckVoucher einloesen(String code) =>
        KeckVoucher(code: code, action: VoucherAction.redeem, type: VoucherType.multiPurpose, amountCents: 1750);

    Future<String> ueberKasse(String code, String servertext) async {
      final w = _weg({'status': 'error', 'message': servertext, 'code': fehlerCode});
      try {
        await w.kasse.sell(items: [item], payments: zahlung, vouchers: [einloesen(code)]);
      } on KasseneckApiError catch (e) {
        expect(e.code, fehlerCode, reason: 'der Code bleibt, die Kasse entscheidet daran');
        return '${e.message} $e';
      }
      fail('kein Fehler');
    }

    Future<String> ueberApi(String code, String servertext) async {
      final api = KasseneckApi(
        apiKey: 'kr_test_x',
        cashregisterToken: base64Encode(utf8.encode('KECK-1:secret')),
        httpClient: MockClient((r) async => http.Response(
            jsonEncode({'status': 'error', 'message': servertext, 'code': fehlerCode}), 200,
            headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'})),
      );
      try {
        await api.sellReceipt(items: [item], payments: zahlung, vouchers: [einloesen(code)]);
      } on KasseneckApiError catch (e) {
        expect(e.code, fehlerCode);
        return '${e.message} $e';
      }
      fail('kein Fehler');
    }

    final wege = <String, Future<String> Function(String, String)>{'Kassenweg': ueberKasse, 'API-Schluessel': ueberApi};
    for (final e in wege.entries) {
      test('${e.key}: getippte Schreibweise (klein, Leerzeichen), normiert und formatiert werden geschwaerzt', () async {
        final text = await e.value('dtd5 9ecf 5knz', 'Nichts zu dtd5 9ecf 5knz, DTD59ECF5KNZ oder DTD5-9ECF-5KNZ.');
        for (final klar in ['dtd5 9ecf 5knz', 'DTD59ECF5KNZ', 'DTD5-9ECF-5KNZ']) {
          expect(text, isNot(contains(klar)), reason: klar);
        }
        expect(text, contains('****'));
      });

      test('${e.key}: ein Code mit falschem Pruefzeichen wird ebenfalls geschwaerzt', () async {
        final text = await e.value('DTD5-9ECF-5KNY', 'Der Code DTD5-9ECF-5KNY gilt nicht.');
        expect(text, isNot(contains('DTD5-9ECF-5KNY')));
      });

      test('${e.key}: eine vierstellige Endung wird nie geschwaerzt', () async {
        final text = await e.value('DTD5-9ECF-5KNZ', 'Gutschein ····-5KNZ nicht gefunden.');
        expect(text, contains('5KNZ'));
      });
    }
  });

  group('reprintVoucherLabel', () {
    test('sendet die Id und liefert den Klartext-Code', () async {
      final w = _weg(_fall('reprintVoucherLabel', 'success_manager')['response'] as Map<String, dynamic>);
      expect(await w.kasse.reprintVoucherLabel('gmz1'), 'B1KK-5EQ5-7DHP');
      expect(w.log.single.url.toString(), 'https://kasse.kasseneck.at/api/v3/reprintVoucherLabel');
      expect(_params(w.log.single)['id'], 'gmz1');
      await expectLater(reprintVoucherLabel(w.transport, '  '), throwsA(isA<KasseneckValidationError>()));
      expect(w.log, hasLength(1));
    });

    test('fehlendes Recht, unbekannter und stornierter Gutschein am Code', () async {
      for (final (name, code) in [('cashier_without_permission', 'not_permitted'), ('unknown', 'voucher_not_found'), ('cancelled', 'voucher_cancelled')]) {
        final f = _fall('reprintVoucherLabel', name);
        await expectLater(_weg(f['response'] as Map<String, dynamic>).kasse.reprintVoucherLabel(f['params']['id'] as String),
            throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', code)), reason: name);
      }
    });

    test('ein Lesefehler der Antwort nennt den Code nicht', () async {
      for (final daten in [
        {'code': 12345},
        {'code': '', 'voucher': {'code': 'B1KK-5EQ5-7DHP'}},
      ]) {
        final antwort = _kopie(_fall('reprintVoucherLabel', 'success_manager')['response'] as Map<String, dynamic>)..['data'] = daten;
        await expectLater(
            _weg(antwort).kasse.reprintVoucherLabel('gmz1'),
            throwsA(isA<KasseneckValidationError>()
                .having((e) => e.kind, 'kind', 'response')
                .having((e) => '$e', 'Text', allOf(isNot(contains('12345')), isNot(contains('B1KK'))))));
      }
    });
  });

  group('Rechte (voucherPermsOf)', () {
    const kassier = VoucherPerms(voucherSell: true, voucherRedeem: true, voucherManage: false);

    test('fehlende Schluessel gelten wie beim Kassier', () {
      expect(voucherPermsOf(RegisterUserPerms.fromJson(const {})), kassier);
      expect(voucherPermsOf(null), kassier);
      expect(voucherPermsOf(const RegisterUserPerms()), kassier);
      expect(voucherPermsOf(RegisterUserPerms.fromJson(const {'voucherManage': true})),
          const VoucherPerms(voucherSell: true, voucherRedeem: true, voucherManage: true));
    });

    test('ein ausdrueckliches false sperrt, kein Nicht-Wahrheitswert erteilt', () {
      expect(voucherPermsOf(RegisterUserPerms.fromJson(const {'voucherSell': false, 'voucherRedeem': false, 'voucherManage': false})),
          const VoucherPerms(voucherSell: false, voucherRedeem: false, voucherManage: false));
      expect(voucherPermsOf(RegisterUserPerms.fromJson(const {'voucherManage': 'yes'})).voucherManage, isFalse);
      expect(voucherPermsOf(RegisterUserPerms.fromJson(const {'voucherSell': null})).voucherSell, isFalse);
    });

    test('typisiert, nicht im Auffangbecken; [] liefert den Rohwert', () {
      final p = RegisterUserPerms.fromJson(const {'voucherSell': true, 'voucherRedeem': true, 'voucherManage': true});
      expect(p.other, isEmpty);
      for (final r in ['voucherSell', 'voucherRedeem', 'voucherManage']) {
        expect(p[r], isTrue, reason: r);
      }
      expect(const RegisterUserPerms()['voucherSell'], isFalse);
    });

    test('liest die Rechte der Anmeldung im Vertrag', () {
      final gefunden = <Map<String, dynamic>>[];
      void lauf(Object? o) {
        if (o is Map) {
          if (o['voucherSell'] is bool) gefunden.add(o.cast<String, dynamic>());
          o.values.forEach(lauf);
        } else if (o is List) {
          o.forEach(lauf);
        }
      }

      lauf(_kasse);
      expect(gefunden, isNotEmpty);
      for (final p in gefunden) {
        expect(
            voucherPermsOf(RegisterUserPerms.fromJson(p)),
            VoucherPerms(
                voucherSell: p['voucherSell'] as bool, voucherRedeem: p['voucherRedeem'] as bool, voucherManage: p['voucherManage'] as bool));
      }
    });
  });

  group('Einstellung (Block vouchers)', () {
    const zu = PosVoucherSettings.off;

    test('der Block aus dem Vertrag wird gelesen, auch ueber PosSettingsClient', () async {
      final faelle = ((_kasse['getKasseSettings'] as Map)['cases'] as List)
          .cast<Map<String, dynamic>>()
          .where((f) => (f['response']['data'] as Map?)?['vouchers'] != null)
          .toList();
      expect(faelle, isNotEmpty);
      for (final f in faelle) {
        final block = f['response']['data']['vouchers'] as Map<String, dynamic>;
        // Das alte Feld `label` gilt Kassen vor 11.8 (Ruling R3); das Paket liest `labelDefault` und `types[].label`.
        expect(PosVoucherSettings.fromJson(block).toJson(), {...block}..remove('label'), reason: '${f['case']}');
      }
      final w = _weg(faelle.first['response'] as Map<String, dynamic>);
      final s = await PosSettingsClient(w.transport, deviceId: '').load();
      expect(s.vouchers, PosVoucherSettings.fromJson(faelle.first['response']['data']['vouchers']));
    });

    test('fehlt der Block, ist Verkaufen aus', () {
      expect(zu.toJson(), {
        'sale': false,
        'valueVoucherType': null,
        'vatRateBp': null,
        ..._ohneSorten,
      });
      expect(PosSettings.fromJson(const {'business': {}, 'device': {}}).vouchers, zu);
      expect(PosSettings.fromJson(null).vouchers, zu);
      expect(const PosSettings.standard().vouchers, zu);
      expect(PosVoucherSettings.fromJson({'sale': 'ja'}), zu);
    });

    test('stimmige Bloecke gehen unveraendert durch', () {
      for (final b in [
        {'sale': true, 'valueVoucherType': 'single_purpose', 'vatRateBp': 2000},
        {'sale': true, 'valueVoucherType': 'multi_purpose', 'vatRateBp': null},
        {'sale': false, 'valueVoucherType': 'single_purpose', 'vatRateBp': 1000},
        {'sale': false, 'valueVoucherType': 'multi_purpose', 'vatRateBp': null},
        {'sale': false, 'valueVoucherType': null, 'vatRateBp': null},
      ]) {
        expect(PosVoucherSettings.fromJson(b).toJson(), {...b, ..._ohneSorten});
      }
    });

    test('ein unstimmiges Feld schliesst den ganzen Block', () {
      final faelle = <Object?>[
        {'sale': 'ja', 'valueVoucherType': null, 'vatRateBp': null},
        {'valueVoucherType': 'multi_purpose', 'vatRateBp': null},
        {'sale': true, 'valueVoucherType': 'xyz', 'vatRateBp': null},
        {'sale': true, 'valueVoucherType': 5, 'vatRateBp': null},
        {'sale': true, 'valueVoucherType': 'single_purpose', 'vatRateBp': 10.5},
        {'sale': true, 'valueVoucherType': 'single_purpose', 'vatRateBp': -1},
        {'sale': true, 'valueVoucherType': 'single_purpose', 'vatRateBp': '2000'},
        {'sale': true, 'valueVoucherType': null, 'vatRateBp': null},
        {'sale': true, 'valueVoucherType': 'single_purpose', 'vatRateBp': null},
        {'sale': false, 'valueVoucherType': 'single_purpose', 'vatRateBp': null},
        {'sale': true, 'valueVoucherType': 'multi_purpose', 'vatRateBp': 2000},
        [], 'x', 3, true,
      ];
      for (final f in faelle) {
        expect(PosVoucherSettings.fromJson(f), zu, reason: '$f');
      }
    });

    test('gespeichert nur, wenn vom Standard abweichend: ein Stand ohne Gutschein bleibt Byte fuer Byte', () {
      expect(const PosSettings.standard().toJson().keys, ['business', 'device']);
      final ein = PosSettings.fromJson({
        'vouchers': {'sale': true, 'valueVoucherType': 'single_purpose', 'vatRateBp': 2000},
      });
      expect(PosSettings.fromJson(ein.toJson()).vouchers, ein.vouchers);
      expect(ein.vouchers.sale, isTrue);
    });
  });

  test('Arten und Staende sind die des Vertrags', () {
    expect(voucherKinds, _surface['pos']['voucherKinds']);
    expect(voucherStatuses, _surface['pos']['voucherStatuses']);
    for (final s in VoucherStatus.values) {
      expect(VoucherStatus.fromWire(s.wire), s);
    }
    expect(VoucherStatus.fromWire('frozen'), isNull);
  });

  group('Belege der neuen Form lesen und wieder schreiben', () {
    Iterable<(String, Map<String, dynamic>)> mitGutschein() sync* {
      for (final (datei, faelle) in [('belege', _belege), ('kasse-belege', _kasseBelege), ('storno', _storno)]) {
        for (final f in faelle) {
          final daten = (f['response'] as Map)['data'];
          if (daten is! Map || daten['receipt'] is! Map) continue;
          if (((daten['receipt'] as Map)['vouchers'] as List? ?? const []).isEmpty) continue;
          yield ('$datei/${f['name']}${f['channel'] == null ? '' : '/${f['channel']}'}', daten.cast<String, dynamic>());
        }
      }
    }

    test('jeder Beispielbeleg mit Gutschein ueberlebt Lesen, Schreiben, Lesen; nichts geht verloren', () {
      var n = 0;
      for (final (name, daten) in mitGutschein()) {
        final roh = daten['receipt'] as Map<String, dynamic>;
        final r = KasseneckReceipt.fromJson(daten);
        final zurueck = KasseneckReceipt.fromJson(r.toJson());
        expect([for (final v in zurueck.vouchers!) v.toJson()], [for (final v in r.vouchers!) v.toJson()], reason: name);
        expect([for (final i in zurueck.items) i.toJson()], [for (final i in r.items) i.toJson()], reason: name);
        // Jedes Feld des Servers kommt an (ausser dem Euro-Wert `value`, der aus valueCents folgt).
        for (final (i, v) in (roh['vouchers'] as List).cast<Map<String, dynamic>>().indexed) {
          final gelesen = r.vouchers![i].toJson();
          for (final e in v.entries) {
            expect(gelesen[e.key], e.value, reason: '$name: vouchers[$i].${e.key}');
          }
        }
        for (final (i, p) in (roh['items'] as List).cast<Map<String, dynamic>>().indexed) {
          expect(r.items[i].kind, p['kind'], reason: '$name: items[$i].kind');
        }
        n++;
      }
      expect(n, greaterThanOrEqualTo(8));
    });

    test('gelesene Felder der neuen Form, Gutscheinzeilen erkannt', () {
      Map<String, dynamic> daten(String name) => _belege.firstWhere((f) => f['name'] == name)['response']['data'] as Map<String, dynamic>;
      final leistung = KasseneckReceipt.fromJson(daten('redeem_service_voucher')).vouchers!.single;
      expect([leistung.type, leistung.voucherType, leistung.codeSuffix, leistung.voucherId, leistung.positions, leistung.remainingQuantityAfter, leistung.vatRateBp, leistung.amountCents],
          [VoucherType.service, 'service', '5KNN', 'gls1', [0], 2, 2000, 3500]);
      expect(KasseneckReceipt.fromJson(daten('sale_service_voucher')).vouchers!.single.article,
          const VoucherArticle(id: 'art_mani', name: 'Maniküre', vatRateBp: 2000, priceCents: 3500));
      final auszahlung = KasseneckReceipt.fromJson(daten('payout_multi_purpose_voucher'));
      expect(auszahlung.vouchers!.single.action, VoucherAction.payout);
      expect(auszahlung.vouchers!.single.zeroRateBucket, isTrue);
      final zeile = auszahlung.items.single;
      expect([zeile.isVoucherFloat, zeile.isVoucher, zeile.priceCents], [true, false, -3000]);
      final einzweck = KasseneckReceipt.fromJson(daten('redeem_single_purpose_voucher')).items.firstWhere((i) => i.kind != null);
      expect([einzweck.isVoucher, einzweck.isVoucherFloat, einzweck.negative.kind], [true, false, 'voucher']);
    });
  });

  group('Wuensche senden (createReceipt)', () {
    const namen = [
      'sale_single_purpose_voucher', 'sale_multi_purpose_voucher', 'sale_service_voucher', 'redeem_multi_purpose_voucher',
      'redeem_single_purpose_voucher', 'redeem_service_voucher', 'redeem_promotion_voucher', 'payout_multi_purpose_voucher',
    ];

    List<KeckPaymentInput> zahlungen(Map<String, dynamic> p) => [
          for (final z in (p['payments'] as List).cast<Map<String, dynamic>>())
            KeckPaymentInput(method: KeckPaymentMethod.values.byName(z['method'] as String), amountCents: z['amountCents'] as int),
        ];
    List<KasseneckItem> positionen(Map<String, dynamic> p) =>
        [for (final i in (p['items'] as List? ?? const []).cast<Map<String, dynamic>>()) KasseneckItem.fromJson(i)];
    List<KeckVoucher> wuensche(Map<String, dynamic> p) =>
        [for (final v in (p['vouchers'] as List).cast<Map<String, dynamic>>()) KeckVoucher.fromJson(v)];

    for (final name in namen) {
      test('$name: geht ueber den Kassenweg und den API-Schluessel unveraendert hinaus', () async {
        final kassenFall = _kasseBelege.firstWhere((f) => f['name'] == name);
        final kp = (kassenFall['params'] as Map).cast<String, dynamic>();
        final w = _weg(kassenFall['response'] as Map<String, dynamic>);
        final beleg = await w.kasse.sell(items: positionen(kp), payments: zahlungen(kp), vouchers: wuensche(kp));
        // Der ganze Rumpf wie im Vertrag (Positionen, Zahlungen, Wuensche), nicht nur die
        // Gutscheine. Die Kasse legt der Sitzungs-Transport jeder Nutzlast bei (wie
        // kasse_v3_test); nennt der Fall sie nicht, zaehlt sie nicht.
        // Positionen zeichnet der Vertrag in der inneren Form auf (amount,
        // priceOneCents, vat), der Kassenweg sendet sie unter /v3 englisch (wie
        // `_soll` in kasse_v3_test); der Artikel bleibt dabei.
        final gesendet = Map<String, dynamic>.from(_params(w.log.single));
        expect(gesendet.remove('cashregisterId'), 'KASSE1');
        expect(gesendet, {
          ...kp,
          'items': [
            for (final i in (kp['items'] as List).cast<Map<String, dynamic>>())
              {
                'name': i['name'],
                'quantity': i['quantity'] ?? i['amount'],
                'unitPriceCents': i['unitPriceCents'] ?? i['priceOneCents'],
                'vatRate': i['vatRate'] ?? i['vat'],
                'articleId': ?i['articleId'],
              },
          ],
        });
        expect(beleg.vouchers, isNotEmpty);

        final apiFall = _belege.firstWhere((f) => f['name'] == name);
        final ap = (apiFall['params'] as Map).cast<String, dynamic>();
        final log = <http.Request>[];
        final api = KasseneckApi(
          apiKey: 'kr_test_x',
          cashregisterToken: base64Encode(utf8.encode('KECK-1:secret')),
          httpClient: MockClient((r) async {
            log.add(r);
            return http.Response(jsonEncode(apiFall['response']), 200,
                headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'});
          }),
        );
        await api.sellReceipt(items: positionen(ap), payments: zahlungen(ap), vouchers: wuensche(ap));
        final p = _params(log.single);
        expect(p['vouchers'], ap['vouchers']);
        expect(p['payments'], ap['payments']);
        if ((ap['items'] as List? ?? const []).isEmpty) expect(p['items'], isEmpty);
      });
    }

    Future<Object?> fehlerBeimVerkauf({
      List<KasseneckItem> items = const [],
      required List<KeckVoucher> vouchers,
      List<KeckPaymentInput> payments = const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 5000)],
      int? tipCents,
    }) async {
      final w = _weg({'status': 'error', 'message': 'darf nicht gesendet werden'});
      try {
        await w.kasse.sell(items: items, payments: payments, vouchers: vouchers, tipCents: tipCents);
      } catch (e) {
        expect(w.log, isEmpty, reason: 'nichts geht hinaus');
        return e;
      }
      fail('kein Fehler');
    }

    final kaffee = KasseneckItem(name: 'Kaffee', quantity: 1, priceCents: 320, vat: VatRate.vat20);

    test('Serverfelder an einem Wunsch und Gutscheinzeilen werden vor dem Senden abgewiesen', () async {
      for (final v in [
        KeckVoucher(action: VoucherAction.redeem, type: VoucherType.multiPurpose, code: 'X', amountCents: 1, voucherId: 'g1'),
        KeckVoucher(action: VoucherAction.redeem, type: VoucherType.multiPurpose, code: 'X', amountCents: 1, codeSuffix: '5KN2'),
        KeckVoucher(action: VoucherAction.redeem, type: VoucherType.multiPurpose, code: 'X', amountCents: 1, zeroRateBucket: true),
        KeckVoucher(action: VoucherAction.redeem, type: VoucherType.multiPurpose, code: 'X', amountCents: 1, voucherType: 'multi_purpose'),
      ]) {
        expect(await fehlerBeimVerkauf(items: [kaffee], vouchers: [v]),
            isA<KasseneckValidationError>().having((e) => e.reason, 'reason', startsWith('voucher_invalid')));
      }
      // Eine Gutscheinzeile, auch mit leerem Namen: voucher_invalid vor jeder anderen Positionspruefung.
      final zeile = KasseneckItem(name: '', quantity: 1, priceCents: -100, vat: VatRate.vat20, kind: 'voucher_float');
      expect(await fehlerBeimVerkauf(items: [zeile], vouchers: const []),
          isA<KasseneckValidationError>().having((e) => e.reason, 'reason', startsWith('voucher_invalid')));
    });

    test('Kombinationen: Verkauf und Einloesung nie zusammen, Aktion allein', () async {
      final verkauf = KeckVoucher(action: VoucherAction.sell, type: VoucherType.multiPurpose, amountCents: 100);
      final einloesung = KeckVoucher(action: VoucherAction.redeem, type: VoucherType.multiPurpose, code: 'C', amountCents: 100);
      final aktion = KeckVoucher(action: VoucherAction.redeem, type: VoucherType.promotion, code: 'P');
      expect(await fehlerBeimVerkauf(items: [kaffee], vouchers: [verkauf, einloesung]), isA<KasseneckValidationError>());
      expect(await fehlerBeimVerkauf(items: [kaffee], vouchers: [aktion, einloesung]), isA<KasseneckValidationError>());
      // Einloesen ohne Ware geht nicht.
      expect(await fehlerBeimVerkauf(vouchers: [einloesung]), isA<KasseneckValidationError>());
    });

    test('reine Auszahlung: genau eine negative Barzahlung, ohne gegeben und ohne Trinkgeld', () async {
      final auszahlung = KeckVoucher(
          action: VoucherAction.payout, type: VoucherType.multiPurpose, code: 'DTD1-NKT1-8CN5', amountCents: 3000, reason: 'Kunde zieht weg');
      for (final payments in [
        const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 3000)],
        const [KeckPaymentInput(method: KeckPaymentMethod.creditCard, amountCents: -3000)],
        const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: -1000), KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: -2000)],
        const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: -3000, tenderedCents: 0)],
        const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: -3000, tipCents: 100)],
      ]) {
        expect(await fehlerBeimVerkauf(vouchers: [auszahlung], payments: payments), isA<KasseneckValidationError>(), reason: '$payments');
      }
      // Mit Ware ist es ein gewoehnlicher Verkauf: Zahlungen positiv.
      expect(
          await fehlerBeimVerkauf(
              items: [kaffee], vouchers: [auszahlung], payments: const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: -2680)]),
          isA<KasseneckValidationError>());
    });
  });
}
