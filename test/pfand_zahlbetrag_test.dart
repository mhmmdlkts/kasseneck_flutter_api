import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/receipt_type.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/enums/voucher_action.dart';
import 'package:kasseneck_api/enums/voucher_type.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/models/keck_voucher.dart';
import 'package:kasseneck_api/pos.dart' show VoucherCheck, VoucherStatus, distributeDiscount;
import 'package:kasseneck_api/src/receipt/due.dart';

/// Pfand und Leergut im Zahlbetrag (Spec Pfand & Leergut, E17/E18, Leergut-
/// Auszahlung): die Vertragsfaelle stehen in receipt_due_test.dart; hier die
/// Regeln, die sie nicht einzeln benennen. Zwilling von `test/pfand-zahlbetrag.test.ts`.

VatRate _satz(num s) => VatRate.values.firstWhere((v) => v.rate == s);

KasseneckItem ware(int cents, num satz) => KasseneckItem(name: 'Ware', quantity: 1, priceCents: cents, vat: _satz(satz));

KasseneckItem pfand(int cents, num satz, {String kind = 'reusable', String id = 'kiste'}) => KasseneckItem(
    name: 'Pfand', quantity: 1, priceCents: cents, vat: _satz(satz), kind: 'deposit', depositTypeId: id, depositKind: kind);

KasseneckItem leergut(int stueck, int centsJe, num satz) => KasseneckItem(
    name: 'Leergut',
    quantity: stueck,
    priceCents: -centsJe,
    vat: _satz(satz),
    kind: 'deposit_return',
    depositTypeId: 'kiste',
    depositKind: 'reusable');

const code = '5TD5-9ECF-5KN2';

VoucherCheck einzweck(int balanceCents, int vatRateBp) => VoucherCheck(
    type: VoucherType.singlePurpose,
    status: VoucherStatus.active,
    codeSuffix: '5KN2',
    balanceCents: balanceCents,
    faceValueCents: 5000,
    vatRateBp: vatRateBp);

