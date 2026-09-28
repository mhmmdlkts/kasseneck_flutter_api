import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kreiseck_design/kreiseck_design.dart';

/// Das Kassenthema: vier Stile, eine Betriebsfarbe, vier Schriftgrößen.
///
/// Die Stile sind keine Geschmacksfrage, sondern vier Orte: helle Theke,
/// Bäckerei bei Sonne, Bar am Abend, und ein Stil für grelles Licht oder
/// schwache Augen. Was sie unterscheidet, ist deshalb mehr als Farbe.

PosBusinessSettings betriebMit(Map<String, dynamic> g) => PosSettings.fromJson({'business': g}).business;

PosThemeData themaMit(Map<String, dynamic> g) => PosThemeData.fromSettings(betriebMit(g));

/// Ein Betrieb mit Standardwerten, nur der Stil gesetzt.
PosBusinessSettings betrieb(PosTheme stil) => betriebMit({'theme': stil.value});

/// `Farbe.ausHex` mit einem Ersatzwert, der in diesen Tests nie greifen soll
/// — jeder hier verwendete Hex-Code ist gültig. `ersatz` ist seit 6.0.0
/// Pflicht (kein stillschweigendes Panel-Blau mehr).
PosColor hex(String h) => PosColor.fromHex(h, fallback: const PosColor(0xFF, 0x00, 0xFF));

