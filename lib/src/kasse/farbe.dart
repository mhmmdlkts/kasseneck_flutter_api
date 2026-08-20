/// Farben ohne Flutter — damit das Kassenthema auch dort gilt, wo kein
/// Bildschirm ist (Prüfungen, Bonlayout, künftig die Browser-Kasse).
///
/// Gerechnet wird nach WCAG: [kontrast] liefert dasselbe Verhältnis, das jedes
/// Prüfwerkzeug meldet. Das ist kein Selbstzweck — an dieser Zahl hängt, ob
/// ein Kassier am Fenster seine Summe noch lesen kann.
library;

import 'dart:math' as math;

class Farbe {
  const Farbe(this.r, this.g, this.b);

  /// `#RRGGBB`; alles andere ergibt [ersatz] — eine Farbangabe aus dem Panel
  /// darf keine unsichtbare Kasse erzeugen.
  factory Farbe.ausHex(String hex, {Farbe ersatz = const Farbe(0x1B, 0x46, 0xF5)}) {
    final h = hex.trim().replaceFirst('#', '');
    if (h.length != 6) return ersatz;
    final wert = int.tryParse(h, radix: 16);
    if (wert == null) return ersatz;
    return Farbe((wert >> 16) & 0xFF, (wert >> 8) & 0xFF, wert & 0xFF);
  }

  final int r;
  final int g;
  final int b;

  /// Sieht eine Farbangabe wie `#RRGGBB` aus?
  static bool istHex(String hex) {
    final h = hex.trim().replaceFirst('#', '');
    return h.length == 6 && int.tryParse(h, radix: 16) != null;
  }

  String get hex => '#'
      '${r.toRadixString(16).padLeft(2, '0')}'
      '${g.toRadixString(16).padLeft(2, '0')}'
      '${b.toRadixString(16).padLeft(2, '0')}'
      .toUpperCase();

  int get wert => 0xFF000000 | (r << 16) | (g << 8) | b;

  /// Relative Helligkeit nach WCAG (0 = Schwarz, 1 = Weiß).
  double get helligkeit {
    double kanal(int v) {
      final s = v / 255;
      return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * kanal(r) + 0.7152 * kanal(g) + 0.0722 * kanal(b);
  }

  /// Mischt zu [andere] hin; [anteil] 0 = diese Farbe, 1 = die andere.
  Farbe gemischt(Farbe andere, double anteil) {
    final t = anteil < 0 ? 0.0 : (anteil > 1 ? 1.0 : anteil);
    int misch(int a, int b) => (a + (b - a) * t).round();
    return Farbe(misch(r, andere.r), misch(g, andere.g), misch(b, andere.b));
  }

  @override
  bool operator ==(Object other) => other is Farbe && other.r == r && other.g == g && other.b == b;

  @override
  int get hashCode => Object.hash(r, g, b);

  @override
  String toString() => hex;
}

/// Aus Farbton, Sättigung und Helligkeit (HSV) eine Farbe.
///
/// [ton] in Grad (0–360), [saettigung] und [helligkeit] von 0 bis 1. Gebraucht
/// für eine freie Farbwahl: ein Regler je Größe ist begreiflicher als sechs
/// Hexzeichen.
Farbe farbeAusHsv(double ton, double saettigung, double helligkeit) {
  final h = (ton % 360 + 360) % 360;
  final s = saettigung.clamp(0.0, 1.0);
  final v = helligkeit.clamp(0.0, 1.0);
  final c = v * s;
  final x = c * (1 - ((h / 60) % 2 - 1).abs());
  final m = v - c;
  final (r, g, b) = switch (h ~/ 60) {
    0 => (c, x, 0.0),
    1 => (x, c, 0.0),
    2 => (0.0, c, x),
    3 => (0.0, x, c),
    4 => (x, 0.0, c),
    _ => (c, 0.0, x),
  };
  int acht(double f) => ((f + m) * 255).round().clamp(0, 255);
  return Farbe(acht(r), acht(g), acht(b));
}

/// Taugt diese Farbe als Betriebsfarbe?
///
/// Sie sitzt auf dem Knopf, den der Kassier sucht. Ein zu blasser Ton ergibt
/// einen Knopf, der auf weißem Grund verschwindet — und das merkt der Chef
/// erst am Tresen. Geprüft wird gegen **beide** hellen Gründe, weil ein Betrieb
/// den Stil wechseln kann.
bool markeTaugt(Farbe farbe) {
  const helleGruende = [Farbe(0xFF, 0xFF, 0xFF), Farbe(0xF1, 0xF4, 0xF9)];
  for (final grund in helleGruende) {
    if (kontrast(farbe, grund) < 2.0) return false;
  }
  return true;
}

/// Kontrastverhältnis nach WCAG: 1 (gleich) bis 21 (Schwarz auf Weiß).
///
/// 4,5 ist die Schwelle für Fließtext, 3 für große Schrift. Die Kasse hält
/// sich an 4,5 — auch für den großen Betrag, denn gelesen wird er oft schräg
/// und in schlechtem Licht.
double kontrast(Farbe a, Farbe b) {
  final ha = a.helligkeit;
  final hb = b.helligkeit;
  final hell = ha > hb ? ha : hb;
  final dunkel = ha > hb ? hb : ha;
  return (hell + 0.05) / (dunkel + 0.05);
}

/// Die besser lesbare von zwei Farben auf [grund].
Farbe lesbarAuf(Farbe grund, {Farbe hell = const Farbe(0xFF, 0xFF, 0xFF), Farbe dunkel = const Farbe(0x0F, 0x17, 0x2A)}) {
  return kontrast(hell, grund) >= kontrast(dunkel, grund) ? hell : dunkel;
}
