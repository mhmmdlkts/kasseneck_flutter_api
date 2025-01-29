enum ReceiptType {
  start(false),
  standard(true),
  zero(false),
  cancellation(true),
  training(true);

  final bool needsItems;

  const ReceiptType(this.needsItems);
}