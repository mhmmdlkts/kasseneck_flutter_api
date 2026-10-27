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
      expect(v(type: VoucherType.promo, cents: 150).receiptText, 'Aktionsgutschein 1,50 EUR');
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

    // Neue Form (Spec 2026-10-14, „Bon und Beleg“): Zeilen wie am Bon, nie der Klartext-Code.
    KeckVoucher gelesen(String voucherType, VoucherAction action, {VoucherType? type, String? name, int? valueCents, int? amountCents}) =>
        KeckVoucher.fromJson({
          'action': action.name,
          'type': (type ?? VoucherType.fromWire(voucherType)!).wire,
          'voucherType': voucherType,
          'name': ?name,
          'valueCents': ?valueCents,
          'amountCents': ?amountCents,
          'code': '····-····-9DWT',
          'codeSuffix': '9DWT',
          'voucherId': 'g1',
        });

    test('neue Form: Einloesung „Gutschein ····-XXXX“, Auszahlung mit „Auszahlung“ davor', () {
      expect(gelesen('multi_purpose', VoucherAction.redeem, type: VoucherType.value, name: 'Gutschein', valueCents: 1750).receiptText,
          'Gutschein ····-9DWT');
      expect(gelesen('single_purpose', VoucherAction.redeem, name: 'Gutschein', amountCents: 3050).receiptText, 'Gutschein ····-9DWT');
      expect(gelesen('service', VoucherAction.redeem, name: 'Gutschein', amountCents: 3500).receiptText, 'Gutschein ····-9DWT');
      expect(gelesen('multi_purpose', VoucherAction.payout, type: VoucherType.value, name: 'Auszahlung Gutschein', valueCents: 1200).receiptText,
          'Auszahlung Gutschein ····-9DWT');
    });

    test('neue Form: Verkauf mit Bezeichnung und kurzer Code-Maske (R2)', () {
      expect(gelesen('single_purpose', VoucherAction.sell, name: 'Einzweckgutschein 20 %', amountCents: 5000).receiptText,
          'Einzweckgutschein 20 % ····-9DWT');
      expect(gelesen('multi_purpose', VoucherAction.sell, type: VoucherType.value, name: 'Mehrzweckgutschein', valueCents: 5000).receiptText,
          'Mehrzweckgutschein ····-9DWT');
      expect(gelesen('service', VoucherAction.sell, amountCents: 7000).receiptText, 'Leistungsgutschein ····-9DWT');
    });

    test('neue Form, Wunsch mit Klartext-Code: nur die letzten vier Zeichen, nie der Code', () {
      final wunsch = KeckVoucher(action: VoucherAction.redeem, type: VoucherType.multiPurpose, code: 'B1KK5EQ57DHP', amountCents: 500);
      expect(wunsch.receiptText, 'Gutschein ····-7DHP');
      expect(wunsch.receiptText, isNot(contains('B1KK5EQ5')));
      expect(KeckVoucher(action: VoucherAction.redeem, type: VoucherType.promotion, code: 'B1KK5EQ57DHP').receiptText,
          'Aktionsgutschein ····-7DHP');
      expect(KeckVoucher(action: VoucherAction.sell, type: VoucherType.singlePurpose, amountCents: 5000).receiptText, 'Einzweckgutschein');
    });

    test('Aktion: altes Wort am gespeicherten Namen steht allein, wie gespeichert', () {
      expect(v(type: VoucherType.promo, cents: 300, name: 'Promotionsgutschein Sommer').receiptText, 'Promotionsgutschein Sommer');
      expect(v(type: VoucherType.promo, cents: 300, name: 'Aktionsgutschein Herbst').receiptText, 'Aktionsgutschein Herbst');
      // Nur bei der Aktion: ein Wertgutschein mit diesem Namen bleibt Wertgutschein.
      expect(v(cents: 300, name: 'Promotionsgutschein').receiptText, 'Wertgutschein 3 EUR - Promotionsgutschein');
    });

    test('Aktion, wie der Server sie liest (type promo): Rabattzeile wie bisher', () {
      final aktion = gelesen('promotion', VoucherAction.redeem, type: VoucherType.promo, name: 'Aktion', valueCents: 200);
      expect(aktion.receiptText, 'Aktionsgutschein 2 EUR - Aktion');
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

  group('neue Form (Zwilling von voucher-neue-form.test.ts)', () {
    KeckVoucher n(VoucherAction action, VoucherType type,
            {String? code,
            int? amountCents,
            String? articleId,
            int? quantity,
            List<int>? positions,
            String? reason,
            int? valueCents,
            String? voucherId,
            String? typeId}) =>
        KeckVoucher(
            action: action,
            type: type,
            typeId: typeId,
            code: code,
            amountCents: amountCents,
            articleId: articleId,
            quantity: quantity,
            positions: positions,
            reason: reason,
            valueCents: valueCents,
            voucherId: voucherId);
    const sell = VoucherAction.sell, redeem = VoucherAction.redeem, payout = VoucherAction.payout;
    const m = VoucherType.multiPurpose, e = VoucherType.singlePurpose, l = VoucherType.service, a = VoucherType.promotion;

    test('Drahtwerte der Arten und Aktionen', () {
      expect([for (final t in VoucherType.values) t.wire], ['value', 'promo', 'multi_purpose', 'single_purpose', 'service', 'promotion']);
      expect([for (final t in VoucherType.values) t.isNewForm], [false, false, true, true, true, true]);
      expect(VoucherType.fromWire('single_purpose'), VoucherType.singlePurpose);
      expect(VoucherType.fromWire('singlePurpose'), isNull);
      expect(VoucherAction.payout.name, 'payout');
    });

    test('Pruefung bildet die Server-Regeln ab', () {
      for (final g in [
        n(sell, e, amountCents: 100, typeId: 'vt_1'),
        n(sell, l, articleId: 'a', quantity: 2),
        n(redeem, l, code: 'C', positions: [0]),
        n(redeem, a, code: 'C'),
        n(payout, m, code: 'C', amountCents: 5, reason: 'x'),
      ]) {
        expect(g.isValid, isTrue, reason: '${g.toPayload()}');
      }
      for (final g in [
        n(sell, m),
        // Ein Wertgutschein nur ueber eine Sorte (Server: voucher_type_required, 11.6.0).
        n(sell, e, amountCents: 100),
        n(sell, m, amountCents: 0, typeId: 'vt_1'),
        n(sell, l, articleId: 'a'),
        n(sell, a, code: 'C'),
        n(redeem, m, amountCents: 1),
        n(redeem, l, code: 'C', positions: []),
        n(payout, m, code: 'C', amountCents: 5),
        n(payout, m, code: 'C', amountCents: 5, reason: ''),
        n(payout, m, code: 'C', amountCents: 5, reason: 'x' * 201),
        n(payout, l, code: 'C', amountCents: 5, reason: 'x'),
        n(payout, a, code: 'C', reason: 'x'),
        n(payout, VoucherType.value, code: 'C', valueCents: 5, reason: 'x'),
        n(redeem, m, code: 'C', amountCents: 1, voucherId: 'g'),
        n(sell, m, amountCents: 100, valueCents: 100),
      ]) {
        expect(g.isValid, isFalse, reason: '${g.toPayload()}');
      }
    });

    test('Grenzen wie der Server: Betrag, Menge, Positionen, Grund und Code getrimmt', () {
      expect(n(sell, m, amountCents: 1000000, typeId: 'vt_1').isValid, isTrue);
      expect(n(sell, m, amountCents: 1000001, typeId: 'vt_1').isValid, isFalse);
      expect(n(redeem, e, code: 'C', amountCents: 1000001).isValid, isFalse);
      expect(n(sell, l, articleId: 'a', quantity: 100).isValid, isTrue);
      expect(n(sell, l, articleId: 'a', quantity: 101).isValid, isFalse);
      expect(n(redeem, l, code: 'C', positions: [0, 0]).isValid, isFalse);
      expect(n(redeem, l, code: 'C', positions: [0, 1]).isValid, isTrue);
      expect(n(redeem, m, code: '   ', amountCents: 1).isValid, isFalse);
      expect(n(payout, m, code: 'C', amountCents: 1, reason: '   ').isValid, isFalse);
      expect(n(payout, m, code: 'C', amountCents: 1, reason: ' ${'x' * 200} ').isValid, isTrue);
      expect(n(payout, m, code: 'C', amountCents: 1, reason: 'x' * 201).isValid, isFalse);
    });

    test('Nutzlast: die neue Form roh ohne valueCents, die Altform unveraendert', () {
      expect(n(sell, m, amountCents: 5000, typeId: 'vt_mz').toPayload(),
          {'action': 'sell', 'type': 'multi_purpose', 'typeId': 'vt_mz', 'amountCents': 5000});
      expect(n(redeem, l, code: 'CKD59ECF5KNN', positions: [0]).toPayload(),
          {'action': 'redeem', 'type': 'service', 'code': 'CKD59ECF5KNN', 'positions': [0]});
      expect(v(cents: 500, code: 'WG-1').toPayload(), {'action': 'redeem', 'type': 'value', 'valueCents': 500, 'code': 'WG-1'});
      expect(v(cents: 500, code: 'WG-1').toJson().keys, ['name', 'code', 'action', 'type', 'value', 'valueCents']);
    });

    test('Serverfelder werden erkannt; ein gelesener Auszahlungseintrag gehoert zur neuen Form', () {
      final gelesen = KeckVoucher.fromJson(const {
        'action': 'payout',
        'type': 'value',
        'voucherType': 'multi_purpose',
        'value': 30,
        'valueCents': 3000,
        'codeSuffix': '8CN5',
        'voucherId': 'gmz2',
        'reason': 'Kunde zieht weg',
        'zeroRateBucket': true,
      });
      expect(gelesen.action, VoucherAction.payout);
      expect(gelesen.isNewForm, isTrue);
      expect(gelesen.serverFields, ['voucherId', 'codeSuffix', 'zeroRateBucket', 'voucherType']);
      expect(gelesen.isValid, isFalse);
      expect(gelesen.toPayload()['valueCents'], 3000);
      expect(v().serverFields, isEmpty);
    });

    test('ein Feld mit falschem Typ faellt beim Lesen weg, der Beleg bleibt lesbar', () {
      final g = KeckVoucher.fromJson(const {
        'action': 'redeem',
        'type': 'service',
        'positions': [0, 'x'],
        'quantity': 1.5,
        'article': {'id': 'a'},
        'exempt': 'ja',
      });
      expect([g.type, g.positions, g.quantity, g.article, g.exempt], [VoucherType.service, null, null, null, null]);
    });
  });
}
