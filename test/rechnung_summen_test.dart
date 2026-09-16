import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/rechnung.dart';
import 'package:kasseneck_api/src/vat_math.dart';

/// `rechnungSummen` gegen die Prüffälle des JS-Zwillings.
///
/// Die Fälle liegen in `test/fixtures/vertrag/rechnung-summen.json` — gezogen
/// von `tool/zwillinge.sh` aus dem npm-Paket und in der CI byteweise gegen das
/// Paket geprüft. Eine Kopie, die hier jemand von Hand „richtig" macht, fällt
/// dort auf; geändert werden die Fälle nur im JS-Paket.
///
/// Anlass: Ein Shop stellte im Brutto-Modus 14,79 € + 15,00 € zu 20 % aus und
/// bekam eine Rechnung über 29,80 €.

final _datei = jsonDecode(File('test/fixtures/vertrag/rechnung-summen.json').readAsStringSync()) as Map<String, dynamic>;

List<Map<String, dynamic>> get _faelle => (_datei['faelle'] as List).cast<Map<String, dynamic>>();

SummenPosition _position(Map<String, dynamic> p) => SummenPosition(
      quantity: p['quantity'] as num,
      unitPriceCents: p['unitPriceCents'] as num,
      vatRate: p['vatRate'] as int,
      discountPct: p['discountPct'] as num?,
    );

InvoiceTotals _brutto(int cent, int satz) =>
    rechnungSummen([SummenPosition(quantity: 1, unitPriceCents: cent, vatRate: satz)], 'gross');

