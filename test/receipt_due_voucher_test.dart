import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/enums/receipt_type.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/enums/voucher_action.dart';
import 'package:kasseneck_api/enums/voucher_type.dart';
import 'package:kasseneck_api/kasseneck_api.dart' as wurzel;
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/models/keck_payment.dart';
import 'package:kasseneck_api/models/keck_voucher.dart';
import 'package:kasseneck_api/pos.dart' show PosVoucherSettings, VoucherCheck, VoucherStatus, VoucherValidity;
import 'package:kasseneck_api/src/receipt/due.dart';

import 'helpers/gutschein_setup.dart';

/// Zahlbetrag mit Gutscheinen der neuen Form: Zwilling von
/// `test/due-gutschein.test.ts` im npm-Paket und damit von
/// `gutschein-beleg.plane` + `gutschein-beleg.zahlbetrag` im Backend. Die Kasse
/// rechnet ihn, bevor ein Kartenterminal belastet wird; der Server weist eine
/// andere Summe mit `payments_sum_mismatch` ab.
final _wurzel = Directory('test/fixtures/vertrag');

Map<String, dynamic> _json(String pfad) => jsonDecode(File('${_wurzel.path}/$pfad').readAsStringSync()) as Map<String, dynamic>;

ReceiptDueLine pos(String name, int cents, num satz, {num quantity = 1, String? articleId, String? kind}) =>
    ReceiptDueLine(quantity: quantity, priceCents: cents, vatRate: satz, articleId: articleId, kind: kind);

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

const codeM = 'DTD5-9ECF-5KNZ';
const codeE = '5TD5-9ECF-5KN2';
const codeL = 'CKD59ECF5KNN';
const codeA = '1BD59ECF5KNJ';
const codeP = 'DTD1-NKT1-8CN5';

VoucherCheck mehrzweck(int balanceCents, [VoucherStatus status = VoucherStatus.active, VoucherValidity? validity]) =>
    VoucherCheck(type: VoucherType.multiPurpose, status: status, codeSuffix: '5KNZ', balanceCents: balanceCents, faceValueCents: 5000, validity: validity);
VoucherCheck einzweck(int balanceCents, int vatRateBp, {bool? exempt}) => VoucherCheck(
    type: VoucherType.singlePurpose,
    status: VoucherStatus.active,
    codeSuffix: '9DWT',
    balanceCents: balanceCents,
    faceValueCents: 5000,
    vatRateBp: vatRateBp,
    exempt: exempt);
VoucherCheck leistung(int remainingQuantity) => VoucherCheck(
      type: VoucherType.service,
      status: VoucherStatus.active,
      codeSuffix: '5KNN',
      quantity: 3,
      remainingQuantity: remainingQuantity,
      vatRateBp: 2000,
      article: const VoucherArticle(id: 'art_mani', name: 'Maniküre', vatRateBp: 2000, priceCents: 3500),
    );

KeckVoucher einloesen(VoucherType type, String code, [int? amountCents]) =>
    KeckVoucher(action: VoucherAction.redeem, type: type, code: code, amountCents: amountCents);

VoucherDueInfo info(String code, VoucherCheck check) => VoucherDueInfo(code: code, check: check);

/// Wirft die Rechnung `invalid_voucher` (mit [code], wenn genannt), und nennt
/// keine Meldung den Klartext-Code?
Matcher wirft([String? code]) => throwsA(predicate((Object? e) {
      if (e is! ReceiptDueError) return false;
      if (e.reason != 'invalid_voucher') return false;
      if (code != null && e.voucherErrorCode != code) return false;
      for (final c in [codeM, codeE, codeL, codeA, codeP]) {
        if (e.message.contains(c) || e.message.contains(c.replaceAll('-', '')) || e.toString().contains(c.replaceAll('-', ''))) return false;
      }
      return true;
    }, 'ReceiptDueError(invalid_voucher${code == null ? '' : ', $code'}) ohne Klartext-Code'));

const mehrzweckEin = PosVoucherSettings(sale: true, valueVoucherType: VoucherType.multiPurpose, vatRateBp: null);

