/// Zeichenraster (Zwilling von `renderReceiptGrid` im JS-Paket
/// `@kreiseck/kasseneck-api`): der Beleg als Zeilen mit **exakt N Zeichen**
/// (58 mm = 32, 80 mm = 48) — die eine Wahrheit für Bildschirm, Bondruck und
/// PDF. Regeln (fest, damit überall dasselbe herauskommt):
/// - Spalten in Zwölfteln → ganze Zeichen (`floor(N*w/12)`, Rest an die letzte,
///   jede mindestens 1); zwischen zwei Spalten immer mindestens ein
///   Leerzeichen (letztes Zeichen jeder nicht-letzten Spalte); die letzte
///   Spalte endet bündig am rechten Rand.
/// - Text/Aufdruck/Spalteninhalt bricht **wortweise** (letztes Leerzeichen
///   innerhalb der Breite, Leerzeichen fällt weg; ohne Leerzeichen hart).
/// - Trennlinie über die volle Breite, Leerraum als Leerzeilen, QR als eigene
///   Zeile mit Nutzlast (der Zeichner setzt das Bild).
/// Die Golden-Dateien `test/fixtures/vertrag/expected/*.grid32.txt|grid48.txt`
/// des JS-Pakets halten beide Seiten zeichengenau gleich.
library;

import 'package:kasseneck_api/models/beleg_layout.dart';

const int charsPer58mm = 32;
const int charsPer80mm = 48;

enum GridLineKind { text, columns, rule, space, qr, banner }

class GridLine {
  /// Genau N Zeichen (bei `qr`: zentrierter Platzhalter).
  final String text;
  final GridLineKind kind;
  final bool bold;
  /// Bei `banner` (Rahmen- und Textzeilen): Testkasse/Testsignatur/Ausfall.
  final bool warning;
  /// Bei `qr`: die Nutzlast.
  final String? qr;
  const GridLine({required this.text, required this.kind, this.bold = false, this.warning = false, this.qr});
}

const String _nbsp = '\u00a0';

/// Wortweiser Umbruch auf höchstens [max] Zeichen (Zwilling von `wortzeilenText`):
/// geschütztes Leerzeichen bricht nie (wird als Leerzeichen ausgegeben), ein
/// überlanges Wort bricht nach einem Bindestrich, sonst hart.
List<String> wrapWords(String text, int max) {
  final grenze = max < 1 ? 1 : max;
  final out = <String>[];
  var rest = text;
  while (rest.length > grenze) {
    var schnitt = grenze;
    if (rest[grenze] != ' ') {
      var i = grenze - 1;
      while (i > 0 && rest[i] != ' ') {
        i -= 1;
      }
      if (i > 0) {
        schnitt = i;
      } else {
        var h = grenze - 1;
        while (h > 0 && rest[h] != '-') {
          h -= 1;
        }
        if (h > 0) schnitt = h + 1;
      }
    }
    out.add(rest.substring(0, schnitt).replaceFirst(RegExp(r' +$'), '').replaceAll(_nbsp, ' '));
    var weiter = schnitt;
    while (weiter < rest.length && rest[weiter] == ' ') {
      weiter += 1;
    }
    rest = rest.substring(weiter);
  }
  out.add(rest.replaceAll(_nbsp, ' '));
  return out;
}

/// Text hinter der ersten Umbruchzeile (Präfix des Textes ohne Endleerzeichen).
String _restNach(String text, String erste) {
  var i = erste.length;
  while (i < text.length && text[i] == ' ') {
    i += 1;
  }
  return text.substring(i);
}

/// Zwölftel → Zeichen je Spalte (ganze Zeichen, Rest an die letzte, mindestens 1).
List<int> gridColumnWidths(List<int> zwoelftel, int zeichen) {
  final out = <int>[];
  var vergeben = 0;
  for (var i = 0; i < zwoelftel.length; i++) {
    final letzte = i == zwoelftel.length - 1;
    final b = letzte ? (zeichen - vergeben < 1 ? 1 : zeichen - vergeben) : ((zeichen * zwoelftel[i]) ~/ 12).clamp(1, 1 << 30);
    out.add(b);
    vergeben += b;
  }
  return out;
}

String _ausrichten(String text, int breite, LayoutAlign align) {
  final t = text.length > breite ? text.substring(0, breite) : text;
  final rest = breite - t.length;
  switch (align) {
    case LayoutAlign.right:
      return ' ' * rest + t;
    case LayoutAlign.center:
      final links = rest ~/ 2;
      return ' ' * links + t + ' ' * (rest - links);
    case LayoutAlign.left:
      return t + ' ' * rest;
  }
}

