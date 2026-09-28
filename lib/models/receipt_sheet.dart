/// Das Beleg-Blatt (Zwilling von `receiptSheet` in `@kreiseck/kasseneck-api`
/// ab 0.14.0): die vollstaendige Folge dessen, was auf dem Papier steht --
/// Rasterzeilen, Firmenlogo, QR und Marke, Groessen als Anteil der Blattbreite
/// und in Zeilen. Jeder Zeichner (Bon, Bildschirm) setzt nur noch das Blatt.
///
/// Masseinheit ist der Druckkopf: ein Zeichen 12 Punkte, eine Zeile 24.
/// Die Goldens `test/fixtures/vertrag/expected/*.sheet32.json|sheet48.json`
/// halten beide Seiten gleich; die Rechenreihenfolge nicht umstellen.
library;

import 'dart:convert' show utf8;
import 'dart:math' as math;

import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/models/receipt_layout.dart';
import 'package:kasseneck_api/models/receipt_grid.dart';
import 'package:kasseneck_api/models/brand_mark_data.dart';
import 'package:kasseneck_api/src/printing/qr_groesse.dart';

enum SheetLogoSize {
  s('S', 0.42, 5),
  m('M', 0.62, 8),
  l('L', 0.8, 12),
  xl('XL', 0.94, 16);

  final String code;
  final double widthFraction;
  final int heightLines;
  const SheetLogoSize(this.code, this.widthFraction, this.heightLines);

  /// Die Einstellung `logoSkala` des Betriebs; fehlt sie oder ist sie unbekannt, gilt M.
  static SheetLogoSize fromCode(String? code) =>
      SheetLogoSize.values.firstWhere((s) => s.code == code, orElse: () => SheetLogoSize.m);
}

const int dotsPerChar = 12;
const int dotsPerLine = 24;

class SheetLogo {
  final SheetLogoSize size;
  final int pixelWidth;
  final int pixelHeight;
  const SheetLogo({required this.size, required this.pixelWidth, required this.pixelHeight});
}

class LogoDimensions {
  final double widthFraction;
  final double heightLines;
  const LogoDimensions({required this.widthFraction, required this.heightLines});
}

sealed class SheetBlock {
  const SheetBlock();

  /// Der Block in der Form des Vertrags (`expected/*.sheet*.json`, npm 1.0):
  /// `kind` `line`/`logo`/`qr`/`brandMark`, Felder englisch.
  Map<String, Object> toJson() => switch (this) {
        SheetLine(:final text, :final bold, :final blank) => {'kind': 'line', 'text': text, 'bold': bold, 'blank': blank},
        SheetLogoBlock(:final widthFraction, :final heightLines) => {
            'kind': 'logo',
            'widthFraction': widthFraction,
            'heightLines': heightLines,
          },
        SheetQr(:final payload, :final widthFraction) => {'kind': 'qr', 'payload': payload, 'widthFraction': widthFraction},
        SheetBrandMark(:final width, :final height) => {'kind': 'brandMark', 'width': width, 'height': height},
      };
}

class SheetLine extends SheetBlock {
  final String text;
  final bool bold;
  final bool blank;
  const SheetLine({required this.text, required this.bold, required this.blank});
}

class SheetLogoBlock extends SheetBlock {
  final double widthFraction;
  final double heightLines;
  const SheetLogoBlock({required this.widthFraction, required this.heightLines});
}

class SheetQr extends SheetBlock {
  final String payload;
  final double widthFraction;
  const SheetQr({required this.payload, required this.widthFraction});
}

/// Das Kasseneck-Logo am Belegende, als Rasterbild fest in [width] x [height]
/// Druckpunkten -- diese Masse kommen aus [brandMarkRasters], nicht aus einem
/// Anteil der Blattbreite: das Raster liegt fertig vor (Vertrag), nur welches
/// der beiden Masse gilt, entscheidet die Papierbreite.
class SheetBrandMark extends SheetBlock {
  final int width;
  final int height;
  const SheetBrandMark({required this.width, required this.height});
}

class ReceiptSheet {
  final int charsPerLine;
  final List<SheetBlock> blocks;
  const ReceiptSheet({required this.charsPerLine, required this.blocks});

  /// Das Blatt in der Form des Vertrags: `charsPerLine` und `blocks`.
  Map<String, Object> toJson() => {'charsPerLine': charsPerLine, 'blocks': [for (final b in blocks) b.toJson()]};
}

KeckPaperSize paperSizeForChars(int chars, String fallback) {
  if (chars == KeckPaperSize.mm58.defaultCharCount) return KeckPaperSize.mm58;
  if (chars == KeckPaperSize.mm80.defaultCharCount) return KeckPaperSize.mm80;
  return fallback == 'mm80' ? KeckPaperSize.mm80 : KeckPaperSize.mm58;
}

/// Ins Kaestchen der Stufe eingepasst, nie hochgerechnet (1 Bildpixel hoechstens 1 Druckpunkt).
LogoDimensions logoDimensions(SheetLogo logo, int chars) {
  if (logo.pixelWidth <= 0 || logo.pixelHeight <= 0) {
    throw ArgumentError('Logo ohne Pixelmass');
  }
  final blattPunkte = chars * dotsPerChar;
  final faktor = math.min(
    math.min((logo.size.widthFraction * blattPunkte) / logo.pixelWidth, (logo.size.heightLines * dotsPerLine) / logo.pixelHeight),
    1.0,
  );
  return LogoDimensions(
    widthFraction: (logo.pixelWidth * faktor) / blattPunkte,
    heightLines: (logo.pixelHeight * faktor) / dotsPerLine,
  );
}

