import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/printing.dart';

void main() {
  group('printRawBytesWifi', () {
    test('sendet die Bytes an den Socket und liefert PrintResult.success', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final received = <int>[];
      final gotData = Completer<void>();
      server.listen((socket) {
        socket.listen(received.addAll, onDone: () {
          if (!gotData.isCompleted) gotData.complete();
        });
      });

      final KeckPrintResult res = await KeckPrinterService.printRawBytesWifi(
        [10, 20, 30, 40],
        ip: '127.0.0.1',
        port: server.port,
      );

      expect(res.success, isTrue);
      expect(res.error, isNull);
      await gotData.future.timeout(const Duration(seconds: 3));
      expect(received, [10, 20, 30, 40]);
      await server.close();
    });

    test('ändert den globalen aktiven Drucker NICHT', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((s) => s.listen((_) {}));
      KeckPrinterService.ipAddress = '10.0.0.99';
      KeckPrinterService.port = 9100;

      await KeckPrinterService.printRawBytesWifi([1], ip: '127.0.0.1', port: server.port);

      expect(KeckPrinterService.ipAddress, '10.0.0.99');
      expect(KeckPrinterService.port, 9100);
      await server.close();
    });

    test('liefert failure bei unerreichbarem Host (Timeout)', () async {
      final res = await KeckPrinterService.printRawBytesWifi(
        [1, 2, 3],
        ip: '127.0.0.1',
        port: 1,
        timeout: const Duration(milliseconds: 400),
      );
      expect(res.success, isFalse);
      expect(res.error, isNotNull);
    });

    test('liefert failure bei leeren Bytes / leerer IP (ohne Verbindungsversuch)', () async {
      expect((await KeckPrinterService.printRawBytesWifi([], ip: '127.0.0.1')).success, isFalse);
      expect((await KeckPrinterService.printRawBytesWifi([1], ip: '   ')).success, isFalse);
    });
  });
}
