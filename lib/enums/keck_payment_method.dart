enum KeckPaymentMethod {
  cash(false),
  creditCard(true);

  final bool needsCreditCard;

  const KeckPaymentMethod(this.needsCreditCard);
}