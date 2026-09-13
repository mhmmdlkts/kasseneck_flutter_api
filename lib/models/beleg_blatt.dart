/// Das Beleg-Blatt (Zwilling von `belegBlatt` in `@kreiseck/kasseneck-api`
/// ab 0.14.0): die vollstaendige Folge dessen, was auf dem Papier steht --
/// Rasterzeilen, Firmenlogo, QR und Marke, Groessen als Anteil der Blattbreite
/// und in Zeilen. Jeder Zeichner (Bon, Bildschirm) setzt nur noch das Blatt.
///
/// Masseinheit ist der Druckkopf: ein Zeichen 12 Punkte, eine Zeile 24.
/// Die Goldens `test/fixtures/vertrag/erwartet/*.blatt32.json|blatt48.json`
/// halten beide Seiten gleich; die Rechenreihenfolge nicht umstellen.
library;

import 'dart:convert' show utf8;
import 'dart:math' as math;

import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/models/beleg_layout.dart';
import 'package:kasseneck_api/models/beleg_raster.dart';
import 'package:kasseneck_api/src/printing/qr_groesse.dart';

enum LogoStufe {
  s('S', 0.42, 5),
  m('M', 0.62, 8),
  l('L', 0.8, 12),
  xl('XL', 0.94, 16);

  final String kuerzel;
  final double breiteAnteil;
  final int hoeheZeilen;
  const LogoStufe(this.kuerzel, this.breiteAnteil, this.hoeheZeilen);

  /// Die Einstellung `logoSkala` des Betriebs; fehlt sie oder ist sie unbekannt, gilt M.
  static LogoStufe ausKuerzel(String? kuerzel) =>
      LogoStufe.values.firstWhere((s) => s.kuerzel == kuerzel, orElse: () => LogoStufe.m);
}

const int punkteJeZeichen = 12;
const int punkteJeZeile = 24;
const String markeText = 'erstellt mit Kasseneck';

class BlattLogo {
  final LogoStufe stufe;
  final int pxBreite;
  final int pxHoehe;
  const BlattLogo({required this.stufe, required this.pxBreite, required this.pxHoehe});
}

class LogoMass {
  final double breiteAnteil;
  final double hoeheZeilen;
  const LogoMass({required this.breiteAnteil, required this.hoeheZeilen});
}

sealed class BlattBlock {
  const BlattBlock();
}

class BlattZeile extends BlattBlock {
  final String text;
  final bool fett;
  final bool leer;
  const BlattZeile({required this.text, required this.fett, required this.leer});
}

class BlattLogoBlock extends BlattBlock {
  final double breiteAnteil;
  final double hoeheZeilen;
  const BlattLogoBlock({required this.breiteAnteil, required this.hoeheZeilen});
}

class BlattQr extends BlattBlock {
  final String nutzlast;
  final double breiteAnteil;
  const BlattQr({required this.nutzlast, required this.breiteAnteil});
}

class BelegBlatt {
  final int zeichen;
  final List<BlattBlock> bloecke;
  const BelegBlatt({required this.zeichen, required this.bloecke});
}

KeckPaperSize papierFuerZeichen(int zeichen, String vorgabe) {
  if (zeichen == KeckPaperSize.mm58.defaultCharCount) return KeckPaperSize.mm58;
  if (zeichen == KeckPaperSize.mm80.defaultCharCount) return KeckPaperSize.mm80;
  return vorgabe == 'mm80' ? KeckPaperSize.mm80 : KeckPaperSize.mm58;
}

/// Ins Kaestchen der Stufe eingepasst, nie hochgerechnet (1 Bildpixel hoechstens 1 Druckpunkt).
LogoMass logoMass(BlattLogo logo, int zeichen) {
  if (logo.pxBreite <= 0 || logo.pxHoehe <= 0) {
    throw ArgumentError('Logo ohne Pixelmass');
  }
  final blattPunkte = zeichen * punkteJeZeichen;
  final faktor = math.min(
    math.min((logo.stufe.breiteAnteil * blattPunkte) / logo.pxBreite, (logo.stufe.hoeheZeilen * punkteJeZeile) / logo.pxHoehe),
    1.0,
  );
  return LogoMass(
    breiteAnteil: (logo.pxBreite * faktor) / blattPunkte,
    hoeheZeilen: (logo.pxHoehe * faktor) / punkteJeZeile,
  );
}

