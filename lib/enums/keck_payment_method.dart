enum KeckPaymentMethod {
  cash(false, 'Barzahlung'),
  creditCard(true, 'Kartenzahlung'),
  online(false, 'Onlinezahlung'),
  uberApp(false, 'Uber App'),
  uberCash(false, 'Uber Cash'),
  uberCard(true, 'Uber Card'),
  boltApp(false, 'Bolt App'),
  boltCash(false, 'Bolt Cash'),
  boltCard(true, 'Bolt Card');

  final bool needsCreditCard;

  /// Deutsches Anzeige-Label fuer die Zahlungsart-Zeile auf dem Beleg
  /// (Druck + `KeckReceiptWidget`). Muss 1:1 mit dem Backend-Mapping
  /// `paymentMethodToString` (functions/helper.js) uebereinstimmen.
  final String label;

  const KeckPaymentMethod(this.needsCreditCard, this.label);
}