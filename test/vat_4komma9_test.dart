import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';

/// Neuer Grundnahrungsmittel-Satz 4,9 % (ab 01.07.2026).
/// Backend/RKSV: 4,9 % -> Betrag-Satz-Besonders, Kategorie "G".
void main() {
  group('VatRate 4,9 % (Grundnahrungsmittel)', () {
    test('Enum-Wert vorhanden: rate 4.9, Kategorie G', () {
      expect(VatRate.vat4komma9.rate, 4.9);
      expect(VatRate.vat4komma9.category, 'G');
    });

    test('fromJson(vat: 4.9) -> vat4komma9 (frueher still als 0 % geparst!)', () {
      final item = KasseneckItem.fromJson({
        'name': 'Brot',
        'amount': 1,
        'vat': 4.9,
        'priceOne': 1.20,
      });
      expect(item.vat, VatRate.vat4komma9, reason: 'darf NICHT auf vat0 zurueckfallen');
      expect(item.vat.rate, 4.9);
    });

    test('toJson schickt 4.9 als vat ans Backend', () {
      final item = KasseneckItem(
        name: 'Brot',
        quantity: 1,
        vat: VatRate.vat4komma9,
        priceCents: 120,
      );
      expect(item.toJson()['vat'], 4.9);
      expect(item.toJson()['priceOne'], 1.20); // Wire-Format bleibt Euro
    });

    test('Regression: bestehende Saetze unveraendert', () {
      expect(VatRate.vat20.rate, 20);
      expect(VatRate.vat20.category, 'A');
      expect(VatRate.vat10.rate, 10);
      expect(VatRate.vat0.rate, 0);
      final item = KasseneckItem.fromJson({
        'name': 'Ware',
        'amount': 1,
        'vat': 20,
        'priceOne': 10.0,
      });
      expect(item.vat, VatRate.vat20);
    });
  });
}
