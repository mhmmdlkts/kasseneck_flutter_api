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
library;

import 'einstellungen.dart';
import 'farbe.dart';

/// Die Grundfarben eines Stils. Sie beschreiben Rollen, keine Farbnamen: was
/// „Fläche" ist, entscheidet der Stil.
class Stilfarben {
  const Stilfarben({
    required this.grund,
    required this.flaeche,
    required this.flaecheHoch,
    required this.text,
    required this.leise,
    required this.rand,
    required this.strich,
    required this.gut,
    required this.gutHell,
    required this.warnung,
    required this.warnungHell,
    required this.fehler,
    required this.fehlerHell,
  });

  /// Der Hintergrund der Seite.
  final Farbe grund;

  /// Karten, Panels, alles, was auf dem Grund liegt.
  final Farbe flaeche;

  /// Hervorgehobene Fläche: Kopfzeile, aktives Eingabefeld.
  final Farbe flaecheHoch;

  final Farbe text;

  /// Nebentext — leiser, aber nie unlesbar.
  final Farbe leise;

  /// Umrandung.
  final Farbe rand;

  /// Trennlinie; leichter als [rand].
  final Farbe strich;

  final Farbe gut;
  final Farbe gutHell;
  final Farbe warnung;
  final Farbe warnungHell;
  final Farbe fehler;
  final Farbe fehlerHell;
}

const _klar = Stilfarben(
  grund: Farbe(0xF1, 0xF4, 0xF9),
  flaeche: Farbe(0xFF, 0xFF, 0xFF),
  flaecheHoch: Farbe(0xF8, 0xFA, 0xFD),
  text: Farbe(0x10, 0x18, 0x28),
  leise: Farbe(0x53, 0x5E, 0x74),
  rand: Farbe(0xD3, 0xDA, 0xE6),
  strich: Farbe(0xE6, 0xEA, 0xF1),
  gut: Farbe(0x0B, 0x6B, 0x43),
  gutHell: Farbe(0xE3, 0xF3, 0xEA),
  warnung: Farbe(0x8A, 0x42, 0x04),
  warnungHell: Farbe(0xFD, 0xEF, 0xDC),
  fehler: Farbe(0xA8, 0x1C, 0x16),
  fehlerHell: Farbe(0xFB, 0xE9, 0xE7),
);

const _warm = Stilfarben(
  grund: Farbe(0xF5, 0xF0, 0xE8),
  flaeche: Farbe(0xFF, 0xFD, 0xF9),
  flaecheHoch: Farbe(0xFA, 0xF6, 0xEE),
  text: Farbe(0x2A, 0x21, 0x17),
  leise: Farbe(0x64, 0x58, 0x4A),
  rand: Farbe(0xDE, 0xD4, 0xC5),
  strich: Farbe(0xED, 0xE6, 0xDA),
  gut: Farbe(0x0B, 0x63, 0x3E),
  gutHell: Farbe(0xE6, 0xF1, 0xE4),
  warnung: Farbe(0x83, 0x3D, 0x03),
  warnungHell: Farbe(0xFA, 0xEE, 0xDA),
  fehler: Farbe(0xA0, 0x1B, 0x14),
  fehlerHell: Farbe(0xF9, 0xE7, 0xE1),
);

const _nacht = Stilfarben(
  // Nicht #000000: reines Schwarz flimmert auf OLED beim Blaettern.
  grund: Farbe(0x0D, 0x11, 0x17),
  flaeche: Farbe(0x17, 0x1C, 0x25),
  flaecheHoch: Farbe(0x1E, 0x24, 0x2F),
  text: Farbe(0xE8, 0xEC, 0xF3),
  leise: Farbe(0xA3, 0xAE, 0xC2),
  rand: Farbe(0x2B, 0x33, 0x41),
  strich: Farbe(0x22, 0x28, 0x36),
  gut: Farbe(0x5E, 0xD6, 0x9B),
  gutHell: Farbe(0x11, 0x2B, 0x1E),
  warnung: Farbe(0xF2, 0xBB, 0x6B),
  warnungHell: Farbe(0x33, 0x24, 0x0F),
  fehler: Farbe(0xF5, 0x94, 0x8C),
  fehlerHell: Farbe(0x36, 0x18, 0x16),
);

const _kontrast = Stilfarben(
  grund: Farbe(0xFF, 0xFF, 0xFF),
  flaeche: Farbe(0xFF, 0xFF, 0xFF),
  flaecheHoch: Farbe(0xFF, 0xFF, 0xFF),
  text: Farbe(0x00, 0x00, 0x00),
  leise: Farbe(0x1F, 0x1F, 0x1F),
  rand: Farbe(0x00, 0x00, 0x00),
  strich: Farbe(0x5A, 0x5A, 0x5A),
  gut: Farbe(0x00, 0x4D, 0x26),
  gutHell: Farbe(0xE0, 0xF5, 0xE8),
  warnung: Farbe(0x6B, 0x33, 0x00),
  warnungHell: Farbe(0xFF, 0xF0, 0xDC),
  fehler: Farbe(0x8C, 0x00, 0x00),
  fehlerHell: Farbe(0xFF, 0xE5, 0xE5),
);

