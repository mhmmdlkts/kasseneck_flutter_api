/// Summen einer Rechnung vorab rechnen — genau so, wie der Server sie beim
/// Ausstellen rechnet. Zwilling von `src/rechnung/summen.ts` im JS-Paket.
///
/// Für Shops, die kassieren, bevor die Rechnung entsteht, und denselben Betrag
/// brauchen, den die Rechnung später ausweist.
///
/// Die Regel (je USt-Satz, Beträge in Cent, kaufmännisch gerundet):
///
/// | Modus   | Netto                          | USt                        | Brutto              |
/// |---------|--------------------------------|----------------------------|---------------------|
/// | `net`   | round(Σ Zeilen)                | round(Σ Zeilen × Satz/100) | Netto + USt         |
/// | `gross` | round(B × 100 / (100 + Satz))  | B − Netto                  | B = round(Σ Zeilen) |
///
/// Zeile = Einzelpreis × Menge × (1 − Rabatt/100), ungerundet. Im Brutto-Modus
/// ist das Brutto der vereinbarte Preis und bleibt, wie die Zeilen es ergeben.
/// Bei einem Fall aus [steuerfreieFaelle] zählt jede Zeile zu 0 %.
///
/// Die Prüffälle stehen in `fixtures/rechnung-summen.json` des JS-Pakets;
/// Server, JS-Paket und dieses Paket prüfen gegen dieselbe Datei. Verbindlich
/// bleibt, was der Server rechnet — `RechnungApi.previewInvoice` fragt ihn.
library;

import 'modelle.dart';
import 'vertrag.dart';

/// Netto, USt und Brutto einer Rechnung in Cent, je Satz absteigend — dieselbe
/// Form wie `invoice.totals` in den Antworten.
///
/// [taxScheme] ist der Steuerfall der Rechnung, ohne Angabe `normal`. Leitet
/// der Server einen steuerfreien Fall ab (etwa eine ig. Lieferung), gehört
/// dieser Fall hierher — sonst rechnet die Funktion Steuer, die die Rechnung
/// nicht ausweist.
///
/// Wirft [ArgumentError] bei einem [priceMode] außerhalb von [priceModes],
/// einem [taxScheme] außerhalb von [taxSchemes] und bei einer Zeile, die keine
/// endliche Zahl ergibt. Im JS-Paket schließt der Typ die ersten beiden aus;
/// eine stille Rechnung im falschen Modus wäre hier ein falscher Betrag.
InvoiceTotals rechnungSummen(Iterable<SummenPosition> items, String priceMode, [String taxScheme = 'normal']) {
  if (!priceModes.contains(priceMode)) {
    throw ArgumentError.value(priceMode, 'priceMode', 'erwartet: ${priceModes.join(', ')}');
  }
  if (!taxSchemes.contains(taxScheme)) {
    throw ArgumentError.value(taxScheme, 'taxScheme', 'erwartet: ${taxSchemes.join(', ')}');
  }
  final steuerfrei = steuerfreieFaelle.contains(taxScheme);
  final bruttoPreise = priceMode == 'gross' && !steuerfrei;

  // Ungerundete Zeilen je Satz, in Euro wie am Server. Die Reihenfolge der
  // Rechenschritte ist die des JS-Zwillings — nur dann trifft das Gleitkomma
  // Bit fuer Bit dieselbe Zahl, und nur dann rundet ein Grenzfall gleich.
  // num statt int als Schluessel: es gibt Saetze mit Nachkommastelle (4,9 %
  // Grundnahrungsmittel). Zwei Zeilen zu 4,9 % landen im selben Eintrag, weil
  // gleiche Zahlen in Dart gleich hashen -- auch 20 und 20.0.
  final jeSatz = <num, double>{};
  for (final p in items) {
    final satz = steuerfrei ? 0 : p.vatRate;
    // `preisInCent` nimmt den Preis aus dem Feld, das ihn traegt (Cent oder
    // Mikro-Euro). Die Rechenschritte bleiben dieselben wie im JS-Zwilling:
    // nur so trifft das Gleitkomma Bit fuer Bit dieselbe Zahl. Exakt gerundet
    // wird erst mit dem Stichtag (Schalter), im Zwilling ebenso.
    final zeile = (p.preisInCent / 100) * p.quantity * (1 - (p.discountPct ?? 0) / 100);
    if (!zeile.isFinite) {
      throw ArgumentError('Position ergibt keine endliche Zahl (Menge, Preis oder Rabatt)');
    }
    jeSatz[satz] = (jeSatz[satz] ?? 0.0) + zeile;
  }

  final byRate = <VatRateTotal>[];
  for (final MapEntry(key: rate, value: roh) in jeSatz.entries) {
    final int netCents;
    final int vatCents;
    if (bruttoPreise) {
      final grossCents = _euroZuCent(roh);
      netCents = _centRund(grossCents * 100 / (100 + rate));
      vatCents = grossCents - netCents;
    } else {
      netCents = _euroZuCent(roh);
      vatCents = _euroZuCent(roh * rate / 100);
    }
    byRate.add(VatRateTotal(rate: rate, netCents: netCents, vatCents: vatCents, grossCents: netCents + vatCents));
  }
  byRate.sort((a, b) => b.rate.compareTo(a.rate));

  var net = 0;
  var vat = 0;
  var gross = 0;
  for (final r in byRate) {
    net += r.netCents;
    vat += r.vatCents;
    gross += r.grossCents;
  }
  return InvoiceTotals(netCents: net, vatCents: vat, grossCents: gross, byRate: List.unmodifiable(byRate));
}

/// `Number.EPSILON` aus JavaScript, 2^-52.
const double _epsilon = 2.220446049250313e-16;

// Gerundet wird mit roundToDouble, wo JavaScript Math.round nimmt. Die beiden
// unterscheiden sich nur bei einem NEGATIVEN halben Wert (-2,5: Dart -3,
// JavaScript -2) — und der kommt hier nicht vor: _euroRund und _centRund
// runden nur Betraege (|x|), und _euroZuCent rundet ein Vielfaches von 0,01
// mal 100, das hoechstens ein paar Ulp neben einer ganzen Zahl liegt.

/// Auf Cent gerundete Euro — dieselbe Rundung wie am Server (halber Cent vom
/// Nullpunkt weg; das Epsilon faengt 1,005 € ab, das als 1,00499… ankommt).
double _euroRund(double n) => (n < 0 ? -1 : 1) * ((n.abs() + _epsilon) * 100).roundToDouble() / 100;

int _euroZuCent(double euro) => _ganz((_euroRund(euro) * 100).roundToDouble());

/// Ganze Cent kaufmaennisch; ein Gleitkomma-Rest wie x,4999999… zaehlt als
/// halber Cent (erst auf sechs Stellen, dann ganz).
///
/// Fuer ganze Brutto-Cent und die Saetze 10/13/20 faellt das mit
/// `nettoCentsAusBrutto` (lib/src/vat_math.dart) zusammen —
/// test/rechnung_summen_test.dart haelt das fest. Getrennt bleibt es, weil
/// dieser Weg dem Server folgt und jener dem Beleg.
int _centRund(double x) {
  final betrag = (x.abs() * 1e6).roundToDouble() / 1e6;
  return _ganz((x < 0 ? -1 : 1) * betrag.roundToDouble());
}

/// Double -> int, eine negative Null wird zur Null (in JavaScript `|| 0`).
int _ganz(double x) {
  if (!x.isFinite) throw ArgumentError('Summe ist keine endliche Zahl');
  return x.toInt();
}
