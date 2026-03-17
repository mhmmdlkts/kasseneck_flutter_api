enum KeckPaymentMethod {
  cash(false),
  creditCard(true),
  online(false),
  uberApp(false),
  uberCash(false),
  uberCard(true),
  boltApp(false),
  boltCash(false),
  boltCard(true);

  final bool needsCreditCard;

  const KeckPaymentMethod(this.needsCreditCard);
}