const Map<KasseStil, Stilfarben> stilfarben = {
  KasseStil.klar: _klar,
  KasseStil.warm: _warm,
  KasseStil.nacht: _nacht,
  KasseStil.kontrast: _kontrast,
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

/// Petrol — die Farbe der Marke Kasseneck und damit jede Handlung in der
/// Kasse. Zwilling von `markeFarbe` im Flutter-Paket `kasseneck_marke` und der
/// Farbe im App-Zeichen.
const Farbe markenfarbe = Farbe(0x11, 0x6B, 0x6B);

class Kassenthema {
  const Kassenthema({
    required this.stil,
    required this.farben,
    required this.marke,
    required this.markeTief,
    required this.markeHell,
    required this.aufMarke,
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
    final stil = betrieb.stil;
    final farben = stilfarben[stil]!;
    final dunkel = stil == KasseStil.nacht;
    final scharf = stil == KasseStil.kontrast;

    // **Die Marke steht fest.** Die Knöpfe, mit denen kassiert wird, sind
    // Teil des Produkts: Kassen, die einander nicht mehr ähneln, kosten jeden
    // neuen Kassier eine Eingewöhnung — und eine Hausfarbe, auf der „Bar
    // passend" nicht mehr lesbar ist, merkt niemand vor dem Tresen.
    // `betrieb.farbe` bleibt im Datenmodell (Panel und Rechnungs-PDF lesen
    // es), färbt hier aber nichts mehr.
    const gewaehlt = markenfarbe;
    // Im Nachtstil wird die Marke aufgehellt: ein sattes Blau auf fast
    // schwarzem Grund ist kaum zu sehen, und die Marke muss der Knopf sein,
    // den man findet.
    final marke = dunkel ? gewaehlt.gemischt(const Farbe(0xFF, 0xFF, 0xFF), 0.28) : gewaehlt;

    return Kassenthema(
      stil: stil,
      farben: farben,
      marke: marke,
      // Liegt unter dem Knopf und gibt ihm Tiefe.
      markeTief: dunkel
          ? marke.gemischt(const Farbe(0x00, 0x00, 0x00), 0.28)
          : marke.gemischt(const Farbe(0x00, 0x00, 0x00), 0.24),
      // Hintergrund der geltenden Auswahl — nur ein Hauch Farbe.
      markeHell: dunkel ? marke.gemischt(farben.grund, 0.76) : marke.gemischt(farben.flaeche, 0.88),
      // Nach Helligkeit gewählt: eine gelbe Hausfarbe braucht dunklen Text,
      // sonst sind die Knöpfe unlesbar.
      aufMarke: lesbarAuf(marke, dunkel: farben.text.helligkeit < 0.2 ? farben.text : const Farbe(0x0F, 0x17, 0x2A)),
      schriftfaktor: schriftfaktoren[betrieb.schrift]!,
      // **Mal Schriftfaktor.** Die Höhe einer Kachel ist keine feste Zahl,
      // sondern das, was Name und Preis brauchen. Bei Schrift XL in eine
      // Kachel für Schrift M gepresst, wird dem Namen die Unterlänge
      // abgeschnitten — und „Leistung" ohne das g liest sich falsch.
      kachelhoehe: kachelhoehen[geraet?.hoehe ?? KasseHoehe.m]! * schriftfaktoren[betrieb.schrift]!,
      spaltenExtra: geraet?.spaltenExtra ?? 0,
      radius: scharf ? 6 : 14,
      radiusKachel: scharf ? 6 : 12,
      // Bewusst KEIN Vollrund: eine Pille sieht nach Etikett aus, und die
      // Auswahl an einer Kasse ist ein Schalter, kein Etikett.
      radiusKlein: scharf ? 4 : 8,
      linie: scharf ? 2 : 1,
      // Schatten sind Tiefe; im Kontraststil sind sie Unschärfe.
      schattenTiefe: scharf ? 0 : (dunkel ? 0.5 : 1),
      kachelstil: betrieb.kachelstil,
      emoji: betrieb.emoji,
      katFarben: betrieb.katFarben,
    );
  }

  final KasseStil stil;
  final Stilfarben farben;

  /// Die Betriebsfarbe, für Handlungen.
  final Farbe marke;

  /// Dunklere Marke — Tiefe unter dem Knopf.
  final Farbe markeTief;

  /// Sehr heller Markenton — Hintergrund der geltenden Auswahl.
  final Farbe markeHell;

  /// Lesbare Textfarbe auf [marke].
  final Farbe aufMarke;

  final double schriftfaktor;
  final double kachelhoehe;

  /// Wie viele Kachelspalten mehr (oder mit Minus: weniger) als die Vorgabe
  /// nebeneinander stehen sollen. Gehört zum Gerät, nicht zum Betrieb: ein
  /// Tablet an der Theke und ein Handy im Gastgarten wollen Verschiedenes.
  final int spaltenExtra;
  final double radius;
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
  bool get hell => farben.text.helligkeit < farben.grund.helligkeit;

  Farbe get grund => farben.grund;
  Farbe get flaeche => farben.flaeche;
  Farbe get flaecheHoch => farben.flaecheHoch;
  Farbe get text => farben.text;
  Farbe get leise => farben.leise;
  Farbe get rand => farben.rand;
  Farbe get strich => farben.strich;
  Farbe get gut => farben.gut;
  Farbe get warnung => farben.warnung;
  Farbe get fehler => farben.fehler;
  Farbe get fehlerHell => farben.fehlerHell;

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
