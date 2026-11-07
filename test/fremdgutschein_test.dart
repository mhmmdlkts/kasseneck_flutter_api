import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/receipt_type.dart';
import 'package:kasseneck_api/enums/voucher_action.dart';
import 'package:kasseneck_api/enums/voucher_type.dart';
import 'package:kasseneck_api/inventory.dart'
    show
        InventoryReceiptCancelledEvent,
        InventoryReceiptCreatedEvent,
        KasseneckValidationError,
        ReceiptCancelledItem,
        ReceiptRefund,
        inventoryWebhookEvents,
        parseInventoryWebhookEvent,
        receiptWebhookEvents;
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/keck_voucher.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/pos.dart' show PosExternalVouchers, PosVoucherSettings, externalVouchers, messageText, voucherErrorMessage;
import 'package:kasseneck_api/src/kasse/gutschein_wunsch.dart' show voucherWishError, vouchersWithoutItems;
import 'package:kasseneck_api/src/printing/escpos/escpos.dart';
import 'package:kasseneck_api/src/receipt/due.dart';
import 'package:kreiseck_validator/kreiseck_validator.dart' show VoucherCode;

import 'helpers/gutschein_setup.dart';

/// Fremdgutscheine (Server 2026-11) und Beleg-Webhooks: Zwilling von
/// `test/fremdgutschein.test.ts` im npm-Paket 1.30.0. Nummer, Form des
/// Wunschs, Zahlbetrag und Bon gegen die Pruefaelle des Backends
/// (`stored/voucher-cases.json` des Vertrags, byte-gleich
/// `functions/test/unit/fixtures/gutschein-faelle.json`), dazu die
/// Beleg-Ereignisse der Konto-Webhooks.
final _wurzel = Directory('test/fixtures/vertrag');

Map<String, dynamic> _json(String pfad) => jsonDecode(File('${_wurzel.path}/$pfad').readAsStringSync()) as Map<String, dynamic>;

final Map<String, dynamic> _katalog = _json('stored/voucher-cases.json');
final List<Map<String, dynamic>> _fremdFaelle =
    (_katalog['faelle'] as List).cast<Map<String, dynamic>>().where((f) => (f['name'] as String).startsWith('fg_')).toList();

Map<String, dynamic> _fall(String name) =>
    (_katalog['faelle'] as List).cast<Map<String, dynamic>>().firstWhere((f) => f['name'] == name);

KeckVoucher _mz({VoucherAction action = VoucherAction.redeem, String? number = 'W-77', int? amountCents = 300, String? reason, int? vatRateBp, String? taxedWith, String? code, String? typeId, String? articleId, int? quantity, List<int>? positions, int? valueCents, String? voucherId, String? codeSuffix, int? balanceAfterCents, VoucherType type = VoucherType.multiPurpose}) =>
    KeckVoucher(
      source: voucherSourceExternal,
      action: action,
      type: type,
      number: number,
      amountCents: amountCents,
      reason: reason,
      vatRateBp: vatRateBp,
      taxedWith: taxedWith,
      code: code,
      typeId: typeId,
      articleId: articleId,
      quantity: quantity,
      positions: positions,
      valueCents: valueCents,
      voucherId: voucherId,
      codeSuffix: codeSuffix,
      balanceAfterCents: balanceAfterCents,
    );

KeckVoucher _ez({VoucherAction action = VoucherAction.redeem, String? number = 'FG-1234', int amountCents = 2000, int? vatRateBp = 2000, String? taxedWith, String? reason}) =>
    KeckVoucher(
      source: voucherSourceExternal,
      action: action,
      type: VoucherType.singlePurpose,
      number: number,
      amountCents: amountCents,
      vatRateBp: vatRateBp,
      taxedWith: taxedWith,
      reason: reason,
    );

// ---- Pruefaelle in die Form der Kasse -----------------------------------------------

const _art = {'mehrzweck': 'multi_purpose', 'einzweck': 'single_purpose', 'leistung': 'service', 'aktion': 'promotion'};
const _freigabe = {'aus': PosExternalVouchers.off, 'wert': PosExternalVouchers.multiPurpose, 'beide': PosExternalVouchers.all};
const _umbenannt = {
  'betragCents': 'amountCents',
  'nummer': 'number',
  'satzBp': 'vatRateBp',
  'versteuertMit': 'taxedWith',
  'grund': 'reason',
  'sorteId': 'typeId',
  'artikelId': 'articleId',
  'stueck': 'quantity',
  'positionen': 'positions',
};

/// Code eines eigenen Gutscheins im Fall: der Server loest ihn vorher zur
/// `gutscheinId` auf (die Codes der Datei tragen kein gueltiges
/// Pruefzeichen); die Kasse sendet einen gueltigen Code und kennt seine
/// Pruefung. Dieselbe Ableitung wie `codeFuer` im npm-Test.
String _codeFuer(String gutscheinId) =>
    VoucherCode.generate([for (var k = 0; k < 11; k++) (gutscheinId.codeUnitAt(k % gutscheinId.length) + k * 5) & 31]);

