import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/printing.dart';

import 'helpers/test_receipts.dart';
import 'keck_printer_test.dart' show FakeTransport, containsSubsequence;

/// Die gewaehlte Code-Tabelle erreicht jeden Belegweg; ohne Wahl bleibt es
/// Tabelle 16 wie bisher.
void main() {
  const escT19 = [0x1b, 0x74, 19];
  const escT16 = [0x1b, 0x74, 16];

  void pruefe(List<int> bytes, {required bool gewaehlt}) {
    expect(containsSubsequence(bytes, escT19), gewaehlt);
    expect(containsSubsequence(bytes, escT16), !gewaehlt);
  }

  test('getPaperFromReceipt', () async {
    final mit = await KeckPrinterService.getPaperFromReceipt(cartA(), KeckPaperSize.mm58, codeTable: CodeTableId.pc858);
    final ohne = await KeckPrinterService.getPaperFromReceipt(cartA(), KeckPaperSize.mm58);
    expect(mit.codeTable, CodeTableId.pc858);
    pruefe(mit.bytes.expand((e) => e).toList(), gewaehlt: true);
    pruefe(ohne.bytes.expand((e) => e).toList(), gewaehlt: false);
  });

  test('getBytesFromReceipt und KasseneckReceipt.getPrintBytes', () async {
    pruefe((await KeckPrinterService.getBytesFromReceipt(cartA(), KeckPaperSize.mm58, codeTable: CodeTableId.pc858))
        .expand((e) => e).toList(), gewaehlt: true);
    pruefe((await cartA().getPrintBytes(paperSize: KeckPaperSize.mm58, codeTable: CodeTableId.pc858))
        .expand((e) => e).toList(), gewaehlt: true);
    pruefe((await cartA().getPrintBytes(paperSize: KeckPaperSize.mm58)).expand((e) => e).toList(), gewaehlt: false);
  });

  test('KeckPrinter.printReceipt', () async {
    final fake = FakeTransport();
    await KeckPrinter(fake, size: KeckPaperSize.mm58).printReceipt(cartA(), codeTable: CodeTableId.pc858);
    pruefe(fake.captured, gewaehlt: true);
    await KeckPrinter(fake, size: KeckPaperSize.mm58).printReceipt(cartA());
    pruefe(fake.captured, gewaehlt: false);
  });
}
