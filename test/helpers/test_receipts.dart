import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/enums/receipt_type.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/enums/voucher_action.dart';
import 'package:kasseneck_api/enums/voucher_type.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/keck_voucher.dart';

/// Gemeinsame Beleg-Fabrik fuer die Tests. Alle Felder gefuellt, damit auch
/// Render-Tests (Print/Widget) ohne Sonderfaelle laufen.
KasseneckReceipt buildReceipt({
  List<KasseneckItem>? items,
  List<KeckVoucher>? vouchers,
  KeckPaymentMethod paymentMethod = KeckPaymentMethod.cash,
  ReceiptType receiptType = ReceiptType.standard,
  DateTime? timeStamp,
  String sig = 'header.payload.echteSignatur',
  String? uid = 'ATU12345678',
  Map<String, dynamic>? cardPaymentData,
  cardProvider,
  String? cardPaymentId,
  bool showKreiseckLogo = false,
}) {
  return KasseneckReceipt(
    receiptId: 'TEST-ID-1',
    cashregisterId: 'TESTBOX-1',
    timeStamp: timeStamp ?? DateTime(2026, 6, 12, 10, 30, 5),
    items: items ?? [],
    vouchers: vouchers,
    paymentMethod: paymentMethod,
    turnoverCounterAES256ICM: 'dHVybm92ZXI=',
    signaturePreviousReceipt: 'cHJldg==',
    certificateSerialNumber: '5ca2bef9',
    receiptType: receiptType,
    sig: sig,
    qr: 'TESTQRDATA',
    companyName: 'Kasseneck Test GmbH',
    phone: '+43 1 2345678',
    isSmallBusiness: false,
    uid: uid,
    taxnr: '12 345/6789',
    street: 'Teststrasse 1',
    zip: '1010',
    city: 'Wien',
    fullReceiptId: 'enc-full-id',
    footer1: 'Footer Eins',
    footer2: 'Footer Zwei',
    customerDetails: const [],
    creditCardProvider: cardProvider,
    cardPaymentData: cardPaymentData,
    cardPaymentId: cardPaymentId,
    showKreiseckLogo: showKreiseckLogo,
  );
}

/// Warenkorb A (Geraete-Testbeleg): 3x19,99@20% + 0,29@4,9% + 2x1,05@10%
/// + Promo-Gutschein 1,50. Gesamt 60,86 — MwSt-Brutto: A 58,52 / G 0,29 / B 2,05.
KasseneckReceipt cartA() => buildReceipt(
      items: [
        KasseneckItem(name: 'Klassiker', quantity: 3, vat: VatRate.vat20, priceCents: 1999),
        KasseneckItem(name: 'Brot', quantity: 1, vat: VatRate.vat4komma9, priceCents: 29),
        KasseneckItem(name: 'Milch', quantity: 2, vat: VatRate.vat10, priceCents: 105),
      ],
      vouchers: [
        KeckVoucher(name: 'Aktion', action: VoucherAction.redeem, type: VoucherType.promo, valueCents: 150),
      ],
    );

/// Warenkorb B: gleiche Items + Wertgutschein verkauft (10) und eingeloest (5).
/// Zwischensumme 72,36 / Gesamt 67,36 — MwSt-Brutto: A 59,97 / G 0,29 / B 2,10 / D 10,00.
KasseneckReceipt cartB() => buildReceipt(
      items: [
        KasseneckItem(name: 'Klassiker', quantity: 3, vat: VatRate.vat20, priceCents: 1999),
        KasseneckItem(name: 'Brot', quantity: 1, vat: VatRate.vat4komma9, priceCents: 29),
        KasseneckItem(name: 'Milch', quantity: 2, vat: VatRate.vat10, priceCents: 105),
      ],
      vouchers: [
        KeckVoucher(name: 'Geschenkkarte', action: VoucherAction.sell, type: VoucherType.value, valueCents: 1000),
        KeckVoucher(name: 'Geschenkkarte', code: 'GS-1', action: VoucherAction.redeem, type: VoucherType.value, valueCents: 500),
      ],
    );