/// Ein Wunsch des Falls (innere Form) so, wie eine Kasse ihn unter /v3 sendet.
KeckVoucher _wunsch(Map<String, dynamic> v) {
  final raus = <String, dynamic>{};
  for (final MapEntry(:key, :value) in v.entries) {
    if (key == 'artikel') continue;
    if (key == 'gutscheinId') {
      raus['code'] = _codeFuer(value as String);
      continue;
    }
    if (key == 'code' && v['gutscheinId'] != null) continue;
    if (key == 'quelle') {
      raus['source'] = value == 'extern' ? 'external' : value;
    } else if (key == 'type') {
      raus['type'] = _art[value] ?? value;
    } else {
      raus[_umbenannt[key] ?? key] = value;
    }
  }
  return KeckVoucher.fromJson(raus);
}

List<VoucherDueInfo> _pruefungen(Map<String, dynamic> e) => [
      for (final v in (e['vouchers'] as List).cast<Map<String, dynamic>>())
        if (v['gutscheinId'] != null && (e['gutscheine'] as Map?)?[v['gutscheinId']] != null)
          VoucherDueInfo(
              code: _codeFuer(v['gutscheinId'] as String),
              check: pruefungAus(((e['gutscheine'] as Map)[v['gutscheinId']] as Map).cast<String, dynamic>())),
    ];

ReceiptDueBreakdown _rechne(Map<String, dynamic> e, {bool mitFreigabe = true}) {
  final info = _pruefungen(e);
  return receiptDueBreakdownForLines(
    [for (final it in (e['items'] as List? ?? const []).cast<Map<String, dynamic>>()) ReceiptDueLine.fromJson(it)],
    [for (final v in (e['vouchers'] as List).cast<Map<String, dynamic>>()) _wunsch(v)],
    ReceiptType.standard,
    externalVouchers: mitFreigabe ? _freigabe[e['fremd'] ?? 'aus'] : null,
    smallBusiness: e['kleinunternehmer'] == true,
    today: e['heute'] as String,
    zeroRateBucketFrom: _katalog['nulltopfAb'] as String,
    voucherInfo: info.isEmpty ? null : info,
  );
}

/// Gutschein-Eintrag in der gespeicherten Form des Servers nach /v3 (Zwilling
/// von `BELEG_GUTSCHEIN` in `stored/draht.ts` des npm-Pakets, nur die Felder
/// der Pruefaelle).
const _eintragNachAussen = {
  'art': 'voucherType',
  'gutscheinId': 'voucherId',
  'codeEnde': 'codeSuffix',
  'betragCents': 'amountCents',
  'satzBp': 'vatRateBp',
  'saldoNachCents': 'balanceAfterCents',
  'versteuertMit': 'taxedWith',
  'befreit': 'exempt',
  'grund': 'reason',
  'imNullTopf': 'zeroRateBucket',
  'quelle': 'source',
  'nummer': 'number',
};

Map<String, dynamic> _eintrag(Map<String, dynamic> v) => {
      for (final MapEntry(:key, :value) in v.entries)
        if (key == 'type')
          'type': _art[value] ?? value
        else if (key == 'art')
          'voucherType': _art[value] ?? value
        else if (key == 'quelle')
          'source': value == 'extern' ? 'external' : value
        else
          _eintragNachAussen[key] ?? key: value,
    };

/// Der Beleg eines Falls, wie der Server ihn speichert (Ware + Gutscheinzeilen), gelesen wie unter /v3.
KasseneckReceipt _beleg(Map<String, dynamic> f) {
  final e = f['eingabe'] as Map<String, dynamic>;
  final x = f['erwartet'] as Map<String, dynamic>;
  final storno = e['stornoVon'] != null;
  final items = storno ? x['positionen'] as List : [...(e['items'] as List? ?? const []), ...x['positionen'] as List];
  return KasseneckReceipt.fromMetadata({
    'receiptId': 'KASSE1-ID-7',
    'cashregisterId': 'KASSE1',
    'timeStamp': '2026-11-05T10:15:30',
    'receiptType': storno ? 'cancellation' : 'standard',
    'items': items,
    'vouchers': [for (final v in (x['vouchers'] as List).cast<Map<String, dynamic>>()) _eintrag(v)],
    'paymentMethod': 'cash',
    'payments': <Object?>[],
    'qr': 'QR',
    'sig': 'SIG',
    'turnoverCounterAES256ICM': 'U',
    'signaturePreviousReceipt': 'V',
    'certificateSerialNumber': 'C',
  }, {'company': 'Bäckerei Kornblum'});
}

/// Was der Rueckfall ohne Server-Layout druckt, als Zeilen (Zweispalter mit " | ").
Future<List<String>> _gedruckt(KasseneckReceipt beleg, {KeckPaperSize papier = KeckPaperSize.mm80}) async {
  final paper = PrintPaper(paperSize: papier, profile: CapabilityProfile());
  await paper.setKeckReceipt(beleg);
  return [
    for (final c in paper.myPosPaper.commands)
      switch (c['type']) {
        'doubleText' => '${c['leftValue']} | ${c['rightValue']}',
        'text' => c['value'] as String,
        _ => '',
      }
  ];
}

