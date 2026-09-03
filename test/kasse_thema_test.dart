import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/kasse.dart';
import 'package:kreiseck_design/kreiseck_design.dart';

/// Das Kassenthema: vier Stile, eine Betriebsfarbe, vier Schriftgrößen.
///
/// Die Stile sind keine Geschmacksfrage, sondern vier Orte: helle Theke,
/// Bäckerei bei Sonne, Bar am Abend, und ein Stil für grelles Licht oder
/// schwache Augen. Was sie unterscheidet, ist deshalb mehr als Farbe.

KasseSettingsBetrieb betriebMit(Map<String, dynamic> g) => KasseSettings.aus({'betrieb': g}).betrieb;

Kassenthema themaMit(Map<String, dynamic> g) => Kassenthema.aus(betriebMit(g));

/// Ein Betrieb mit Standardwerten, nur der Stil gesetzt.
KasseSettingsBetrieb betrieb(KasseStil stil) => betriebMit({'stil': stil.name});

void main() {
  group('Design-System', () {
    test('jeder Stil bildet auf einen Modus des Design-Systems ab', () {
      expect(Kassenthema.aus(betrieb(KasseStil.klar)).modus, KdMode.light);
      expect(Kassenthema.aus(betrieb(KasseStil.warm)).modus, KdMode.warm);
      expect(Kassenthema.aus(betrieb(KasseStil.nacht)).modus, KdMode.dark);
      expect(Kassenthema.aus(betrieb(KasseStil.kontrast)).modus, KdMode.contrast);
    });

    test('die Farben sind die Rollen des Design-Systems, keine eigenen Tabellen', () {
      final t = Kassenthema.aus(betrieb(KasseStil.nacht));
      expect(t.grund.hex.toUpperCase(), '#131B1B'); // neutral-950, § 131b
      expect(t.marke.hex.toUpperCase(), '#139E9B'); // brand-500 im Dunkeln
      expect(t.aufMarke.hex.toUpperCase(), '#131B1B'); // on-brand dunkel
      final k = Kassenthema.aus(betrieb(KasseStil.klar));
      expect(k.text.hex.toUpperCase(), '#132A2A'); // neutral-900, § 132a
    });

    test('der Kontrast-Stil schärft Ränder, nicht Radien', () {
      final t = Kassenthema.aus(betrieb(KasseStil.kontrast));
      expect(t.linie, 2);
      expect(t.radiusKlein, 10);
      expect(t.radius, 14);
      expect(t.schattenTiefe, 0);
    });
  });

  group('Stile', () {
    test('klar ist die Vorgabe: heller Grund, dunkler Text', () {
      final t = themaMit({});
      expect(t.stil, KasseStil.klar);
      expect(t.hell, isTrue);
      expect(t.grund.helligkeit, greaterThan(0.8));
      expect(t.text.helligkeit, lessThan(0.2));
    });

    test('nacht dreht es um — dunkler Grund, heller Text', () {
      // Für Taxi und Bar. Reines Schwarz wäre falsch: es flimmert auf OLED
      // beim Blättern und lässt jeden Rand hart wirken.
      final t = themaMit({'stil': 'nacht'});
      expect(t.hell, isFalse);
      expect(t.grund.helligkeit, lessThan(0.15));
      expect(t.grund, isNot(Farbe.ausHex('#000000')));
      expect(t.text.helligkeit, greaterThan(0.8));
    });

    test('warm ist heller Grund mit warmem Ton', () {
      final klar = themaMit({});
      final warm = themaMit({'stil': 'warm'});
      expect(warm.hell, isTrue);
      // Mehr Rot als Blau — das unterscheidet cremiges Papier von kühlem Grau.
      expect(warm.grund.r - warm.grund.b, greaterThan(klar.grund.r - klar.grund.b));
    });

    test('kontrast schärft Linien und nimmt Schatten, lässt Radien in Ruhe', () {
      // Er ist ein Stil für schwache Augen, kein Farbschema: dickere Linien,
      // keine Schatten. Radien bleiben unverändert — das unterscheidet ihn
      // von einem reinen Farbtausch, ohne die Kasse in der Form zu verstellen.
      final klar = themaMit({});
      final k = themaMit({'stil': 'kontrast'});

      expect(k.text, Farbe.ausHex('#000000'));
      expect(k.grund, Farbe.ausHex('#FFFFFF'));
      expect(k.flaeche, Farbe.ausHex('#FFFFFF'));
      expect(k.linie, greaterThan(klar.linie));
      expect(k.radius, klar.radius);
      expect(k.radiusKlein, klar.radiusKlein);
      expect(k.schattenTiefe, 0.0);
    });

    test('jeder Stil trägt seinen Text lesbar auf seinem Grund', () {
      // Die Zusage, die alles andere trägt. 4,5:1 ist die Schwelle für
      // Fließtext (WCAG AA).
      for (final stil in KasseStil.values) {
        final t = themaMit({'stil': stil.name});
        expect(kontrast(t.text, t.grund), greaterThanOrEqualTo(4.5), reason: '${stil.name}: Text auf Grund');
        expect(kontrast(t.text, t.flaeche), greaterThanOrEqualTo(4.5), reason: '${stil.name}: Text auf Flaeche');
        // Nebentext darf leiser sein, aber nicht unlesbar.
        expect(kontrast(t.leise, t.flaeche), greaterThanOrEqualTo(4.5), reason: '${stil.name}: Nebentext');
      }
    });
  });

  group('Radien', () {
    test('kleine Bedienelemente sind leicht gerundet, nie vollrund', () {
      // Eine Pille sieht nach Etikett aus; die Auswahl an einer Kasse ist ein
      // Schalter. Die Grenze: deutlich weniger als die halbe Hoehe eines
      // Chips (rund 32 dp) waere vollrund.
      for (final stil in KasseStil.values) {
        final t = themaMit({'stil': stil.name});
        expect(t.radiusKlein, greaterThan(0), reason: '${stil.name}: gar keine Rundung waere hart');
        expect(t.radiusKlein, lessThan(12), reason: '${stil.name}: zu rund');
        expect(t.radiusKlein, lessThanOrEqualTo(t.radiusKachel));
      }
    });
  });

  group('Betriebsfarbe', () {
    test('färbt die Kasse nicht mehr — auch keine kaputte Angabe', () {
      // Sie bleibt im Datenmodell (Panel und Rechnungs-PDF lesen sie), aber
      // die Knöpfe der Kasse gehören zum Produkt. Damit kann auch ein
      // Tippfehler aus dem Panel hier nichts mehr anrichten.
      final vorgabe = themaMit({}).marke;
      for (final wert in ['#1B46F5', '#FFE066', '', 'blau', '#12345']) {
        expect(themaMit({'farbe': wert}).marke, vorgabe, reason: wert);
      }
    });

    test('auf der Marke steht immer lesbarer Text', () {
      for (final stil in KasseStil.values) {
        final t = themaMit({'stil': stil.name});
        expect(kontrast(t.aufMarke, t.marke), greaterThanOrEqualTo(4.5), reason: stil.name);
      }
    });
  });

  group('Schriftgröße', () {
    test('M ist die Vorgabe und der Bezugspunkt', () {
      expect(themaMit({}).schriftfaktor, 1.0);
    });

    test('S ist kleiner, L und XL größer — in dieser Reihenfolge', () {
      final faktoren = [
        for (final s in ['S', 'M', 'L', 'XL']) themaMit({'schrift': s}).schriftfaktor,
      ];
      expect(faktoren, orderedEquals([...faktoren]..sort()));
      expect(faktoren.first, lessThan(1.0));
      expect(faktoren.last, greaterThan(1.2));
    });

    test('auch XL bleibt bedienbar — kein Faktor, der die Kasse sprengt', () {
      expect(themaMit({'schrift': 'XL'}).schriftfaktor, lessThanOrEqualTo(1.5));
    });
  });

  group('Kachelhöhe', () {
    test('flach, normal, hoch — in dieser Reihenfolge', () {
      final hoehen = [
        for (final h in ['S', 'M', 'L']) Kassenthema.aus(betriebMit({}), geraet: KasseSettings.aus({'geraet': {'hoehe': h}}).geraet).kachelhoehe,
      ];
      expect(hoehen, orderedEquals([...hoehen]..sort()));
    });

    test('auch die flachste Kachel bleibt ein Fingerziel', () {
      // 48 dp ist die Untergrenze, unter der ein Finger nicht mehr trifft.
      final flach = Kassenthema.aus(betriebMit({}), geraet: KasseSettings.aus({'geraet': {'hoehe': 'S'}}).geraet);
      expect(flach.kachelhoehe, greaterThanOrEqualTo(48));
    });
  });

  group('Farbe', () {
    test('liest #RRGGBB', () {
      final f = Farbe.ausHex('#1B46F5');
      expect(f.r, 0x1B);
      expect(f.g, 0x46);
      expect(f.b, 0xF5);
    });

    test('mischt zwei Farben', () {
      expect(Farbe.ausHex('#000000').gemischt(Farbe.ausHex('#FFFFFF'), 0.5).r, 128);
      expect(Farbe.ausHex('#000000').gemischt(Farbe.ausHex('#FFFFFF'), 0), Farbe.ausHex('#000000'));
      expect(Farbe.ausHex('#000000').gemischt(Farbe.ausHex('#FFFFFF'), 1), Farbe.ausHex('#FFFFFF'));
    });

    test('Kontrast: Schwarz auf Weiß ist der Höchstwert 21', () {
      expect(kontrast(Farbe.ausHex('#000000'), Farbe.ausHex('#FFFFFF')), closeTo(21, 0.1));
      expect(kontrast(Farbe.ausHex('#FFFFFF'), Farbe.ausHex('#FFFFFF')), closeTo(1, 0.01));
    });

    test('als Hex zurück', () {
      expect(Farbe.ausHex('#1b46f5').hex, '#1B46F5');
    });
  });

  group('freie Farbwahl', () {
    test('HSV ergibt die erwarteten Ecken', () {
      expect(farbeAusHsv(0, 1, 1), Farbe.ausHex('#FF0000'));
      expect(farbeAusHsv(120, 1, 1), Farbe.ausHex('#00FF00'));
      expect(farbeAusHsv(240, 1, 1), Farbe.ausHex('#0000FF'));
      expect(farbeAusHsv(0, 0, 1), Farbe.ausHex('#FFFFFF'));
      expect(farbeAusHsv(0, 0, 0), Farbe.ausHex('#000000'));
    });

    test('der Farbton läuft rundherum weiter', () {
      expect(farbeAusHsv(360, 1, 1), farbeAusHsv(0, 1, 1));
      expect(farbeAusHsv(-120, 1, 1), farbeAusHsv(240, 1, 1));
    });

    test('eine zu blasse Farbe taugt nicht als Marke', () {
      // Sie ergäbe einen Knopf, der auf weißem Grund verschwindet — und das
      // merkt der Chef erst am Tresen.
      expect(markeTaugt(Farbe.ausHex('#FFF9C4')), isFalse);
      expect(markeTaugt(Farbe.ausHex('#FFFFFF')), isFalse);
    });

    test('kräftige Farben taugen — auch helle wie Orange', () {
      for (final hex in ['#1B46F5', '#0F7B4F', '#B3261E', '#C2410C', '#000000']) {
        expect(markeTaugt(Farbe.ausHex(hex)), isTrue, reason: hex);
      }
    });
  });

  group('Markenfarbe', () {
    test('steht fest — eine eingestellte Betriebsfarbe färbt die Knöpfe nicht', () {
      // Die Knöpfe, mit denen kassiert wird, sind Teil des Produkts. Wer sie
      // je Betrieb umfärben kann, bekommt Kassen, die einander nicht mehr
      // ähneln — und eine Hausfarbe, die auf einem Knopf nicht mehr lesbar
      // ist, merkt niemand vor dem Tresen.
      final vorgabe = themaMit({}).marke;
      final eigen = themaMit({'farbe': '#B3261E'});
      expect(eigen.marke, vorgabe);
      expect(vorgabe.hex.toUpperCase(), '#136B6B');
    });

    test('im Nachtstil wird sie aufgehellt, bleibt aber die Marke', () {
      // Ein sattes Petrol auf fast schwarzem Grund ist kaum zu sehen — die
      // Rolle des Design-Systems hellt sie im Dunkeln von sich aus auf.
      final klar = themaMit({});
      final nacht = themaMit({'stil': 'nacht'});
      expect(nacht.marke, isNot(klar.marke));
      expect(nacht.marke.g, greaterThan(nacht.marke.r));
    });

    test('und sie traegt lesbare Schrift', () {
      expect(markeTaugt(const Farbe(0x11, 0x6B, 0x6B)), isTrue);
    });
  });
}