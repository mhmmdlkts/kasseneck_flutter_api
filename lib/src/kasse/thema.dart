/// Das Kassenthema: was die Einstellungen des Betriebs für das Aussehen
/// bedeuten — als Werte, ohne Flutter und ohne CSS.
///
/// **Die vier Stile sind vier Orte, keine Geschmacksfrage.**
///
/// * `klar` — helle Theke bei Tageslicht. Der Neutralton hat eine Spur Blau
///   zur Marke hin; ein reines Mittelgrau wirkt geerbt statt gewählt.
/// * `warm` — Bäckerei und Café. Cremiges Papier statt kühlem Grau.
/// * `nacht` — Taxi und Bar. Tief, aber **nicht schwarz**: reines Schwarz
///   flimmert auf OLED beim Blättern und macht jeden Rand hart.
/// * `kontrast` — grelles Licht oder schwache Augen. Er ändert deshalb mehr
///   als Farben: dickere Linien, kleinere Radien, keine Schatten. Wer nur die
///   Farben tauscht, hat ihn nicht verstanden.
///
/// **Die Betriebsfarbe ist für Handlungen da, nicht für Schmuck.** Sie sitzt
/// auf dem Knopf, den der Kassier sucht, und auf der Auswahl, die gerade gilt
/// — nirgends sonst. Die Bedeutungsfarben (gut, Warnung, Fehler) sind von ihr
/// unabhängig: ein Betrieb mit roter Hausfarbe darf keine Kasse bekommen, in
/// der jeder Knopf nach Fehler aussieht.
///
/// Jede Farbpaarung dieser Datei hält 4,5:1 nach WCAG — die Schwelle für
/// Fließtext. Auch für den großen Betrag, denn der wird oft schräg und in
/// schlechtem Licht gelesen.
///
/// Farbe, Form und Modi kommen aus `kreiseck_design`; dieses Thema bleibt eine
/// dünne Sicht darauf plus das Kassen-Fach (Kachelhöhe, Spalten, Kachelstil,
/// Emoji, Kategoriefarben, Schriftfaktor).
library;

import 'package:kreiseck_design/kreiseck_design.dart';

import 'einstellungen.dart';
import 'farbe.dart';

/// Welcher Modus des Design-Systems hinter einem Stil steht. Die Enum
/// [KasseStil] bleibt deutsch — sie steht in Kundendaten.
KdMode modusFuer(KasseStil stil) => switch (stil) {
      KasseStil.klar => KdMode.light,
      KasseStil.warm => KdMode.warm,
      KasseStil.nacht => KdMode.dark,
      KasseStil.kontrast => KdMode.contrast,
    };

/// Schriftfaktoren. Auch XL bleibt bedienbar — ein Faktor, der die Kasse
/// sprengt, hilft niemandem, der schlecht sieht.
const Map<KasseSchrift, double> schriftfaktoren = {
  KasseSchrift.s: 0.9,
  KasseSchrift.m: 1.0,
  KasseSchrift.l: 1.15,
  KasseSchrift.xl: 1.35,
};

/// Kachelhöhen in dp. Auch die flachste bleibt ein Fingerziel: unter 48 dp
/// trifft ein Finger nicht mehr verlässlich.
const Map<KasseHoehe, double> kachelhoehen = {
  KasseHoehe.s: 62,
  KasseHoehe.m: 82,
  KasseHoehe.l: 108,
};

class Kassenthema {
  const Kassenthema({
    required this.stil,
    required this.modus,
    required this.schriftfaktor,
    required this.kachelhoehe,
    required this.spaltenExtra,
    required this.radius,
    required this.radiusKachel,
    required this.radiusKlein,
    required this.linie,
    required this.schattenTiefe,
    required this.kachelstil,
    required this.emoji,
    required this.katFarben,
  });

  /// Das Thema aus den Einstellungen. [geraet] steuert, was nur dieses Gerät
  /// betrifft (Kachelhöhe); ohne es gelten die Vorgaben.
  factory Kassenthema.aus(KasseSettingsBetrieb betrieb, {KasseSettingsGeraet? geraet}) {
    final modus = modusFuer(betrieb.stil);
    final scharf = modus == KdMode.contrast;

    // **Die Marke steht fest.** Die Knöpfe, mit denen kassiert wird, sind
    // Teil des Produkts: Kassen, die einander nicht mehr ähneln, kosten jeden
    // neuen Kassier eine Eingewöhnung — und eine Hausfarbe, auf der „Bar
    // passend" nicht mehr lesbar ist, merkt niemand vor dem Tresen.
    // `betrieb.farbe` bleibt im Datenmodell (Panel und Rechnungs-PDF lesen
    // es), färbt hier aber nichts mehr.
    return Kassenthema(
      stil: betrieb.stil,
      modus: modus,
      schriftfaktor: schriftfaktoren[betrieb.schrift]!,
      // **Mal Schriftfaktor.** Die Höhe einer Kachel ist keine feste Zahl,
      // sondern das, was Name und Preis brauchen. Bei Schrift XL in eine
      // Kachel für Schrift M gepresst, wird dem Namen die Unterlänge
      // abgeschnitten — und „Leistung" ohne das g liest sich falsch.
      kachelhoehe: kachelhoehen[geraet?.hoehe ?? KasseHoehe.m]! * schriftfaktoren[betrieb.schrift]!,
      spaltenExtra: geraet?.spaltenExtra ?? 0,
      // Radien kommen aus dem Design-System und sind in jedem Modus gleich;
      // der Kontrast-Modus schärft Ränder und nimmt Schatten, sonst nichts.
      radius: KdForm.radiusLg,
      radiusKachel: KdForm.radius,
      radiusKlein: KdForm.radius,
      linie: scharf ? 2 : KdForm.borderWidth,
      schattenTiefe: scharf ? 0 : (modus == KdMode.dark ? 0.5 : 1),
      kachelstil: betrieb.kachelstil,
      emoji: betrieb.emoji,
      katFarben: betrieb.katFarben,
    );
  }