({int breite, int hoehe}) logoRasterMass(LogoMass mass, int zeichen) => (
      breite: math.max(1, (mass.breiteAnteil * zeichen * punkteJeZeichen).round()),
      hoehe: math.max(1, (mass.hoeheZeilen * punkteJeZeile).round()),
    );

/// Byte-Kapazitaet je QR-Version bei Korrektur M (ISO/IEC 18004) -- dieselbe
/// Tabelle wie `qrModulAnzahl` im npm-Paket. Bewusst nicht `QrMass.modulAnzahl`:
/// das Blatt muss dieselben Zahlen liefern wie die npm-Goldens.
const List<int> _byteKapazitaetM = [
  14, 26, 42, 62, 84, 106, 122, 152, 180, 213,
  251, 287, 331, 362, 412, 450, 504, 560, 624, 666,
  711, 779, 857, 911, 997, 1059, 1125, 1190, 1264, 1370,
  1452, 1538, 1628, 1722, 1809, 1911, 1989, 2099, 2213, 2331,
];

int qrModulAnzahlWieNpm(String nutzlast) {
  final laenge = utf8.encode(nutzlast).length;
  for (var i = 0; i < _byteKapazitaetM.length; i++) {
    if (laenge <= _byteKapazitaetM[i]) return 17 + 4 * (i + 1);
  }
  throw ArgumentError('QR-Inhalt ist zu lang');
}

/// Anteil der Blattbreite, den der QR am Drucker einnimmt (nativ, sonst Bildweg).
double qrBlattAnteil(String nutzlast, KeckPaperSize papier, {QrModulGroesse groesse = QrModulGroesse.auto}) {
  if (nutzlast.isEmpty) return 0;
  final module = qrModulAnzahlWieNpm(nutzlast);
  final mass = QrMass.berechne(papierbreitePunkte: papier.druckPunkte, moduleAnzahl: module, groesse: groesse);
  if (mass.passt) return mass.breitePunkte / papier.druckPunkte;
  final gesamt = module + 2 * QrMass.ruhezoneModule;
  final punkte = math.max(1, math.min(groesse.deckelPunkte, papier.druckPunkte ~/ gesamt));
  return (gesamt * punkte) / papier.druckPunkte;
}

String _zentriert(String text, int zeichen) {
  final t = text.length > zeichen ? text.substring(0, zeichen) : text;
  final links = (zeichen - t.length) ~/ 2;
  return ' ' * links + t + ' ' * (zeichen - t.length - links);
}

BelegBlatt belegBlatt(BelegLayout layout,
    {int? zeichen, BlattLogo? logo, bool marke = false, QrModulGroesse qrGroesse = QrModulGroesse.auto}) {
  final raster = BelegRaster.render(layout, zeichen: zeichen);
  final n = raster.zeichen;
  final papier = papierFuerZeichen(n, layout.paperSize);
  final leerzeile = BlattZeile(text: ' ' * n, fett: false, leer: true);
  BlattBlock block(RasterZeile z) => z.art == RasterArt.qr
      ? BlattQr(nutzlast: z.qr ?? '', breiteAnteil: qrBlattAnteil(z.qr ?? '', papier, groesse: qrGroesse))
      : BlattZeile(text: z.text, fett: z.bold, leer: z.art == RasterArt.space);

  final bloecke = <BlattBlock>[];
  var i = 0;
  if (logo != null) {
    // Fuehrende Aufdrucke bleiben ganz oben; die Leerzeilen um das Logo sind Vertrag.
    while (i < raster.lines.length && raster.lines[i].art == RasterArt.banner) {
      bloecke.add(block(raster.lines[i]));
      i += 1;
    }
    if (i > 0) bloecke.add(leerzeile);
    final mass = logoMass(logo, n);
    bloecke.add(BlattLogoBlock(breiteAnteil: mass.breiteAnteil, hoeheZeilen: mass.hoeheZeilen));
    bloecke.add(leerzeile);
  }
  for (; i < raster.lines.length; i++) {
    bloecke.add(block(raster.lines[i]));
  }
  if (marke) {
    bloecke.add(leerzeile);
    bloecke.add(BlattZeile(text: _zentriert(markeText, n), fett: false, leer: false));
  }
  return BelegBlatt(zeichen: n, bloecke: bloecke);
}
