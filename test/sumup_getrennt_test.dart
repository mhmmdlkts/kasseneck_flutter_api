// SumUp liegt bei der App: das Paket bindet das `sumup`-Plugin nicht mehr
// ein (seit 11.0.0). Sonst erbte jede App mit diesem Paket das SumUp-SDK und
// dessen Mindest-iOS, auch ohne SumUp. Das Datenmodell bleibt, weil Bon und
// Vorschau den SumUp-Block aus `providerData` zeichnen.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/models/sumup_checkout_response.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('pubspec hängt nicht am sumup-Plugin', () {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    expect((pubspec['dependencies'] as YamlMap).containsKey('sumup'), isFalse);
  });

  test('lib/ importiert package:sumup nirgends', () {
    final funde = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains('package:sumup/'))
        .map((f) => f.path)
        .toList();
    expect(funde, isEmpty);
  });

  test('SumupCheckoutResponse: toJson und fromMap ergeben dasselbe Ergebnis', () {
    final r = SumupCheckoutResponse(
      success: true,
      transactionCode: 'TC9',
      amount: 15.5,
      currency: 'EUR',
      vatAmount: 1.41,
      tipAmount: 0,
      paymentType: 'CARD',
      entryMode: 'CONTACTLESS',
      installments: 1,
      cardType: 'VISA',
      cardLastDigits: '4242',
    );
    final zurueck = SumupCheckoutResponse.fromMap(r.toJson());
    expect(zurueck.toJson(), r.toJson());
  });
}
