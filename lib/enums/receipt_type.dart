enum ReceiptType {
  start(false, true, false),
  standard(true, false, true),
  zero(false, true, false),
  cancellation(true, false, true),
  training(true, false, true);

  final bool needsItems;
  final bool isZero;
  final bool allowsVouchers;

  const ReceiptType(this.needsItems, this.isZero, this.allowsVouchers);
}