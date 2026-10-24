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

import '../services/vienna_time.dart';

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
        LayoutColumnsLine(:final columns, :final bold) => {
            'kind': 'columns',
            'columns': [for (final c in columns) {'text': c.text, 'width': c.width, 'align': c.align.name}],
            if (bold) 'bold': true,
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
        return LayoutColumnsLine(spalten, bold: j['bold'] == true);
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

  /// Die ganze Zeile fett (z. B. „Bleibt in der Kassenlade“ auf dem Z-Bon); im
  /// Bauplan (`toJson`) steht `bold` nur, wenn `true` – wie im JS-Paket.
  final bool bold;
  const LayoutColumnsLine(this.columns, {this.bold = false});
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

/// Beschriftung der Duplikat-Zeile; derselbe Text im npm-Paket.
const String _duplikatAm = 'Duplikat am:';

/// Spaltenbreiten in Zwölfteln. 5:7 setzt Beschriftung (12 Zeichen) und Zeit
/// (19 Zeichen) auf 32 und 48 Zeichen ohne Umbruch in eine Zeile, den Wert am
/// rechten Rand wie bei `Datum:`: 13 + 19 bzw. 20 + 28 Zeichen. Die Breiten
/// von `Beleg-ID:` (6:6) und `Datum:` (4:8) reichen auf 32 Zeichen nicht.
const int _duplikatLinks = 5;
const int _duplikatRechts = 7;

bool _istZeile(LayoutLine z, String beschriftung) => z is LayoutColumnsLine && z.columns.isNotEmpty && z.columns.first.text == beschriftung;

/// Zeitpunkt als `TT.MM.JJJJ HH:MM:SS` in Wiener Zeit; Bruchteile fallen weg.
///
/// Bewusst nicht über [ViennaTime.toWallClock]: das baut ein lokales
/// `DateTime`, und eine Wiener Uhrzeit, die es in der Zeitzone des Geräts
/// nicht gibt (Sommerzeitlücke dort), verschöbe sich um eine Stunde. Die
/// Felder kommen darum aus einem UTC-Wert, der um den Wiener Versatz
/// verschoben ist.
String _wienerZeit(DateTime zeitpunkt) {
  final utc = zeitpunkt.toUtc();
  final t = utc.add(ViennaTime.offsetAt(utc));
  String zwei(int n) => n.toString().padLeft(2, '0');
  return '${zwei(t.day)}.${zwei(t.month)}.${t.year} ${zwei(t.hour)}:${zwei(t.minute)}:${zwei(t.second)}';
}

/// Kennzeichnet einen Nachdruck als **Belegduplikat** (Zwilling von
/// `markAsDuplicate` in `@kreiseck/kasseneck-api/receipt`).
/// Registrierkassen-Erlass BMF-AV Nr. 2/2026, Abschnitt 4.5.6: „Ein
/// Belegduplikat ist als solches zu bezeichnen, nicht nochmals zu signieren,
/// nicht neuerlich im Datenerfassungsprotokoll aufzunehmen und darf zu keiner
/// Veränderung des Umsatzzählers führen.“ Signatur, DEP und Zähler bleiben
/// ohnehin unberührt, weil ein Nachdruck den gespeicherten Beleg druckt; diese
/// Funktion liefert die Bezeichnung.
///
/// Die Kasse ruft sie bei **jedem** Nachdruck und bei „Kopie drucken“ mit dem
/// Zeitpunkt des Drucks auf, nie beim Erstdruck und nie für Mail, Link oder
/// PDF, und gibt das Ergebnis an denselben Druckweg
/// (`PrintPaper.setReceiptSheet`, `receiptSheet`, `KeckReceiptSheetWidget`).
///
/// Neu ist genau eine Zeile im Kennungsblock, direkt unter `Beleg-ID:`, in
/// der Spaltenform von `Datum:` (nicht fett, Wert rechtsbündig):
///
/// ```
/// Beleg-ID:          AT0-KASSE1-42
/// Duplikat am: 24.10.2026 14:10:05
/// ```
///
/// [printedAt] ist ein Zeitpunkt (UTC oder lokal, gleich); gedruckt wird er
/// in Wiener Zeit (Sommerzeit nach EU-Regel), nie in der Zeitzone des Geräts.
/// Ohne Spaltenzeile `Beleg-ID:` (Schicht-Bons) steht die Zeile ganz oben.
/// Alles andere bleibt Zeile für Zeile wie beim Erstdruck.
///
/// Reine Funktion: die Eingabe bleibt unangetastet, das Ergebnis trägt eine
/// eigene Zeilenliste und je Spaltenzeile eine eigene Spaltenliste (wie im
/// npm-Paket); wer am Duplikat dreht, dreht nie am Erstdruck. Trägt das
/// Layout schon eine Zeile `Duplikat am:`, bekommt nur sie die neue Zeit (der
/// letzte Nachdruck gilt); es bleibt bei einer Zeile.
ReceiptLayout markAsDuplicate(ReceiptLayout layout, {required DateTime printedAt}) {
  final neu = LayoutColumnsLine([
    const LayoutColumn(text: _duplikatAm, width: _duplikatLinks),
    LayoutColumn(text: _wienerZeit(printedAt), width: _duplikatRechts, align: LayoutAlign.right),
  ]);
  final vorhanden = layout.lines.indexWhere((z) => _istZeile(z, _duplikatAm));
  final lines = [
    for (final z in layout.lines)
      if (!_istZeile(z, _duplikatAm)) z is LayoutColumnsLine ? LayoutColumnsLine([...z.columns], bold: z.bold) : z,
  ];
  final stelle = vorhanden >= 0 ? vorhanden : lines.indexWhere((z) => _istZeile(z, 'Beleg-ID:')) + 1;
  lines.insert(stelle, neu);
  return ReceiptLayout(lines: lines, paperSize: layout.paperSize, ruleset: layout.ruleset);
}
