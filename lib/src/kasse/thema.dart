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
/// * `contrastRatio` — grelles Licht oder schwache Augen. Er ändert deshalb mehr
///   als Farben: schärfere Linien (2 px), keine Schatten. Die Radien bleiben
///   — sie kommen aus dem Design-System und sind in jedem Modus gleich. Wer
///   nur die Farben tauscht, hat ihn nicht verstanden.
///
/// **Die Betriebsfarbe ist für Handlungen da, nicht für Schmuck.** Sie sitzt
/// auf dem Knopf, den der Kassier sucht, und auf der Auswahl, die gerade gilt
/// — nirgends sonst. Die Bedeutungsfarben (gut, Warnung, Fehler) sind von ihr
/// unabhängig: ein Betrieb mit roter Hausfarbe darf keine Kasse bekommen, in
/// der jeder Knopf nach Fehler aussieht.
///
/// **Die Textfarben halten 4,5:1 nach WCAG — die Schwelle für Fließtext —
/// überall, wo sie stehen; Bedeutungsfarben und Marke nur dort, wo sie
/// stehen.** Konkret: `text` und `textMuted` halten 4,5:1 auf `ground`, `surface`
/// und `surfaceRaised`. Bedeutungsfarben (`success`, `warning`, `fehler`) und
/// `brand` halten 4,5:1 auf `ground` und `surface` — sie stehen laut
/// Design-System nicht auf `surfaceRaised` (Kopfzeile, aktives Feld); dort
/// steht `text`/`textMuted`. Auch für den großen Betrag, denn der wird oft
/// schräg und in schlechtem Licht gelesen.
///
/// Farbe, Form und Modi kommen aus `kreiseck_design`; dieses Thema bleibt eine
/// dünne Sicht darauf plus das Kassen-Fach (Kachelhöhe, Spalten, Kachelstil,
/// Emoji, Kategoriefarben, Schriftfaktor).
library;

import 'package:kreiseck_design/kreiseck_design.dart';

import 'einstellungen.dart';
import 'farbe.dart';

/// Welcher Modus des Design-Systems hinter einem Stil steht.
KdMode modeFor(PosTheme style) => switch (style) {
      PosTheme.clear => KdMode.light,
      PosTheme.warm => KdMode.warm,
      PosTheme.night => KdMode.dark,
      PosTheme.contrast => KdMode.contrast,
    };

/// Schriftfaktoren. Auch XL bleibt bedienbar — ein Faktor, der die Kasse
/// sprengt, hilft niemandem, der schlecht sieht.
const Map<PosFontSize, double> fontScales = {
  PosFontSize.s: 0.9,
  PosFontSize.m: 1.0,
  PosFontSize.l: 1.15,
  PosFontSize.xl: 1.35,
};

/// Kachelhöhen in dp. Auch die flachste bleibt ein Fingerziel: unter 48 dp
/// trifft ein Finger nicht mehr verlässlich.
const Map<PosTileHeight, double> tileHeights = {
  PosTileHeight.s: 62,
  PosTileHeight.m: 82,
  PosTileHeight.l: 108,
};

class PosThemeData {
  const PosThemeData({
    required this.theme,
    required this.mode,
    required this.fontScale,
    required this.tileHeight,
    required this.extraColumns,
    required this.radius,
    required this.radiusTile,
    required this.radiusSmall,
    required this.lineWidth,
    required this.shadowDepth,
    required this.tileStyle,
    required this.emoji,
    required this.categoryColors,
  });

  /// Das Thema aus den Einstellungen. [device] steuert, was nur dieses Gerät
  /// betrifft (Kachelhöhe); ohne es gelten die Vorgaben.
  factory PosThemeData.fromSettings(PosBusinessSettings business, {PosDeviceSettings? device}) {
    final modus = modeFor(business.theme);
    final scharf = modus == KdMode.contrast;

    // **Die Marke steht fest.** Die Knöpfe, mit denen kassiert wird, sind
    // Teil des Produkts: Kassen, die einander nicht mehr ähneln, kosten jeden
    // neuen Kassier eine Eingewöhnung — und eine Hausfarbe, auf der „Bar
    // passend" nicht mehr lesbar ist, merkt niemand vor dem Tresen.
    // `business.color` bleibt im Datenmodell (Panel und Rechnungs-PDF lesen
    // es), färbt hier aber nichts mehr.
    return PosThemeData(
      theme: business.theme,
      mode: modus,
      fontScale: fontScales[business.fontSize]!,
      // **Mal Schriftfaktor.** Die Höhe einer Kachel ist keine feste Zahl,
      // sondern das, was Name und Preis brauchen. Bei Schrift XL in eine
      // Kachel für Schrift M gepresst, wird dem Namen die Unterlänge
      // abgeschnitten — und „Leistung" ohne das g liest sich falsch.
      tileHeight: tileHeights[device?.tileHeight ?? PosTileHeight.m]! * fontScales[business.fontSize]!,
      extraColumns: device?.extraColumns ?? 0,
      // Radien kommen aus dem Design-System und sind in jedem Modus gleich;
      // der Kontrast-Modus schärft Ränder und nimmt Schatten, sonst nichts.
      radius: KdForm.radiusLg,
      radiusTile: KdForm.radius,
      radiusSmall: KdForm.radius,
      lineWidth: scharf ? 2 : KdForm.borderWidth,
      shadowDepth: scharf ? 0 : (modus == KdMode.dark ? 0.5 : 1),
      tileStyle: business.tileStyle,
      emoji: business.emoji,
      categoryColors: business.categoryColors,
    );
  }

