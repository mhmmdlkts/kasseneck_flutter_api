/// USt-Zerlegung eines Brutto-Betrags in ganzen Cent.
///
/// **Die einzige Stelle im Paket, an der aus Brutto Netto und MwSt wird** —
/// Beleg-Widget, Beleg-Druck und Kassieren-Schirm rechnen alle hierueber.
/// Vorher gab es drei Rechenwege fuer dieselbe Zahl, und fuer 0,99 EUR zu
/// 20 % lieferten sie 0,16 / 0,17 / 0,17 EUR MwSt — je nachdem, wer fragte.
library;

/// Netto aus Brutto, in ganzen Cent.
///
/// Dieselbe Regel wie im JS-Zwilling (`receipt/layout.ts`, `nettoAusBrutto`)
/// und in der Browser-Kasse: **einmal** runden, die MwSt ist die Differenz.
/// Wer Netto und MwSt getrennt aus Gleitkommazahlen rundet, verliert bei
/// jedem sechsten Cent-Betrag zu 20 % einen Cent — 99 Cent zeigten
/// „0,82 / 0,17" statt „0,83 / 0,16", und Netto + MwSt ergab nicht Brutto.
/// Der Betrag wird ueber den Absolutwert gerechnet, damit ein Storno
/// spiegelbildlich zu seinem Beleg zerfaellt.
int nettoCentsAusBrutto(int bruttoCents, num rate) {
  final int betrag = ((bruttoCents.abs() * 100) / (100 + rate)).round();
  return bruttoCents < 0 ? -betrag : betrag;
}

/// Enthaltene MwSt aus Brutto, in ganzen Cent — die Differenz zum Netto.
///
/// Ausdruecklich **nicht** `(brutto * satz / (100 + satz)).round()`: das waere
/// eine zweite, eigene Rundung derselben Groesse. Bei 20 % faellt sie fuer
/// jedes Brutto ≡ 3 (mod 6) um einen Cent anders aus (99 Cent: 17 statt 16) —
/// ueber 1…10000 Cent gemessen 1667 abweichende Betraege. Bei 19/13/10/4,9 %
/// trifft der exakte Quotient die 0,5-Grenze nie, dort fallen die beiden
/// Regeln nicht auseinander; genau deshalb faellt der Fehler so selten auf.
int ustCentsAusBrutto(int bruttoCents, num rate) =>
    bruttoCents - nettoCentsAusBrutto(bruttoCents, rate);
