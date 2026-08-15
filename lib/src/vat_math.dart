/// USt-Zerlegung eines Brutto-Betrags in ganzen Cent.
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
