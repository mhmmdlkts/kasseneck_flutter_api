import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/src/printing/escpos/escpos.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native QR-Modus erzeugt Modulgroesse-Byte', () async {
    final paper = PrintPaper(paperSize: KeckPaperSize.mm58, profile: CapabilityProfile());
    paper.addQrCode('TESTTOKEN'); // native
    final flat = paper.bytes.expand((e) => e).toList();
    expect(flat.join(','), contains([0x31, 0x43].join(','))); // FN167 QR-Modulgroesse
  });
}