void main() {
  group('Vertragsfaelle der neuen Form (zahlbetrag-faelle.json)', () {
    final faelle = (_json('v3/zahlbetrag-faelle.json')['cases'] as List).cast<Map<String, dynamic>>();
    final neu = faelle.where((f) => (f['input']['vouchers'] as List)
        .any((v) => VoucherType.fromWire(v['type'])?.isNewForm == true || v['action'] == 'payout'));

    test('die Faelle mit Gutscheinen der neuen Form sind da', () {
      final namen = neu.map((f) => f['name']).toSet();
      for (final n in ['single_purpose_voucher_sell', 'single_purpose_voucher_redeem', 'service_voucher_sell', 'service_voucher_redeem', 'promotion_voucher_redeem']) {
        expect(namen, contains(n));
      }
    });

    test('Trinkgeld-Regel (ein Gutschein deckt nie das Trinkgeld) mit Server-Ergebnis', () {
      final namen = neu.map((f) => f['name']).toSet();
      for (final n in [
        'tip_staff_value_voucher_capped', 'tip_owner_value_voucher_capped', 'tip_owner_value_voucher_over_tip', 'tip_payment_tipcents_value_voucher',
        'tip_promo_and_value_voucher', 'tip_value_voucher_boundary_accepted', 'tip_value_voucher_boundary_rejected', 'tip_single_purpose_voucher_goods_only',
      ]) {
        expect(namen, contains(n));
      }
      expect(neu.where(istAbgelehnt).length, greaterThanOrEqualTo(2));
    });

    for (final fall in neu) {
      test('${fall['name']}: Zahlbetrag, Toepfe und Fluss bzw. Abweisung wie der Server (auch ueber KasseneckItem)', () {
        final input = fall['input'] as Map<String, dynamic>;
        final roh = (input['items'] as List).cast<Map<String, dynamic>>();
        final vouchers = [for (final v in (input['vouchers'] as List).cast<Map<String, dynamic>>()) KeckVoucher.fromJson(v)];
        final a = angabenAusSetup(fall['setup'] as Map<String, dynamic>?);
        final t = trinkgeldAus(input);
        final typ = ReceiptType.values.byName(input['receiptType'] as String);
        ReceiptDueBreakdown zeilen() => receiptDueBreakdownForLines([for (final p in roh) ReceiptDueLine.fromJson(p)], vouchers, typ,
            tip: t.tip, payments: t.payments, tipRecipient: t.tipRecipient,
            voucherInfo: a.info, voucherSettings: a.settings, voucherArticles: a.articles);
        int positionen() => receiptDueCents([for (final p in roh) KasseneckItem.fromJson(p)], vouchers, typ,
            tip: t.tip, payments: t.payments, tipRecipient: t.tipRecipient,
            voucherInfo: a.info, voucherSettings: a.settings, voucherArticles: a.articles);
        if (istAbgelehnt(fall)) {
          final code = (fall['expected'] as Map)['errorCode'] as String;
          expect(zeilen, wirft(code));
          expect(positionen, wirft(code));
          return;
        }
        expect(alsMap(zeilen()), fall['expected']);
        expect(positionen(), (fall['expected'] as Map)['dueCents']);
      });
    }
  });

  group('Mehrzweck', () {
    test('einloesen ist Zahlung: mindert den Zahlbetrag, nicht die Toepfe', () {
      final e = receiptDueBreakdownForLines([pos('Blumenstrauß', 2240, 20)], [einloesen(VoucherType.multiPurpose, codeM, 1750)],
          ReceiptType.standard,
          voucherInfo: [info(codeM, mehrzweck(5000))]);
      expect(alsMap(e), {
        'dueCents': 490,
        'counterDeltaCents': 2240,
        'valueVoucherFlowCents': -1750,
        'bucketsCents': toepfe({'amountRateStandard': 2240}),
      });
    });

    test('deckt den ganzen Betrag: Zahlbetrag 0 (der Code tolerant geschrieben)', () {
      final items = [KasseneckItem(name: 'Blumenstrauß', quantity: 1, priceCents: 2240, vat: VatRate.vat20)];
      expect(
          receiptDueCents(items, [einloesen(VoucherType.multiPurpose, 'dtd59ecf5knz', 2240)], ReceiptType.standard,
              voucherInfo: [info(codeM, mehrzweck(5000))]),
          0);
    });

    test('ueber der Summe: der Server antwortet voucher_exceeds_total, hier wirft es vorher', () {
      expect(
          () => receiptDueBreakdownForLines([pos('Blumenstrauß', 2240, 20)], [einloesen(VoucherType.multiPurpose, codeM, 3000)],
              ReceiptType.standard,
              voucherInfo: [info(codeM, mehrzweck(5000))]),
          wirft('voucher_exceeds_total'));
    });

    test('ueber dem Saldo: voucher_insufficient_balance', () {
      expect(
          () => receiptDueBreakdownForLines([pos('Blumenstrauß', 2240, 20)], [einloesen(VoucherType.multiPurpose, codeM, 2000)],
              ReceiptType.standard,
              voucherInfo: [info(codeM, mehrzweck(1999))]),
          wirft('voucher_insufficient_balance'));
    });

    test('verkaufen: vor dem Stichtag Fluss, ab dem Stichtag Position im 0-%-Topf', () {
      final v = [KeckVoucher(action: VoucherAction.sell, type: VoucherType.multiPurpose, amountCents: 5000)];
      expect(voucherZeroRateBucketFrom, '2099-12-31');
      expect(alsMap(receiptDueBreakdownForLines(const [], v, ReceiptType.standard, voucherSettings: mehrzweckEin)), {
        'dueCents': 5000,
        'counterDeltaCents': 0,
        'valueVoucherFlowCents': 5000,
        'bucketsCents': toepfe(),
      });
      expect(
          alsMap(receiptDueBreakdownForLines(const [], v, ReceiptType.standard,
              voucherSettings: mehrzweckEin, zeroRateBucketFrom: '2026-10-01', today: '2026-10-19')),
          {
            'dueCents': 5000,
            'counterDeltaCents': 5000,
            'valueVoucherFlowCents': 0,
            'bucketsCents': toepfe({'amountRateZero': 5000}),
          });
      // Vor dem Stichtag (heute davor): wie bisher.
      expect(
          receiptDueBreakdownForLines(const [], v, ReceiptType.standard,
                  voucherSettings: mehrzweckEin, zeroRateBucketFrom: '2026-10-20', today: '2026-10-19')
              .valueVoucherFlowCents,
          5000);
      // Altform-Verkauf ab dem Stichtag ebenso in den 0-%-Topf.
      final alt = [KeckVoucher(action: VoucherAction.sell, type: VoucherType.value, valueCents: 2500, code: 'G1')];
      expect(
          alsMap(receiptDueBreakdownForLines([pos('Kaffee', 320, 20)], alt, ReceiptType.standard,
              zeroRateBucketFrom: '2026-10-01', today: '2026-10-19')),
          {
            'dueCents': 2820,
            'counterDeltaCents': 2820,
            'valueVoucherFlowCents': 0,
            'bucketsCents': toepfe({'amountRateStandard': 320, 'amountRateZero': 2500}),
          });
    });

    test('Verkauf ohne Gutschein-Einstellung: voucher_settings_missing (Mehrzweck wie Einzweck)', () {
      for (final type in [VoucherType.multiPurpose, VoucherType.singlePurpose]) {
        final v = [KeckVoucher(action: VoucherAction.sell, type: type, amountCents: 5000)];
        expect(() => receiptDueBreakdownForLines(const [], v, ReceiptType.standard), wirft('voucher_settings_missing'));
        expect(() => receiptDueBreakdownForLines(const [], v, ReceiptType.standard, voucherSettings: PosVoucherSettings.off),
            wirft('voucher_settings_missing'));
      }
    });

    test('Altform nach dem Stichtag: plane laeuft, ein negativer Zahlbetrag ist voucher_exceeds_total', () {
      final v = [
        KeckVoucher(action: VoucherAction.sell, type: VoucherType.value, valueCents: 1000, code: 'G1'),
        KeckVoucher(action: VoucherAction.redeem, type: VoucherType.value, valueCents: 5000, code: 'G2'),
      ];
      final items = [pos('Kaffee', 320, 20)];
      // Vor dem Stichtag wie bisher (der Server prueft das Vorzeichen erst an den Zahlungen).
      expect(receiptDueBreakdownForLines(items, v, ReceiptType.standard, today: '2026-10-19').dueCents, -3680);
      expect(() => receiptDueBreakdownForLines(items, v, ReceiptType.standard, today: '2026-10-19', zeroRateBucketFrom: '2026-01-01'),
          wirft('voucher_exceeds_total'));
    });

    test('verkaufen mit Einzweck-Einstellung: voucher_invalid', () {
      final v = [KeckVoucher(action: VoucherAction.sell, type: VoucherType.multiPurpose, amountCents: 5000)];
      expect(
          () => receiptDueBreakdownForLines(const [], v, ReceiptType.standard,
              voucherSettings: const PosVoucherSettings(sale: true, valueVoucherType: VoucherType.singlePurpose, vatRateBp: 2000)),
          wirft('voucher_invalid'));
    });

    test('Auszahlung: immer Position im 0-%-Topf, Zahlbetrag negativ, kein Fluss', () {
      final v = [KeckVoucher(action: VoucherAction.payout, type: VoucherType.multiPurpose, code: codeP, amountCents: 3000, reason: 'Kunde zieht weg')];
      expect(alsMap(receiptDueBreakdownForLines(const [], v, ReceiptType.standard, voucherInfo: [info(codeP, mehrzweck(3000))])), {
        'dueCents': -3000,
        'counterDeltaCents': -3000,
        'valueVoucherFlowCents': 0,
        'bucketsCents': toepfe({'amountRateZero': -3000}),
      });
    });

    test('Auszahlung abgelaufen: bis rueckzahlbar-bis erlaubt, danach voucher_expired', () {
      final v = [KeckVoucher(action: VoucherAction.payout, type: VoucherType.multiPurpose, code: codeP, amountCents: 1000, reason: 'Ablauf')];
      final check = mehrzweck(3000, VoucherStatus.expired, const VoucherValidity(pattern: '1+3', refundableUntil: '2026-12-31'));
      expect(receiptDueBreakdownForLines(const [], v, ReceiptType.standard, voucherInfo: [info(codeP, check)], today: '2026-10-19').dueCents, -1000);
      expect(() => receiptDueBreakdownForLines(const [], v, ReceiptType.standard, voucherInfo: [info(codeP, check)], today: '2027-01-01'),
          wirft('voucher_expired'));
    });
  });

  group('Einzweck', () {
    final korb = [pos('Maniküre', 3500, 20), pos('Shampoo', 1200, 10)];

    test('einloesen: Minuszeile im Satz des Gutscheins', () {
      expect(
          alsMap(receiptDueBreakdownForLines(korb, [einloesen(VoucherType.singlePurpose, codeE, 3000)], ReceiptType.standard,
              voucherInfo: [info(codeE, einzweck(5000, 2000))])),
          {
            'dueCents': 1700,
            'counterDeltaCents': 1700,
            'valueVoucherFlowCents': 0,
            'bucketsCents': toepfe({'amountRateStandard': 500, 'amountRateReduced1': 1200}),
          });
    });

    test('deckt nie mehr als die Positionen seines Topfs: voucher_rate_mismatch', () {
      expect(
          () => receiptDueBreakdownForLines(korb, [einloesen(VoucherType.singlePurpose, codeE, 3501)], ReceiptType.standard,
              voucherInfo: [info(codeE, einzweck(5000, 2000))]),
          wirft('voucher_rate_mismatch'));
    });

    test('deckt keine Trinkgeld-Position; Trinkgeld kommt vor den Gutscheinzeilen', () {
      final items = [pos('Kaffee', 320, 20)];
      expect(
          () => receiptDueBreakdownForLines(items, [einloesen(VoucherType.singlePurpose, codeE, 400)], ReceiptType.standard,
              voucherInfo: [info(codeE, einzweck(5000, 2000))], tip: const ReceiptDueTip(100), tipRecipient: ReceiptDueTipRecipient.owner),
          wirft('voucher_rate_mismatch'));
      expect(
          receiptDueBreakdownForLines(items, [einloesen(VoucherType.singlePurpose, codeE, 320)], ReceiptType.standard,
                  voucherInfo: [info(codeE, einzweck(5000, 2000))], tip: const ReceiptDueTip(100), tipRecipient: ReceiptDueTipRecipient.staff)
              .dueCents,
          100);
    });

    test('19 % deckt auch 4,9 %: ein Topf (Besonders), wie der Server zaehlt', () {
      expect(
          receiptDueBreakdownForLines([pos('Brot', 400, 4.9)], [einloesen(VoucherType.singlePurpose, codeE, 400)], ReceiptType.standard,
                  voucherInfo: [info(codeE, einzweck(5000, 1900))])
              .dueCents,
          0);
    });

    test('als Kleinunternehmer: anteilig auf alle Saetze, groesster Rest', () {
      expect(
          alsMap(receiptDueBreakdownForLines(korb, [einloesen(VoucherType.singlePurpose, codeE, 1000)], ReceiptType.standard,
              voucherInfo: [info(codeE, einzweck(5000, 2000))], smallBusiness: true)),
          {
            'dueCents': 3700,
            'counterDeltaCents': 3700,
            'valueVoucherFlowCents': 0,
            'bucketsCents': toepfe({'amountRateStandard': 2755, 'amountRateReduced1': 945}),
          });
    });

    test('befreit verkauft (exempt) in einem steuerpflichtigen Konto: anteilig wie Kleinunternehmer', () {
      final v = [einloesen(VoucherType.singlePurpose, codeE, 1000)];
      expect(receiptDueBreakdownForLines(korb, v, ReceiptType.standard, voucherInfo: [info(codeE, einzweck(5000, 0, exempt: true))]).bucketsCents,
          toepfe({'amountRateStandard': 2755, 'amountRateReduced1': 945}));
      // Ohne exempt waere es eine Minuszeile zu 0 %, die hier keine Position deckt.
      expect(() => receiptDueBreakdownForLines(korb, v, ReceiptType.standard, voucherInfo: [info(codeE, einzweck(5000, 0))]),
          wirft('voucher_rate_mismatch'));
    });

    test('verkaufen: Position im Satz der Einstellung; ohne Einstellung nicht rechenbar', () {
      final v = [KeckVoucher(action: VoucherAction.sell, type: VoucherType.singlePurpose, amountCents: 5000)];
      const e = PosVoucherSettings(sale: true, valueVoucherType: VoucherType.singlePurpose, vatRateBp: 1000);
      expect(alsMap(receiptDueBreakdownForLines(const [], v, ReceiptType.standard, voucherSettings: e)), {
        'dueCents': 5000,
        'counterDeltaCents': 5000,
        'valueVoucherFlowCents': 0,
        'bucketsCents': toepfe({'amountRateReduced1': 5000}),
      });
      expect(receiptDueBreakdownForLines(const [], v, ReceiptType.standard, voucherSettings: e, smallBusiness: true).bucketsCents,
          toepfe({'amountRateZero': 5000}));
      expect(() => receiptDueBreakdownForLines(const [], v, ReceiptType.standard), wirft('voucher_settings_missing'));
    });

    test('Auszahlung: Minusposition im Satz des Gutscheins', () {
      final v = [KeckVoucher(action: VoucherAction.payout, type: VoucherType.singlePurpose, code: codeE, amountCents: 1200, reason: 'Kulanz')];
      expect(alsMap(receiptDueBreakdownForLines(const [], v, ReceiptType.standard, voucherInfo: [info(codeE, einzweck(2000, 2000))])), {
        'dueCents': -1200,
        'counterDeltaCents': -1200,
        'valueVoucherFlowCents': 0,
        'bucketsCents': toepfe({'amountRateStandard': -1200}),
      });
    });
  });

  group('Leistung', () {
    test('einloesen: je Satz eine Minuszeile ueber die gewaehlten Positionen samt Menge', () {
      final items = [pos('Maniküre', 3500, 20, articleId: 'art_mani', quantity: 2), pos('Kaffee', 320, 20)];
      final v = KeckVoucher(action: VoucherAction.redeem, type: VoucherType.service, code: codeL, positions: const [0]);
      ReceiptDueBreakdown mit(KeckVoucher g, int offen) =>
          receiptDueBreakdownForLines(items, [g], ReceiptType.standard, voucherInfo: [info(codeL, leistung(offen))]);
      expect(mit(v, 3).dueCents, 320);
      expect(() => mit(v, 1), wirft('voucher_insufficient_balance'));
      expect(() => mit(KeckVoucher(action: VoucherAction.redeem, type: VoucherType.service, code: codeL, positions: const [1]), 3),
          wirft('voucher_item_mismatch'));
      expect(() => mit(KeckVoucher(action: VoucherAction.redeem, type: VoucherType.service, code: codeL, positions: const [5]), 3),
          wirft('voucher_item_mismatch'));
    });

    test('einloesen ueber KasseneckItem: die Position ohne Kennzeichnung gilt als Ware', () {
      final items = [KasseneckItem(name: 'Maniküre', quantity: 1, priceCents: 3500, vat: VatRate.vat20, articleId: 'art_mani')];
      final v = [KeckVoucher(action: VoucherAction.redeem, type: VoucherType.service, code: codeL, positions: const [0])];
      expect(receiptDueCents(items, v, ReceiptType.standard, voucherInfo: [info(codeL, leistung(3))]), 0);
    });

    test('verkaufen: Stueck mal Artikelpreis im Artikelsatz; ohne Artikel nicht rechenbar', () {
      final v = [KeckVoucher(action: VoucherAction.sell, type: VoucherType.service, articleId: 'art_mani', quantity: 3)];
      expect(
          alsMap(receiptDueBreakdownForLines(const [], v, ReceiptType.standard,
              voucherArticles: const [VoucherDueArticle(id: 'art_mani', priceCents: 3500, vatRateBp: 2000)])),
          {
            'dueCents': 10500,
            'counterDeltaCents': 10500,
            'valueVoucherFlowCents': 0,
            'bucketsCents': toepfe({'amountRateStandard': 10500}),
          });
      expect(() => receiptDueBreakdownForLines(const [], v, ReceiptType.standard), wirft('voucher_item_mismatch'));
    });
  });

  group('Aktion', () {
    test('mit Prozent: abgerundet von der Summe der deckbaren Positionen, wie promo verteilt', () {
      final items = [pos('Kaffee', 333, 20), pos('Semmel', 79, 10)];
      final v = [einloesen(VoucherType.promotion, codeA)];
      const prozent = VoucherCheck(type: VoucherType.promotion, status: VoucherStatus.active, codeSuffix: '5KNJ', discountPercentBp: 1000);
      // 412 * 10 % = 41,2 -> 41
      expect(receiptDueBreakdownForLines(items, v, ReceiptType.standard, voucherInfo: [info(codeA, prozent)]).dueCents, 371);
      const gross = VoucherCheck(type: VoucherType.promotion, status: VoucherStatus.active, codeSuffix: '5KNJ', discountCents: 10000);
      expect(receiptDueBreakdownForLines(items, v, ReceiptType.standard, voucherInfo: [info(codeA, gross)]).dueCents, 0);
    });

    test('nur allein am Beleg', () {
      expect(
          () => receiptDueBreakdownForLines(
                [pos('Kaffee', 320, 20)],
                [einloesen(VoucherType.promotion, codeA), einloesen(VoucherType.multiPurpose, codeM, 100)],
                ReceiptType.standard,
                voucherInfo: [
                  info(codeA, const VoucherCheck(type: VoucherType.promotion, status: VoucherStatus.active, codeSuffix: '5KNJ', discountCents: 100)),
                  info(codeM, mehrzweck(5000)),
                ],
              ),
          wirft('voucher_invalid'));
    });
  });

  group('Pruefung fehlt, Regeln des Plans', () {
    final items = [pos('Kaffee', 320, 20)];
    final v = [einloesen(VoucherType.multiPurpose, codeM, 100)];

    test('Einloesung ohne passende Pruefung: invalid_voucher, der Code steht nicht in der Meldung', () {
      expect(() => receiptDueBreakdownForLines(items, v, ReceiptType.standard), wirft('voucher_not_found'));
      expect(() => receiptDueBreakdownForLines(items, v, ReceiptType.standard, voucherInfo: [info(codeE, mehrzweck(5000))]),
          wirft('voucher_not_found'));
      expect(() => receiptDueBreakdownForLines(items, v, ReceiptType.standard, voucherInfo: [info(codeM, einzweck(5000, 2000))]),
          wirft('voucher_invalid'));
      expect(
          () => receiptDueBreakdownForLines(items, v, ReceiptType.standard,
              voucherInfo: [info(codeM, mehrzweck(5000, VoucherStatus.blocked))]),
          wirft('voucher_blocked'));
    });

    test('Verkauf und Einloesung zusammen, derselbe Gutschein zweimal, Gutscheinzeilen von aussen: invalid_voucher', () {
      final i = [info(codeM, mehrzweck(5000))];
      expect(
          () => receiptDueBreakdownForLines(
              items, [KeckVoucher(action: VoucherAction.sell, type: VoucherType.multiPurpose, amountCents: 1000), ...v], ReceiptType.standard,
              voucherInfo: i, voucherSettings: mehrzweckEin),
          wirft('voucher_invalid'));
      expect(
          () => receiptDueBreakdownForLines(items, [...v, einloesen(VoucherType.multiPurpose, 'dtd5 9ecf 5knz', 100)], ReceiptType.standard,
              voucherInfo: i),
          wirft('voucher_invalid'));
      expect(
          () => receiptDueBreakdownForLines([...items, pos('Gutschein', -100, 20, kind: 'voucher')], v, ReceiptType.standard, voucherInfo: i),
          wirft('voucher_invalid'));
    });

    test('neue Form nicht am Storno und nicht auf Schulungsbelegen', () {
      final i = [info(codeM, mehrzweck(5000))];
      expect(() => receiptDueBreakdownForLines(items, v, ReceiptType.cancellation, voucherInfo: i), wirft('voucher_invalid'));
      expect(() => receiptDueBreakdownForLines(items, v, ReceiptType.training, voucherInfo: i), wirft('voucher_invalid'));
    });
  });

  test('Gelesener Beleg der neuen Form: Positionen tragen das Geld, nur Mehrzweck ohne 0-%-Topf fliesst', () {
    // So steht der Einzweck-Einloesebeleg im Vertrag (antworten/belege.json, redeem_single_purpose_voucher).
    final items = [pos('Kaffee', 320, 20, quantity: 2), pos('Gutschein ····-5KN2', -300, 20, kind: 'voucher')];
    final v = [
      KeckVoucher(
          action: VoucherAction.redeem,
          type: VoucherType.singlePurpose,
          voucherType: 'single_purpose',
          amountCents: 300,
          vatRateBp: 2000,
          codeSuffix: '5KN2',
          voucherId: 'gez1'),
    ];
    expect(receiptDueBreakdownForLines(items, v, ReceiptType.standard).dueCents, 340);
    final auszahlung = [
      KeckVoucher(
          action: VoucherAction.payout,
          type: VoucherType.value,
          voucherType: 'multi_purpose',
          valueCents: 3000,
          codeSuffix: '8CN5',
          voucherId: 'gmz2',
          zeroRateBucket: true),
    ];
    expect(receiptDueBreakdownForLines([pos('Auszahlung Gutschein ····-8CN5', -3000, 0, kind: 'voucher_float')], auszahlung, ReceiptType.standard).dueCents,
        -3000);
  });

  group('Vorbelegung an der Kasse (voucherRedeemMaxCents)', () {
    final korb = [pos('Maniküre', 3500, 20), pos('Shampoo', 1200, 10)];

    test('Einzweck 20 % deckt nur Positionen seines Satzes, hoechstens den Saldo', () {
      expect(voucherRedeemMaxCentsForLines(korb, einzweck(5000, 2000)), 3500);
      expect(voucherRedeemMaxCentsForLines(korb, einzweck(1950, 2000)), 1950);
      expect(voucherRedeemMaxCentsForLines(korb, einzweck(5000, 1300)), 0);
    });

    test('Mehrzweck hoechstens der offene Betrag, Leistung und Aktion kein Betrag, nie negativ', () {
      final items = [KasseneckItem(name: 'Blumenstrauß', quantity: 1, priceCents: 2240, vat: VatRate.vat20)];
      expect(voucherRedeemMaxCents(items, mehrzweck(5000)), 2240);
      expect(voucherRedeemMaxCents(items, mehrzweck(1000)), 1000);
      expect(voucherRedeemMaxCents(items, mehrzweck(5000, VoucherStatus.expired)), 0);
      expect(voucherRedeemMaxCents(items, leistung(3)), 0);
      expect(
          voucherRedeemMaxCents(items, const VoucherCheck(type: VoucherType.promotion, status: VoucherStatus.active, codeSuffix: '5KNJ', discountCents: 500)),
          0);
      expect(voucherRedeemMaxCents(const [], mehrzweck(5000)), 0);
      expect(voucherRedeemMaxCentsForLines([pos('Rabatt', -500, 20)], mehrzweck(5000)), 0);
    });

    test('an halben Cent: 1478 x 0,25 zu 4,9 % deckt 369, nicht 370 (der Topf liefe auf -1 Cent)', () {
      final items = [pos('Brot', 1478, 4.9, quantity: 0.25)];
      final check = einzweck(5000, 490);
      expect(voucherRedeemMaxCentsForLines(items, check), 369);
      ReceiptDueBreakdown mit(int cents) => receiptDueBreakdownForLines(items, [einloesen(VoucherType.singlePurpose, codeE, cents)],
          ReceiptType.standard,
          voucherInfo: [info(codeE, check)]);
      expect(mit(369).dueCents, 0);
      expect(() => mit(370), wirft('voucher_exceeds_total'));
    });

    test('Kleinunternehmer: Summe je Satz (kuTeile), nicht die Summe ueber den Korb', () {
      // 2931 x 0,25 zu 4,9 % = 732,75 -> 733; 443 x 0,25 zu 20 % = 110,75 -> 111; Korb 843, je Satz 844 (Server-Hoechstbetrag).
      final items = [pos('Brot', 2931, 4.9, quantity: 0.25), pos('Kaffee', 443, 20, quantity: 0.25)];
      final check = einzweck(100000, 2000);
      expect(voucherRedeemMaxCentsForLines(items, check, smallBusiness: true), 844);
      expect(voucherRedeemMaxCentsForLines(items, einzweck(100000, 2000, exempt: true)), 844);
      ReceiptDueBreakdown mit(int cents) => receiptDueBreakdownForLines(items, [einloesen(VoucherType.singlePurpose, codeE, cents)],
          ReceiptType.standard,
          voucherInfo: [info(codeE, check)], smallBusiness: true);
      expect(mit(844).dueCents, 0);
      expect(() => mit(845), wirft());
    });

    test('Kleinunternehmer, gleiche Reste: der Cent geht nach der Topf-Reihenfolge (Werte aus gutschein-beleg.kuTeile des Servers)', () {
      // Server (functions/gemeinsam/gutschein-beleg.js kuTeile, 19.10.2026 ausgefuehrt):
      // 20 %/10 % je 10,00: 1 Cent -> 20 % 1; 3 Cent -> 20 % 2, 10 % 1; auch bei umgekehrter
      // Positionsfolge. 13 %/10 %/20 % je 5,00: 4 Cent -> 20 % 2, 10 % 1, 13 % 1.
      final ku = einzweck(100000, 0, exempt: true);
      Map<String, int>? topf(List<ReceiptDueLine> korb, int cents) => receiptDueBreakdownForLines(
              korb, [einloesen(VoucherType.singlePurpose, codeE, cents)], ReceiptType.standard,
              voucherInfo: [info(codeE, ku)])
          .bucketsCents;
      final gleich = [pos('Gelnägel', 1000, 20), pos('Handcreme', 1000, 10)];
      expect(topf(gleich, 1), toepfe({'amountRateStandard': 999, 'amountRateReduced1': 1000}));
      expect(topf(gleich, 3), toepfe({'amountRateStandard': 998, 'amountRateReduced1': 999}));
      expect(topf(gleich.reversed.toList(), 3), toepfe({'amountRateStandard': 998, 'amountRateReduced1': 999}));
      final drei = [pos('Blumen', 500, 13), pos('Handcreme', 500, 10), pos('Gelnägel', 500, 20)];
      expect(topf(drei, 4), toepfe({'amountRateStandard': 498, 'amountRateReduced1': 499, 'amountRateReduced2': 499}));
    });

    test('Hoechstbetrag mit Abstand P + 6 zur alten Grenze: der Wert des Servers, nie 0', () {
      // Ein schon gewaehlter Einzweck 20 % (P) mindert den 20-%-Topf; der befreite Einzweck verteilt
      // anteilig auf die Saetze (je 10,00). Server (gutschein-beleg.plane, 19.10.2026): P = 57 nimmt
      // genau 1886, P = 58 genau 1884, jeweils einen Cent mehr voucher_rate_mismatch. Vor npm 1.12.0
      // Task 8c bot die Kasse bei P = 58 nach 64 Schritten 0 an.
      final korb = [pos('Gelnägel', 1000, 20), pos('Handcreme', 1000, 10)];
      const codeK = 'DTD5-9ECF-5KNZ';
      int max(int p) => voucherRedeemMaxCentsForLines(korb, einzweck(100000, 0, exempt: true),
          vouchers: [einloesen(VoucherType.singlePurpose, codeK, p)], voucherInfo: [info(codeK, einzweck(5000, 2000))]);
      expect(max(57), 1886);
      expect(max(58), 1884);
    });

    // Erwartete Hoechstbetraege mit dem Server-Code (gutschein-beleg.plane) durch Abzaehlen aller
    // Betraege ermittelt (npm 1.12.0, Task 8c).
    VoucherCheck befreit() => einzweck(1000000, 0, exempt: true);

    test('befreit neben einem schon gewaehlten Einzweck: Anteil je Topf plus Vorgaenger (Server 3357, nicht 0)', () {
      // 3500 zu 20 %, 1200 zu 10 %; schon gewaehlt 1000 Einzweck 20 %. Der 20-%-Anteil 3500/4700 * c plus
      // 1000 darf 3500 nicht uebersteigen.
      final items = [pos('Maniküre', 3500, 20), pos('Shampoo', 1200, 10)];
      final vorher = [einloesen(VoucherType.singlePurpose, codeE, 1000)];
      final i = [info(codeE, einzweck(1000000, 2000))];
      expect(voucherRedeemMaxCentsForLines(items, befreit(), vouchers: vorher, voucherInfo: i), 3357);
      // Als Kleinunternehmer verteilt sich auch der schon gewaehlte Gutschein anteilig: dann begrenzt nur
      // der offene Betrag (Server 3700).
      expect(voucherRedeemMaxCentsForLines(items, einzweck(1000000, 2000), vouchers: vorher, voucherInfo: i, smallBusiness: true),
          3700);
      int mit(int cents) => receiptDueBreakdownForLines(
              items, [...vorher, einloesen(VoucherType.singlePurpose, codeM, cents)], ReceiptType.standard,
              voucherInfo: [...i, info(codeM, befreit())])
          .dueCents;
      expect(mit(3357), 343);
      expect(() => mit(3358), wirft('voucher_rate_mismatch'));
    });

    test('mehr als 64 Cent unter der Grenze findet die Bisektion den Hoechstbetrag (Server 67)', () {
      // 20000 zu 20 %, je 100 zu 19 % und 4,9 %; der Topf Besonders ist durch 200 Einzweck 19 % voll.
      // Angenommen wird nur, solange kein Cent dorthin faellt: bis 67 (danach erhalten 19 % und 4,9 % den
      // groessten Rest). Grenze 202.
      final items = [pos('Ware', 20000, 20), pos('Wein', 100, 19), pos('Brot', 100, 4.9)];
      final vorher = [einloesen(VoucherType.singlePurpose, codeE, 200)];
      expect(
          voucherRedeemMaxCentsForLines(items, befreit(), vouchers: vorher, voucherInfo: [info(codeE, einzweck(1000000, 1900))]), 67);
    });

    test('kuTeile: gleicher Rest in zwei Saetzen, der Cent geht an den Topf in fester Reihenfolge (20 % vor 10 %)', () {
      final items = [pos('Kaffee', 100, 20), pos('Semmel', 100, 10)];
      expect(
          receiptDueBreakdownForLines(items, [einloesen(VoucherType.singlePurpose, codeE, 1)], ReceiptType.standard,
                  voucherInfo: [info(codeE, befreit())])
              .bucketsCents,
          toepfe({'amountRateStandard': 99, 'amountRateReduced1': 100}));
    });

    test('mit schon gewaehlten Gutscheinen: der Rest des Topfs und des Betrags', () {
      final vorher = [einloesen(VoucherType.singlePurpose, codeE, 3000)];
      final i = [info(codeE, einzweck(5000, 2000))];
      expect(voucherRedeemMaxCentsForLines(korb, einzweck(5000, 2000), vouchers: vorher, voucherInfo: i), 500);
      expect(voucherRedeemMaxCentsForLines(korb, mehrzweck(5000), vouchers: vorher, voucherInfo: i), 1700);
    });
  });

  group('Trinkgeld: ein Gutschein deckt es nie (gutschein-beleg.plane)', () {
    final items = [pos('Maniküre', 2000, 20)];
    const personal = (tip: ReceiptDueTip(200), recipient: ReceiptDueTipRecipient.staff);
    const inhaber = (tip: ReceiptDueTip(200), recipient: ReceiptDueTipRecipient.owner);
    const gemischt = (
      tip: ReceiptDueTip(200, recipients: [ReceiptDueTipShare(cents: 120, owner: true), ReceiptDueTipShare(cents: 80, owner: false)]),
      recipient: null,
    );
    List<KeckVoucher> promo(int cents) => [KeckVoucher(action: VoucherAction.redeem, type: VoucherType.promo, valueCents: cents, code: 'R')];
    final ueberZahlung = [const KeckPaymentInput(method: KeckPaymentMethod.creditCard, amountCents: 2200, tipCents: 200)];

    test('Einloesung bis Ware, nie in das Trinkgeld (Personal wie Inhaber, auch Grenzwerte 2001, 2100, 2199, 2200)', () {
      int mit(int cents, {ReceiptDueTip? tip, ReceiptDueTipRecipient? recipient, List<KeckPaymentInput>? payments}) =>
          receiptDueBreakdownForLines(items, [einloesen(VoucherType.multiPurpose, codeM, cents)], ReceiptType.standard,
                  tip: tip, payments: payments, tipRecipient: recipient, voucherInfo: [info(codeM, mehrzweck(5000))])
              .dueCents;
      for (final o in [personal, inhaber, gemischt]) {
        expect(mit(2000, tip: o.tip, recipient: o.recipient), 200);
        for (final zuViel in [2001, 2100, 2199, 2200]) {
          expect(() => mit(zuViel, tip: o.tip, recipient: o.recipient), wirft('voucher_exceeds_total'), reason: '$zuViel');
        }
      }
      // Trinkgeld ueber die Zahlung (payments[].tipCents) zaehlt genauso.
      expect(mit(2000, payments: ueberZahlung, recipient: ReceiptDueTipRecipient.staff), 200);
      expect(() => mit(2001, payments: ueberZahlung, recipient: ReceiptDueTipRecipient.staff), wirft('voucher_exceeds_total'));
    });

    test('ohne Gutschein der neuen Form bleibt alles wie bisher (Storno, Altform-Rabatt)', () {
      expect(receiptDueBreakdownForLines(items, const [], ReceiptType.standard, tip: personal.tip, tipRecipient: personal.recipient).dueCents,
          2200);
      // Altform-Rabatt verteilt sich auch auf das Inhaber-Trinkgeld; ohne Plan prueft der Server das nicht.
      expect(
          receiptDueBreakdownForLines(items, promo(2200), ReceiptType.standard, tip: inhaber.tip, tipRecipient: inhaber.recipient).dueCents,
          0);
      expect(receiptDueBreakdownForLines([pos('Maniküre', -2000, 20)], const [], ReceiptType.cancellation).dueCents, -2000);
    });

    test('Aktionsgutschein mindert nur die Ware, das Trinkgeld bleibt zu zahlen', () {
      const check = VoucherCheck(type: VoucherType.promotion, status: VoucherStatus.active, codeSuffix: '5KNJ', discountCents: 10000);
      for (final o in [personal, inhaber]) {
        expect(
            receiptDueBreakdownForLines(items, [einloesen(VoucherType.promotion, codeA)], ReceiptType.standard,
                    tip: o.tip, tipRecipient: o.recipient, voucherInfo: [info(codeA, check)])
                .dueCents,
            200);
      }
    });

    test('Vorbelegung: Mehrzweck hoechstens der offene Betrag ohne Trinkgeld (Personal und Inhaber)', () {
      expect(voucherRedeemMaxCentsForLines(items, mehrzweck(5000), tip: personal.tip, tipRecipient: personal.recipient), 2000);
      expect(voucherRedeemMaxCentsForLines(items, mehrzweck(5000), tip: inhaber.tip, tipRecipient: inhaber.recipient), 2000);
      expect(
          voucherRedeemMaxCentsForLines(items, mehrzweck(5000),
              payments: [const KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 2200, tipCents: 200)],
              tipRecipient: ReceiptDueTipRecipient.staff),
          2000);
      // Der Saldo begrenzt weiter.
      expect(voucherRedeemMaxCentsForLines(items, mehrzweck(1500), tip: personal.tip, tipRecipient: personal.recipient), 1500);
      // Schon gewaehlte Einloesung: der Rest der Ware, nie das Trinkgeld.
      expect(
          voucherRedeemMaxCentsForLines(items, mehrzweck(5000),
              vouchers: [einloesen(VoucherType.multiPurpose, codeP, 1200)],
              voucherInfo: [info(codeP, mehrzweck(5000))],
              tip: inhaber.tip,
              tipRecipient: inhaber.recipient),
          800);
    });

    test('Vorbelegung: Einzweck, der nur Ware deckt, bekommt die Ware (nicht 0)', () {
      expect(voucherRedeemMaxCentsForLines(items, einzweck(5000, 2000), tip: personal.tip, tipRecipient: personal.recipient), 2000);
      expect(voucherRedeemMaxCentsForLines(items, einzweck(5000, 2000), tip: inhaber.tip, tipRecipient: inhaber.recipient), 2000);
      // Zwei Saetze: Einzweck 10 % deckt nur seinen Topf, das Trinkgeld begrenzt hier nicht.
      final zwei = [pos('Maniküre', 2000, 20), pos('Shampoo', 1200, 10)];
      expect(voucherRedeemMaxCentsForLines(zwei, einzweck(5000, 1000), tip: inhaber.tip, tipRecipient: inhaber.recipient), 1200);
    });

    test('Vorbelegung mit Rabatt bzw. Altform-Aktion: Deckel nach dem Abzug, nie negativ', () {
      final rabatt = pos('Rabatt', -500, 20, kind: 'discount');
      expect(voucherRedeemMaxCentsForLines([...items, rabatt], mehrzweck(5000), tip: personal.tip, tipRecipient: personal.recipient), 1500);
      expect(voucherRedeemMaxCentsForLines([...items, rabatt], mehrzweck(5000), tip: inhaber.tip, tipRecipient: inhaber.recipient), 1500);
      expect(
          voucherRedeemMaxCentsForLines([...items, rabatt], einzweck(5000, 2000), tip: personal.tip, tipRecipient: personal.recipient), 1500);
      expect(
          voucherRedeemMaxCentsForLines(items, mehrzweck(5000), vouchers: promo(500), tip: personal.tip, tipRecipient: personal.recipient),
          1500);
      expect(
          voucherRedeemMaxCentsForLines(items, mehrzweck(5000), vouchers: promo(500), tip: inhaber.tip, tipRecipient: inhaber.recipient),
          1500);
      // Rabatt in Hoehe der Ware: nur noch das Trinkgeld offen, also 0 (nie negativ).
      expect(
          voucherRedeemMaxCentsForLines(items, mehrzweck(5000), vouchers: promo(2000), tip: personal.tip, tipRecipient: personal.recipient),
          0);
      expect(
          voucherRedeemMaxCentsForLines(items, mehrzweck(5000), vouchers: promo(2200), tip: inhaber.tip, tipRecipient: inhaber.recipient),
          0);
      expect(
          voucherRedeemMaxCentsForLines(items, einzweck(5000, 2000),
              vouchers: promo(2200), tip: inhaber.tip, tipRecipient: inhaber.recipient),
          0);
    });

    test('Vorbelegung wirft nie: nicht rechenbarer Beleg (Trinkgeld ohne Ware) ergibt 0', () {
      final gratis = [pos('Gratisprobe', 0, 20)];
      expect(voucherRedeemMaxCentsForLines(gratis, mehrzweck(5000), tip: personal.tip, tipRecipient: personal.recipient), 0);
      expect(voucherRedeemMaxCentsForLines(gratis, einzweck(5000, 2000), tip: inhaber.tip, tipRecipient: inhaber.recipient), 0);
      expect(voucherRedeemMaxCentsForLines(const [], mehrzweck(5000), tip: personal.tip, tipRecipient: personal.recipient), 0);
      // Ohne Empfaenger (tip_recipient_missing) ebenso.
      expect(voucherRedeemMaxCentsForLines(items, mehrzweck(5000), tip: const ReceiptDueTip(200)), 0);
      // Schon gewaehlte Gutscheine decken das Trinkgeld bereits: 0 statt Wurf.
      expect(
          voucherRedeemMaxCentsForLines(items, mehrzweck(5000),
              vouchers: [einloesen(VoucherType.multiPurpose, codeP, 2100)],
              voucherInfo: [info(codeP, mehrzweck(5000))],
              tip: personal.tip,
              tipRecipient: personal.recipient),
          0);
    });
  });

  test('ReceiptDueError: voucherErrorCode nur bei Gutscheinen, sonst null', () {
    const ohne = ReceiptDueError('tip_without_goods', 'x');
    expect(ohne.voucherErrorCode, isNull);
    const mit = ReceiptDueError('invalid_voucher', 'x', 'voucher_rate_mismatch');
    expect(mit.voucherErrorCode, 'voucher_rate_mismatch');
    expect(mit.code, receiptDueErrorCode);
  });

  test('Wurzel exportiert die Gutschein-Teile des Zahlbetrags', () {
    expect(wurzel.voucherRedeemMaxCents, same(voucherRedeemMaxCents));
    expect(wurzel.voucherRedeemMaxCentsForLines, same(voucherRedeemMaxCentsForLines));
    expect(wurzel.voucherZeroRateBucketFrom, '2099-12-31');
    expect(const wurzel.VoucherDueArticle(id: 'a', priceCents: 1, vatRateBp: 2000), isA<VoucherDueArticle>());
  });

  group('Erzeugte Gutscheinfaelle (receipt-due-voucher-generated.json, echter Backend-Code)', () {
    final datei = _json('receipt-due-voucher-generated.json');
    final faelle = (datei['cases'] as List).cast<Map<String, dynamic>>();

    test('genug und von jeder Art (Bruchmengen, Trinkgeld, Kleinunternehmer, befreit, Stichtag, Abweisungen)', () {
      Iterable<Map<String, dynamic>> wo(bool Function(Map<String, dynamic> input) p) => faelle.where((f) => p(f['input'] as Map<String, dynamic>));
      expect(faelle.length, greaterThanOrEqualTo(400));
      expect(wo((i) => (i['items'] as List).any((p) => p['quantity'] is! int)).length, greaterThanOrEqualTo(150));
      expect(wo((i) => i['tip'] != null).length, greaterThanOrEqualTo(50));
      expect(wo((i) => i['smallBusiness'] == true).length, greaterThanOrEqualTo(50));
      expect(wo((i) => (i['voucherInfo'] as List? ?? const []).any((x) => x['check']['exempt'] == true)).length, greaterThanOrEqualTo(20));
      expect(wo((i) => (i['today'] as String).compareTo(voucherZeroRateBucketFrom) >= 0).length, greaterThanOrEqualTo(100));
      for (final art in ['multi_purpose', 'single_purpose', 'service', 'promotion']) {
        expect(
            faelle.any((f) =>
                (f['input']['vouchers'] as List).any((v) => v['type'] == art && v['action'] == 'redeem') &&
                (f['expected'] as Map).containsKey('dueCents')),
            isTrue,
            reason: art);
      }
      for (final code in ['voucher_rate_mismatch', 'voucher_exceeds_total', 'voucher_insufficient_balance', 'voucher_item_mismatch', 'voucher_settings_missing']) {
        expect(faelle.any((f) => (f['expected'] as Map)['voucherError'] == code), isTrue, reason: code);
      }
    });

    test('jeder stimmt exakt mit dem Backend (Betrag, Toepfe, Fluss bzw. Abweisungscode)', () {
      final abweichend = <String>[];
      for (final f in faelle) {
        final i = f['input'] as Map<String, dynamic>;
        final einstellung = i['voucherSettings'] as Map<String, dynamic>?;
        Object? ist;
        try {
          ist = alsMap(receiptDueBreakdownForLines(
            [for (final p in (i['items'] as List).cast<Map<String, dynamic>>()) ReceiptDueLine.fromJson({...p, 'unitPriceCents': p['priceCents']})],
            [for (final v in (i['vouchers'] as List).cast<Map<String, dynamic>>()) KeckVoucher.fromJson(v)],
            ReceiptType.values.byName(i['receiptType'] as String),
            tip: i['tip'] == null ? null : ReceiptDueTip(i['tip'] as int),
            tipRecipient: switch (i['tipRecipient']) {
              'owner' => ReceiptDueTipRecipient.owner,
              'staff' => ReceiptDueTipRecipient.staff,
              _ => null,
            },
            voucherInfo: [
              for (final x in (i['voucherInfo'] as List? ?? const []).cast<Map<String, dynamic>>())
                VoucherDueInfo(code: x['code'] as String, check: pruefungAusDraht((x['check'] as Map).cast())),
            ],
            voucherSettings: einstellung == null ? null : PosVoucherSettings.fromJson(einstellung),
            voucherArticles: [
              for (final a in (i['voucherArticles'] as List? ?? const []).cast<Map<String, dynamic>>())
                VoucherDueArticle(id: a['id'] as String, priceCents: a['priceCents'] as int, vatRateBp: a['vatRateBp'] as int),
            ],
            smallBusiness: i['smallBusiness'] == true,
            today: i['today'] as String,
          ));
        } on ReceiptDueError catch (e) {
          ist = e.voucherErrorCode != null ? {'voucherError': e.voucherErrorCode} : {'error': e.reason};
        }
        final erwartet = f['expected'] as Map<String, dynamic>;
        // Der eine Fehlerfall der Datei ist Trinkgeld ohne Ware (der Text ist der des Servers).
        final soll = erwartet.containsKey('error') ? {'error': 'tip_without_goods'} : erwartet;
        if (jsonEncode(ist) != jsonEncode(soll)) abweichend.add('${f['name']}: ${jsonEncode(ist)} statt ${jsonEncode(soll)}');
      }
      expect(abweichend.take(5).toList(), isEmpty, reason: '${abweichend.length} Abweichungen');
    });
  });
}
