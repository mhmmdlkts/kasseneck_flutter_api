import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/models/receipt_sheet.dart';
import 'package:kasseneck_api/models/receipt_layout.dart';
import 'package:kasseneck_api/src/printing/qr_groesse.dart';

/// Zwilling von `belegBlatt` (npm 0.14.0): fuer jede Golden-Fixture muss das
/// Blatt mit Probe-Logo (M, 300x120) und Marke Block fuer Block der
/// `sheet32.json` bzw. `sheet48.json` des Pakets entsprechen, in der
/// englischen Form des Vertrags (`BelegBlatt.toJson`).
final _wurzel = Directory('test/fixtures/vertrag');

void _gleich(Object? ist, Object? soll, String wo) {
  if (soll is num) {
    expect(ist, isA<num>(), reason: wo);
    expect((ist as num).toDouble(), closeTo(soll.toDouble(), 1e-12), reason: wo);
  } else if (soll is Map) {
    expect((ist as Map).keys.toSet(), soll.keys.toSet(), reason: wo);
    for (final k in soll.keys) {
      _gleich(ist[k], soll[k], '$wo.$k');
    }
  } else if (soll is List) {
    expect((ist as List).length, soll.length, reason: wo);
    for (var i = 0; i < soll.length; i++) {
      _gleich(ist[i], soll[i], '$wo[$i]');
    }
  } else {
    expect(ist, soll, reason: wo);
  }
}

