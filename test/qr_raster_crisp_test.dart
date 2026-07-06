import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/src/printing/escpos/escpos.dart';
import 'package:qr/qr.dart';

/// Beweist die Schaerfe der direkt aus der QR-Modul-Matrix gerasterten Grafik
/// OHNE Drucker: reine schwarz/weiss-Pixel (kein Anti-Aliasing), korrekte
/// Dimension, deterministische Bytes.
void main() {
  const String data =
      '_R1-AT1_KASSE01_2024-01-01T10:00:00_1,00_0,00_0,00_0,00_0,00_abc==';

  /// Modulanzahl fuer denselben Input/EC-Level wie renderQrMatrix.
  int moduleCountOf(String d) {
    final qr = QrCode.fromData(
      data: d,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    return qr.moduleCount;
  }

  group('renderQrMatrix', () {
    test('jedes Pixel ist rein schwarz ODER rein weiss (kein Grauwert)', () {
      final RasterImage img = PrintPaper.renderQrMatrix(data);
      final px = img.rgba;
      for (int i = 0; i < px.length; i += 4) {
        final int r = px[i], g = px[i + 1], b = px[i + 2], a = px[i + 3];
        // Alpha immer voll deckend.
        expect(a, 255, reason: 'Alpha bei Byte $i muss 255 sein');
        // Reines Schwarz (0,0,0) oder reines Weiss (255,255,255).
        final bool black = r == 0 && g == 0 && b == 0;
        final bool white = r == 255 && g == 255 && b == 255;
        expect(black || white, isTrue,
            reason: 'Pixel bei Byte $i ist weder rein schwarz noch rein weiss: '
                '($r,$g,$b)');
      }
    });

    test('Dimension = (moduleCount + 8) * scale, quadratisch', () {
      const int size = 280;
      final int n = moduleCountOf(data);
      final int full = n + 8; // 4 Module Quiet-Zone rundum
      final int scale = (size / full).floor().clamp(2, 64);
      final int expectedDim = full * scale;

      final RasterImage img = PrintPaper.renderQrMatrix(data, size: size);
      expect(img.width, img.height, reason: 'muss quadratisch sein');
      expect(img.width, expectedDim);
      expect(img.rgba.length, expectedDim * expectedDim * 4);
    });

    test('Determinismus: gleicher Input -> identische Bytes', () {
      final a = PrintPaper.renderQrMatrix(data);
      final b = PrintPaper.renderQrMatrix(data);
      expect(a.width, b.width);
      expect(a.height, b.height);
      expect(a.rgba, orderedEquals(b.rgba));
    });

    test('scale ist ganzzahlig und passt in die gewuenschte Groesse', () {
      const int size = 280;
      final int n = moduleCountOf(data);
      final int full = n + 8;
      final RasterImage img = PrintPaper.renderQrMatrix(data, size: size);
      // dim/full muss exakt aufgehen (ganzzahliger Modul-Scale).
      expect(img.width % full, 0);
      final int scale = img.width ~/ full;
      expect(scale, greaterThanOrEqualTo(2));
      expect(scale, lessThanOrEqualTo(64));
      // Innerhalb des Wunsches (floor) -> nicht groesser als size (ausser Clamp).
      expect(img.width, lessThanOrEqualTo(size));
    });

    test('Finder-Pattern: obere-linke Ecke nach Quiet-Zone ist dunkel', () {
      const int size = 280;
      final int n = moduleCountOf(data);
      final int full = n + 8;
      final int scale = (size / full).floor().clamp(2, 64);
      final RasterImage img = PrintPaper.renderQrMatrix(data, size: size);

      // Erstes Modul des Finder-Patterns liegt bei Modul (0,0), also nach der
      // 4-Modul-Quiet-Zone. Pixel-Mitte dieses Moduls abtasten.
      final int px = (4 * scale) + scale ~/ 2;
      final int py = (4 * scale) + scale ~/ 2;
      final int idx = (py * img.width + px) * 4;
      expect(img.rgba[idx], 0);
      expect(img.rgba[idx + 1], 0);
      expect(img.rgba[idx + 2], 0);
      expect(img.rgba[idx + 3], 255);
    });

    test('Quiet-Zone links oben ist rein weiss', () {
      final RasterImage img = PrintPaper.renderQrMatrix(data);
      // Pixel (0,0) liegt in der Quiet-Zone -> weiss.
      expect(img.rgba[0], 255);
      expect(img.rgba[1], 255);
      expect(img.rgba[2], 255);
      expect(img.rgba[3], 255);
    });
  });
}
