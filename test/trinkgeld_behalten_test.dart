import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/register.dart';

/// Bar-Trinkgeld „gleich behalten“ (Backend: Schichten-Spec, Nachtrag 4):
/// Zwilling von `test/trinkgeld-behalten.test.ts` im npm-Paket. Am Draht
/// `tip.keptByEmployee` (nur `true`) und `items[].keptByEmployee`; die
/// Einstellung `business.tipKeptByDefault` ist optional wie `device.drawerId`.
void main() {
  test('KeckTip: keptByEmployee geht nur als true hinaus', () {
    expect(const KeckTip(cents: 200, keptByEmployee: true).toJson(), {'cents': 200, 'keptByEmployee': true});
    expect(const KeckTip(cents: 200).toJson(), {'cents': 200});
  });

  test('Trinkgeld-Position: keptByEmployee wird gelesen, geschrieben und beim Storno gespiegelt', () {
    final p = KasseneckItem.fromJson({
      'kind': 'tip', 'name': 'Trinkgeld Personal', 'quantity': 1, 'unitPriceCents': 200, 'vatRate': 0,
      'paymentMethod': 'cash', 'recipient': {'registerUserId': 'ru1', 'name': 'Livia Lindmayr'},
      'receivedImmediately': true, 'keptByEmployee': true,
    });
    expect(p.keptByEmployee, isTrue);
    expect(p.toJson()['keptByEmployee'], isTrue);
    expect(p.negative.keptByEmployee, isTrue);
    final ohne = KasseneckItem.fromJson({'kind': 'tip', 'name': 'Trinkgeld Personal', 'quantity': 1, 'unitPriceCents': 200, 'vatRate': 0});
    expect(ohne.keptByEmployee, isFalse);
    expect(ohne.toJson().containsKey('keptByEmployee'), isFalse);
    // Eine Warenzeile traegt das Merkmal nie.
    expect(KasseneckItem.fromJson({'name': 'Kaffee', 'quantity': 1, 'unitPriceCents': 200, 'vatRate': 20, 'keptByEmployee': true}).keptByEmployee, isFalse);
  });

  test('Einstellung tipKeptByDefault: optional, Standard aus, nur ein Wahrheitswert', () {
    expect(posBusinessOptionalFields, ['tipKeptByDefault']);
    const standard = PosBusinessSettings();
    expect(standard.toJson().containsKey('tipKeptByDefault'), isFalse);
    expect(posTipKeptByDefault(standard), isFalse);
    expect(posTipKeptByDefault(null), isFalse);
    final an = PosBusinessSettings.fromJson({'tipKeptByDefault': true});
    expect(an.tipKeptByDefault, isTrue);
    expect(posTipKeptByDefault(an), isTrue);
    expect(an.toJson()['tipKeptByDefault'], isTrue);
    expect(PosBusinessSettings.fromJson({'tipKeptByDefault': 'ja'}).tipKeptByDefault, isNull);
    expect(standard.merge({'tipKeptByDefault': true}).tipKeptByDefault, isTrue);
    expect(an.merge({'clock': false}).tipKeptByDefault, isTrue, reason: 'bleibt beim Mischen');
    expect(() => standard.merge({'tipKeptByDefault': 'ja'}), throwsArgumentError);
  });

  test('saveBusiness: tipKeptByDefault geht als Wahrheitswert hinaus, alles andere wirft vor dem Senden', () async {
    final log = <http.Request>[];
    final mock = MockClient((r) async {
      log.add(r);
      return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'business': {'tipKeptByDefault': true},
            },
          }),
          200,
          headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'});
    });
    final client = PosSettingsClient(
      RegisterTransport(idToken: () async => 'tok', sessionId: () async => 'sess', cashregisterId: 'KASSE1', httpClient: mock),
      deviceId: 'GERAET1',
    );
    final b = await client.saveBusiness({'tipKeptByDefault': true});
    expect(b.tipKeptByDefault, isTrue);
    expect(jsonDecode(log.single.body)['params']['business'], {'tipKeptByDefault': true});
    await expectLater(client.saveBusiness({'tipKeptByDefault': 'ja'}), throwsA(isA<KasseneckValidationError>()));
    expect(log, hasLength(1));
  });

  test('Texte: Schalter und Einstellung (Beschriftung + Hinweis)', () {
    expect(labelText('checkout.tip_kept'), 'gleich behalten');
    expect(labelText('tip.kept_setting'), 'Bar-Trinkgeld behält der Mitarbeiter gleich');
    expect(messageText('tip.kept_setting_hint'), contains('zählt nicht ins Soll der Lade'));
  });
}