void main() {
  final manifest = jsonDecode(File('${_wurzel.path}/manifest.json').readAsStringSync()) as Map<String, dynamic>;
  final namen = (manifest['receipts'] as Map<String, dynamic>).keys.toList()..sort();

  test('Golden: Blatt aller Fixtures mit Probe-Logo und Marke (32 und 48 Zeichen)', () {
    expect(namen.length, greaterThanOrEqualTo(31));
    for (final n in namen) {
      final layout = ReceiptLayout.fromJson(jsonDecode(File('${_wurzel.path}/expected/$n.lines.json').readAsStringSync()))!;
      for (final zeichen in [32, 48]) {
        final soll = jsonDecode(File('${_wurzel.path}/expected/$n.sheet$zeichen.json').readAsStringSync());
        final blatt = receiptSheet(layout, charsPerLine: zeichen, logo: const SheetLogo(size: SheetLogoSize.m, pixelWidth: 300, pixelHeight: 120), brandMark: true);
        _gleich(blatt.toJson(), soll, '$n@$zeichen');
      }
    }
  });

  test('Rot-Probe: ein Blatt ohne Marke ist nicht das Golden', () {
    final layout = ReceiptLayout.fromJson(jsonDecode(File('${_wurzel.path}/expected/sale-cash.lines.json').readAsStringSync()))!;
    final soll = jsonDecode(File('${_wurzel.path}/expected/sale-cash.sheet48.json').readAsStringSync()) as Map;
    final ohne = receiptSheet(layout, charsPerLine: 48, logo: const SheetLogo(size: SheetLogoSize.m, pixelWidth: 300, pixelHeight: 120));
    expect(ohne.blocks.length, isNot((soll['blocks'] as List).length));
  });

  test('logoMass nie hochgerechnet, Stufen wie npm, ausKuerzel faellt auf M', () {
    final klein = logoDimensions(const SheetLogo(size: SheetLogoSize.xl, pixelWidth: 100, pixelHeight: 50), 48);
    expect(klein.widthFraction, closeTo(100 / 576, 1e-12));
    expect(klein.heightLines, closeTo(50 / 24, 1e-12));
    expect(logoRasterSize(klein, 48), (width: 100, height: 50));
    expect(SheetLogoSize.values.map((s) => '${s.code}:${s.widthFraction}x${s.heightLines}').toList(), ['S:0.42x5', 'M:0.62x8', 'L:0.8x12', 'XL:0.94x16']);
    expect(SheetLogoSize.fromCode('XL'), SheetLogoSize.xl);
    expect(SheetLogoSize.fromCode(null), SheetLogoSize.m);
    expect(() => logoDimensions(const SheetLogo(size: SheetLogoSize.m, pixelWidth: 0, pixelHeight: 1), 48), throwsArgumentError);
  });

  test('qrBlattAnteil wie npm: 109 Byte -> 45 Module, 80 mm auto 6 Punkte (auto heisst in beiden Paketen dasselbe)', () {
    const qr = '_R1-AT1_KASSE1_AT0-KASSE1-42_2026-08-13T00:30:00_5,00_2,70_0,00_0,00_0,00_UMSATZ_VORGAENGER_5A1C3E07_SIGNATUR';
    expect(qrModuleCount(qr), 45);
    expect(qrSheetWidthFraction(qr, KeckPaperSize.mm80), 53 * 6 / 576);
    expect(qrSheetWidthFraction(qr, KeckPaperSize.mm80, moduleSize: QrModuleSize.small), 53 * 4 / 576);
    expect(qrSheetWidthFraction('', KeckPaperSize.mm58), 0);
    expect(paperSizeForChars(32, 'mm80'), KeckPaperSize.mm58);
    expect(paperSizeForChars(40, 'mm80'), KeckPaperSize.mm80);
  });

  test('zwei Modulzaehler, eine Zahl: qrModulAnzahlWieNpm == QrMass.modulAnzahl an jeder Versionsgrenze', () {
    // Die Grenzen werden aus der Tabelle des Blatts abgelesen, nicht
    // abgeschrieben: wo die Modulzahl springt, liegt die Kapazitaet. An
    // Kapazitaet und Kapazitaet + 1 (v1..v39) muss die QR-Bibliothek dasselbe
    // sagen -- sonst rechnete das Blatt mit einem anderen Symbol, als Bon und
    // Schirm zeichnen. ASCII-Nutzlast, also Byte-Modus wie beim Beleg-QR.
    String nutzlast(int n) => 'a' * n;
    final kapazitaeten = <int>[
      for (var n = 1; n < 2331; n++)
        if (qrModuleCount(nutzlast(n + 1)) != qrModuleCount(nutzlast(n))) n,
      2331,
    ];
    expect(kapazitaeten, hasLength(40));
    expect(kapazitaeten.first, 14);
    for (final (i, kap) in kapazitaeten.indexed) {
      final version = i + 1;
      expect(qrModuleCount(nutzlast(kap)), 17 + 4 * version, reason: 'v$version, Kapazitaet $kap');
      expect(QrMetrics.moduleCount(nutzlast(kap)), qrModuleCount(nutzlast(kap)), reason: 'v$version: $kap Byte');
      if (version < 40) {
        expect(QrMetrics.moduleCount(nutzlast(kap + 1)), qrModuleCount(nutzlast(kap + 1)), reason: 'v$version: ${kap + 1} Byte');
      }
    }
    // Hinter v40 gibt es kein Symbol: das Blatt lehnt ab. `QrMass.modulAnzahl`
    // meldet dort (qr 3.0.2) noch 177 Module statt abzulehnen -- ausserhalb
    // jeder druckbaren Groesse, aber keine gemeinsame Zahl mehr.
    expect(() => qrModuleCount(nutzlast(2332)), throwsArgumentError);
  });

  test('qrBlattAnteil: Inhalt ohne passende QR-Version ergibt 0 statt zu werfen, Grenze in Byte wie npm', () {
    expect(qrFitsInVersion('x' * 2331), isTrue);
    expect(qrFitsInVersion('x' * 2332), isFalse);
    // Mehrbyte: 777 Euro-Zeichen sind 2331 Byte, eines mehr passt nicht mehr.
    expect(qrFitsInVersion('€' * 777), isTrue);
    expect(qrFitsInVersion('€' * 777 + 'x'), isFalse);
    expect(qrSheetWidthFraction('x' * 2332, KeckPaperSize.mm80), 0);
    expect(qrSheetWidthFraction('x' * 2331, KeckPaperSize.mm80), greaterThan(0));
  });

  test('belegBlatt: QR-Inhalt ohne passende Version wirft nicht, der QR-Block bleibt mit Anteil 0', () {
    final layout = ReceiptLayout(paperSize: 'mm80', ruleset: 2, lines: [
      LayoutTextLine(text: 'Firma', align: LayoutAlign.center, bold: true),
      LayoutQrLine(data: 'x' * 2332),
    ]);
    final blatt = receiptSheet(layout, charsPerLine: 48);
    final qr = blatt.blocks.whereType<SheetQr>().single;
    expect(qr.widthFraction, 0);
  });
}
