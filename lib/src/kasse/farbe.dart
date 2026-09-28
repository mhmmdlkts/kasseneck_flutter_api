/// Farben ohne Flutter — damit das Kassenthema auch dort gilt, wo kein
/// Bildschirm ist (Prüfungen, Bonlayout, künftig die Browser-Kasse).
///
/// Gerechnet wird nach WCAG: [contrastRatio] liefert dasselbe Verhältnis, das jedes
/// Prüfwerkzeug meldet. Das ist kein Selbstzweck — an dieser Zahl hängt, ob
/// ein Kassier am Fenster seine Summe noch lesen kann.
library;

import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:kreiseck_design/kreiseck_design.dart';

class PosColor {
  const PosColor(this.r, this.g, this.b);

  /// Aus einer Flutter-Farbe: das Design-System liefert `Color`, die Kasse
  /// rechnet und druckt mit [PosColor]. Alpha wird verworfen — Belege kennen
  /// keine Transparenz.
  factory PosColor.fromColor(Color c) {
    final v = c.toARGB32();
    return PosColor((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
  }

  /// `#RRGGBB`; alles andere ergibt [fallback] — eine Farbangabe aus dem Panel
  /// darf keine unsichtbare Kasse erzeugen. [fallback] ist Pflicht: ein
  /// stillschweigendes Panel-Blau als Vorgabe wäre eine Entscheidung des
  /// Aufrufers, die er nie getroffen hat.
  factory PosColor.fromHex(String hex, {required PosColor fallback}) {
    final h = hex.trim().replaceFirst('#', '');
    if (h.length != 6) return fallback;
    final wert = int.tryParse(h, radix: 16);
    if (wert == null) return fallback;
    return PosColor((wert >> 16) & 0xFF, (wert >> 8) & 0xFF, wert & 0xFF);
  }

  final int r;
  final int g;
  final int b;

  /// Sieht eine Farbangabe wie `#RRGGBB` aus?
  static bool isHex(String hex) {
    final h = hex.trim().replaceFirst('#', '');
    return h.length == 6 && int.tryParse(h, radix: 16) != null;
  }

  String get hex => '#'
      '${r.toRadixString(16).padLeft(2, '0')}'
      '${g.toRadixString(16).padLeft(2, '0')}'
      '${b.toRadixString(16).padLeft(2, '0')}'
      .toUpperCase();

  int get value => 0xFF000000 | (r << 16) | (g << 8) | b;

  /// Relative Helligkeit nach WCAG (0 = Schwarz, 1 = Weiß).
  double get luminance {
    double kanal(int v) {
      final s = v / 255;
      return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * kanal(r) + 0.7152 * kanal(g) + 0.0722 * kanal(b);
  }

  /// Mischt zu [other] hin; [fraction] 0 = diese Farbe, 1 = die andere.
  PosColor mixedWith(PosColor other, double fraction) {
    final t = fraction < 0 ? 0.0 : (fraction > 1 ? 1.0 : fraction);
    int misch(int a, int b) => (a + (b - a) * t).round();
    return PosColor(misch(r, other.r), misch(g, other.g), misch(b, other.b));
  }

  @override
  bool operator ==(Object other) => other is PosColor && other.r == r && other.g == g && other.b == b;

  @override
  int get hashCode => Object.hash(r, g, b);

  @override
  String toString() => hex;
}

/// Aus Farbton, Sättigung und Helligkeit (HSV) eine Farbe.
///
/// [hue] in Grad (0–360), [saturation] und [luminance] von 0 bis 1. Gebraucht
/// für eine freie Farbwahl: ein Regler je Größe ist begreiflicher als sechs
/// Hexzeichen.
PosColor colorFromHsv(double hue, double saturation, double value) {
  final h = (hue % 360 + 360) % 360;
  final s = saturation.clamp(0.0, 1.0);
  final v = value.clamp(0.0, 1.0);
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
  return PosColor(acht(r), acht(g), acht(b));
}

/// Taugt diese Farbe als Betriebsfarbe?
///
/// Sie sitzt auf dem Knopf, den der Kassier sucht. Ein zu blasser Ton ergibt
/// einen Knopf, der auf weißem Grund verschwindet — und das merkt der Chef
/// erst am Tresen. Geprüft wird gegen **beide** hellen Gründe, weil ein Betrieb
/// den Stil wechseln kann.
bool isUsableBrandColor(PosColor color) {
  final helleGruende = [const PosColor(0xFF, 0xFF, 0xFF), PosColor.fromColor(kdColor(KdMode.light, 'ground'))];
  for (final grund in helleGruende) {
    if (contrastRatio(color, grund) < 2.0) return false;
  }
  return true;
}

/// Kontrastverhältnis nach WCAG: 1 (gleich) bis 21 (Schwarz auf Weiß).
///
/// 4,5 ist die Schwelle für Fließtext, 3 für große Schrift. Die Kasse hält
/// sich an 4,5 — auch für den großen Betrag, denn gelesen wird er oft schräg
/// und in schlechtem Licht.
double contrastRatio(PosColor a, PosColor b) {
  final ha = a.luminance;
  final hb = b.luminance;
  final hell = ha > hb ? ha : hb;
  final dunkel = ha > hb ? hb : ha;
  return (hell + 0.05) / (dunkel + 0.05);
}

/// Die besser lesbare von zwei Farben auf [background].
PosColor readableOn(PosColor background, {PosColor light = const PosColor(0xFF, 0xFF, 0xFF), PosColor dark = const PosColor(0x0F, 0x17, 0x2A)}) {
  return contrastRatio(light, background) >= contrastRatio(dark, background) ? light : dark;
}
