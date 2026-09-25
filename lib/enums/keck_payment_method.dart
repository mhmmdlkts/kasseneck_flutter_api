enum KeckPaymentMethod {
  cash(false, 'Barzahlung'),
  creditCard(true, 'Kartenzahlung'),
  online(false, 'Onlinezahlung'),
  uberApp(false, 'Uber App'),
  uberCash(false, 'Uber Cash'),
  uberCard(true, 'Uber Card'),
  boltApp(false, 'Bolt App'),
  boltCash(false, 'Bolt Cash'),
  boltCard(true, 'Bolt Card'),

  /// Vergibt nur der Server: ein Beleg mit mehreren Zahlungen verschiedener
  /// Zahlart (`payments`) traegt ihn als Einzelfeld `paymentMethod` (zwei
  /// Karten ergeben `creditCard`). Lesen ja, senden nie -- wer mehrere
  /// Zahlarten kassiert, schickt die Zahlungsliste.
  mixed(false, 'Mehrere Zahlungsarten');

  final bool needsCreditCard;

  /// Deutsches Anzeige-Label fuer die Zahlungsart-Zeile auf dem Beleg
  /// (Druck + `KeckReceiptWidget`). Muss 1:1 mit dem Backend-Mapping
  /// `paymentMethodToString` (functions/helper.js) uebereinstimmen.
  final String label;

  const KeckPaymentMethod(this.needsCreditCard, this.label);
}