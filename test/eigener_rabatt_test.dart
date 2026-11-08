import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/register.dart';

/// Eigener Rabatt an der Kasse (`business.customDiscountAllowed`, gespeichert
/// `rabattFrei`): Zwilling von `test/eigener-rabatt.test.ts` im npm-Paket.
/// `true` = neben den Rabatt-Chips das freie Feld (Betrag oder Prozent),
/// `false` = nur die Chips. Optional wie `tipKeptByDefault`; fehlt es, gilt
/// `true`.
void main() {
  PosSettingsClient clientMit(List<http.Request> log, Map<String, Object?> business) {
    final mock = MockClient((r) async {
      log.add(r);
      return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {'business': business},
          }),
          200,
          headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'});
    });
    return PosSettingsClient(
      RegisterTransport(idToken: () async => 'tok', sessionId: () async => 'sess', cashregisterId: 'KASSE1', httpClient: mock),
      deviceId: 'GERAET1',
    );
  }

  test('customDiscountAllowed: optional, nicht im Standard, fehlt = erlaubt', () {
    expect(posBusinessOptionalFields, contains('customDiscountAllowed'));
    const standard = PosBusinessSettings();
    expect(standard.customDiscountAllowed, isNull);
    expect(standard.toJson().containsKey('customDiscountAllowed'), isFalse);
    expect(posCustomDiscountAllowed(standard), isTrue);
    expect(posCustomDiscountAllowed(null), isTrue);
    expect(posCustomDiscountAllowed(const PosBusinessSettings(customDiscountAllowed: true)), isTrue);
    expect(posCustomDiscountAllowed(const PosBusinessSettings(customDiscountAllowed: false)), isFalse);
  });

  test('fromJson/toJson: nur ein Wahrheitswert wird gelesen, gesendet nur, wenn gesetzt', () {
    final aus = PosBusinessSettings.fromJson({'customDiscountAllowed': false});
    expect(aus.customDiscountAllowed, isFalse);
    expect(posCustomDiscountAllowed(aus), isFalse);
    expect(aus.toJson()['customDiscountAllowed'], isFalse);
    expect(PosBusinessSettings.fromJson({'customDiscountAllowed': true}).toJson()['customDiscountAllowed'], isTrue);
    for (final kaputt in ['nein', 0, 1, null]) {
      final b = PosBusinessSettings.fromJson({'customDiscountAllowed': kaputt});
      expect(b.customDiscountAllowed, isNull, reason: '$kaputt');
      expect(b.toJson().containsKey('customDiscountAllowed'), isFalse, reason: '$kaputt');
      expect(b.unknownValues.containsKey('customDiscountAllowed'), isFalse, reason: '$kaputt');
      expect(posCustomDiscountAllowed(b), isTrue, reason: '$kaputt');
    }
    // Ohne Feld bleibt die Drahtform wie bisher.
    expect(PosBusinessSettings.fromJson(const {}).toJson(), const PosBusinessSettings().toJson());
  });

  test('merge: setzen, behalten, mit null entfernen; kein Wahrheitswert wirft', () {
    const standard = PosBusinessSettings();
    final aus = standard.merge({'customDiscountAllowed': false});
    expect(aus.customDiscountAllowed, isFalse);
    expect(aus.merge({'clock': false}).customDiscountAllowed, isFalse, reason: 'bleibt beim Mischen');
    expect(aus.merge({'tipKeptByDefault': true}).customDiscountAllowed, isFalse, reason: 'der andere Schalter laesst ihn stehen');
    expect(aus.merge({'customDiscountAllowed': null}).customDiscountAllowed, isNull);
    expect(() => standard.merge({'customDiscountAllowed': 'nein'}), throwsArgumentError);
  });

  test('saveBusiness: customDiscountAllowed geht als Wahrheitswert hinaus, alles andere wirft vor dem Senden', () async {
    final log = <http.Request>[];
    final client = clientMit(log, {'customDiscountAllowed': false});
    final b = await client.saveBusiness({'customDiscountAllowed': false});
    expect(b.customDiscountAllowed, isFalse);
    expect(posCustomDiscountAllowed(b), isFalse);
    expect(jsonDecode(log.single.body)['params']['business'], {'customDiscountAllowed': false});
    await expectLater(client.saveBusiness({'customDiscountAllowed': 'nein'}), throwsA(isA<KasseneckValidationError>()));
    expect(log, hasLength(1));
  });

  test('saveBusiness: beide Schalter zusammen und neben einer Einstellung mit Standard', () async {
    final log = <http.Request>[];
    final client = clientMit(log, {'customDiscountAllowed': false, 'tipKeptByDefault': true, 'clock': false});
    await client.saveBusiness({'customDiscountAllowed': false, 'tipKeptByDefault': true});
    expect(jsonDecode(log.last.body)['params']['business'], {'customDiscountAllowed': false, 'tipKeptByDefault': true});
    await client.saveBusiness({'clock': false, 'customDiscountAllowed': true});
    expect(jsonDecode(log.last.body)['params']['business'], {'clock': false, 'customDiscountAllowed': true});
  });
}