void main() {
  group('Prüffälle aus dem Vertrag', () {
    test('jeder Fall trifft genau', () {
      // Die Mindestzahl haelt die Pruefung ehrlich: eine leere oder gekuerzte
      // Datei liesse die Schleife unten sonst grün durchlaufen.
      expect(_faelle.length, greaterThanOrEqualTo(15));
      for (final f in _faelle) {
        final items = [for (final p in (f['items'] as List).cast<Map<String, dynamic>>()) _position(p)];
        final summen = f.containsKey('taxScheme')
            ? rechnungSummen(items, f['priceMode'] as String, f['taxScheme'] as String)
            : rechnungSummen(items, f['priceMode'] as String);
        expect(summen.toJson(), f['erwartet'], reason: f['name'] as String);
      }
    });

    test('die Rückmeldung des Shops steht drin', () {
      final namen = _faelle.map((f) => f['name'] as String).join('\n');
      expect(namen, contains('0,03 €'));
      expect(namen, contains('29,79 €'));
    });
  });

  group('Brutto bleibt Brutto', () {
    test('jeder Betrag von 1 bis 10000 Cent zu 10, 13 und 20 %', () {
      final falsch = <String>[];
      for (final satz in [10, 13, 20]) {
        for (var c = 1; c <= 10000; c++) {
          final s = _brutto(c, satz);
          final r = s.byRate.single;
          if (s.grossCents != c || s.netCents + s.vatCents != c || r.grossCents != c || r.rate != satz) {
            falsch.add('$c@$satz');
          }
        }
      }
      expect(falsch, isEmpty);
    });

    test('Netto ist B × 100 / (100 + Satz), halber Cent aufwärts', () {
      for (var c = 1; c <= 5000; c++) {
        // In ganzen Zahlen: floor((200·c + 120) / 240) ist round(c·100/120)
        // mit halbem Cent aufwaerts.
        expect(_brutto(c, 20).netCents, (200 * c + 120) ~/ 240, reason: '$c Cent');
      }
    });

    test('für die Rechnungssätze dieselbe Zahl wie nettoCentsAusBrutto am Beleg', () {
      // Zwei Rechenwege fuer dieselbe Zahl sind hier bewusst getrennt (Server
      // gegen Beleg) — aber nur, solange sie dasselbe ergeben. Faellt einer
      // auseinander, soll das hier auffallen und nicht an der Kasse.
      final falsch = <String>[];
      for (final satz in [10, 13, 20]) {
        for (var c = 1; c <= 10000; c++) {
          if (_brutto(c, satz).netCents != nettoCentsAusBrutto(c, satz)) falsch.add('$c@$satz');
        }
      }
      expect(falsch, isEmpty);
    });

    test('mehrere Zeilen: das Brutto ist die Summe der Zeilen, nicht die Summe gerundeter Nettos', () {
      final s = rechnungSummen(const [
        InvoiceItemInput(description: 'Maniküre', quantity: 1, unitPriceCents: 1479, vatRate: 20),
        InvoiceItemInput(description: 'Lack', quantity: 1, unitPriceCents: 1500, vatRate: 20),
      ], 'gross');
      expect((s.netCents, s.vatCents, s.grossCents), (2483, 496, 2979));
    });
  });

  group('Steuerfall', () {
    test('steuerfrei sind genau die Fälle ohne eigenen Steuerausweis', () {
      expect(
        steuerfreieFaelle.toSet(),
        taxSchemes.where((s) => s != 'normal' && s != 'oss').toSet(),
      );
    });

    test('jeder steuerfreie Fall zählt alles zu 0 %, auch im Brutto-Modus', () {
      for (final fall in steuerfreieFaelle) {
        for (final modus in priceModes) {
          final s = rechnungSummen(
            const [SummenPosition(quantity: 1, unitPriceCents: 1200, vatRate: 20)],
            modus,
            fall,
          );
          expect(s.toJson()['byRate'], [
            {'rate': 0, 'netCents': 1200, 'vatCents': 0, 'grossCents': 1200},
          ], reason: '$fall/$modus');
        }
      }
    });

    test('ohne Angabe gilt normal — die Steuer wird ausgewiesen', () {
      final s = rechnungSummen(const [SummenPosition(quantity: 1, unitPriceCents: 1200, vatRate: 20)], 'gross');
      expect(s.toJson()['byRate'], [
        {'rate': 20, 'netCents': 1000, 'vatCents': 200, 'grossCents': 1200},
      ]);
      // oss ist nicht steuerfrei: der Satz bleibt stehen.
      expect(rechnungSummen(const [SummenPosition(quantity: 1, unitPriceCents: 1200, vatRate: 20)], 'gross', 'oss')
          .byRate
          .single
          .rate, 20);
    });
  });

  group('Eingaben', () {
    test('InvoiceItemInput geht unverändert hinein, Positionsreihenfolge egal, Sätze absteigend', () {
      const a = InvoiceItemInput(description: 'A', quantity: 1, unitPriceCents: 555, vatRate: 10);
      const b = InvoiceItemInput(description: 'B', quantity: 1, unitPriceCents: 1479, vatRate: 20);
      const c = InvoiceItemInput(description: 'C', quantity: 1, unitPriceCents: 1500, vatRate: 20);
      final eins = rechnungSummen(const [a, b, c], 'gross');
      final zwei = rechnungSummen(const [c, a, b], 'gross');
      expect(eins.byRate.map((r) => r.rate).toList(), [20, 10]);
      expect(eins.toJson(), zwei.toJson());
    });

    test('ein unbekannter Modus oder Steuerfall wird abgewiesen statt still gerechnet', () {
      const p = [SummenPosition(quantity: 1, unitPriceCents: 1200, vatRate: 20)];
      expect(() => rechnungSummen(p, 'brutto'), throwsArgumentError);
      expect(() => rechnungSummen(p, 'gross', 'kleinunternehmer'), throwsArgumentError);
    });

    test('eine Zeile ohne endliche Zahl wird abgewiesen', () {
      for (final p in const [
        SummenPosition(quantity: double.nan, unitPriceCents: 100, vatRate: 20),
        SummenPosition(quantity: 1, unitPriceCents: double.infinity, vatRate: 20),
        SummenPosition(quantity: 1, unitPriceCents: 100, vatRate: 20, discountPct: double.negativeInfinity),
      ]) {
        expect(() => rechnungSummen([p], 'net'), throwsArgumentError);
      }
    });

    test('ein negativer Betrag ist das Spiegelbild des positiven, auch beim halben Cent', () {
      // Gerundet wird der Betrag, das Vorzeichen kommt danach: ein halber Cent
      // geht in beide Richtungen vom Nullpunkt weg. Wer ohne Betrag rundet
      // (etwa floor(x + 0,5)), rundet -0,5 Cent zu 0 statt zu -1.
      final falsch = <String>[];
      for (final satz in [10, 13, 20]) {
        for (var c = 1; c <= 2000; c++) {
          for (final (modus, preis) in [('gross', c), ('net', c + 0.5)]) {
            final plus = rechnungSummen([SummenPosition(quantity: 1, unitPriceCents: preis, vatRate: satz)], modus);
            final minus = rechnungSummen([SummenPosition(quantity: -1, unitPriceCents: preis, vatRate: satz)], modus);
            if (minus.netCents != -plus.netCents ||
                minus.vatCents != -plus.vatCents ||
                minus.grossCents != -plus.grossCents) {
              falsch.add('$preis@$satz/$modus');
            }
          }
        }
      }
      expect(falsch, isEmpty);
      final halb = rechnungSummen(const [SummenPosition(quantity: -1, unitPriceCents: 0.5, vatRate: 10)], 'net');
      expect((halb.netCents, halb.vatCents), (-1, 0));
    });

    test('keine Positionen ergeben null', () {
      expect(rechnungSummen(const [], 'net').toJson(), {'netCents': 0, 'vatCents': 0, 'grossCents': 0, 'byRate': []});
    });
  });
}
