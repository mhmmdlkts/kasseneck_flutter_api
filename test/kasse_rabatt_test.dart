import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/kasse.dart';

/// `verteileRabatt` (kassieren.dart) gegen die JS-Golden-Zahlen — dieselben
/// Werte wie src/receipt/discount.ts, damit beide Pakete nachweislich gleich
/// rechnen; seit kind 'discount' auch die Kennzeichnung.
void main() {
  final semmel = KasseneckItem(name: 'Semmel', quantity: 4, vat: VatRate.vat10, priceCents: 79);
  final kaffee = KasseneckItem(name: 'Kaffee klein', quantity: 1, vat: VatRate.vat20, priceCents: 280);

  test('verteilt anteilig je Steuersatz und kennzeichnet mit kind discount (Golden-Zahlen 0,60 auf 5,96)', () {
    final zeilen = verteileRabatt([semmel, kaffee], 60, name: 'Rabatt 10 %');
    expect(zeilen.length, 2);
    final b = zeilen.firstWhere((z) => z.vat == VatRate.vat10);
    final a = zeilen.firstWhere((z) => z.vat == VatRate.vat20);
    // 3,16 : 2,80 -> 32 : 28 Cent (wie das JS-Paket / Golden rabattzeilen)
    expect(b.priceCents, -32);
    expect(a.priceCents, -28);
    expect(zeilen.every((z) => z.isDiscount && z.quantity == 1 && z.name == 'Rabatt 10 %'), isTrue);
  });

  test('Hare-Niemeyer: Restcent geht an den groessten Bruchteil', () {
    // 100 auf 3 gleiche Saetze gibt es nicht -- 1 Cent auf zwei gleiche
    // Umsaetze: eine Gruppe bekommt ihn, Summe stimmt exakt.
    final a = KasseneckItem(name: 'A', quantity: 1, vat: VatRate.vat10, priceCents: 100);
    final b = KasseneckItem(name: 'B', quantity: 1, vat: VatRate.vat20, priceCents: 100);
    final zeilen = verteileRabatt([a, b], 1);
    expect(zeilen.length, 1);
    expect(zeilen.single.priceCents, -1);
  });

  test('Rot-Proben: 0 ergibt nichts, negativ und mehr als der Umsatz werfen', () {
    expect(verteileRabatt([semmel], 0), isEmpty);
    expect(() => verteileRabatt([semmel], -1), throwsArgumentError);
    expect(() => verteileRabatt([semmel], 10000), throwsArgumentError);
  });

  test('negative Positionen (bestehende Rabatte/Stornos) zaehlen nicht zur Basis', () {
    final alt = KasseneckItem(name: 'Rabatt', quantity: 1, vat: VatRate.vat10, priceCents: -100, kind: 'discount');
    final zeilen = verteileRabatt([semmel, alt], 60);
    expect(zeilen.length, 1);
    expect(zeilen.single.vat, VatRate.vat10);
    expect(zeilen.single.priceCents, -60);
  });
}
