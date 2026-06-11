import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/enums/receipt_type.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/enums/voucher_action.dart';
import 'package:kasseneck_api/enums/voucher_type.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/keck_voucher.dart';

/// Sollwerte fuer die manuellen Geraete-Tests (v3-Migration):
/// zwei "fiese" Warenkoerbe, deren Summen am Geraet, am Ausdruck und im
/// QR-Code genau so erscheinen muessen.
///
/// Hinweis: Promo-Gutscheine duerfen laut Kombinationsregeln NICHT mit
/// anderen Gutscheinen kombiniert werden -> daher zwei getrennte Belege.
void main() {
  KasseneckReceipt receipt({required List<KasseneckItem> items, List<KeckVoucher>? vouchers}) {
    return KasseneckReceipt(
      receiptId: 'R1', cashregisterId: 'C1', timeStamp: DateTime(2026, 6, 12),
      items: items, vouchers: vouchers, paymentMethod: KeckPaymentMethod.cash,
      turnoverCounterAES256ICM: '', signaturePreviousReceipt: '',
      certificateSerialNumber: '', receiptType: ReceiptType.standard,
      sig: 'h.p.s', qr: '', companyName: '', phone: '', isSmallBusiness: false,
      uid: null, taxnr: '', street: '', zip: '', city: '', fullReceiptId: '',
      footer1: '', footer2: '',
    );
  }

  final items = [
    KasseneckItem(name: 'Klassiker', quantity: 3, vat: VatRate.vat20, priceCents: 1999), // 59,97
    KasseneckItem(name: 'Brot 4,9%', quantity: 1, vat: VatRate.vat4komma9, priceCents: 29), // 0,29
    KasseneckItem(name: 'Milch', quantity: 2, vat: VatRate.vat10, priceCents: 105), // 2,10
  ];

  test('Beleg A (Promo-Gutschein): Gesamt 60,86 — kein Zwischensummen-Block', () {
    final r = receipt(items: items, vouchers: [
      KeckVoucher(name: 'Aktion', action: VoucherAction.redeem, type: VoucherType.promo, valueCents: 150),
    ]);
    expect(r.subSumCents, 6086); // 5997 + 29 + 210 - 150
    expect(r.sumCents, 6086);    // Promo wirkt schon in der Zwischensumme
    expect(r.totalPromoVoucherValueCents, 150);
    // sum == subSum -> der Zwischensummen-Block wird am Ausdruck NICHT gedruckt
  });

  test('Beleg B (Wertgutscheine): Zwischensumme 72,36 / Gesamt 67,36', () {
    final r = receipt(items: items, vouchers: [
      KeckVoucher(name: 'Geschenkkarte', action: VoucherAction.sell, type: VoucherType.value, valueCents: 1000),
      KeckVoucher(name: 'Geschenkkarte', code: 'GS-0001', action: VoucherAction.redeem, type: VoucherType.value, valueCents: 500),
    ]);
    expect(r.subSumCents, 7236); // 6236 + 1000 (verkaufter Gutschein)
    expect(r.sumCents, 6736);    // - 500 (eingeloester Gutschein)
  });

  test('Gutschein-Text: krumme Betraege exakt ("1,50"), keine ~Rundung mehr', () {
    final promo = KeckVoucher(action: VoucherAction.redeem, type: VoucherType.promo, valueCents: 150);
    expect(promo.receiptText, 'Promotionsgutschein 1,50 EUR');
    final value = KeckVoucher(name: 'Geschenkkarte', action: VoucherAction.sell, type: VoucherType.value, valueCents: 1000);
    expect(value.receiptText, 'Wertgutschein 10 EUR - Geschenkkarte');
  });

  test('Storno von Beleg A: alle Betraege exakt negativ', () {
    final storno = items.map((i) => i.negative).toList();
    final r = receipt(items: storno);
    expect(r.sumCents, -6236);
    expect(storno[0].totalCents, -5997);
    expect(storno[1].priceCents, -29);
  });
}