  final KasseStil stil;
  final KdMode modus;

  final double schriftfaktor;
  final double kachelhoehe;

  /// Wie viele Kachelspalten mehr (oder mit Minus: weniger) als die Vorgabe
  /// nebeneinander stehen sollen. Gehört zum Gerät, nicht zum Betrieb: ein
  /// Tablet an der Theke und ein Handy im Gastgarten wollen Verschiedenes.
  final int spaltenExtra;

  /// Karten, Blätter, Dialoge.
  final double radius;

  /// Knöpfe, Felder, Kästchen, Kacheln.
  final double radiusKachel;

  /// Kleine Bedienelemente: Auswahl, Steuersatz, Schnellbetrag.
  final double radiusKlein;

  final double linie;

  /// 0 = keine Schatten (Kontraststil), 1 = volle Tiefe.
  final double schattenTiefe;

  final KasseKachelstil kachelstil;
  final bool emoji;
  final bool katFarben;

  /// Heller Stil? Entscheidet über Statusleiste und Bilder.
  bool get hell => modus != KdMode.dark;

  /// Der Hintergrund der Seite.
  Farbe get grund => Farbe.ausColor(kdColor(modus, 'ground'));

  /// Karten, Panels, alles, was auf dem Grund liegt.
  Farbe get flaeche => Farbe.ausColor(kdColor(modus, 'surface'));

  /// Hervorgehobene Fläche: Kopfzeile, aktives Eingabefeld.
  Farbe get flaecheHoch => Farbe.ausColor(kdColor(modus, 'surface-raised'));

  Farbe get text => Farbe.ausColor(kdColor(modus, 'ink'));

  /// Nebentext — leiser, aber nie unlesbar.
  Farbe get leise => Farbe.ausColor(kdColor(modus, 'ink-muted'));

  /// Umrandung.
  Farbe get rand => Farbe.ausColor(kdColor(modus, 'border'));

  /// Trennlinie; leichter als [rand].
  Farbe get strich => Farbe.ausColor(kdColor(modus, 'divider'));

  Farbe get gut => Farbe.ausColor(kdColor(modus, 'success'));
  Farbe get gutHell => Farbe.ausColor(kdColor(modus, 'success-surface'));
  Farbe get warnung => Farbe.ausColor(kdColor(modus, 'warning'));
  Farbe get warnungHell => Farbe.ausColor(kdColor(modus, 'warning-surface'));
  Farbe get fehler => Farbe.ausColor(kdColor(modus, 'danger'));
  Farbe get fehlerHell => Farbe.ausColor(kdColor(modus, 'danger-surface'));

  /// Die Betriebsfarbe, für Handlungen.
  Farbe get marke => Farbe.ausColor(kdColor(modus, 'brand'));

  /// Dunklere Marke — Tiefe unter dem Knopf.
  Farbe get markeTief => Farbe.ausColor(kdColor(modus, 'brand-pressed'));

  /// Sehr heller Markenton — Hintergrund der geltenden Auswahl.
  Farbe get markeHell => Farbe.ausColor(kdColor(modus, 'brand-surface'));

  /// Lesbare Textfarbe auf [marke].
  Farbe get aufMarke => Farbe.ausColor(kdColor(modus, 'on-brand'));

  /// Schriftgrößen in dp, bereits mit dem Faktor des Betriebs.
  ///
  /// Die Skala ist bewusst kurz: fünf Größen, jede mit einer Aufgabe. Mehr
  /// Stufen heißt nur, dass niemand mehr weiß, welche gemeint ist.
  ///
  /// **Die Vorgabe ist zurückhaltend.** Wer größer braucht, stellt `schrift`
  /// auf L oder XL — dafür ist die Einstellung da. Eine Kasse, die von Haus
  /// aus schreit, lässt sich nicht kleiner machen, ohne dass sie eng wirkt.
  double get riesig => 36 * schriftfaktor; // der Betrag, das Rückgeld
  double get gross => 24 * schriftfaktor; // Summen
  double get titel => 18 * schriftfaktor; // Überschriften
  double get normal => 15 * schriftfaktor; // alles Übrige
  double get klein => 12.5 * schriftfaktor; // Nebentext
}
