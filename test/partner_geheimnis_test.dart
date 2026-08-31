import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/partner.dart';

/// Die Zusage: ein Geheimnis eines fremden Betriebs verlässt das Objekt NUR
/// über `.reveal()`. Jeder andere Weg — Zeichenkette, Protokoll, JSON,
/// Absturzbericht — zeigt eine Maske.
///
/// Woran diese Tests scheitern: an einem [KasseneckSecret], das eine seiner
/// Ausgabewege-Überschreibungen verliert. Ein weggenommenes `toString` macht
/// „toString und jede Einbettung" und „jeder bekannte Ausgabeweg" rot, ein
/// weggenommenes `toJson` die beiden jsonEncode-Prüfungen.
void main() {
  const klartext = 'kr_live_GEHEIMERKUNDENSCHLUESSEL9d3';
  const token = 'cb_live_GEHEIMESKASSENTOKEN77';

  test('reveal ist der einzige Weg an den Klartext', () {
    final geheim = KasseneckSecret('apiKey', klartext);
    expect(geheim.reveal(), klartext);
    expect(geheim.vorhanden, isTrue);
    expect(KasseneckSecret('apiKey', '').vorhanden, isFalse);
  });

  test('toString und jede Einbettung zeigen die Maske', () {
    final geheim = KasseneckSecret('apiKey', klartext);
    for (final weg in <String>['$geheim', geheim.toString(), 'Zugang: $geheim']) {
      expect(weg, contains(kSecretMaske));
      expect(weg, isNot(contains(klartext)));
      expect(weg, contains('apiKey'),
          reason: 'die Beschriftung fehlt — ein Protokoll sähe nicht, WELCHER Wert fehlt');
    }
  });

  test('jsonEncode gibt den Klartext nicht aus', () {
    final geheim = KasseneckSecret('cashregisterToken', token);
    final text = jsonEncode(<String, dynamic>{
      'a': <String, dynamic>{'b': geheim}
    }, toEncodable: KasseneckSecret.encode);
    expect(text, isNot(contains(token)));
    expect(text, contains(kSecretMaske));
  });

  test('jeder bekannte Ausgabeweg zeigt die Maske', () {
    // Der JS-Zwilling kann zusätzlich beweisen, dass am Objekt gar kein Feld
    // mit dem Klartext hängt (Object.getOwnPropertyNames). In Dart geht das
    // nicht: dart:mirrors steht in Flutter nicht zur Verfügung, und ohne
    // Spiegelung lässt sich „hat kein Feld" nicht behaupten. Was sich prüfen
    // lässt, ist die Wirkung — jeder Weg, auf dem ein Wert in Dart nach
    // aussen gerät. Die Expando bleibt die Vorkehrung dahinter, nicht die
    // hier geprüfte Zusage.
    final geheim = KasseneckSecret('apiKey', klartext);
    final wege = <String>[
      geheim.toString(),
      geheim.toJson(),
      '$geheim',
      <dynamic>[geheim].toString(),
      <String, dynamic>{'access': geheim}.toString(),
      <String, dynamic>{
        'tief': <dynamic>[
          <String, dynamic>{'z': geheim}
        ]
      }.toString(),
      jsonEncode(geheim, toEncodable: KasseneckSecret.encode),
    ];
    for (final weg in wege) {
      expect(weg, isNot(contains(klartext)), reason: 'Klartext auf diesem Weg: $weg');
      expect(weg, contains(kSecretMaske), reason: 'keine Maske auf diesem Weg: $weg');
    }
  });

  test('ein einmal gelesenes Geheimnis maskiert weiter, und zwei teilen sich nichts', () {
    final a = KasseneckSecret('apiKey', klartext);
    final b = KasseneckSecret('cashregisterToken', token);
    expect(a.reveal(), klartext);
    // Nach dem Lesen bleibt die Maske — kein Zwischenspeicher, der sie umgeht.
    expect('$a', isNot(contains(klartext)));
    // Und die Expando ordnet je Instanz zu, nicht je Beschriftung.
    expect(b.reveal(), token);
    expect(a.reveal(), klartext);
  });

  test('die Werte aus getCustomerCredentials sind gehüllt, nicht roh', () {
    final zugang = BetriebZugangsdaten.aus(<String, dynamic>{
      'customerId': 'cust_1',
      'companyName': 'Bäckerei Jobst',
      'env': 'live',
      'apiKey': klartext,
      'cashregisters': <dynamic>[
        <String, dynamic>{
          'cashregisterId': 'kasse_1',
          'name': 'Theke',
          'live': true,
          'cashregisterToken': token,
        }
      ],
      'note': 'Nur verschlüsselt speichern.',
    }, 'cust_1');

    expect(zugang.apiKey, isA<KasseneckSecret>());
    expect(zugang.kassen.single.cashregisterToken, isA<KasseneckSecret>());

    // Der ganze Antwortbaum, so wie ihn ein unachtsames Protokoll ausgeben
    // würde: print(zugang), print(zugang.kassen), jsonEncode(...).
    final ausgabe = '${zugang.toString()} ${zugang.kassen} '
        '${jsonEncode(<String, dynamic>{'k': zugang.kassen.single.cashregisterToken}, toEncodable: KasseneckSecret.encode)}';
    expect(ausgabe, isNot(contains(klartext)), reason: 'der api_key des Betriebs stand in der Ausgabe');
    expect(ausgabe, isNot(contains(token)), reason: 'ein Kassen-Token stand in der Ausgabe');

    // Und der Weg heraus führt trotzdem hin.
    expect(zugang.apiKey.reveal(), klartext);
    expect(zugang.kassen.single.cashregisterToken.reveal(), token);
  });

  test('eine fehlende Angabe wird ein leeres Geheimnis, kein null', () {
    // Ein `null` wäre hier das schlimmste Ergebnis: der Aufrufer hätte einen
    // Typ, der Geheimnis sagt, und einen Wert, den er mit `?? ''` überbrückt —
    // und hielte dann wieder eine rohe Zeichenkette in der Hand.
    final zugang = BetriebZugangsdaten.aus(<String, dynamic>{
      'customerId': 'cust_1',
      'cashregisters': <dynamic>[<String, dynamic>{}],
    }, 'cust_1');
    expect(zugang.apiKey, isA<KasseneckSecret>());
    expect(zugang.apiKey.vorhanden, isFalse);
    expect(zugang.apiKey.reveal(), '');
    expect(zugang.kassen.single.cashregisterToken.vorhanden, isFalse);
  });
}
