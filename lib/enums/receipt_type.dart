enum ReceiptType {
  start(false, true),
  standard(true, false),
  zero(false, true),
  cancellation(true, false),
  training(true, false);

  final bool needsItems;
  final bool isZero;

  const ReceiptType(this.needsItems, this.isZero);
}