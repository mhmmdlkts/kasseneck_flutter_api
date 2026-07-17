import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/enums/receipt_type.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/enums/voucher_action.dart';
import 'package:kasseneck_api/enums/voucher_type.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/keck_invoice_item.dart';
import 'package:kasseneck_api/models/keck_voucher.dart';

/// Geld als Integer-Cent: Beweis-Tests fuer die v3-Migration.
///
/// Das Wichtigste ist der Wire-Roundtrip: das JSON-Format Richtung Backend
/// bleibt Euro (`priceOne: 19.99`). cents -> /100 -> double -> *100 -> round
/// muss fuer JEDEN Betrag verlustfrei sein, sonst waere die Migration nicht
/// backend-kompatibel.
void main() {
  KasseneckReceipt receipt({required List<KasseneckItem> items, List<KeckVoucher>? vouchers}) {
    return KasseneckReceipt(
      receiptId: 'R1',
      cashregisterId: 'C1',
      timeStamp: DateTime(2026, 6, 11),
      items: items,
      vouchers: vouchers,
      paymentMethod: KeckPaymentMethod.cash,
      turnoverCounterAES256ICM: '',
      signaturePreviousReceipt: '',
      certificateSerialNumber: '',
      receiptType: ReceiptType.standard,
      sig: 'h.p.s',
      qr: '',
      companyName: '',
      phone: '',
      isSmallBusiness: false,
      uid: null,
      taxnr: '',
      street: '',
      zip: '',
      city: '',
      fullReceiptId: '',
      footer1: '',
      footer2: '',
    );
  }

  group('Wire-Roundtrip (JSON bleibt Euro, verlustfrei)', () {
    test('alle Cent-Betraege 0..99999 ueberleben toJson -> fromJson exakt', () {
      for (int cents = 0; cents <= 99999; cents++) {
        final item = KasseneckItem(name: 'x', quantity: 1, vat: VatRate.vat20, priceCents: cents);
        final back = KasseneckItem.fromJson(item.toJson());
        expect(back.priceCents, cents, reason: 'Roundtrip-Verlust bei $cents Cent');
      }
    });

    test('grosse und negative Betraege (Storno) verlustfrei', () {
      final rnd = Random(42);
      for (int i = 0; i < 20000; i++) {
        final cents = (rnd.nextInt(2000000000) - 1000000000); // +/- 10 Mio EUR
        final item = KasseneckItem(name: 'x', quantity: 1, vat: VatRate.vat10, priceCents: cents);
        expect(KasseneckItem.fromJson(item.toJson()).priceCents, cents);
      }
    });

    test('KeckVoucher-Roundtrip inkl. null', () {
      for (final cents in [null, 1, 99, 500, 12345, 99999999]) {
        final v = KeckVoucher(action: VoucherAction.sell, type: VoucherType.value, valueCents: cents);
        expect(KeckVoucher.fromJson(v.toJson()).valueCents, cents);
      }
    });

    test('KeckInvoiceItem-Roundtrip', () {
      for (final cents in [0, 1, 29, 1005, 199999]) {
        final it = KeckInvoiceItem(name: 'x', quantity: 2, quantityUnit: 'Stk', vat: VatRate.vat13, priceCents: cents);
        expect(KeckInvoiceItem.fromJson(it.toJson()).priceCents, cents);
      }
    });
  });

  group('Wire-Format: v2 (ganze Cent) senden, v1+v2 lesen', () {
    test('toJson sendet v2-Form mit Integer-Cent', () {
      final j = KasseneckItem(name: 'x', quantity: 1, vat: VatRate.vat20, priceCents: 1999).toJson();
      expect(j['unitPriceCents'], 1999);
      expect(j['quantity'], 1);
      expect(j['vatRate'], 20);
      final v = KeckVoucher(action: VoucherAction.sell, type: VoucherType.value, valueCents: 500).toJson();
      expect(v['valueCents'], 500);
      expect(v['value'], 5.0);
    });

    test('fromJson bevorzugt Cents (bei widerspruechlichen Feldern gewinnt Cents)', () {
      final item = KasseneckItem.fromJson({
        'name': 'x', 'amount': 1, 'vat': 20,
        'priceOne': 99.99, 'priceOneCents': 1234, // absichtlich widerspruechlich
      });
      expect(item.priceCents, 1234);
      final voucher = KeckVoucher.fromJson({
        'action': 'sell', 'type': 'value', 'value': 99.0, 'valueCents': 500,
      });
      expect(voucher.valueCents, 500);
    });

    test('Legacy-JSON (nur Euro, z. B. alte Belege) parst weiterhin', () {
      final item = KasseneckItem.fromJson({'name': 'x', 'amount': 2, 'vat': 10, 'priceOne': 1.05});
      expect(item.priceCents, 105);
      final voucher = KeckVoucher.fromJson({'action': 'redeem', 'type': 'promo', 'value': 1.5});
      expect(voucher.valueCents, 150);
    });
  });

  group('Klassische double-Fallen sind jetzt exakt', () {
    test('0,10 + 0,20 = 0,30 (statt 0.30000000000000004)', () {
      final r = receipt(items: [
        KasseneckItem(name: 'a', quantity: 1, vat: VatRate.vat20, priceCents: 10),
        KasseneckItem(name: 'b', quantity: 1, vat: VatRate.vat20, priceCents: 20),
      ]);
      expect(r.sumCents, 30);
    });

    test('3 x 19,99 = 59,97 (statt 59.97000000000001)', () {
      final item = KasseneckItem(name: 'x', quantity: 3, vat: VatRate.vat20, priceCents: 1999);
      expect(item.totalCents, 5997);
    });

    test('KasseneckItem.euro rundet genau einmal an der Grenze', () {
      expect(KasseneckItem.euro(name: 'x', quantity: 1, vat: VatRate.vat20, singlePrice: 19.99).priceCents, 1999);
      expect(KasseneckItem.euro(name: 'x', quantity: 1, vat: VatRate.vat20, singlePrice: 0.29).priceCents, 29);
      expect(KasseneckItem.euro(name: 'x', quantity: 1, vat: VatRate.vat20, singlePrice: 0.1 + 0.2).priceCents, 30);
    });
  });

  group('Belegsummen: exakte Cent-Arithmetik inkl. Gutscheine', () {
    test('subSum/sum mit Promo- und Wertgutschein', () {
      final r = receipt(
        items: [
          KasseneckItem(name: 'a', quantity: 3, vat: VatRate.vat10, priceCents: 333),   // 9,99
          KasseneckItem(name: 'b', quantity: 1, vat: VatRate.vat4komma9, priceCents: 240), // 2,40
        ],
        vouchers: [
          KeckVoucher(action: VoucherAction.redeem, type: VoucherType.promo, valueCents: 150),
          KeckVoucher(action: VoucherAction.redeem, type: VoucherType.value, valueCents: 500),
          KeckVoucher(action: VoucherAction.sell, type: VoucherType.value, valueCents: 1000),
        ],
      );
      // subSum = 999 + 240 - 150 (promo) + 1000 (verkaufter Wertgutschein) = 2089
      expect(r.subSumCents, 2089);
      // sum = subSum - 500 (eingeloester Wertgutschein) = 1589
      expect(r.sumCents, 1589);
      expect(r.totalPromoVoucherValueCents, 150);
      // Euro-Getter sind konsistente Sichten auf dieselben Cents
      expect(r.sum, 15.89);
      expect(r.subSum, 20.89);
    });

    test('Property: Zufallswarenkoerbe — Belegsumme == manuelle Cent-Summe', () {
      final rnd = Random(7);
      for (int run = 0; run < 2000; run++) {
        final items = List.generate(1 + rnd.nextInt(15), (i) => KasseneckItem(
          name: 'item$i',
          quantity: 1 + rnd.nextInt(9),
          vat: VatRate.values[rnd.nextInt(VatRate.values.length)],
          priceCents: 1 + rnd.nextInt(99999),
        ));
        final r = receipt(items: items);
        final manual = items.fold<int>(0, (s, it) => s + it.priceCents * it.quantity);
        expect(r.sumCents, manual);
        expect(r.subSumCents, manual);
        // und der Wire-Roundtrip der Items bleibt verlustfrei
        for (final it in items) {
          expect(KasseneckItem.fromJson(it.toJson()).priceCents, it.priceCents);
        }
      }
    });
  });
}
