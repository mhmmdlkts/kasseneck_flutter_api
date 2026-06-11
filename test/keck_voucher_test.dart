import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/voucher_action.dart';
import 'package:kasseneck_api/enums/voucher_type.dart';
import 'package:kasseneck_api/models/keck_voucher.dart';

KeckVoucher v({VoucherAction action = VoucherAction.redeem, VoucherType type = VoucherType.value, int? cents = 100, String? name, String? code}) =>
    KeckVoucher(name: name, code: code, action: action, type: type, valueCents: cents);

void main() {
  group('isValid-Vollmatrix', () {
    test('Wertgutschein ohne Wert -> ungueltig', () {
      expect(v(type: VoucherType.value, cents: null).isValid, isFalse);
    });
    test('Promo ohne Wert -> ungueltig', () {
      expect(v(type: VoucherType.promo, cents: null).isValid, isFalse);
    });
    test('Promo darf nur redeem sein', () {
      expect(v(type: VoucherType.promo, action: VoucherAction.sell).isValid, isFalse);
      expect(v(type: VoucherType.promo, action: VoucherAction.redeem).isValid, isTrue);
    });
    test('Wert 0 oder negativ -> ungueltig', () {
      expect(v(cents: 0).isValid, isFalse);
      expect(v(cents: -100).isValid, isFalse);
    });
    test('gueltige Kombinationen', () {
      expect(v(type: VoucherType.value, action: VoucherAction.sell).isValid, isTrue);
      expect(v(type: VoucherType.value, action: VoucherAction.redeem).isValid, isTrue);
      expect(v(type: VoucherType.promo, action: VoucherAction.redeem, cents: 1).isValid, isTrue);
    });
  });

  group('receiptText', () {
    test('Wertgutschein mit ganzem Betrag', () {
      expect(v(cents: 1000).receiptText, 'Wertgutschein 10 EUR');
    });
    test('krummer Betrag exakt (kein ~ mehr)', () {
      expect(v(type: VoucherType.promo, cents: 150).receiptText, 'Promotionsgutschein 1,50 EUR');
      expect(v(cents: 1).receiptText, 'Wertgutschein 0,01 EUR');
    });
    test('Name wird angehaengt', () {
      expect(v(cents: 500, name: 'Geschenk').receiptText, 'Wertgutschein 5 EUR - Geschenk');
    });
    test('Name, der den Typ schon enthaelt, ersetzt den Text komplett', () {
      expect(v(cents: 500, name: 'Mein Wertgutschein XL').receiptText, 'Mein Wertgutschein XL');
    });
    test('leerer Name wird ignoriert', () {
      expect(v(cents: 500, name: '').receiptText, 'Wertgutschein 5 EUR');
    });
  });

  group('euro-Konstruktor', () {
    test('rundet einmal an der Grenze', () {
      expect(KeckVoucher.euro(action: VoucherAction.sell, type: VoucherType.value, value: 9.99).valueCents, 999);
      expect(KeckVoucher.euro(action: VoucherAction.redeem, type: VoucherType.promo, value: 0.1 + 0.2).valueCents, 30);
    });
  });

  group('JSON', () {
    test('null-Wert ueberlebt Roundtrip', () {
      final j = v(cents: null).toJson();
      expect(j['value'], isNull);
      expect(j['valueCents'], isNull);
      expect(KeckVoucher.fromJson(j).valueCents, isNull);
    });
    test('unbekannte action/type fallen auf sell/promo zurueck', () {
      final voucher = KeckVoucher.fromJson({'action': 'XXX', 'type': 'YYY', 'value': 1.0});
      expect(voucher.action, VoucherAction.sell);
      expect(voucher.type, VoucherType.promo);
    });
    test('valueCents als double wird gerundet', () {
      expect(KeckVoucher.fromJson({'action': 'sell', 'type': 'value', 'valueCents': 500.0}).valueCents, 500);
    });
  });
}
