import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/src/aufrufe.dart';

void main() {
  // Die Vollstaendigkeit von Aufrufe.alle haelt seit der Zwillingspruefung
  // test/zwillinge_test.dart (Vergleich gegen den Vertrag des JS-Pakets).
  // Hier bleibt nur, was dieser Test wirklich zeigt: die Menge ist gefuellt und
  // enthaelt Stichproben aus beiden Aufrufwegen.
  test('Aufrufe.alle ist gefüllt und enthält die Stichproben', () {
    expect(Aufrufe.alle, contains(Aufrufe.createReceipt));
    expect(Aufrufe.alle, contains(Aufrufe.listRegisterUsersForDevice));
    expect(Aufrufe.alle.length, greaterThanOrEqualTo(12));
  });
}