  final PosTheme theme;
  final KdMode mode;

  final double fontScale;
  final double tileHeight;

  /// Wie viele Kachelspalten mehr (oder mit Minus: weniger) als die Vorgabe
  /// nebeneinander stehen sollen. Gehört zum Gerät, nicht zum Betrieb: ein
  /// Tablet an der Theke und ein Handy im Gastgarten wollen Verschiedenes.
  final int extraColumns;

  /// Karten, Blätter, Dialoge.
  final double radius;

  /// Knöpfe, Felder, Kästchen, Kacheln.
  final double radiusTile;

  /// Kleine Bedienelemente: Auswahl, Steuersatz, Schnellbetrag.
  final double radiusSmall;

  final double lineWidth;

  /// 0 = keine Schatten (Kontraststil), 1 = volle Tiefe.
  final double shadowDepth;

  final PosTileStyle tileStyle;
  final bool emoji;
  final bool categoryColors;

  /// Heller Stil? Entscheidet über Statusleiste und Bilder.
  bool get isLight => mode != KdMode.dark;

  /// Der Hintergrund der Seite.
  PosColor get ground => PosColor.fromColor(kdColor(mode, 'ground'));

  /// Karten, Panels, alles, was auf dem Grund liegt.
  PosColor get surface => PosColor.fromColor(kdColor(mode, 'surface'));

  /// Hervorgehobene Fläche: Kopfzeile, aktives Eingabefeld.
  PosColor get surfaceRaised => PosColor.fromColor(kdColor(mode, 'surface-raised'));

  PosColor get text => PosColor.fromColor(kdColor(mode, 'ink'));

  /// Nebentext — leiser, aber nie unlesbar.
  PosColor get textMuted => PosColor.fromColor(kdColor(mode, 'ink-muted'));

  /// Umrandung.
  PosColor get border => PosColor.fromColor(kdColor(mode, 'border'));

  /// Trennlinie; leichter als [border] — außer im Kontrast-Modus, dort sind
  /// beide Schwarz.
  PosColor get divider => PosColor.fromColor(kdColor(mode, 'divider'));

  PosColor get success => PosColor.fromColor(kdColor(mode, 'success'));
  PosColor get successSurface => PosColor.fromColor(kdColor(mode, 'success-surface'));
  PosColor get warning => PosColor.fromColor(kdColor(mode, 'warning'));
  PosColor get warningSurface => PosColor.fromColor(kdColor(mode, 'warning-surface'));
  PosColor get danger => PosColor.fromColor(kdColor(mode, 'danger'));
  PosColor get dangerSurface => PosColor.fromColor(kdColor(mode, 'danger-surface'));

  /// Die Betriebsfarbe, für Handlungen.
  PosColor get brand => PosColor.fromColor(kdColor(mode, 'brand'));

  /// Dunklere Marke — Tiefe unter dem Knopf.
  PosColor get brandPressed => PosColor.fromColor(kdColor(mode, 'brand-pressed'));

  /// Sehr heller Markenton — Hintergrund der geltenden Auswahl.
  PosColor get brandSurface => PosColor.fromColor(kdColor(mode, 'brand-surface'));

  /// Lesbare Textfarbe auf [brand].
  PosColor get onBrand => PosColor.fromColor(kdColor(mode, 'on-brand'));

  /// Schriftgrößen in dp, bereits mit dem Faktor des Betriebs.
  ///
  /// Die Skala ist bewusst kurz: fünf Größen, jede mit einer Aufgabe. Mehr
  /// Stufen heißt nur, dass niemand mehr weiß, welche gemeint ist.
  ///
  /// **Die Vorgabe ist zurückhaltend.** Wer größer braucht, stellt `schrift`
  /// auf L oder XL — dafür ist die Einstellung da. Eine Kasse, die von Haus
  /// aus schreit, lässt sich nicht kleiner machen, ohne dass sie eng wirkt.
  double get huge => 36 * fontScale; // der Betrag, das Rückgeld
  double get large => 24 * fontScale; // Summen
  double get title => 18 * fontScale; // Überschriften
  double get normal => 15 * fontScale; // alles Übrige
  double get small => 12.5 * fontScale; // Nebentext
}
