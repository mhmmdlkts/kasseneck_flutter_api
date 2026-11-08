import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/register.dart';

/// Trinkgeld gleich behalten in drei Stufen (`business.tipKeptMode`, Backend
/// `tgDirektModus` fragen|immer|nie, 11.22.0): Zwilling von
/// `test/trinkgeld-stufe.test.ts` im npm-Paket. Fehlt die Stufe, gilt `ask`
/// wie bisher; `tipKeptByDefault` bleibt die Vorbelegung des Schalters.
void main() {
  Map<String, dynamic> json(String pfad) => jsonDecode(File('test/fixtures/vertrag/$pfad').readAsStringSync()) as Map<String, dynamic>;
  PosBusinessSettings mit(Map<String, dynamic> b) => PosBusinessSettings.fromJson(b);

  test('Stufen: dieselben wie der Vertrag, optional ohne Standardwert', () {
    final werte = [for (final m in PosTipKeptMode.values) m.value];
    expect(werte, ['ask', 'always', 'never']);
    final pos = (json('surface.json')['pos'] as Map).cast<String, dynamic>();
    expect(werte, pos['tipKeptMode']);
    expect(posBusinessOptionalChoices, pos['posBusinessOptionalChoices']);
    final katalog = (json('v3/v3-vokabular.json')['catalogs'] as Map)['KASSE_BETRIEB_WERTE.tipKeptMode'] as Map;
    expect(werte, katalog.values.toList());
    expect(legacyValues['tipKeptMode'], {for (final e in katalog.entries) e.key as String: e.value as String});
    expect(const PosBusinessSettings().toJson().containsKey('tipKeptMode'), isFalse);
    expect(posBusinessValues['tipKeptMode'], werte);
  });

  test('posTipKeptMode: gespeichert, sonst ask (fehlt, unbekannt, deutscher Altwert)', () {
    expect(posTipKeptMode(const PosBusinessSettings()), PosTipKeptMode.ask);
    expect(posTipKeptMode(null), PosTipKeptMode.ask);
    expect(posTipKeptMode(mit({'tipKeptMode': 'always'})), PosTipKeptMode.always);
    expect(posTipKeptMode(mit({'tipKeptMode': 'never'})), PosTipKeptMode.never);
    final neu = mit({'tipKeptMode': 'sometimes'});
    expect(posTipKeptMode(neu), PosTipKeptMode.ask);
    // Ein unbekannter Wert eines neueren Servers bleibt woertlich erhalten.
    expect(neu.unknownValues['tipKeptMode'], 'sometimes');
    // Ein deutscher Wert der inneren Form kommt gar nicht erst ins Modell.
    final alt = mit({'tipKeptMode': 'immer'});
    expect(alt.tipKeptMode, isNull);
    expect(alt.toJson().containsKey('tipKeptMode'), isFalse);
    expect(mit({'tipKeptMode': 'never'}).toJson()['tipKeptMode'], 'never');
  });

  test('tipKeptFor: eine Regel fuer Web und App', () {
    // ask: Schalter, Vorbelegung tipKeptByDefault, eine Wahl am Schalter gewinnt.
    expect(tipKeptFor(const PosBusinessSettings()), (showSwitch: true, kept: false));
    expect(tipKeptFor(mit({'tipKeptByDefault': true})), (showSwitch: true, kept: true));
    expect(tipKeptFor(mit({'tipKeptByDefault': true, 'tipKeptMode': 'ask'}), false), (showSwitch: true, kept: false));
    expect(tipKeptFor(mit({'tipKeptByDefault': false}), true), (showSwitch: true, kept: true));
    expect(tipKeptFor(mit({'tipKeptByDefault': true}), null), (showSwitch: true, kept: true));
    // always/never: kein Schalter, eine Wahl zaehlt nicht, die Vorbelegung auch nicht.
    for (final wahl in <bool?>[null, true, false]) {
      expect(tipKeptFor(mit({'tipKeptMode': 'always', 'tipKeptByDefault': false}), wahl), (showSwitch: false, kept: true));
      expect(tipKeptFor(mit({'tipKeptMode': 'never', 'tipKeptByDefault': true}), wahl), (showSwitch: false, kept: false));
    }
    // Unbekannte Stufe (neuer Server): wie ask.
    expect(tipKeptFor(mit({'tipKeptMode': 'sometimes', 'tipKeptByDefault': true})), (showSwitch: true, kept: true));
    expect(tipKeptFor(null), (showSwitch: true, kept: false));
  });

  test('merge: tipKeptMode setzen und mit null entfernen, ein Nicht-Text wirft', () {
    final b = const PosBusinessSettings().merge({'tipKeptMode': 'never'});
    expect(b.tipKeptMode, PosTipKeptMode.never);
    expect(b.merge({'tipKeptMode': null}).tipKeptMode, isNull);
    expect(b.merge({'theme': 'night'}).tipKeptMode, PosTipKeptMode.never);
    expect(() => b.merge({'tipKeptMode': 3}), throwsArgumentError);
  });

  test('saveBusiness: tipKeptMode geht nur mit einem Wert des Katalogs hinaus', () async {
    final log = <http.Request>[];
    final mock = MockClient((r) async {
      log.add(r);
      return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'business': {'tipKeptMode': 'never'},
            },
          }),
          200,
          headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'});
    });
    final client = PosSettingsClient(
      RegisterTransport(idToken: () async => 'tok', sessionId: () async => 'sess', cashregisterId: 'KASSE1', httpClient: mock),
      deviceId: 'GERAET1',
    );
    final b = await client.saveBusiness({'tipKeptMode': 'never'});
    expect(posTipKeptMode(b), PosTipKeptMode.never);
    expect(jsonDecode(log.single.body)['params']['business'], {'tipKeptMode': 'never'});
    await expectLater(client.saveBusiness({'tipKeptMode': 'nie'}), throwsA(isA<KasseneckValidationError>()));
    await expectLater(client.saveBusiness({'tipKeptMode': 'sometimes'}), throwsA(isA<KasseneckValidationError>()));
    expect(log, hasLength(1));
  });

  test('Texte: Stufen im Kundenbereich und Hinweise an der Kasse', () {
    expect(labelText('tip_kept_mode.title'), 'Trinkgeld gleich behalten');
    expect([for (final m in PosTipKeptMode.values) labelText(tipKeptModeLabels[m.value]!)], ['Jedes Mal fragen', 'Immer gleich behalten', 'Immer offen lassen']);
    expect(messageText('tip.kept_hint'), 'Trinkgeld kommt als eigene Position auf den Beleg; der angemeldete Benutzer nimmt es gleich bar aus der Lade.');
    expect(messageText('tip.open_hint'), 'Trinkgeld kommt als eigene Position auf den Beleg und bleibt für den angemeldeten Benutzer offen, bis es ausgezahlt wird.');
  });
}
