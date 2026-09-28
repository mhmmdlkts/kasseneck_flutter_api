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

  /// Die Zeile in der Form des Vertrags (`expected/*.lines.json`).
  Map<String, Object> toJson() => switch (this) {
        BelegText(:final text, :final align, :final bold) => {'kind': 'text', 'text': text, 'align': align.name, 'bold': bold},
        BelegSpalten(:final columns) => {
            'kind': 'columns',
            'columns': [for (final c in columns) {'text': c.text, 'width': c.width, 'align': c.align.name}],
          },
        BelegLinie(:final char) => {'kind': 'rule', 'char': char},
        BelegLeerraum(:final lines) => {'kind': 'space', 'lines': lines},
        BelegQr(:final data) => {'kind': 'qr', 'data': data},
        BelegBanner(:final text, :final tone) => {'kind': 'banner', 'text': text, 'tone': tone.wire},
      };

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
        return BelegBanner(text: (j['text'] ?? '').toString(), tone: LayoutBannerTone.aus(j['tone']));
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

/// Ton einer hervorgehobenen Zeile, Drahtwert `tone` (Katalog `LAYOUT_TON`):
/// `receipt_type` fuer die Belegart (STORNOBELEG …), `warning` fuer
/// TESTKASSE/TESTSIGNATUR und den Ausfall der Signatureinheit.
enum LayoutBannerTone {
  receiptType('receipt_type'),
  warning('warning');

  const LayoutBannerTone(this.wire);

  /// Der Wert am Draht.
  final String wire;

  /// Liest den Drahtwert. Ein unbekannter kuenftiger Ton zeigt die Zeile als
  /// Belegart-Aufdruck: sichtbar bleibt sie so oder so, nur die Farbe fehlt.
  static LayoutBannerTone aus(Object? wert) => wert == warning.wire ? warning : receiptType;
}

/// Hervorgehobene Zeile: Belegart (STORNOBELEG …) oder Warnung
/// (TESTKASSE/TESTSIGNATUR). Im Raster steht sie zwischen zwei `=`-Rahmenzeilen.
class BelegBanner extends BelegZeile {
  final String text;
  final LayoutBannerTone tone;
  const BelegBanner({required this.text, this.tone = LayoutBannerTone.receiptType});

  /// Warnung (TESTKASSE, TESTSIGNATUR, Ausfall) statt Belegart?
  bool get warning => tone == LayoutBannerTone.warning;
}

class BelegLayout {
  final List<BelegZeile> lines;
  /// `mm58` oder `mm80` — wonach die Spaltenbreiten der USt-Tabelle gewählt wurden.
  final String paperSize;
  /// Version des Layout-Regelwerks (Drahtwert `ruleset`, heute 2). Fehlt er
  /// (Backend vor dem Regelwerk), gilt 1.
  final int ruleset;

  const BelegLayout({required this.lines, required this.paperSize, required this.ruleset});

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
      ruleset: (json['ruleset'] is num) ? (json['ruleset'] as num).toInt() : 1,
    );
  }

  /// Das Layout in der Form des Vertrags (`paperSize`, `ruleset`, `lines`).
  Map<String, Object> toJson() => {
        'paperSize': paperSize,
        'ruleset': ruleset,
        'lines': [for (final z in lines) z.toJson()],
      };

  /// Alle Banner-Texte (Belegart/Warnungen) — für Tests und Anzeigen.
  List<String> get bannerTexte => lines.whereType<BelegBanner>().map((b) => b.text).toList();

  /// Nutzlast des RKSV-QR (erste QR-Zeile) oder null.
  String? get qrDaten => lines.whereType<BelegQr>().map((q) => q.data).cast<String?>().firstWhere((_) => true, orElse: () => null);
}
