enum KeckInvoicePaymentMethod {
  bankTransferUnpaid(false),
  bankTransferPaid(true),
  cash(true),
  card(true),
  sepa(true),
  online(true);

  final bool isPaid;

  const KeckInvoicePaymentMethod(this.isPaid);
}