import 'dart:convert';
import 'commands.dart';

class QRSize {
  const QRSize(this.value);
  final int value;
  static const size1 = QRSize(0x01);
  static const size2 = QRSize(0x02);
  static const size3 = QRSize(0x03);
  static const size4 = QRSize(0x04);
  static const size5 = QRSize(0x05);
  static const size6 = QRSize(0x06);
  static const size7 = QRSize(0x07);
  static const size8 = QRSize(0x08);
}

class QRCorrection {
  const QRCorrection._internal(this.value);
  final int value;
  static const L = QRCorrection._internal(48);
  static const M = QRCorrection._internal(49);
  static const Q = QRCorrection._internal(50);
  static const H = QRCorrection._internal(51);
}

class QRCode {
  List<int> bytes = <int>[];
  QRCode(String text, QRSize size, QRCorrection level) {
    bytes += cQrHeader.codeUnits + [0x03, 0x00, 0x31, 0x43] + [size.value];
    bytes += cQrHeader.codeUnits + [0x03, 0x00, 0x31, 0x45] + [level.value];
    List<int> textBytes = latin1.encode(text);
    bytes +=
        cQrHeader.codeUnits + [textBytes.length + 3, 0x00, 0x31, 0x50, 0x30];
    bytes += textBytes;
    bytes += cQrHeader.codeUnits + [0x03, 0x00, 0x31, 0x52, 0x30];
    bytes += cQrHeader.codeUnits + [0x03, 0x00, 0x31, 0x51, 0x30];
  }
}
