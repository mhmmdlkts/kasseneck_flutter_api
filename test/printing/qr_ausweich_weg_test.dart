import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/printing.dart';

import '../helpers/test_receipts.dart';
import 'qr_native_groesse_test.dart' show echterQr;

/// Der Weg des Ausweich-Hinweises vom Papier bis zum Aufrufer.
///
/// Er ist der Grund, aus dem Punkt 3 des Auftrags keine stille Aenderung ist:
/// weicht der Druck vom nativen Befehl aufs Bild aus, soll die Kasse es dem
/// Chef sagen und den Weg dauerhaft umstellen koennen. Ohne diesen Weg waere
/// der Wechsel nur im Bytestrom sichtbar -- also nirgends.

/// Ein Beleg, dessen QR fuer den nativen Befehl zu breit ist (121 Module auf
/// 58 mm). Der Drucker wuerde ihn gar nicht drucken.
KasseneckReceipt belegZuBreit() => buildReceipt(qr: 'X' * 1000);

class FakeTransport implements PrinterTransport {
  int sendCount = 0;

  @override
  Future<KeckPrintResult> send(List<int> bytes) async {
    sendCount++;
    return const KeckPrintResult.success();
  }

  @override
  Future<void> dispose() async {}
}

int? modulgroesse(List<int> b) {
  for (int i = 0; i + 2 < b.length; i++) {
    if (b[i] == 0x31 && b[i + 1] == 0x43) return b[i + 2];
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('getBytesFromReceipt meldet den Ausweich am Dienst', () async {
    await KeckPrinterService.getBytesFromReceipt(belegZuBreit(), KeckPaperSize.mm58,
        qrMode: QrPrintMode.native);
    expect(KeckPrinterService.letzterQrAusweich, isNotNull);
    expect(KeckPrinterService.letzterQrFehler, isNull);
  });

  test('ein sauber nativ gedruckter Beleg raeumt die Meldung weg', () async {
    await KeckPrinterService.getBytesFromReceipt(belegZuBreit(), KeckPaperSize.mm58,
        qrMode: QrPrintMode.native);
    expect(KeckPrinterService.letzterQrAusweich, isNotNull);
    await KeckPrinterService.getBytesFromReceipt(buildReceipt(qr: echterQr), KeckPaperSize.mm58,
        qrMode: QrPrintMode.native);
    expect(KeckPrinterService.letzterQrAusweich, isNull,
        reason: 'sonst haengt der Ausweich eines frueheren Belegs am naechsten');
  });

  test('getPaperFromReceipt bleibt frei von globalem Zustand', () async {
    await KeckPrinterService.getBytesFromReceipt(belegZuBreit(), KeckPaperSize.mm58,
        qrMode: QrPrintMode.native);
    final String? fremd = KeckPrinterService.letzterQrAusweich;
    expect(fremd, isNotNull);

    final PrintPaper paper = await KeckPrinterService.getPaperFromReceipt(
        buildReceipt(qr: echterQr), KeckPaperSize.mm58,
        qrMode: QrPrintMode.native);
    expect(paper.qrAusweich, isNull, reason: 'am eigenen Papier steht nichts');
    expect(KeckPrinterService.letzterQrAusweich, fremd,
        reason: 'und das Signal eines fremden Druckvorgangs bleibt stehen');
  });

  test('KeckPrinter.printReceipt traegt ihn im Ergebnis', () async {
    final FakeTransport fake = FakeTransport();
    final KeckPrintResult res = await KeckPrinter(fake, size: KeckPaperSize.mm58)
        .printReceipt(belegZuBreit(), qrMode: QrPrintMode.native);
    expect(res.qrAusweich, isNotNull);
    expect(res.qrFehler, isNull);
    expect(res.success, isTrue);
    expect(fake.sendCount, 1);
  });

  test('die gewaehlte Modulgroesse erreicht die Bytes', () async {
    final List<int> bytes = (await KeckPrinterService.getBytesFromReceipt(
            buildReceipt(qr: echterQr), KeckPaperSize.mm80,
            qrMode: QrPrintMode.native, qrGroesse: QrModulGroesse.gross))
        .expand((e) => e)
        .toList();
    expect(modulgroesse(bytes), 8);
  });

  test('auch ueber den Beleg selbst', () async {
    final List<int> bytes = (await buildReceipt(qr: echterQr).getPrintBytes(
            paperSize: KeckPaperSize.mm58,
            qrMode: QrPrintMode.native,
            qrGroesse: QrModulGroesse.klein))
        .expand((e) => e)
        .toList();
    expect(modulgroesse(bytes), 4);
  });
}
