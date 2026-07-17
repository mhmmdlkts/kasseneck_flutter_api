import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/models/keck_invoice_item.dart';

void main() {
  group('KasseneckItem.euro (Rundung an der API-Grenze)', () {
    test('typische Preise', () {
      expect(KasseneckItem.euro(name: 'x', quantity: 1, vat: VatRate.vat20, singlePrice: 19.99).priceCents, 1999);
      expect(KasseneckItem.euro(name: 'x', quantity: 1, vat: VatRate.vat20, singlePrice: 0.01).priceCents, 1);
      expect(KasseneckItem.euro(name: 'x', quantity: 1, vat: VatRate.vat20, singlePrice: 100).priceCents, 10000);
    });
    test('negative Preise (Storno) runden korrekt', () {
      expect(KasseneckItem.euro(name: 'x', quantity: 1, vat: VatRate.vat20, singlePrice: -19.99).priceCents, -1999);
    });
    test('Berechnungsreste (0.1+0.2) werden weggerundet', () {
      expect(KasseneckItem.euro(name: 'x', quantity: 1, vat: VatRate.vat20, singlePrice: 0.1 + 0.2).priceCents, 30);
    });
    test('Halbcent-Eingaben: Verhalten dokumentiert (round() auf Binaerwert)', () {
      // 1.005 und 1.015 sind binaer beide knapp UNTER dem Halbcent
      // (1.00499..., 1.01499...) -> es rundet ab. Wer exakte Halbcent-Preise
      // braucht, setzt direkt priceCents.
      expect(KasseneckItem.euro(name: 'x', quantity: 1, vat: VatRate.vat20, singlePrice: 1.005).priceCents, 100);
      expect(KasseneckItem.euro(name: 'x', quantity: 1, vat: VatRate.vat20, singlePrice: 1.015).priceCents, 101);
    });
  });

  group('negative / cancel', () {
    final item = KasseneckItem(name: 'x', quantity: 3, vat: VatRate.vat10, priceCents: 250);
    test('negative kehrt nur den Preis um', () {
      final n = item.negative;
      expect(n.priceCents, -250);
      expect(n.quantity, 3);
      expect(n.vat, VatRate.vat10);
      expect(n.name, 'x');
    });
    test('doppelt negiert == Original', () {
      expect(item.negative.negative.priceCents, item.priceCents);
    });
    test('totalCents von negativem Item', () {
      expect(item.negative.totalCents, -750);
    });
  });

  group('isValid', () {
    test('gueltig', () {
      expect(KasseneckItem(name: 'x', quantity: 1, vat: VatRate.vat20, priceCents: 0).isValid, isTrue);
    });
    test('leerer Name -> ungueltig', () {
      expect(KasseneckItem(name: '', quantity: 1, vat: VatRate.vat20, priceCents: 100).isValid, isFalse);
    });
    test('quantity 0 / negativ -> ungueltig', () {
      expect(KasseneckItem(name: 'x', quantity: 0, vat: VatRate.vat20, priceCents: 100).isValid, isFalse);
      expect(KasseneckItem(name: 'x', quantity: -1, vat: VatRate.vat20, priceCents: 100).isValid, isFalse);
    });
  });

  group('fromJson Grenzfaelle', () {
    test('unbekannter vat-Satz faellt auf vat0 zurueck (dokumentiertes Verhalten)', () {
      final item = KasseneckItem.fromJson({'name': 'x', 'amount': 1, 'vat': 7, 'priceOne': 1.0});
      expect(item.vat, VatRate.vat0);
    });
    test('alle bekannten Saetze mappen korrekt', () {
      for (final rate in VatRate.values) {
        final item = KasseneckItem.fromJson({'name': 'x', 'amount': 1, 'vat': rate.rate, 'priceOne': 1.0});
        expect(item.vat, rate, reason: 'Satz ${rate.rate}');
      }
    });
    test('priceOneCents als double (JSON kennt kein int) wird gerundet', () {
      final item = KasseneckItem.fromJson({'name': 'x', 'amount': 1, 'vat': 20, 'priceOneCents': 1999.0});
      expect(item.priceCents, 1999);
    });
    test('v2-Form (unitPriceCents/quantity/vatRate) wird gelesen', () {
      final item = KasseneckItem.fromJson({
        'name': 'Brot', 'quantity': 3, 'vatRate': 10, 'unitPriceCents': 249,
      });
      expect(item.name, 'Brot');
      expect(item.quantity, 3);
      expect(item.vat, VatRate.vat10);
      expect(item.priceCents, 249);
    });
    test('v2 gewinnt gegen v1 bei gemischten Feldern', () {
      final item = KasseneckItem.fromJson({
        'name': 'x', 'quantity': 5, 'amount': 1,
        'vatRate': 20, 'vat': 10,
        'unitPriceCents': 500, 'priceOneCents': 100, 'priceOne': 99.0,
      });
      expect(item.quantity, 5);
      expect(item.vat, VatRate.vat20);
      expect(item.priceCents, 500);
    });
    test('toJson->fromJson Round-Trip (v2)', () {
      final orig = KasseneckItem(name: 'Kaffee', quantity: 2, vat: VatRate.vat13, priceCents: 320);
      final back = KasseneckItem.fromJson(orig.toJson());
      expect(back.name, 'Kaffee');
      expect(back.quantity, 2);
      expect(back.vat, VatRate.vat13);
      expect(back.priceCents, 320);
    });
  });

  group('singlePrice-Getter (Euro-Sicht)', () {
    test('ist immer priceCents/100', () {
      expect(KasseneckItem(name: 'x', quantity: 1, vat: VatRate.vat20, priceCents: 1999).singlePrice, 19.99);
      expect(KasseneckItem(name: 'x', quantity: 1, vat: VatRate.vat20, priceCents: -50).singlePrice, -0.5);
    });
  });

  group('KeckInvoiceItem (Spiegel-Suite)', () {
    test('euro-Konstruktor + totalCents', () {
      final it = KeckInvoiceItem.euro(name: 'x', quantity: 4, quantityUnit: 'Stk', vat: VatRate.vat13, singlePrice: 2.50);
      expect(it.priceCents, 250);
      expect(it.totalCents, 1000);
    });
    test('toJson dual + fromJson-Praezedenz', () {
      final j = KeckInvoiceItem(name: 'x', quantity: 1, quantityUnit: 'kg', vat: VatRate.vat10, priceCents: 333).toJson();
      expect(j['singlePrice'], 3.33);
      expect(j['singlePriceCents'], 333);
      final back = KeckInvoiceItem.fromJson({...j, 'singlePrice': 99.0});
      expect(back.priceCents, 333, reason: 'Cents muessen gewinnen');
    });
    test('isValid wie KasseneckItem', () {
      expect(KeckInvoiceItem(name: '', quantity: 1, quantityUnit: 'x', vat: VatRate.vat0, priceCents: 1).isValid, isFalse);
      expect(KeckInvoiceItem(name: 'x', quantity: 0, quantityUnit: 'x', vat: VatRate.vat0, priceCents: 1).isValid, isFalse);
    });
  });

  group('VatRate-Tabelle (API-Kontrakt)', () {
    test('alle 6 Saetze mit Kategorien', () {
      expect(VatRate.values.length, 6);
      expect(VatRate.vat0.rate, 0);
      expect(VatRate.vat0.category, 'D');
      expect(VatRate.vat4komma9.rate, 4.9);
      expect(VatRate.vat4komma9.category, 'G');
      expect(VatRate.vat10.rate, 10);
      expect(VatRate.vat10.category, 'B');
      expect(VatRate.vat13.rate, 13);
      expect(VatRate.vat13.category, 'C');
      expect(VatRate.vat19.rate, 19);
      expect(VatRate.vat19.category, 'E');
      expect(VatRate.vat20.rate, 20);
      expect(VatRate.vat20.category, 'A');
    });
  });
}
