enum PaymentMethod {
  cash(false),
  creditCard(true);

  final bool needsCreditCard;

  const PaymentMethod(this.needsCreditCard);
}