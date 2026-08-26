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
  /// Groesste Nutzlast, die das Laengenfeld (pL, pH) von GS ( k fassen kann.
  static const int maxNutzlast = 0xFFFF - 3;

  List<int> bytes = <int>[];

  /// Nativer QR-Befehl GS ( k fuer [text].
  ///
  /// Die Nutzlast geht als **UTF-8** hinaus, nicht als Latin-1. Ein QR-Code
  /// traegt Daten, keine Schrift: der Drucker legt die Bytes im Byte-Modus ab,
  /// und der Bildmodus-Weg (`qr`-Paket, `QrByte`) kodiert denselben Beleg-QR
  /// ebenfalls als UTF-8 — beide Wege ergeben damit denselben Code. Vorher
  /// warf `latin1.encode` bei jedem Zeichen ueber 0xFF und riss den gesamten
  /// Beleg mit. Fuer reines ASCII — die Form, in der RKSV-Belegdaten kommen —
  /// ist das Ergebnis byteweise unveraendert.
  ///
  /// Die Nutzlast wird bewusst **nicht** entschaerft (kein Ersatzzeichen fuer
  /// Unbekanntes): ein veraendertes Zeichen ergaebe einen QR, der sich sauber
  /// lesen laesst und trotzdem nicht mehr zum signierten Beleg passt. Falsche
  /// Daten sind schlimmer als keine.
  QRCode(String text, QRSize size, QRCorrection level) {
    bytes += cQrHeader.codeUnits + [0x03, 0x00, 0x31, 0x43] + [size.value];
    bytes += cQrHeader.codeUnits + [0x03, 0x00, 0x31, 0x45] + [level.value];
    final List<int> textBytes = utf8.encode(text);
    if (textBytes.length > maxNutzlast) {
      throw ArgumentError.value(textBytes.length, 'text',
          'QR-Nutzlast ueberschreitet das Laengenfeld von GS ( k (max. $maxNutzlast Byte)');
    }
    // Die Laenge ist zweiteilig (pL, pH). pH stand fest auf 0x00: ab 253 Byte
    // Nutzlast lief pL still ueber (Uint8List.fromList schneidet modulo 256
    // ab) und der Drucker bekam ein protokollwidriges Laengenfeld.
    final int n = textBytes.length + 3;
    bytes += cQrHeader.codeUnits + [n & 0xFF, (n >> 8) & 0xFF, 0x31, 0x50, 0x30];
    bytes += textBytes;
    bytes += cQrHeader.codeUnits + [0x03, 0x00, 0x31, 0x52, 0x30];
    bytes += cQrHeader.codeUnits + [0x03, 0x00, 0x31, 0x51, 0x30];
  }
}
