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
/// Die Golden-Dateien `test/fixtures/belege/erwartet/*.grid32.txt|grid48.txt`
/// des JS-Pakets halten beide Seiten zeichengenau gleich.
library;

import 'package:kasseneck_api/models/beleg_layout.dart';

const int zeichen58mm = 32;
const int zeichen80mm = 48;

enum RasterArt { text, columns, rule, space, qr, banner }

class RasterZeile {
  /// Genau N Zeichen (bei `qr`: zentrierter Platzhalter).
  final String text;
  final RasterArt art;
  final bool bold;
  /// Bei `banner`: invers/auffällig.
  final bool warnung;
  /// Bei `qr`: die Nutzlast.
  final String? qr;
  const RasterZeile({required this.text, required this.art, this.bold = false, this.warnung = false, this.qr});
}

const String _nbsp = '\u00a0';

/// Wortweiser Umbruch auf höchstens [max] Zeichen (Zwilling von `wortzeilenText`):
/// geschütztes Leerzeichen bricht nie (wird als Leerzeichen ausgegeben), ein
/// überlanges Wort bricht nach einem Bindestrich, sonst hart.
List<String> wortzeilen(String text, int max) {
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
List<int> rasterSpaltenBreiten(List<int> zwoelftel, int zeichen) {
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

String _ausrichten(String text, int breite, BelegAlign align) {
  final t = text.length > breite ? text.substring(0, breite) : text;
  final rest = breite - t.length;
  switch (align) {
    case BelegAlign.right:
      return ' ' * rest + t;
    case BelegAlign.center:
      final links = rest ~/ 2;
      return ' ' * links + t + ' ' * (rest - links);
    case BelegAlign.left:
      return t + ' ' * rest;
  }
}

class BelegRaster {
  final List<RasterZeile> lines;
  final int zeichen;
  const BelegRaster({required this.lines, required this.zeichen});

  /// Setzt das Zeilenmodell ins Raster; [zeichen] fehlt → nach `paperSize` (32/48).
  static BelegRaster render(BelegLayout layout, {int? zeichen}) {
    final n0 = zeichen ?? (layout.paperSize == 'mm80' ? zeichen80mm : zeichen58mm);
    final n = n0 < 8 ? 8 : n0;
    final leer = ' ' * n;
    final out = <RasterZeile>[];
    for (final z in layout.lines) {
      switch (z) {
        case BelegText():
          for (final t in wortzeilen(z.text, n)) {
            out.add(RasterZeile(text: _ausrichten(t, n, z.align), art: RasterArt.text, bold: z.bold));
          }
        case BelegBanner():
          for (final t in wortzeilen(z.text, n)) {
            out.add(RasterZeile(text: _ausrichten(t, n, BelegAlign.center), art: RasterArt.banner, bold: true, warnung: z.warnung));
          }
        case BelegLinie():
          out.add(RasterZeile(text: (z.char.isEmpty ? '-' : z.char[0]) * n, art: RasterArt.rule));
        case BelegLeerraum():
          for (var i = 0; i < z.lines; i++) {
            out.add(RasterZeile(text: leer, art: RasterArt.space));
          }
        case BelegQr():
          out.add(RasterZeile(text: _ausrichten('[QR-Code]', n, BelegAlign.center), art: RasterArt.qr, qr: z.data));
        case BelegSpalten():
          final breiten = rasterSpaltenBreiten(z.columns.map((c) => c.width).toList(), n);
          final inhalt = <int>[for (var i = 0; i < breiten.length; i++) i < breiten.length - 1 ? (breiten[i] - 1 < 1 ? 1 : breiten[i] - 1) : breiten[i]];
          final teile = <List<String>>[for (var i = 0; i < z.columns.length; i++) wortzeilen(z.columns[i].text, inhalt[i])];
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
            out.add(RasterZeile(text: text.length == n ? text : _ausrichten(text, n, BelegAlign.left), art: RasterArt.columns));
          }
          if (fliesst) {
            final i = weiterlaufend.first;
            final rest = _restNach(z.columns[i].text, teile[i].first);
            for (final t in wortzeilen(rest, n)) {
              out.add(RasterZeile(text: _ausrichten(t, n, z.columns[i].align), art: RasterArt.columns));
            }
          }
      }
    }
    return BelegRaster(lines: out, zeichen: n);
  }

  /// Klartext (eine Zeile je Rasterzeile) — für Golden-Vergleiche und Logs.
  String alsText() => lines.map((z) => z.text).join('\n');
}
