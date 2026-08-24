import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/src/aufrufe.dart';

void main() {
  test('Aufrufe.alle trägt jede Konstante genau einmal', () {
    expect(Aufrufe.alle, contains(Aufrufe.createReceipt));
    expect(Aufrufe.alle, contains(Aufrufe.listRegisterUsersForDevice));
    expect(Aufrufe.alle.length, greaterThanOrEqualTo(12));
  });
}
