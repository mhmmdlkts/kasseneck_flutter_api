import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/kasse.dart';

/// Die Token-Werte des Kassenthemas liegen zusätzlich als Golden-Datei vor.
///
/// Nicht als Zierde: die Browser-Kasse soll denselben Entwurf übernehmen, und
/// ohne eine gemeinsame Datei wären es zwei Farbsätze, die man von Hand
/// abgleichen müsste. Genau das ist der Fehler, den wir überall sonst schon
/// beseitigt haben.
///
/// Ändert sich das Thema absichtlich, schreibt `KECK_GOLDEN=schreiben` die
/// Datei neu — und der Unterschied steht dann im Commit, wo man ihn sieht.

Map<String, dynamic> stilWerte(Kassenthema t) => {
      'grund': t.grund.hex,
      'flaeche': t.flaeche.hex,
      'flaecheHoch': t.flaecheHoch.hex,
      'text': t.text.hex,
      'leise': t.leise.hex,
      'rand': t.rand.hex,
      'strich': t.strich.hex,
      'gut': t.farben.gut.hex,
      'gutHell': t.farben.gutHell.hex,
      'warnung': t.farben.warnung.hex,
      'warnungHell': t.farben.warnungHell.hex,
      'fehler': t.farben.fehler.hex,
      'fehlerHell': t.farben.fehlerHell.hex,
      'marke': t.marke.hex,
      'markeTief': t.markeTief.hex,
      'markeHell': t.markeHell.hex,
      'aufMarke': t.aufMarke.hex,
      'radius': t.radius,
      'radiusKachel': t.radiusKachel,
      'radiusKlein': t.radiusKlein,
      'linie': t.linie,
      'schattenTiefe': t.schattenTiefe,
    };

Map<String, dynamic> jetzigesThema() => {
      'hinweis': 'Erzeugt aus lib/src/kasse/thema.dart mit der Vorgabe-Betriebsfarbe. '
          'Die Browser-Kasse liest dieselben Werte, damit App und Browser nicht auseinanderlaufen.',
      'schriftfaktoren': {for (final e in schriftfaktoren.entries) e.key.wert: e.value},
      'kachelhoehen': {for (final e in kachelhoehen.entries) e.key.wert: e.value},
      'stile': {
        for (final stil in KasseStil.values)
          stil.name: stilWerte(Kassenthema.aus(KasseSettings.aus({
            'betrieb': {'stil': stil.name},
          }).betrieb)),
      },
    };

void main() {
  test('die Golden-Datei stimmt mit dem Thema überein', () {
    final datei = File('test/fixtures/kasse/kasse-thema.json');
    final jetzt = jetzigesThema();

    if (Platform.environment['KECK_GOLDEN'] == 'schreiben' || !datei.existsSync()) {
      datei.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(jetzt)}\n');
    }

    final gespeichert = jsonDecode(datei.readAsStringSync()) as Map<String, dynamic>;
    expect(gespeichert, jetzt);
  });
}
