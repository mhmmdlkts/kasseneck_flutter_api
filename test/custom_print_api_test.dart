import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/printing.dart';

/// Deckt die additive Custom-Print-API ab: byte-Bausteine ueber den vendierten
/// [EscPosGenerator] und die Akkumulation im [CustomPrintJob].
void main() {
  EscPosGenerator gen() => EscPosGenerator(EscPaperSize.mm58, CapabilityProfile());

  group('Barrel-Export (printing.dart)', () {
    test('EscPosGenerator + Typen sind ueber das Barrel nutzbar', () {
      final g = gen();
      final bytes = <int>[
        ...g.text('Hallo', styles: const PosStyles(align: PosAlign.center)),
        ...g.cut(),
      ];
      expect(bytes, isNotEmpty);
    });
  });

  group('CustomPrintJob akkumuliert korrekt', () {
    test('leerer Job -> leere Bytes', () {
      expect(CustomPrintJob().build(gen()), isEmpty);
    });

    test('Reihenfolge bleibt erhalten; build == Summe der Einzelbefehle', () {
      final job = CustomPrintJob()
        ..text('A')
        ..feed(2)
        ..qr('XYZ', size: 6)
        ..drawer()
        ..cut();

      final built = job.build(gen());

      final g = gen();
      final expected = <int>[
        ...g.text('A'),
        ...g.feed(2),
        ...g.qrcode('XYZ', size: QRSize.size6),
        ...g.drawer(),
        ...g.cut(),
      ];
      expect(built, expected);
    });

    test('raw() haengt beliebige Bytes unveraendert an', () {
      final built = (CustomPrintJob()..raw(const [1, 2, 3, 255])).build(gen());
      expect(built, [1, 2, 3, 255]);
    });

    test('Fluent-Verkettung liefert dieselbe Instanz', () {
      final job = CustomPrintJob();
      expect(identical(job.text('x'), job), isTrue);
    });
  });

  group('Byte-Praefixe der Bausteine', () {
    test("cut() enthaelt den ESC/POS-Full-Cut (GS V '0' = 29,86,48)", () {
      final b = gen().cut();
      expect(b.join(','), contains([29, 86, 48].join(',')));
    });

    test('drawer() erzeugt den Kassenlade-Puls (ESC p = 27,112,...)', () {
      final b = gen().drawer();
      expect(b.take(2).toList(), [27, 112]);
    });

    test('text() enthaelt den Klartext als Latin-1-Bytes', () {
      final b = gen().text('Bon');
      expect(b.join(','), contains('Bon'.codeUnits.join(',')));
    });

    test('qrcode(size:4) nutzt die native Modulgroesse 4', () {
      final b = gen().qrcode('D', size: QRSize.size4);
      expect(b.join(','), contains([0x31, 0x43, 0x04].join(',')));
    });
  });
}
