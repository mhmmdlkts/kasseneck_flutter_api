enum VatRate {
  vat0(0, 'D'),
  vat10(10, 'B'),
  vat13(13, 'C'),
  vat19(19, 'E'),
  vat20(20, 'A');

  final int rate;
  final String category;

  const VatRate(this.rate, this.category);
}