enum ReceiptType {
  start(
      needsItems: false, isZero: true, allowsVouchers: false, allowsTip: false),
  standard(
      needsItems: true, isZero: false, allowsVouchers: true, allowsTip: true),
  zero(
      needsItems: false, isZero: true, allowsVouchers: false, allowsTip: false),
  cancellation(
      needsItems: true, isZero: false, allowsVouchers: true, allowsTip: false),
  training(
      needsItems: true, isZero: false, allowsVouchers: true, allowsTip: true);

  final bool needsItems;
  final bool isZero;
  final bool allowsVouchers;

  /// Darf dieser Beleg Trinkgeld tragen?
  ///
  /// Nur Standard- und Trainingsbelege. Ein Storno traegt Trinkgeld nur als
  /// Spiegelung der Positionen des Originals — nie ueber den Parameter, sonst
  /// entstuende beim Zuruecknehmen neues Trinkgeld.
  final bool allowsTip;

  const ReceiptType({
    required this.needsItems,
    required this.isZero,
    required this.allowsVouchers,
    required this.allowsTip,
  });
}
