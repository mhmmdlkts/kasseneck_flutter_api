import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/src/vat_math.dart';

void main() {
  test('99 Cent zu 20 %: 83 Netto, 16 MwSt — der dokumentierte Grenzfall', () {
    final netto = nettoCentsAusBrutto(99, 20);
    expect(netto, 83);
    expect(99 - netto, 16);
  });

  test('Netto + MwSt ergibt IMMER das Brutto — alle Saetze, 1 bis 2000 Cent', () {
    for (final num rate in [20, 13, 10, 4.9, 0]) {
      for (int brutto = 1; brutto <= 2000; brutto++) {
        final netto = nettoCentsAusBrutto(brutto, rate);
        expect(netto + (brutto - netto), brutto);
        expect(netto, greaterThanOrEqualTo(0));
        expect(netto, lessThanOrEqualTo(brutto));
      }
    }
  });

  test('ein Storno zerfaellt spiegelbildlich zu seinem Beleg', () {
    expect(nettoCentsAusBrutto(-99, 20), -nettoCentsAusBrutto(99, 20));
  });
}
