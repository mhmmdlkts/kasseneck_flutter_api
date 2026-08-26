import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/printing.dart';

import 'helpers/test_receipts.dart';

/// Gerätunabhängiger Transport, der die gesendeten Bytes und die Aufrufzahl
/// mitschneidet und immer Erfolg meldet.
class FakeTransport implements PrinterTransport {
  final List<int> captured = <int>[];
  int sendCount = 0;
  int disposeCount = 0;

  @override
  Future<KeckPrintResult> send(List<int> bytes) async {
    sendCount++;
    captured
      ..clear()
      ..addAll(bytes);
    return const KeckPrintResult.success();
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }
}

/// Sucht [needle] als zusammenhaengende Teilsequenz in [haystack].
bool containsSubsequence(List<int> haystack, List<int> needle) {
  if (needle.isEmpty) return true;
  for (int i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (int j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

/// Ein Beleg, dessen QR nicht entstehen kann: leere Nutzlast gilt als Ausfall
/// (das Backend kann `data: ""` liefern), statt als QR ohne Inhalt.
KasseneckReceipt belegOhneQr() => cartA()..qr = '';

void main() {
  group('Der QR-Ausfall erreicht den Aufrufer', () {
    // Der QR-Code ist gesetzlich gefordert. Bis hierher baute jeder Druckweg
    // das PrintPaper intern und gab nur Bytes bzw. MyPosPaper zurueck -- das
    // Objekt mit qrFehler wurde verworfen, der Ausfall war auf KEINEM
    // dokumentierten Weg erreichbar.
    setUp(() => KeckPrinterService.letzterQrFehler = null);

    test('getPaperFromReceipt traegt den Ausfall im Rueckgabewert', () async {
      final paper = await KeckPrinterService.getPaperFromReceipt(belegOhneQr(), KeckPaperSize.mm58);
      expect(paper.qrFehler, isNotNull);
    });

    test('getPaperFromReceipt: ein gelungener QR setzt keinen Fehler', () async {
      final paper = await KeckPrinterService.getPaperFromReceipt(cartA(), KeckPaperSize.mm58);
      expect(paper.qrFehler, isNull);
    });

    test('getBytesFromReceipt meldet den Ausfall am Dienst', () async {
      await KeckPrinterService.getBytesFromReceipt(belegOhneQr(), KeckPaperSize.mm58);
      expect(KeckPrinterService.letzterQrFehler, isNotNull);
    });

    test('KasseneckReceipt.getPrintBytes ebenso — der Bluetooth-Weg baut darueber', () async {
      await belegOhneQr().getPrintBytes(paperSize: KeckPaperSize.mm58);
      expect(KeckPrinterService.letzterQrFehler, isNotNull);
    });

    test('getMyPosPaperFromReceipt ebenso — der MyPos-Terminaldruck baut darueber', () async {
      await KeckPrinterService.getMyPosPaperFromReceipt(belegOhneQr());
      expect(KeckPrinterService.letzterQrFehler, isNotNull);
    });

    test('printReceiptWifi meldet den Ausfall, auch ohne konfigurierten Drucker', () async {
      KeckPrinterService.ipAddress = null;
      await KeckPrinterService.printReceiptWifi(belegOhneQr());
      expect(KeckPrinterService.letzterQrFehler, isNotNull);
    });

    test('ein gelungener Beleg raeumt die Meldung wieder weg', () async {
      await KeckPrinterService.getBytesFromReceipt(belegOhneQr(), KeckPaperSize.mm58);
      expect(KeckPrinterService.letzterQrFehler, isNotNull);
      await KeckPrinterService.getBytesFromReceipt(cartA(), KeckPaperSize.mm58);
      expect(KeckPrinterService.letzterQrFehler, isNull,
          reason: 'sonst haengt der Ausfall eines frueheren Belegs am naechsten');
    });

    test('KeckPrinter.printReceipt traegt ihn im Ergebnis — ohne globalen Zustand', () async {
      final fake = FakeTransport();
      final res = await KeckPrinter(fake, size: KeckPaperSize.mm58).printReceipt(belegOhneQr());

      expect(res.qrFehler, isNotNull);
      expect(res.success, isTrue, reason: 'der Bon geht trotzdem hinaus');
      expect(fake.sendCount, 1);
    });

    test('KeckPrinter.printReceipt: gelungener QR laesst das Ergebnis leer', () async {
      final res = await KeckPrinter(FakeTransport(), size: KeckPaperSize.mm58).printReceipt(cartA());
      expect(res.qrFehler, isNull);
    });

    test('printRawBytesWifi kennt keinen Beleg und meldet keinen QR-Ausfall', () async {
      final res = await KeckPrinterService.printRawBytesWifi(const [1, 2, 3], ip: '');
      expect(res.qrFehler, isNull);
    });
  });

  group('KeckPrinter mit FakeTransport', () {
    test('printText schreibt plausible Textbytes; send genau 1x', () async {
      final fake = FakeTransport();
      final res = await KeckPrinter(fake).printText('Hi');

      expect(res.success, isTrue);
      expect(fake.sendCount, 1);
      expect(fake.captured, isNotEmpty);
      // Die ASCII-Codes von "Hi" muessen im Byte-Strom vorkommen.
      expect(containsSubsequence(fake.captured, 'Hi'.codeUnits), isTrue);
    });

    test('printBarcode enthaelt die GS k-Sequenz', () async {
      final fake = FakeTransport();
      await KeckPrinter(fake).printBarcode(BarcodeType.code128, '12345');

      // GS k m=73 (CODE128, Form 2)
      expect(containsSubsequence(fake.captured, [0x1D, 0x6B, 73]), isTrue);
    });

    test('printQr sendet genau 1x und liefert nicht-leere Bytes', () async {
      final fake = FakeTransport();
      final res = await KeckPrinter(fake).printQr('https://kasseneck.at', size: 6);

      expect(res.success, isTrue);
      expect(fake.sendCount, 1);
      expect(fake.captured, isNotEmpty);
    });

    test('printReceipt sendet nicht-leere Bytes, send genau 1x', () async {
      final fake = FakeTransport();
      final res = await KeckPrinter(fake).printReceipt(buildReceipt());

      expect(res.success, isTrue);
      expect(fake.sendCount, 1);
      expect(fake.captured, isNotEmpty);
    });

    test('printRawBytes reicht die Bytes unveraendert durch', () async {
      final fake = FakeTransport();
      await KeckPrinter(fake).printRawBytes(const [1, 2, 3]);

      expect(fake.captured, [1, 2, 3]);
    });

    test('printJob sendet den gebauten Auftrag in EINEM send', () async {
      final fake = FakeTransport();
      final job = CustomPrintJob()
        ..text('A')
        ..cut();
      await KeckPrinter(fake).printJob(job);

      expect(fake.sendCount, 1);
      expect(fake.captured, isNotEmpty);
    });

    test('cut/openDrawer/feed liefern success', () async {
      final fake = FakeTransport();
      final p = KeckPrinter(fake);
      expect((await p.cut()).success, isTrue);
      expect((await p.openDrawer()).success, isTrue);
      expect((await p.feed(2)).success, isTrue);
      expect(fake.sendCount, 3);
    });

    test('dispose ruft transport.dispose', () async {
      final fake = FakeTransport();
      await KeckPrinter(fake).dispose();
      expect(fake.disposeCount, 1);
    });
  });

  group('KeckPrinter.wifi gegen lokalen ServerSocket', () {
    test('printRawBytes sendet die Bytes an den Socket, Ergebnis success', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final received = <int>[];
      final gotData = Completer<void>();
      server.listen((socket) {
        socket.listen(received.addAll, onDone: () {
          if (!gotData.isCompleted) gotData.complete();
        });
      });

      final printer = KeckPrinter.wifi(ip: '127.0.0.1', port: server.port);
      final res = await printer.printRawBytes(const [7, 8, 9, 10]);

      expect(res.success, isTrue);
      await gotData.future.timeout(const Duration(seconds: 3));
      expect(received, [7, 8, 9, 10]);

      await printer.dispose();
      await server.close();
    });
  });
}
