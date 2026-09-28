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

enum LayoutAlign { left, center, right }

LayoutAlign _align(dynamic v) {
  switch (v) {
    case 'center':
      return LayoutAlign.center;
    case 'right':
      return LayoutAlign.right;
    default:
      return LayoutAlign.left;
  }
}

sealed class LayoutLine {
  const LayoutLine();

  /// Die Zeile in der Form des Vertrags (`expected/*.lines.json`).
  Map<String, Object> toJson() => switch (this) {
        LayoutTextLine(:final text, :final align, :final bold) => {'kind': 'text', 'text': text, 'align': align.name, 'bold': bold},
        LayoutColumnsLine(:final columns) => {
            'kind': 'columns',
            'columns': [for (final c in columns) {'text': c.text, 'width': c.width, 'align': c.align.name}],
          },
        LayoutRuleLine(:final char) => {'kind': 'rule', 'char': char},
        LayoutSpaceLine(:final lines) => {'kind': 'space', 'lines': lines},
        LayoutQrLine(:final data) => {'kind': 'qr', 'data': data},
        LayoutBannerLine(:final text, :final tone) => {'kind': 'banner', 'text': text, 'tone': tone.wire},
      };

  /// Liest eine Zeile; `null` für unbekannte Arten.
  static LayoutLine? fromJson(Map<String, dynamic> j) {
    switch (j['kind']) {
      case 'text':
        return LayoutTextLine(text: (j['text'] ?? '').toString(), align: _align(j['align']), bold: j['bold'] == true);
      case 'columns':
        final spalten = ((j['columns'] as List?) ?? const [])
            .map((c) => LayoutColumn(
                  text: (c['text'] ?? '').toString(),
                  width: (c['width'] is num) ? (c['width'] as num).toInt() : 1,
                  align: _align(c['align']),
                ))
            .toList();
        return LayoutColumnsLine(spalten);
      case 'rule':
        return LayoutRuleLine(char: (j['char'] ?? '-').toString());
      case 'space':
        return LayoutSpaceLine(lines: (j['lines'] is num) ? (j['lines'] as num).toInt() : 1);
      case 'qr':
        return LayoutQrLine(data: (j['data'] ?? '').toString());
      case 'banner':
        return LayoutBannerLine(text: (j['text'] ?? '').toString(), tone: LayoutBannerTone.fromWire(j['tone']));
      default:
        return null;
    }
  }
}

class LayoutTextLine extends LayoutLine {
  final String text;
  final LayoutAlign align;
  final bool bold;
  const LayoutTextLine({required this.text, this.align = LayoutAlign.left, this.bold = false});
}

class LayoutColumn {
  final String text;
  /// Zwölftel-Anteil der Breite (1..12).
  final int width;
  final LayoutAlign align;
  const LayoutColumn({required this.text, required this.width, this.align = LayoutAlign.left});
}

class LayoutColumnsLine extends LayoutLine {
  final List<LayoutColumn> columns;
  const LayoutColumnsLine(this.columns);
}

class LayoutRuleLine extends LayoutLine {
  final String char;
  const LayoutRuleLine({this.char = '-'});
}

class LayoutSpaceLine extends LayoutLine {
  final int lines;
  const LayoutSpaceLine({this.lines = 1});
}

class LayoutQrLine extends LayoutLine {
  final String data;
  const LayoutQrLine({required this.data});
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
  static LayoutBannerTone fromWire(Object? value) => value == warning.wire ? warning : receiptType;
}

/// Hervorgehobene Zeile: Belegart (STORNOBELEG …) oder Warnung
/// (TESTKASSE/TESTSIGNATUR). Im Raster steht sie zwischen zwei `=`-Rahmenzeilen.
class LayoutBannerLine extends LayoutLine {
  final String text;
  final LayoutBannerTone tone;
  const LayoutBannerLine({required this.text, this.tone = LayoutBannerTone.receiptType});

  /// Warnung (TESTKASSE, TESTSIGNATUR, Ausfall) statt Belegart?
  bool get warning => tone == LayoutBannerTone.warning;
}

class ReceiptLayout {
  final List<LayoutLine> lines;
  /// `mm58` oder `mm80` — wonach die Spaltenbreiten der USt-Tabelle gewählt wurden.
  final String paperSize;
  /// Version des Layout-Regelwerks (Drahtwert `ruleset`, heute 2). Fehlt er
  /// (Backend vor dem Regelwerk), gilt 1.
  final int ruleset;

  const ReceiptLayout({required this.lines, required this.paperSize, required this.ruleset});

  static ReceiptLayout? fromJson(dynamic json) {
    if (json is! Map) return null;
    final roh = json['lines'];
    if (roh is! List) return null;
    final lines = <LayoutLine>[];
    for (final z in roh) {
      if (z is Map) {
        final zeile = LayoutLine.fromJson(Map<String, dynamic>.from(z));
        if (zeile != null) lines.add(zeile);
      }
    }
    return ReceiptLayout(
      lines: lines,
      // Ohne Angabe 80 mm: das Server-Layout hat immer diese Breite.
      paperSize: (json['paperSize'] ?? 'mm80').toString(),
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
  List<String> get bannerTexts => lines.whereType<LayoutBannerLine>().map((b) => b.text).toList();

  /// Nutzlast des RKSV-QR (erste QR-Zeile) oder null.
  String? get qrPayload => lines.whereType<LayoutQrLine>().map((q) => q.data).cast<String?>().firstWhere((_) => true, orElse: () => null);
}