void main() {
  test('Einweg-Pfand liegt im Topf Null, Mehrweg-Pfand im Topf seines Satzes, 4,9 % im Topf Besonders', () {
    final b = receiptDueBreakdown(
      [ware(1000, 20), pfand(150, 0, kind: 'single_use', id: 'einweg'), pfand(400, 20), pfand(100, 4.9)],
      const [],
      ReceiptType.standard,
    );
    expect(b.dueCents, 1650);
    expect(b.bucketsCents, {
      'amountRateStandard': 1400,
      'amountRateReduced1': 0,
      'amountRateReduced2': 0,
      'amountRateZero': 150,
      'amountRateSpecial': 100,
      'amountRatOthers': 0,
    });
    expect(b.payout, isNull);
  });

  test('Rabattgutschein mindert nie das Pfand und rechnet nur ueber die Ware (E17)', () {
    KeckVoucher promo(int cents) => KeckVoucher(action: VoucherAction.redeem, type: VoucherType.promo, valueCents: cents, code: 'R');
    // 10 EUR Ware + 4 EUR Pfand im selben Satz: 5 EUR Rabatt nur von der Ware.
    expect(receiptDueCents([ware(1000, 20), pfand(400, 20)], [promo(500)], ReceiptType.standard), 900);
    // Der Deckel ist die Ware, nicht Ware + Pfand: 20 EUR Rabatt kappen bei 10 EUR.
    expect(receiptDueCents([ware(1000, 20), pfand(400, 20)], [promo(2000)], ReceiptType.standard), 400);
  });

  test('distributeDiscount laesst Pfand und Leergut aus', () {
    final korb = [ware(1000, 20), pfand(400, 20), pfand(150, 0, kind: 'single_use'), leergut(2, 50, 20)];
    final zeilen = distributeDiscount(korb, 200);
    expect(zeilen.length, 1);
    expect(zeilen.single.priceCents, -200);
    expect(zeilen.single.vat, VatRate.vat20);
    // Mehr als die Ware gibt es nicht zu rabattieren, auch wenn das Pfand dazukommt.
    expect(() => distributeDiscount(korb, 1001), throwsArgumentError);
    // Ein Korb nur aus Pfand ist nicht rabattierbar.
    expect(() => distributeDiscount([pfand(400, 20)], 100), throwsArgumentError);
  });

  test('Einzweckgutschein deckt kein Pfand (E18), Mehrzweck als Zahlung deckt den ganzen Beleg', () {
    final korb = [ware(1000, 20), pfand(400, 20)];
    final info = [VoucherDueInfo(code: code, check: einzweck(5000, 2000))];
    List<KeckVoucher> einloesen(int cents) => [KeckVoucher(action: VoucherAction.redeem, type: VoucherType.singlePurpose, code: code, amountCents: cents)];
    expect(receiptDueCents(korb, einloesen(1000), ReceiptType.standard, voucherInfo: info), 400);
    expect(
      () => receiptDueCents(korb, einloesen(1001), ReceiptType.standard, voucherInfo: info),
      throwsA(isA<ReceiptDueError>().having((e) => e.voucherErrorCode, 'voucherErrorCode', 'voucher_rate_mismatch')),
    );
    expect(voucherRedeemMaxCents(korb, einzweck(5000, 2000), voucherInfo: info), 1000);
    final mehrzweck = VoucherCheck(
        type: VoucherType.multiPurpose, status: VoucherStatus.active, codeSuffix: '5KN2', balanceCents: 5000, faceValueCents: 5000);
    expect(
      receiptDueCents(
        korb,
        [KeckVoucher(action: VoucherAction.redeem, type: VoucherType.multiPurpose, code: code, amountCents: 1400)],
        ReceiptType.standard,
        voucherInfo: [VoucherDueInfo(code: code, check: mehrzweck)],
      ),
      0,
    );
  });

  test('Leergut-Auszahlung: payout deposit nur bei negativem Betrag mit Leergut, hoechstens die Leergutsumme', () {
    final rein = receiptDueBreakdown([leergut(2, 50, 20)], const [], ReceiptType.standard);
    expect(rein.dueCents, -100);
    expect(rein.payout, 'deposit');
    // Leergut zu Ware: positiver Betrag, keine Auszahlung.
    final misch = receiptDueBreakdown([ware(1000, 20), leergut(2, 50, 20)], const [], ReceiptType.standard);
    expect(misch.dueCents, 900);
    expect(misch.payout, isNull);
    // Mehr Leergut als Ware: negativ, aber innerhalb der Leergutsumme.
    final mehr = receiptDueBreakdown([ware(30, 20), leergut(2, 50, 20)], const [], ReceiptType.standard);
    expect(mehr.dueCents, -70);
    expect(mehr.payout, 'deposit');
    // Ware fuehrt nie zu einer Auszahlung: eine Negativzeile ohne Leergut zahlt nicht aus.
    final negativ = receiptDueBreakdown([ware(-100, 20)], const [], ReceiptType.standard);
    expect(negativ.dueCents, -100);
    expect(negativ.payout, isNull);
    // Mehr als die Leergutsumme auszahlen waere Ware: keine Leergut-Auszahlung.
    expect(receiptDueBreakdown([ware(-100, 20), leergut(1, 50, 20)], const [], ReceiptType.standard).payout, isNull);
    // Storno ist keine Auszahlung.
    expect(receiptDueBreakdown([leergut(2, 50, 20)], const [], ReceiptType.cancellation).payout, isNull);
  });

  test('Belege ohne Pfand tragen kein payout', () {
    expect(receiptDueBreakdown([ware(1000, 20)], const [], ReceiptType.standard).payout, isNull);
  });

  test('Pfandzeilen werden als Pfandzeilen gelesen, nicht als Ware (Rot-Probe)', () {
    final z = KasseneckItem.fromJson({
      'kind': 'deposit',
      'name': 'Pfand Kiste',
      'quantity': 1,
      'unitPriceCents': 400,
      'vatRate': 20,
      'depositTypeId': 'kiste',
      'depositFor': 0,
      'depositKind': 'reusable',
      'perUnit': 1,
      'gtin': '9012345001018',
      'ownFilling': true,
    });
    expect(z.isDeposit, isTrue);
    expect(z.isDepositReturn, isFalse);
    expect(z.depositTypeId, 'kiste');
    expect(z.depositFor, 0);
    expect(z.depositKind, 'reusable');
    expect(z.perUnit, 1);
    expect(z.gtin, '9012345001018');
    expect(z.ownFilling, isTrue);
    final r = KasseneckItem.fromJson({
      'kind': 'deposit_return',
      'name': 'Leergut Flasche',
      'quantity': 22,
      'unitPriceCents': -50,
      'vatRate': 20,
      'depositTypeId': 'flasche',
      'depositKind': 'reusable',
      'codes': {'9012345001025': 20, '9012345001049': 2, 'x': 0, '': 3},
    });
    expect(r.isDepositReturn, isTrue);
    expect(r.codes, {'9012345001025': 20, '9012345001049': 2});
    // Die Zeile reist unveraendert mit (Zwischenspeicher) und ueberlebt die Spiegelung.
    expect(KasseneckItem.fromJson(z.toJson()).toJson(), z.toJson());
    expect(KasseneckItem.fromJson(r.toJson()).toJson(), r.toJson());
    expect(r.negative.codes, r.codes);
    // Felder ausserhalb einer Pfandzeile bleiben draussen.
    final ware = KasseneckItem.fromJson({'name': 'Cola', 'quantity': 1, 'unitPriceCents': 200, 'vatRate': 20, 'depositTypeId': 'x', 'ean': '1'});
    expect(ware.depositTypeId, isNull);
    expect(ware.ean, isNull);
    expect(ware.toJson().containsKey('depositTypeId'), isFalse);
  });
}
