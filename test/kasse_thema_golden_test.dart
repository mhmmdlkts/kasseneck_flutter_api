import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/pos.dart';

/// Die Token-Werte des Kassenthemas liegen zusätzlich als Golden-Datei vor.
///
/// Nicht als Zierde: die Browser-Kasse soll denselben Entwurf übernehmen, und
/// ohne eine gemeinsame Datei wären es zwei Farbsätze, die man von Hand
/// abgleichen müsste. Genau das ist der Fehler, den wir überall sonst schon
/// beseitigt haben.
///
/// Ändert sich das Thema absichtlich, schreibt `KECK_GOLDEN=schreiben` die
/// Datei neu — und der Unterschied steht dann im Commit, wo man ihn sieht.

Map<String, dynamic> stilWerte(PosThemeData t) => {
      'grund': t.ground.hex,
      'flaeche': t.surface.hex,
      'flaecheHoch': t.surfaceRaised.hex,
      'text': t.text.hex,
      'leise': t.textMuted.hex,
      'rand': t.border.hex,
      'strich': t.divider.hex,
      'gut': t.success.hex,
      'gutHell': t.successSurface.hex,
      'warnung': t.warning.hex,
      'warnungHell': t.warningSurface.hex,
      'fehler': t.danger.hex,
      'fehlerHell': t.dangerSurface.hex,
      'marke': t.brand.hex,
      'markeTief': t.brandPressed.hex,
      'markeHell': t.brandSurface.hex,
      'aufMarke': t.onBrand.hex,
      'radius': t.radius,
      'radiusKachel': t.radiusTile,
      'radiusKlein': t.radiusSmall,
      'linie': t.lineWidth,
      'schattenTiefe': t.shadowDepth,
    };

Map<String, dynamic> jetzigesThema() => {
      'hinweis': 'Erzeugt aus lib/src/kasse/thema.dart, aus den Rollen von kreiseck_design '
          '(Modus je Stil), Betriebsfarbe bewusst nicht. Die Browser-Kasse liest dieselben '
          'Werte, damit App und Browser nicht auseinanderlaufen. Erzeugt gegen kreiseck_design '
          'dfe4a27 (bis zur Veröffentlichung; danach die Version).',
      'schriftfaktoren': {for (final e in fontScales.entries) e.key.value: e.value},
      'kachelhoehen': {for (final e in tileHeights.entries) e.key.value: e.value},
      'kachelhoeheRegel': 'kachelhoehen[hoehe] * schriftfaktoren[schrift] — eine Kachel ist '
          'so hoch, wie Name und Preis sie brauchen. Eine feste Höhe schneidet bei großer '
          'Schrift die Unterlänge des Namens ab.',
      'stile': {
        for (final stil in PosTheme.values)
          stil.value: stilWerte(PosThemeData.fromSettings(PosSettings.fromJson({
            'business': {'theme': stil.value},
          }).business)),
      },
    };

void main() {
  test('die Golden-Datei stimmt mit dem Thema überein', () {
    final datei = File('test/fixtures/kasse/kasse-thema.json');
    final jetzt = jetzigesThema();

    if (Platform.environment['KECK_GOLDEN'] == 'schreiben') {
      datei.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(jetzt)}\n');
    }

    // Fehlt die Golden-Datei, ist der Test rot. Sie hier stillschweigend
    // anzulegen hiesse, das Thema gegen sich selbst zu pruefen: der Test koennte
    // dann nie mehr fehlschlagen, sondern normte jede Aenderung neu ein.
    expect(
      datei.existsSync(),
      isTrue,
      reason: 'Die Golden-Datei ${datei.path} fehlt. Sie wird nicht automatisch '
          'angelegt — neu erzeugen mit: '
          'KECK_GOLDEN=schreiben flutter test test/kasse_thema_golden_test.dart',
    );

    final gespeichert = jsonDecode(datei.readAsStringSync()) as Map<String, dynamic>;
    expect(gespeichert, jetzt);
  });
}