class ReceiptGrid {
  final List<GridLine> lines;
  final int charsPerLine;
  const ReceiptGrid({required this.lines, required this.charsPerLine});

  /// Setzt das Zeilenmodell ins Raster; [charsPerLine] fehlt → nach `paperSize` (32/48).
  static ReceiptGrid render(ReceiptLayout layout, {int? charsPerLine}) {
    final n0 = charsPerLine ?? (layout.paperSize == 'mm80' ? charsPer80mm : charsPer58mm);
    final n = n0 < 8 ? 8 : n0;
    final leer = ' ' * n;
    final out = <GridLine>[];
    for (final z in layout.lines) {
      switch (z) {
        case LayoutTextLine():
          for (final t in wrapWords(z.text, n)) {
            out.add(GridLine(text: _ausrichten(t, n, z.align), kind: GridLineKind.text, bold: z.bold));
          }
        case LayoutBannerLine():
          // Der Rahmen ist Teil des Rasters (Zwilling von renderReceiptGrid ab
          // npm 0.14.0): '=' ueber die volle Breite davor und danach. So setzt
          // ihn jeder Weg zeichengleich -- vorher druckte der Bon doppelt hoch
          // und invers, der Bildschirm fuellte schwarz, das PDF zog ein Rechteck.
          final rahmen = '=' * n;
          out.add(GridLine(text: rahmen, kind: GridLineKind.banner, bold: true, warning: z.warning));
          for (final t in wrapWords(z.text, n)) {
            out.add(GridLine(text: _ausrichten(t, n, LayoutAlign.center), kind: GridLineKind.banner, bold: true, warning: z.warning));
          }
          out.add(GridLine(text: rahmen, kind: GridLineKind.banner, bold: true, warning: z.warning));
        case LayoutRuleLine():
          out.add(GridLine(text: (z.char.isEmpty ? '-' : z.char[0]) * n, kind: GridLineKind.rule));
        case LayoutSpaceLine():
          for (var i = 0; i < z.lines; i++) {
            out.add(GridLine(text: leer, kind: GridLineKind.space));
          }
        case LayoutQrLine():
          out.add(GridLine(text: _ausrichten('[QR-Code]', n, LayoutAlign.center), kind: GridLineKind.qr, qr: z.data));
        case LayoutColumnsLine():
          final breiten = gridColumnWidths(z.columns.map((c) => c.width).toList(), n);
          final inhalt = <int>[for (var i = 0; i < breiten.length; i++) i < breiten.length - 1 ? (breiten[i] - 1 < 1 ? 1 : breiten[i] - 1) : breiten[i]];
          final teile = <List<String>>[for (var i = 0; i < z.columns.length; i++) wrapWords(z.columns[i].text, inhalt[i])];
          // Fließregel (wie renderReceiptGrid): läuft nur EINE Spalte über die erste Zeile
          // hinaus, bekommt ihr Rest die volle Breite; laufen mehrere weiter, bleibt das Raster.
          final weiterlaufend = <int>[for (var i = 0; i < teile.length; i++) if (teile[i].length > 1) i];
          final fliesst = weiterlaufend.length == 1 && z.columns.length > 1;
          var zeilen = 1;
          if (!fliesst) {
            for (final t in teile) {
              if (t.length > zeilen) zeilen = t.length;
            }
          }
          for (var r = 0; r < zeilen; r++) {
            final sb = StringBuffer();
            for (var i = 0; i < z.columns.length; i++) {
              final zelle = _ausrichten(r < teile[i].length ? teile[i][r] : '', inhalt[i], z.columns[i].align);
              sb.write(i < breiten.length - 1 ? zelle + ' ' * (breiten[i] - inhalt[i]) : zelle);
            }
            final text = sb.toString();
            out.add(GridLine(text: text.length == n ? text : _ausrichten(text, n, LayoutAlign.left), kind: GridLineKind.columns));
          }
          if (fliesst) {
            final i = weiterlaufend.first;
            final rest = _restNach(z.columns[i].text, teile[i].first);
            for (final t in wrapWords(rest, n)) {
              out.add(GridLine(text: _ausrichten(t, n, z.columns[i].align), kind: GridLineKind.columns));
            }
          }
      }
    }
    return ReceiptGrid(lines: out, charsPerLine: n);
  }

  /// Klartext (eine Zeile je Rasterzeile) — für Golden-Vergleiche und Logs.
  String toText() => lines.map((z) => z.text).join('\n');
}
