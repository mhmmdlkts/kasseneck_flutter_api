import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';

/// Deutsche Labels muessen 1:1 mit dem Backend-Mapping (functions/helper.js,
/// paymentMethodToString) uebereinstimmen -- sonst zeigt Beleg-PDF und
/// Kassen-Beleg unterschiedliche Zahlungsart-Texte fuer denselben Wert.
void main() {
  test('label je Zahlungsart entspricht dem Backend-Mapping', () {
    expect(KeckPaymentMethod.cash.label, 'Barzahlung');
    expect(KeckPaymentMethod.creditCard.label, 'Kartenzahlung');
    expect(KeckPaymentMethod.online.label, 'Onlinezahlung');
    expect(KeckPaymentMethod.uberApp.label, 'Uber App');
    expect(KeckPaymentMethod.uberCash.label, 'Uber Cash');
    expect(KeckPaymentMethod.uberCard.label, 'Uber Card');
    expect(KeckPaymentMethod.boltApp.label, 'Bolt App');
    expect(KeckPaymentMethod.boltCash.label, 'Bolt Cash');
    expect(KeckPaymentMethod.boltCard.label, 'Bolt Card');
  });
}
