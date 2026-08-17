/// Beleg-Zeilenmodell (Zwilling von `@kreiseck/kasseneck-api/receipt`
/// `ReceiptLayout`): das Backend liefert es bei `getReceipt` als `layout` mit,
/// damit App, Bondrucker, Browser-Kasse und PDF **dieselben Zeilen** zeigen —
/// Kopf/Fuß wie beim Ausstellen des Belegs, Belegart-Aufdruck (STORNOBELEG,
/// TRAININGSBELEG, NULLBELEG …), reduzierter Nullbeleg, Testkasse/Testsignatur.
///
/// Zeilenarten: `text`, `columns`, `rule`, `space`, `qr`, `banner`.
/// Unbekannte Arten (künftiges Regelwerk) werden beim Lesen übersprungen, nie
/// als Fehler behandelt — ein Beleg muss sich immer zeigen lassen.
library;

enum BelegAlign { left, center, right }

BelegAlign _align(dynamic v) {
  switch (v) {
    case 'center':
      return BelegAlign.center;
    case 'right':
      return BelegAlign.right;
    default:
      return BelegAlign.left;
  }
}

sealed class BelegZeile {
  const BelegZeile();

  /// Liest eine Zeile; `null` für unbekannte Arten.
  static BelegZeile? fromJson(Map<String, dynamic> j) {
    switch (j['kind']) {
      case 'text':
        return BelegText(text: (j['text'] ?? '').toString(), align: _align(j['align']), bold: j['bold'] == true);
      case 'columns':
        final spalten = ((j['columns'] as List?) ?? const [])
            .map((c) => BelegSpalte(
                  text: (c['text'] ?? '').toString(),
                  width: (c['width'] is num) ? (c['width'] as num).toInt() : 1,
                  align: _align(c['align']),
                ))
            .toList();
        return BelegSpalten(spalten);
      case 'rule':
        return BelegLinie(char: (j['char'] ?? '-').toString());
      case 'space':
        return BelegLeerraum(lines: (j['lines'] is num) ? (j['lines'] as num).toInt() : 1);
      case 'qr':
        return BelegQr(data: (j['data'] ?? '').toString());
      case 'banner':
        return BelegBanner(text: (j['text'] ?? '').toString(), warnung: j['ton'] == 'warnung');
      default:
        return null;
    }
  }
}

class BelegText extends BelegZeile {
  final String text;
  final BelegAlign align;
  final bool bold;
  const BelegText({required this.text, this.align = BelegAlign.left, this.bold = false});
}

class BelegSpalte {
  final String text;
  /// Zwölftel-Anteil der Breite (1..12).
  final int width;
  final BelegAlign align;
  const BelegSpalte({required this.text, required this.width, this.align = BelegAlign.left});
}

class BelegSpalten extends BelegZeile {
  final List<BelegSpalte> columns;
  const BelegSpalten(this.columns);
}

class BelegLinie extends BelegZeile {
  final String char;
  const BelegLinie({this.char = '-'});
}

class BelegLeerraum extends BelegZeile {
  final int lines;
  const BelegLeerraum({this.lines = 1});
}

class BelegQr extends BelegZeile {
  final String data;
  const BelegQr({required this.data});
}

/// Hervorgehobene Zeile: Belegart (STORNOBELEG …) oder Warnung
/// (TESTKASSE/TESTSIGNATUR — invers).
class BelegBanner extends BelegZeile {
  final String text;
  final bool warnung;
  const BelegBanner({required this.text, this.warnung = false});
}

class BelegLayout {
  final List<BelegZeile> lines;
  /// `mm58` oder `mm80` — wonach die Spaltenbreiten der USt-Tabelle gewählt wurden.
  final String paperSize;
  /// Version des Layout-Regelwerks (heute 1).
  final int regelwerk;

  const BelegLayout({required this.lines, required this.paperSize, required this.regelwerk});

  static BelegLayout? fromJson(dynamic json) {
    if (json is! Map) return null;
    final roh = json['lines'];
    if (roh is! List) return null;
    final lines = <BelegZeile>[];
    for (final z in roh) {
      if (z is Map) {
        final zeile = BelegZeile.fromJson(Map<String, dynamic>.from(z));
        if (zeile != null) lines.add(zeile);
      }
    }
    return BelegLayout(
      lines: lines,
      paperSize: (json['paperSize'] ?? 'mm58').toString(),
      regelwerk: (json['regelwerk'] is num) ? (json['regelwerk'] as num).toInt() : 1,
    );
  }

  /// Alle Banner-Texte (Belegart/Warnungen) — für Tests und Anzeigen.
  List<String> get bannerTexte => lines.whereType<BelegBanner>().map((b) => b.text).toList();

  /// Nutzlast des RKSV-QR (erste QR-Zeile) oder null.
  String? get qrDaten => lines.whereType<BelegQr>().map((q) => q.data).cast<String?>().firstWhere((_) => true, orElse: () => null);
}