String _huelle(String type, Object? data) =>
    jsonEncode({'id': 'evt_0123456789abcdefghij', 'type': type, 'createdAt': 1762334130000, 'accountId': 'kw_betrieb1', 'data': data});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---- Nummer ----------------------------------------------------------------------

  group('Fremdnummer', () {
    test('Rand weg (fester Leerraum-Satz, ohne NEL), keine Normalisierung, 1-40 aus A-Z a-z 0-9 - _ . /', () {
      const n = normalizeExternalVoucherNumber;
      expect(n('FG-1234'), 'FG-1234');
      expect(n(' fg-1 '), 'fg-1');
      expect(n(' FG-1'), 'FG-1');
      expect(n('FG-1 '), 'FG-1');
      expect(n('﻿FG-1'), 'FG-1');
      expect(n('　FG-1 '), 'FG-1');
      expect(n('\t\n\v\f\r        A_b.c/9  '), 'A_b.c/9');
      expect(n('K'), 'K');
      expect(n('FG-K1'), 'FG-K1');
      expect(n('A' * 40), 'A' * 40);
      // Kelvin-Zeichen (U+212A) sieht aus wie K, ist aber kein ASCII: ungueltig, nie still zu K gefaltet.
      expect(n('K'), isNull);
      expect(n('FG-K1'), isNull);
      // NEL (U+0085) nimmt Dart-trim mit, JavaScript-trim nicht: hier bleibt es und macht die Nummer ungueltig.
      for (final falsch in <Object?>[
        '', '   ', 'A' * 41, 'a b', 'ä', '<x>', 'FG-1\u0085', '\u0085FG-1', 'FG​1', 'ＦＧ-1', 'ä', null, 12,
      ]) {
        expect(n(falsch), isNull, reason: jsonEncode('$falsch'));
      }
    });

    test('ein gueltiger eigener Gutscheincode (jede Schreibweise der Kasse) ist keine Fremdnummer, und das zuerst', () {
      const eigen = ExternalVoucherNumberCheck.rejected('external_voucher_number_is_own_code');
      const ungueltig = ExternalVoucherNumberCheck.rejected('external_voucher_number_invalid');
      for (final c in ['7148FGQA935K', '7148-FGQA-935K', '7148 fgqa 935k', ' 7148-FGQA-935K ']) {
        expect(checkExternalVoucherNumber(c), eigen, reason: c);
      }
      for (final c in ['K', 'FG-K1', 'FG-1234', '7148-FGQA-935J']) {
        expect(checkExternalVoucherNumber(c).ok, isTrue, reason: c);
      }
      // Trenner einer Fremdnummer (. _ /) zwischen den Gruppen: trotzdem der eigene Code; die Nummer behaelt ihre Schreibweise.
      for (final c in ['7148.FGQA.935K', '7148_FGQA_935K', '7148/FGQA/935K', '7148.fgqa_935k', '7148/FGQA-935K']) {
        expect(checkExternalVoucherNumber(c), eigen, reason: c);
        expect(normalizeExternalVoucherNumber(c), c, reason: c);
      }
      for (final c in ['7148.FGQA.935J', 'FG.1234', 'A/B_C.D']) {
        expect(checkExternalVoucherNumber(c).ok, isTrue, reason: c);
      }
      // Ein eigener Code mit Kelvin-Zeichen statt K ist kein eigener Code (der Validator faltet nicht), sondern ungueltig.
      expect(checkExternalVoucherNumber('7148FGQA935K'), ungueltig);
      expect(checkExternalVoucherNumber('7148-FGQA-935K'), ungueltig);
      expect(checkExternalVoucherNumber('FG-K1'), ungueltig);
      expect(checkExternalVoucherNumber(' fg-1 '), const ExternalVoucherNumberCheck.ok('fg-1'));
      expect(checkExternalVoucherNumber(' fg-1 ').number, 'fg-1');
      expect(checkExternalVoucherNumber(''), ungueltig);
      expect(checkExternalVoucherNumber('FG-1\u0085'), ungueltig);
      expect(checkExternalVoucherNumber(null), ungueltig);
    });
  });

  // ---- Wunsch ------------------------------------------------------------------------

  group('Wunsch', () {
    test('Fremdgutscheine der Form des Servers sind sendbar, sonst nicht', () {
      expect(voucherSources, ['external']);
      expect([...externalVoucherVatRatesBp]..sort(), [0, 490, 1000, 1300, 1900, 2000]);
      expect([externalVoucherNumberMax, externalVoucherTaxedWithMax], [40, 40]);
      final gut = [
        _mz(),
        _mz(action: VoucherAction.sell),
        _mz(action: VoucherAction.payout, reason: 'Kulanz'),
        _ez(),
        _ez(action: VoucherAction.sell),
        _ez(taxedWith: 'FG-1234-V'),
        _ez(vatRateBp: 0),
        _ez(vatRateBp: 490),
        _ez(action: VoucherAction.payout, reason: 'Kulanz', taxedWith: 'X'),
        _mz(number: ' fg-1 '),
        _mz(amountCents: 1000000),
      ];
      for (final v in gut) {
        expect(v.isExternal, isTrue);
        expect(v.isNewForm, isTrue);
        expect(externalVoucherIsValid(v), isTrue, reason: jsonEncode(v.toPayload()));
        expect(v.isValid, isTrue, reason: jsonEncode(v.toPayload()));
      }
      // Was npm darueber hinaus prueft (code: null, amountCents 1.5, action 'storno', vatRateBp 2000.5), laesst
      // sich in Dart nicht bauen: ein null-Feld geht nie hinaus, Betrag und Satz sind int, die Aktion ein Enum.
      final schlecht = [
        _mz(type: VoucherType.value), _mz(type: VoucherType.service), _mz(type: VoucherType.promotion), _mz(type: VoucherType.promo),
        _mz(number: ''), _mz(number: 'a b'), _mz(number: null), _mz(number: '7148-FGQA-935K'), _mz(number: '7148.FGQA.935K'),
        _mz(amountCents: 0), _mz(amountCents: 1000001), _mz(amountCents: null), _mz(vatRateBp: 2000), _mz(taxedWith: 'X'),
        _mz(code: 'GS-1'), _mz(typeId: 's1'), _mz(articleId: 'a1'), _mz(quantity: 1), _mz(positions: [0]),
        _mz(valueCents: 300), _mz(voucherId: 'g1'), _mz(codeSuffix: 'ABCD'), _mz(balanceAfterCents: 0),
        _mz(action: VoucherAction.payout), _mz(action: VoucherAction.payout, reason: '  '), _mz(action: VoucherAction.payout, reason: 'x' * 201),
        _ez(vatRateBp: null), _ez(vatRateBp: 700),
        _ez(action: VoucherAction.sell, taxedWith: 'X'), _ez(taxedWith: ''), _ez(taxedWith: '   '), _ez(taxedWith: 'x' * 41),
        _ez(taxedWith: 'a\u0007b'), _ez(taxedWith: 'a​b'), _ez(taxedWith: 'X\u0085'),
      ];
      for (final v in schlecht) {
        expect(v.isValid, isFalse, reason: jsonEncode(v.toPayload()));
      }
      // Eine andere Herkunft als external ist kein Fremdgutschein und an einem eigenen Wunsch ungueltig.
      final fremdeQuelle = KeckVoucher(source: 'webshop', action: VoucherAction.redeem, type: VoucherType.multiPurpose, code: '7148-FGQA-935K', amountCents: 500);
      expect(fremdeQuelle.isExternal, isFalse);
      expect(fremdeQuelle.isValid, isFalse);
    });

    test('Felder nur des Fremdgutscheins an einem eigenen Wunsch sind ungueltig (wie der Server)', () {
      KeckVoucher eigen({String? number, String? taxedWith, int? vatRateBp, String? source}) => KeckVoucher(
          action: VoucherAction.redeem,
          type: VoucherType.multiPurpose,
          code: '7148-FGQA-935K',
          amountCents: 500,
          number: number,
          taxedWith: taxedWith,
          vatRateBp: vatRateBp,
          source: source);
      expect(eigen().isValid, isTrue);
      expect(eigen(number: 'FG-1').isValid, isFalse);
      expect(eigen(taxedWith: 'FG-1').isValid, isFalse);
      expect(eigen(vatRateBp: 2000).isValid, isFalse);
      expect(eigen(source: 'webshop').isValid, isFalse);
      // npm prueft dieselben Felder auch als null; in Dart geht ein null-Feld nie hinaus (toPayload laesst es weg).
      expect(eigen().toPayload().keys, isNot(containsAll(['number', 'taxedWith', 'vatRateBp', 'source'])));
    });

    test('geht mit source und number hinaus, ohne valueCents, und liest sich so zurueck', () {
      final p = _ez(taxedWith: 'FG-1234-V').toPayload();
      expect(p, {
        'action': 'redeem',
        'type': 'single_purpose',
        'source': 'external',
        'number': 'FG-1234',
        'amountCents': 2000,
        'vatRateBp': 2000,
        'taxedWith': 'FG-1234-V',
      });
      expect(KeckVoucher.fromJson(p).toPayload(), p);
      expect(_mz().toPayload(), {'action': 'redeem', 'type': 'multi_purpose', 'source': 'external', 'number': 'W-77', 'amountCents': 300});
      // Gespeicherte Form (toJson) traegt Herkunft und Nummer und liest sich gleich zurueck.
      final gespeichert = jsonDecode(jsonEncode(_mz().toJson())) as Map<String, dynamic>;
      expect([gespeichert['source'], gespeichert['number']], ['external', 'W-77']);
      expect(KeckVoucher.fromJson(gespeichert).isExternal, isTrue);
      expect(KeckVoucher.fromJson(gespeichert).number, 'W-77');
    });

    test('Verkaufspruefung vor dem Senden: kein voucher_type_required, keine Positionen noetig, Form wie der Server', () {
      final verkauf = _mz(action: VoucherAction.sell, amountCents: 3000);
      expect(voucherWishError([verkauf], const [], training: false), isNull);
      expect(vouchersWithoutItems([verkauf]), isTrue);
      expect(voucherWishError([_mz(action: VoucherAction.sell, number: 'a b')], const [], training: false), isNotNull);
      // Schulungsbelege kennen die neue Form nicht, den Fremdgutschein auch nicht.
      expect(voucherWishError([verkauf], const [], training: true), contains('Schulungsbelegen'));
    });

    test('Altform mit freiem Code: nur der benannte Weg ist abgekuendigt, die Werte gleichen dem Konstruktor', () {
      // ignore: deprecated_member_use_from_same_package
      final alt = KeckVoucher.legacyValue(action: VoucherAction.redeem, code: 'WG-1', valueCents: 500);
      final gleich = KeckVoucher(action: VoucherAction.redeem, type: VoucherType.value, code: 'WG-1', valueCents: 500);
      expect(alt.toPayload(), gleich.toPayload());
      expect(alt.toPayload(), {'action': 'redeem', 'type': 'value', 'valueCents': 500, 'code': 'WG-1'});
      expect(alt.isValid, isTrue);
    });
  });

  test('Texte: jeder Code der Fremdgutscheine hat einen Satz (Woerter des Backends)', () {
    const erwartet = {
      'external_voucher_not_enabled': 'Fremde Gutscheine sind für dieses Konto nicht freigegeben.',
      'external_voucher_type_not_enabled': 'Fremde Einzweckgutscheine sind für dieses Konto nicht freigegeben.',
      'external_voucher_number_invalid': 'Gutscheinnummer prüfen: 1 bis 40 Zeichen, nur Buchstaben, Ziffern und - _ . / sind erlaubt.',
      'external_voucher_number_is_own_code': 'Das ist ein eigener Gutscheincode. Bitte als eigenen Gutschein einlösen.',
      'external_voucher_duplicate': 'Diese Gutscheinnummer steht schon auf dem Beleg.',
    };
    for (final MapEntry(key: code, value: text) in erwartet.entries) {
      expect(messageText(voucherErrorMessage(code)!), text, reason: code);
    }
  });

  group('Einstellung externalVouchers', () {
    Map<String, dynamic> block([Map<String, Object?> extra = const {}]) => {
          'sale': false,
          'valueVoucherType': null,
          'vatRateBp': null,
          'typeSale': true,
          'types': [
            {
              'id': 'sorte_wert',
              'name': 'Wertgutschein',
              'kind': 'multi_purpose',
              'vatRateBp': null,
              'amount': {'mode': 'free'},
              'validity': {'pattern': 'unlimited'},
              'payout': 'allowed',
              'order': 0,
              'active': true,
            },
          ],
          'serviceArticles': false,
          ...extra,
        };

    test('wird gelesen; unbekannt oder fehlend ist aus und schliesst nie den Block', () {
      expect(externalVouchers, ['off', 'multi_purpose', 'all']);
      for (final f in PosExternalVouchers.values) {
        expect(PosVoucherSettings.fromJson(block({'externalVouchers': f.wire})).externalVouchers, f);
      }
      expect(PosVoucherSettings.fromJson(block()).externalVouchers, PosExternalVouchers.off);
      for (final kaputt in <Object?>['wert', 'beide', 'aus', true, 1, null]) {
        final s = PosVoucherSettings.fromJson(block({'externalVouchers': kaputt}));
        expect(s.externalVouchers, PosExternalVouchers.off, reason: '$kaputt');
        expect(s.types, hasLength(1), reason: '$kaputt');
      }
      expect(PosVoucherSettings.off.externalVouchers, PosExternalVouchers.off);
      // Gleichheit sieht die Freigabe: ein anderer Stand ist ein anderer.
      expect(PosVoucherSettings.fromJson(block({'externalVouchers': 'all'})), isNot(PosVoucherSettings.fromJson(block())));
    });
  });

  // ---- Pruefaelle: Zahlbetrag ------------------------------------------------------

  group('Pruefaelle des Backends (voucher-cases.json)', () {
    test('die Kopie traegt die Fremdfaelle', () {
      expect(_fremdFaelle.length, greaterThanOrEqualTo(30));
      expect(_katalog['nulltopfAb'], isA<String>());
    });

    test('Zahlbetrag, Zaehler, Toepfe und Abweisungscode jedes Fremdfalls wie der Server', () {
      var gerechnet = 0;
      for (final f in _fremdFaelle) {
        final e = f['eingabe'] as Map<String, dynamic>;
        final x = f['erwartet'] as Map<String, dynamic>;
        if (e['stornoVon'] != null) continue;
        final name = f['name'] as String;
        if (x['fehler'] != null) {
          expect(() => _rechne(e), throwsA(isA<ReceiptDueError>().having((r) => r.voucherErrorCode, 'voucherErrorCode', x['fehler'])),
              reason: name);
        } else {
          final r = _rechne(e);
          expect(r.dueCents, x['zahlbetragCents'], reason: '$name: Zahlbetrag');
          expect(r.counterDeltaCents, x['zaehlerDeltaCents'], reason: '$name: Zaehler');
          expect({for (final MapEntry(:key, :value) in r.bucketsCents!.entries) if (value != 0) key: value}, x['toepfeCents'],
              reason: '$name: Toepfe');
        }
        gerechnet++;
      }
      expect(gerechnet, greaterThanOrEqualTo(25));
    });

    test('ohne Freigabe-Angabe prueft nur der Server die Freigabe; die Einstellung zaehlt, wenn die Angabe fehlt', () {
      final e = _fall('fg_fehler_nicht_freigegeben')['eingabe'] as Map<String, dynamic>;
      expect(() => _rechne(e, mitFreigabe: false), returnsNormally);
      final zeilen = [for (final it in (e['items'] as List).cast<Map<String, dynamic>>()) ReceiptDueLine.fromJson(it)];
      final wuensche = [for (final v in (e['vouchers'] as List).cast<Map<String, dynamic>>()) _wunsch(v)];
      ReceiptDueBreakdown mit({PosExternalVouchers? angabe, PosExternalVouchers? einstellung}) => receiptDueBreakdownForLines(
            zeilen,
            wuensche,
            ReceiptType.standard,
            externalVouchers: angabe,
            voucherSettings: einstellung == null
                ? null
                : PosVoucherSettings(sale: false, valueVoucherType: null, vatRateBp: null, externalVouchers: einstellung),
            today: e['heute'] as String,
          );
      Matcher abgelehnt(String code) => throwsA(isA<ReceiptDueError>().having((r) => r.voucherErrorCode, 'code', code));
      expect(() => mit(einstellung: PosExternalVouchers.off), abgelehnt('external_voucher_not_enabled'));
      expect(() => mit(einstellung: PosExternalVouchers.multiPurpose), returnsNormally);
      // Die ausdrueckliche Angabe gewinnt gegen die Einstellung.
      expect(() => mit(angabe: PosExternalVouchers.all, einstellung: PosExternalVouchers.off), returnsNormally);
      expect(() => mit(angabe: PosExternalVouchers.off, einstellung: PosExternalVouchers.all), abgelehnt('external_voucher_not_enabled'));
      // Ein fremder Einzweck braucht `all`; ohne Angabe ueberhaupt rechnet er (der Server prueft).
      final ez = _ez(amountCents: 400);
      ReceiptDueBreakdown einzweck(PosExternalVouchers? f) =>
          receiptDueBreakdownForLines(zeilen, [ez], ReceiptType.standard, externalVouchers: f, today: e['heute'] as String);
      expect(() => einzweck(PosExternalVouchers.multiPurpose), abgelehnt('external_voucher_type_not_enabled'));
      expect(einzweck(PosExternalVouchers.all).dueCents, einzweck(null).dueCents);
    });
  });

  // ---- Pruefaelle: Bon ------------------------------------------------------------------

  group('Bon im Rueckfall (setKeckReceipt) aus den Pruefaellen', () {
    test('jeder Fremdbeleg zeigt „Gutschein Nr. …“, den Vermerk, nie einen Rest, und Gesamt = Zahlbetrag', () async {
      var gezeigt = 0;
      for (final f in _fremdFaelle) {
        final x = f['erwartet'] as Map<String, dynamic>;
        if (x['fehler'] != null || x['vouchers'] is! List) continue;
        final name = f['name'] as String;
        final beleg = _beleg(f);
        final fremde = beleg.vouchers!.where((v) => v.isExternal).toList();
        expect(fremde.length, (x['vouchers'] as List).where((v) => (v as Map)['quelle'] == 'extern').length, reason: name);
        final zeilen = await _gedruckt(beleg);
        // Rest nur bei eigenen Gutscheinen (fg_eigen_und_fremd): je eigener hoechstens eine Zeile.
        final reste = zeilen.where((z) => z.contains('Rest am Gutschein')).length;
        expect(reste, lessThanOrEqualTo(beleg.vouchers!.length - fremde.length), reason: '$name: Rest am Bon');
        for (final v in fremde) {
          expect(zeilen.any((z) => z.contains('Gutschein Nr. ${v.number}')), isTrue, reason: '$name: Zeile ${v.number}\n${zeilen.join('\n')}');
          // Vermerk an der Einloesung; die Auszahlung traegt wie beim eigenen Gutschein den Grund.
          if (v.taxedWith != null && v.action == VoucherAction.redeem) {
            expect(zeilen, contains('  Einzweck, versteuert mit ${v.taxedWith}'), reason: '$name: Vermerk');
          }
          if (v.action == VoucherAction.payout && v.reason != null) {
            expect(zeilen, contains('  Grund: ${v.reason}'), reason: '$name: Grund');
          }
        }
        expect(zeilen.any((z) => z.contains('····')), beleg.vouchers!.length > fremde.length, reason: '$name: Maske nur bei eigenen');
        final gesamt = zeilen.firstWhere((z) => z.startsWith('Gesamt:'));
        expect(gesamt, 'Gesamt: | ${formatCents(x['zahlbetragCents'] as int)} EUR', reason: name);
        expect(beleg.sumCents, x['zahlbetragCents'], reason: '$name: sumCents');
        gezeigt++;
      }
      expect(gezeigt, greaterThanOrEqualTo(20));
    });

    test('das Beispiel der Spec (fg_ez_und_mz_einloesung_bon) Zeile fuer Zeile', () async {
      final zeilen = await _gedruckt(_beleg(_fall('fg_ez_und_mz_einloesung_bon')));
      final von = zeilen.indexOf('1  x Brauereiführung | 20,00 A');
      expect(von, greaterThanOrEqualTo(0), reason: zeilen.join('\n'));
      expect(zeilen.sublist(von, von + 4), [
        '1  x Brauereiführung | 20,00 A',
        '1  x Bier 0,5 | 4,50 A',
        'Gutschein Nr. FG-1234 | -20,00 A',
        '  Einzweck, versteuert mit FG-1234-V',
      ]);
      final zs = zeilen.indexOf('Zwischensumme | 4,50 EUR');
      expect(zeilen.sublist(zs, zs + 2), ['Zwischensumme | 4,50 EUR', 'Gutschein Nr. W-77 | -3,00 EUR']);
      expect(zeilen, contains('Gesamt: | 1,50 EUR'));
      expect(zeilen.any((z) => z.contains('Rest am Gutschein')), isFalse);
    });

    test('Mehrzweck-Verkauf vor dem Stichtag (nur Eintrag): „Gutschein Nr. … (Mehrzweckgutschein)“, USt bei Einlösung, 0 % einmal', () async {
      final beleg = KasseneckReceipt.fromMetadata({
        'receiptId': 'KASSE1-ID-8',
        'cashregisterId': 'KASSE1',
        'timeStamp': '2026-11-05T10:15:30',
        'receiptType': 'standard',
        'items': <Object?>[],
        'vouchers': [
          {
            'source': 'external',
            'action': 'sell',
            'type': 'value',
            'voucherType': 'multi_purpose',
            'number': 'W-77',
            'value': 30,
            'valueCents': 3000,
            'name': 'Gutschein Nr. W-77 (Mehrzweckgutschein)',
          },
        ],
        'paymentMethod': 'cash',
        'qr': 'QR',
        'sig': 'SIG',
        'turnoverCounterAES256ICM': 'U',
        'signaturePreviousReceipt': 'V',
        'certificateSerialNumber': 'C',
      }, {'company': 'Bäckerei Kornblum'});
      final zeilen = await _gedruckt(beleg);
      expect(zeilen, containsAllInOrder(['1  x Gutschein Nr. W-77 (Mehrzweckgutschein) | 30,00 D', '  USt bei Einlösung']));
      expect(zeilen.where((z) => z.contains('W-77')), hasLength(1));
      expect(zeilen.firstWhere((z) => z.startsWith('Gesamt:')), 'Gesamt: | 30,00 EUR');
      expect(beleg.sumCents, 3000);
    });

    test('die Golden-Belege voucher-external-* Zeile fuer Zeile im Positions- und Zahlungsteil', () async {
      Future<List<String>> golden(String name) async {
        final ein = _json('receipts/$name.json');
        return _gedruckt(KasseneckReceipt.fromMetadata(ein['receipt'], {'company': (ein['company'] as Map)['companyName']}));
      }

      final einloesung = await golden('voucher-external-redeem');
      final i = einloesung.indexOf('1  x Brauereiführung | 20,00 A');
      expect(einloesung.sublist(i, i + 4), [
        '1  x Brauereiführung | 20,00 A',
        '1  x Bier 0,5 | 4,50 A',
        'Gutschein Nr. FG-1234 | -20,00 A',
        '  Einzweck, versteuert mit FG-1234-V',
      ]);
      final zs = einloesung.indexOf('Zwischensumme | 4,50 EUR');
      expect(einloesung.sublist(zs, zs + 2), ['Zwischensumme | 4,50 EUR', 'Gutschein Nr. W-77 | -3,00 EUR']);
      expect(einloesung, contains('Gesamt: | 1,50 EUR'));

      final verkauf = await golden('voucher-external-sale');
      final k = verkauf.indexWhere((z) => z.startsWith('1  x Gutschein Nr. W-77'));
      expect(verkauf.sublist(k, k + 3), [
        '1  x Gutschein Nr. W-77 (Mehrzweckgutschein) | 30,00 D',
        '  USt bei Einlösung',
        '1  x Gutschein Nr. FG-1234 (Einzweckgutschein 20 %) | 20,00 A',
      ]);
      expect(verkauf, contains('Gesamt: | 50,00 EUR'));
      expect([...einloesung, ...verkauf].any((z) => z.contains('Rest am Gutschein')), isFalse);
    });
  });

  // ---- Antwort: deprecation ------------------------------------------------------------

  test('Verkauf mit Altform-Wertgutschein und freiem Code: deprecation wird gelesen, sonst null', () {
    final fall = (_json('v3/antworten/belege.json')['cases'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((c) => c['name'] == 'sale_v2_items_value_voucher');
    final daten = (fall['response'] as Map)['data'] as Map<String, dynamic>;
    final r = KasseneckReceipt.fromJson(daten);
    expect(r.deprecation, daten['deprecation']);
    expect(r.deprecation, startsWith('Wertgutscheine mit frei getipptem Code'));
    expect(KasseneckReceipt.fromJson({...daten, 'deprecation': ''}).deprecation, isNull);
    expect(KasseneckReceipt.fromJson({...daten, 'deprecation': 7}).deprecation, isNull);
    expect(KasseneckReceipt.fromJson({...daten}..remove('deprecation')).deprecation, isNull);
    // Beschreibt die Antwort, nicht den Beleg: nie in der gespeicherten Form.
    expect(jsonEncode(r.toJson()), isNot(contains('deprecation')));
  });

  // ---- Beleg-Webhooks --------------------------------------------------------------------

  group('Beleg-Webhooks', () {
    final roh = (_json('receipts/voucher-external-redeem.json')['receipt'] as Map).cast<String, dynamic>();
    // Die Golden-Eingabe fuehrt Freitextzeilen als Liste; am Draht stehen sie als Text.
    final beleg = {...roh, 'customerDetails': '', 'legalMessage': ''};

    test('die Ereignisse stehen hinten in inventoryWebhookEvents', () {
      expect(receiptWebhookEvents, ['receipt.created', 'receipt.cancelled']);
      expect(inventoryWebhookEvents.sublist(inventoryWebhookEvents.length - 2), receiptWebhookEvents);
    });

    test('receipt.created traegt den Beleg wie listReceipts view full', () {
      final e = parseInventoryWebhookEvent(_huelle('receipt.created', {'receipt': beleg}));
      expect(e, isA<InventoryReceiptCreatedEvent>());
      e as InventoryReceiptCreatedEvent;
      expect([e.type, e.id, e.createdAt, e.accountId, e.test], ['receipt.created', 'evt_0123456789abcdefghij', 1762334130000, 'kw_betrieb1', false]);
      expect(e.data.receipt, beleg);
      expect(e.data.truncated, isFalse);
      expect(e.data.hint, isNull);
      final gelesen = KasseneckReceipt.fromMetadata(e.data.receipt, const {});
      expect([for (final v in gelesen.vouchers!) v.number], ['FG-1234', 'W-77']);
      expect(gelesen.vouchers!.every((v) => v.isExternal), isTrue);
      expect(gelesen.sumCents, 150);
      // Gekuerzt: ohne Positionen, mit Hinweis.
      final k = parseInventoryWebhookEvent(
          _huelle('receipt.created', {'receipt': {...beleg}..remove('items'), 'truncated': true, 'hint': 'Beleg zu groß'}));
      k as InventoryReceiptCreatedEvent;
      expect([k.data.truncated, k.data.hint, k.data.receipt.containsKey('items')], [true, 'Beleg zu groß', false]);
      expect(KasseneckReceipt.fromMetadata(k.data.receipt, const {}).items, isEmpty);
      // Nur genau true kuerzt.
      final nicht = parseInventoryWebhookEvent(_huelle('receipt.created', {'receipt': beleg, 'truncated': 'ja', 'hint': 3}));
      expect([(nicht as InventoryReceiptCreatedEvent).data.truncated, nicht.data.hint], [false, null]);
      for (final kaputt in <Object?>[<String, Object?>{}, {'receipt': null}, {'receipt': 'KASSE1-ID-7'}, {'receipt': []}]) {
        expect(() => parseInventoryWebhookEvent(_huelle('receipt.created', kaputt)), throwsA(isA<KasseneckValidationError>()), reason: '$kaputt');
      }
    });

    test('receipt.cancelled mit Bezug, stornierten Positionen und Rueckzahlungen', () {
      final storno = {...beleg, 'receiptType': 'cancellation'};
      final daten = {
        'receipt': storno,
        'cancellationOf': 'KASSE1-ID-6',
        'cancelledItems': [
          {'index': 0, 'quantity': 1},
          {'index': null, 'quantity': 1},
        ],
        'refunds': [
          {'refundOf': 'p1', 'amountCents': 150, 'method': 'cash'},
          {'refundOf': null, 'amountCents': 100, 'method': 'cash'},
        ],
      };
      final e = parseInventoryWebhookEvent(_huelle('receipt.cancelled', daten));
      expect(e, isA<InventoryReceiptCancelledEvent>());
      e as InventoryReceiptCancelledEvent;
      expect(e.type, 'receipt.cancelled');
      expect(e.data.receipt, storno);
      expect(e.data.cancellationOf, 'KASSE1-ID-6');
      expect(e.data.cancelledItems, const [ReceiptCancelledItem(index: 0, quantity: 1), ReceiptCancelledItem(index: null, quantity: 1)]);
      expect(e.data.refunds, const [
        ReceiptRefund(refundOf: 'p1', amountCents: 150, method: 'cash'),
        ReceiptRefund(refundOf: null, amountCents: 100, method: 'cash'),
      ]);
      // Nachsichtig je Feld: Bruchzahl, Text oder leerer Text werden null (wie npm ganzOderNull/textOderNull).
      final schief = parseInventoryWebhookEvent(_huelle('receipt.cancelled', {
        ...daten,
        'cancelledItems': [
          {'index': 1.5, 'quantity': '1'},
          {'index': 2.0},
        ],
        'refunds': [
          {'refundOf': '', 'amountCents': 1.5, 'method': 7},
        ],
      })) as InventoryReceiptCancelledEvent;
      expect(schief.data.cancelledItems, const [ReceiptCancelledItem(index: null, quantity: null), ReceiptCancelledItem(index: 2, quantity: null)]);
      expect(schief.data.refunds, const [ReceiptRefund(refundOf: null, amountCents: null, method: null)]);
      // Der veraltete Storno ohne Bezug: cancellationOf null (auch ein leerer Text).
      for (final ohne in <Object?>[null, '']) {
        final alt = parseInventoryWebhookEvent(_huelle('receipt.cancelled', {...daten, 'cancellationOf': ohne})) as InventoryReceiptCancelledEvent;
        expect(alt.data.cancellationOf, isNull);
      }
      for (final kaputt in [
        {...daten, 'cancellationOf': 7},
        {...daten}..remove('cancellationOf'),
        {...daten, 'cancelledItems': null},
        {...daten, 'cancelledItems': [1]},
        {...daten, 'refunds': [1]},
        {...daten, 'refunds': 'keine'},
        {...daten}..remove('receipt'),
      ]) {
        expect(() => parseInventoryWebhookEvent(_huelle('receipt.cancelled', kaputt)), throwsA(isA<KasseneckValidationError>()),
            reason: jsonEncode(kaputt));
      }
    });

    test('ein Ereignis einer spaeteren Version bleibt null', () {
      expect(parseInventoryWebhookEvent(_huelle('receipt.updated', {'receipt': beleg})), isNull);
    });
  });
}
