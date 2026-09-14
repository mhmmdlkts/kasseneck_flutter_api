import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/qr_print_mode.dart';
import 'package:kasseneck_api/models/beleg_layout.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/src/printing/escpos/escpos.dart';

/// Der Aufdruck ist ein Rahmen aus drei Rasterzeilen -- am Bon ohne doppelte
/// Hoehe und ohne Invertieren, genau wie am Bildschirm und im PDF.
void main() {
  test('setBelegLayout: STORNOBELEG als zwei Rahmenzeilen und Text, ohne GS ! Hoehe und ohne GS B', () async {
    final paper = PrintPaper(paperSize: KeckPaperSize.mm58, profile: CapabilityProfile());
    await paper.setBelegLayout(
      const BelegLayout(lines: [BelegBanner(text: 'STORNOBELEG', warnung: true)], paperSize: 'mm58', regelwerk: 2),
      cut: false,
      qrMode: QrPrintMode.native,
    );
    final alles = String.fromCharCodes(paper.bytes.expand((b) => b));
    expect(RegExp('=' * 32).allMatches(alles).length, 2);
    expect(alles.contains('STORNOBELEG'), isTrue);
    for (final m in RegExp('\x1d!(.)', dotAll: true).allMatches(alles)) {
      expect(m.group(1)!.codeUnitAt(0) & 0x0f, 0, reason: 'doppelte Hoehe im Bytestrom');
    }
    for (final m in RegExp('\x1dB(.)', dotAll: true).allMatches(alles)) {
      expect(m.group(1)!.codeUnitAt(0), 0, reason: 'Invertieren im Bytestrom');
    }
  });
}
