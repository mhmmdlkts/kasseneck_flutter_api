import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/src/printing/escpos/qrcode.dart';

void main() {
  test('QRCode nativer Befehl ist byte-exakt (FN167/169/180/182/181)', () {
    final qr = QRCode('ABC', QRSize.size6, QRCorrection.L);
    final h = '\x1D(k'.codeUnits; // cQrHeader
    final expected = <int>[
      ...h, 0x03, 0x00, 0x31, 0x43, 0x06, // Modulgroesse 6
      ...h, 0x03, 0x00, 0x31, 0x45, 48,   // Korrektur L
      ...h, 3 + 3, 0x00, 0x31, 0x50, 0x30, ...latin1.encode('ABC'), // store
      ...h, 0x03, 0x00, 0x31, 0x52, 0x30, // Groesse
      ...h, 0x03, 0x00, 0x31, 0x51, 0x30, // Druck
    ];
    expect(qr.bytes, expected);
  });
}