({int width, int height}) logoRasterSize(LogoDimensions dimensions, int chars) => (
      width: math.max(1, (dimensions.widthFraction * chars * dotsPerChar).round()),
      height: math.max(1, (dimensions.heightLines * dotsPerLine).round()),
    );

/// Byte-Kapazitaet je QR-Version bei Korrektur M (ISO/IEC 18004) -- dieselbe
/// Tabelle wie `qrModulAnzahl` im npm-Paket. Bewusst nicht `QrMetrics.moduleCount`:
/// das Blatt muss dieselben Zahlen liefern wie die npm-Goldens.
const List<int> _byteKapazitaetM = [
  14, 26, 42, 62, 84, 106, 122, 152, 180, 213,
  251, 287, 331, 362, 412, 450, 504, 560, 624, 666,
  711, 779, 857, 911, 997, 1059, 1125, 1190, 1264, 1370,
  1452, 1538, 1628, 1722, 1809, 1911, 1989, 2099, 2213, 2331,
];

int qrModuleCount(String payload) {
  final laenge = utf8.encode(payload).length;
  for (var i = 0; i < _byteKapazitaetM.length; i++) {
    if (laenge <= _byteKapazitaetM[i]) return 17 + 4 * (i + 1);
  }
  throw ArgumentError('QR-Inhalt ist zu lang');
}

/// Ob [payload] in irgendeine QR-Version bei Korrektur M passt -- dieselbe
/// Tabelle wie [qrModuleCount], aber ohne zu werfen (npm `qrPasstInVersion`).
bool qrFitsInVersion(String payload) => utf8.encode(payload).length <= _byteKapazitaetM.last;

/// Anteil der Blattbreite, den der QR am Drucker einnimmt (nativ, sonst Bildweg).
double qrSheetWidthFraction(String payload, KeckPaperSize paper, {QrModuleSize moduleSize = QrModuleSize.auto}) {
  if (payload.isEmpty) return 0;
  // Ein Inhalt, der in keine QR-Version passt, liesse [qrModuleCount]
  // werfen und risse jeden Zeichner mit (Widget, Bon). 0 wie bei leerer
  // Nutzlast: der Beleg steht ohne QR, statt gar nicht zu stehen.
  if (!qrFitsInVersion(payload)) return 0;
  final module = qrModuleCount(payload);
  final mass = QrMetrics.compute(paperWidthDots: paper.printWidthDots, moduleCount: module, moduleSize: moduleSize);
  if (mass.fits) return mass.widthDots / paper.printWidthDots;
  final gesamt = module + 2 * QrMetrics.quietZoneModules;
  final punkte = math.max(1, math.min(moduleSize.capDots, paper.printWidthDots ~/ gesamt));
  return (gesamt * punkte) / paper.printWidthDots;
}

ReceiptSheet receiptSheet(ReceiptLayout layout,
    {int? charsPerLine, SheetLogo? logo, bool brandMark = false, QrModuleSize qrModuleSize = QrModuleSize.auto}) {
  final raster = ReceiptGrid.render(layout, charsPerLine: charsPerLine);
  final n = raster.charsPerLine;
  final papier = paperSizeForChars(n, layout.paperSize);
  final leerzeile = SheetLine(text: ' ' * n, bold: false, blank: true);
  SheetBlock block(GridLine z) => z.kind == GridLineKind.qr
      ? SheetQr(payload: z.qr ?? '', widthFraction: qrSheetWidthFraction(z.qr ?? '', papier, moduleSize: qrModuleSize))
      : SheetLine(text: z.text, bold: z.bold, blank: z.kind == GridLineKind.space);

  final bloecke = <SheetBlock>[];
  var i = 0;
  if (logo != null) {
    // Fuehrende Aufdrucke bleiben ganz oben; die Leerzeilen um das Logo sind Vertrag.
    while (i < raster.lines.length && raster.lines[i].kind == GridLineKind.banner) {
      bloecke.add(block(raster.lines[i]));
      i += 1;
    }
    if (i > 0) bloecke.add(leerzeile);
    final mass = logoDimensions(logo, n);
    bloecke.add(SheetLogoBlock(widthFraction: mass.widthFraction, heightLines: mass.heightLines));
    bloecke.add(leerzeile);
  }
  for (; i < raster.lines.length; i++) {
    bloecke.add(block(raster.lines[i]));
  }
  if (brandMark) {
    // Das Raster deckt nur die beiden bekannten Papierbreiten ab
    // (markeRaster). Faende sich hier eine dritte, faellt die Marke weg statt
    // ein Raster in falscher Groesse zu drucken -- derselbe Grundsatz wie
    // beim Firmenlogo: eine Marke ist Zierde, der Beleg ist Pflicht.
    final raster = brandMarkRasters[papier];
    if (raster != null) {
      bloecke.add(leerzeile);
      bloecke.add(SheetBrandMark(width: raster.width, height: raster.height));
    }
  }
  return ReceiptSheet(charsPerLine: n, blocks: bloecke);
}
