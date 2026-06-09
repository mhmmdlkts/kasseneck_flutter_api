enum VatRate {
  vat0(0, 'D'),
  vat4komma9(4.9, 'G'),   // Grundnahrungsmittel ab 01.07.2026 -> Betrag-Satz-Besonders (BMF/RKSV)
  vat10(10, 'B'),
  vat13(13, 'C'),
  vat19(19, 'E'),
  vat20(20, 'A');

  final num rate;
  final String category;

  const VatRate(this.rate, this.category);
}