void main() {
  group('Design-System', () {
    test('jeder Stil bildet auf einen Modus des Design-Systems ab', () {
      expect(PosThemeData.fromSettings(betrieb(PosTheme.clear)).mode, KdMode.light);
      expect(PosThemeData.fromSettings(betrieb(PosTheme.warm)).mode, KdMode.warm);
      expect(PosThemeData.fromSettings(betrieb(PosTheme.night)).mode, KdMode.dark);
      expect(PosThemeData.fromSettings(betrieb(PosTheme.contrast)).mode, KdMode.contrast);
    });

    test('die Farben sind die Rollen des Design-Systems, keine eigenen Tabellen', () {
      // Gegen die Rollen geprueft, nicht gegen abgeschriebene Hex-Werte: eine
      // Tabelle hier waere genau das, was dieser Test ausschliessen soll, und
      // sie veraltet beim naechsten Zug am Design-System.
      String rolle(KdMode modus, String name) =>
          '#${kdColor(modus, name).toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

      final t = PosThemeData.fromSettings(betrieb(PosTheme.night));
      expect(t.ground.hex.toUpperCase(), rolle(KdMode.dark, 'ground'));
      expect(t.brand.hex.toUpperCase(), rolle(KdMode.dark, 'brand'));
      expect(t.onBrand.hex.toUpperCase(), rolle(KdMode.dark, 'on-brand'));
      final k = PosThemeData.fromSettings(betrieb(PosTheme.clear));
      expect(k.text.hex.toUpperCase(), rolle(KdMode.light, 'ink'));
    });

    test('der Kontrast-Stil schärft Ränder, nicht Radien', () {
      final t = PosThemeData.fromSettings(betrieb(PosTheme.contrast));
      expect(t.lineWidth, 2);
      expect(t.radiusSmall, 10);
      expect(t.radius, 14);
      expect(t.shadowDepth, 0);
    });

    test('hell folgt den Farben, nicht der Aufzählung', () {
      for (final stil in PosTheme.values) {
        final t = themaMit({'theme': stil.value});
        expect(t.isLight, t.text.luminance < t.ground.luminance, reason: stil.name);
      }
    });
  });

  group('Stile', () {
    test('klar ist die Vorgabe: heller Grund, dunkler Text', () {
      final t = themaMit({});
      expect(t.theme, PosTheme.clear);
      expect(t.isLight, isTrue);
      expect(t.ground.luminance, greaterThan(0.8));
      expect(t.text.luminance, lessThan(0.2));
    });

    test('nacht dreht es um — dunkler Grund, heller Text', () {
      // Für Taxi und Bar. Reines Schwarz wäre falsch: es flimmert auf OLED
      // beim Blättern und lässt jeden Rand hart wirken.
      final t = themaMit({'theme': 'night'});
      expect(t.isLight, isFalse);
      expect(t.ground.luminance, lessThan(0.15));
      expect(t.ground, isNot(hex('#000000')));
      expect(t.text.luminance, greaterThan(0.8));
    });

    test('warm ist heller Grund mit warmem Ton', () {
      final klar = themaMit({});
      final warm = themaMit({'theme': 'warm'});
      expect(warm.isLight, isTrue);
      // Mehr Rot als Blau — das unterscheidet cremiges Papier von kühlem Grau.
      expect(warm.ground.r - warm.ground.b, greaterThan(klar.ground.r - klar.ground.b));
    });

    test('kontrast schärft Linien und nimmt Schatten, lässt Radien in Ruhe', () {
      // Er ist ein Stil für schwache Augen, kein Farbschema: dickere Linien,
      // keine Schatten. Radien bleiben unverändert — das unterscheidet ihn
      // von einem reinen Farbtausch, ohne die Kasse in der Form zu verstellen.
      final klar = themaMit({});
      final k = themaMit({'theme': 'contrast'});

      expect(k.text, hex('#000000'));
      expect(k.ground, hex('#FFFFFF'));
      expect(k.surface, hex('#FFFFFF'));
      expect(k.lineWidth, greaterThan(klar.lineWidth));
      expect(k.radius, klar.radius);
      expect(k.radiusSmall, klar.radiusSmall);
      expect(k.shadowDepth, 0.0);
    });

    test('jeder Stil trägt seinen Text lesbar auf seinem Grund', () {
      // Die Zusage, die alles andere trägt. 4,5:1 ist die Schwelle für
      // Fließtext (WCAG AA).
      for (final stil in PosTheme.values) {
        final t = themaMit({'theme': stil.value});
        expect(contrastRatio(t.text, t.ground), greaterThanOrEqualTo(4.5), reason: '${stil.name}: Text auf Grund');
        expect(contrastRatio(t.text, t.surface), greaterThanOrEqualTo(4.5), reason: '${stil.name}: Text auf Flaeche');
        // Nebentext darf leiser sein, aber nicht unlesbar.
        expect(contrastRatio(t.textMuted, t.surface), greaterThanOrEqualTo(4.5), reason: '${stil.name}: Nebentext');
      }
    });
  });

  group('Kontrastzusage', () {
    // Die eingeschränkte Zusage aus der Klassendoku, wörtlich als Test: die
    // Bedeutungsfarben und die Marke stehen laut Design-System nicht auf
    // flaecheHoch (Kopfzeile, aktives Feld) — dort steht text/leise.
    test('text und leise halten 4,5:1 auf grund, flaeche und flaecheHoch', () {
      for (final stil in PosTheme.values) {
        final t = themaMit({'theme': stil.value});
        for (final MapEntry(key: name, value: flaeche) in {'grund': t.ground, 'flaeche': t.surface, 'flaecheHoch': t.surfaceRaised}.entries) {
          expect(contrastRatio(t.text, flaeche), greaterThanOrEqualTo(4.5), reason: '${stil.name}: text auf $name');
          expect(contrastRatio(t.textMuted, flaeche), greaterThanOrEqualTo(4.5), reason: '${stil.name}: leise auf $name');
        }
      }
    });

    test('Bedeutungsfarben und Marke halten 4,5:1 auf grund und flaeche', () {
      for (final stil in PosTheme.values) {
        final t = themaMit({'theme': stil.value});
        for (final MapEntry(key: name, value: flaeche) in {'grund': t.ground, 'flaeche': t.surface}.entries) {
          expect(contrastRatio(t.success, flaeche), greaterThanOrEqualTo(4.5), reason: '${stil.name}: gut auf $name');
          expect(contrastRatio(t.warning, flaeche), greaterThanOrEqualTo(4.5), reason: '${stil.name}: warnung auf $name');
          expect(contrastRatio(t.danger, flaeche), greaterThanOrEqualTo(4.5), reason: '${stil.name}: fehler auf $name');
          expect(contrastRatio(t.brand, flaeche), greaterThanOrEqualTo(4.5), reason: '${stil.name}: marke auf $name');
        }
      }
    });
  });

  group('Radien', () {
    test('kleine Bedienelemente sind leicht gerundet, nie vollrund', () {
      // Eine Pille sieht nach Etikett aus; die Auswahl an einer Kasse ist ein
      // Schalter. Die Grenze: deutlich weniger als die halbe Hoehe eines
      // Chips (rund 32 dp) waere vollrund.
      for (final stil in PosTheme.values) {
        final t = themaMit({'theme': stil.value});
        expect(t.radiusSmall, greaterThan(0), reason: '${stil.name}: gar keine Rundung waere hart');
        expect(t.radiusSmall, lessThan(12), reason: '${stil.name}: zu rund');
        expect(t.radiusSmall, lessThanOrEqualTo(t.radiusTile));
      }
    });
  });

  group('Betriebsfarbe', () {
    test('färbt die Kasse nicht mehr — auch keine kaputte Angabe', () {
      // Sie bleibt im Datenmodell (Panel und Rechnungs-PDF lesen sie), aber
      // die Knöpfe der Kasse gehören zum Produkt. Damit kann auch ein
      // Tippfehler aus dem Panel hier nichts mehr anrichten.
      final vorgabe = themaMit({}).brand;
      for (final wert in ['#1B46F5', '#FFE066', '', 'blau', '#12345']) {
        expect(themaMit({'color': wert}).brand, vorgabe, reason: wert);
      }
    });

    test('auf der Marke steht immer lesbarer Text', () {
      for (final stil in PosTheme.values) {
        final t = themaMit({'theme': stil.value});
        expect(contrastRatio(t.onBrand, t.brand), greaterThanOrEqualTo(4.5), reason: stil.name);
      }
    });
  });

  group('Schriftgröße', () {
    test('M ist die Vorgabe und der Bezugspunkt', () {
      expect(themaMit({}).fontScale, 1.0);
    });

    test('S ist kleiner, L und XL größer — in dieser Reihenfolge', () {
      final faktoren = [
        for (final s in ['S', 'M', 'L', 'XL']) themaMit({'fontSize': s}).fontScale,
      ];
      expect(faktoren, orderedEquals([...faktoren]..sort()));
      expect(faktoren.first, lessThan(1.0));
      expect(faktoren.last, greaterThan(1.2));
    });

    test('auch XL bleibt bedienbar — kein Faktor, der die Kasse sprengt', () {
      expect(themaMit({'fontSize': 'XL'}).fontScale, lessThanOrEqualTo(1.5));
    });
  });

  group('Kachelhöhe', () {
    test('flach, normal, hoch — in dieser Reihenfolge', () {
      final hoehen = [
        for (final h in ['S', 'M', 'L']) PosThemeData.fromSettings(betriebMit({}), device: PosSettings.fromJson({'device': {'tileHeight': h}}).device).tileHeight,
      ];
      expect(hoehen, orderedEquals([...hoehen]..sort()));
    });

    test('auch die flachste Kachel bleibt ein Fingerziel', () {
      // 48 dp ist die Untergrenze, unter der ein Finger nicht mehr trifft.
      final flach = PosThemeData.fromSettings(betriebMit({}), device: PosSettings.fromJson({'device': {'tileHeight': 'S'}}).device);
      expect(flach.tileHeight, greaterThanOrEqualTo(48));
    });
  });

  group('Farbe', () {
    test('liest #RRGGBB', () {
      final f = hex('#1B46F5');
      expect(f.r, 0x1B);
      expect(f.g, 0x46);
      expect(f.b, 0xF5);
    });

    test('mischt zwei Farben', () {
      expect(hex('#000000').mixedWith(hex('#FFFFFF'), 0.5).r, 128);
      expect(hex('#000000').mixedWith(hex('#FFFFFF'), 0), hex('#000000'));
      expect(hex('#000000').mixedWith(hex('#FFFFFF'), 1), hex('#FFFFFF'));
    });

    test('Kontrast: Schwarz auf Weiß ist der Höchstwert 21', () {
      expect(contrastRatio(hex('#000000'), hex('#FFFFFF')), closeTo(21, 0.1));
      expect(contrastRatio(hex('#FFFFFF'), hex('#FFFFFF')), closeTo(1, 0.01));
    });

    test('als Hex zurück', () {
      expect(hex('#1b46f5').hex, '#1B46F5');
    });
  });

  group('freie Farbwahl', () {
    test('HSV ergibt die erwarteten Ecken', () {
      expect(colorFromHsv(0, 1, 1), hex('#FF0000'));
      expect(colorFromHsv(120, 1, 1), hex('#00FF00'));
      expect(colorFromHsv(240, 1, 1), hex('#0000FF'));
      expect(colorFromHsv(0, 0, 1), hex('#FFFFFF'));
      expect(colorFromHsv(0, 0, 0), hex('#000000'));
    });

    test('der Farbton läuft rundherum weiter', () {
      expect(colorFromHsv(360, 1, 1), colorFromHsv(0, 1, 1));
      expect(colorFromHsv(-120, 1, 1), colorFromHsv(240, 1, 1));
    });

    test('eine zu blasse Farbe taugt nicht als Marke', () {
      // Sie ergäbe einen Knopf, der auf weißem Grund verschwindet — und das
      // merkt der Chef erst am Tresen.
      expect(isUsableBrandColor(hex('#FFF9C4')), isFalse);
      expect(isUsableBrandColor(hex('#FFFFFF')), isFalse);
    });

    test('kräftige Farben taugen — auch helle wie Orange', () {
      for (final code in ['#1B46F5', '#0F7B4F', '#B3261E', '#C2410C', '#000000']) {
        expect(isUsableBrandColor(hex(code)), isTrue, reason: code);
      }
    });
  });

  group('Markenfarbe', () {
    test('steht fest — eine eingestellte Betriebsfarbe färbt die Knöpfe nicht', () {
      // Die Knöpfe, mit denen kassiert wird, sind Teil des Produkts. Wer sie
      // je Betrieb umfärben kann, bekommt Kassen, die einander nicht mehr
      // ähneln — und eine Hausfarbe, die auf einem Knopf nicht mehr lesbar
      // ist, merkt niemand vor dem Tresen.
      final vorgabe = themaMit({}).brand;
      final eigen = themaMit({'color': '#B3261E'});
      expect(eigen.brand, vorgabe);
      expect(vorgabe.hex.toUpperCase(), '#136B6B');
    });

    test('im Nachtstil wird sie aufgehellt, bleibt aber die Marke', () {
      // Ein sattes Petrol auf fast schwarzem Grund ist kaum zu sehen — die
      // Rolle des Design-Systems hellt sie im Dunkeln von sich aus auf.
      final klar = themaMit({});
      final nacht = themaMit({'theme': 'night'});
      expect(nacht.brand.luminance, greaterThan(klar.brand.luminance));
      expect(nacht.brand.g, greaterThan(nacht.brand.r));
    });

    test('und sie traegt lesbare Schrift', () {
      expect(isUsableBrandColor(themaMit({}).brand), isTrue);
    });
  });
}