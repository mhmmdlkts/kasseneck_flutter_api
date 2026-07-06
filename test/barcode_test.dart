import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/printing.dart';

/// Byte-Level-Tests fuer die 1D-Barcode-Unterstuetzung (GS k, Form 2).
/// Geraetunabhaengig: geprueft wird die erzeugte ESC/POS-Byte-Sequenz.
void main() {
  EscPosGenerator gen() =>
      EscPosGenerator(EscPaperSize.mm58, CapabilityProfile());

  // Sucht das erste Vorkommen von [needle] in [haystack] (-1 = nicht gefunden).
  int indexOfSeq(List<int> haystack, List<int> needle) {
    for (int i = 0; i + needle.length <= haystack.length; i++) {
      bool ok = true;
      for (int j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }

  group('Steuerbefehle Hoehe/Breite/HRI', () {
    test('GS h / GS w / GS H werden gesetzt', () {
      final bytes = gen().barcode(BarcodeType.ean13, '4006381333931',
          height: 120, width: 4, hri: BarcodeHri.above);
      // GS h 120
      expect(indexOfSeq(bytes, [0x1D, 0x68, 120]), greaterThanOrEqualTo(0));
      // GS w 4
      expect(indexOfSeq(bytes, [0x1D, 0x77, 4]), greaterThanOrEqualTo(0));
      // GS H 1 (above)
      expect(indexOfSeq(bytes, [0x1D, 0x48, 1]), greaterThanOrEqualTo(0));
    });

    test('Breite/Hoehe werden geclampt (width 9 -> 6, height 0 -> 1)', () {
      final bytes = gen().barcode(BarcodeType.code39, 'ABC',
          height: 0, width: 9);
      expect(indexOfSeq(bytes, [0x1D, 0x68, 1]), greaterThanOrEqualTo(0));
      expect(indexOfSeq(bytes, [0x1D, 0x77, 6]), greaterThanOrEqualTo(0));
    });
  });

  group('GS k Form 2 Payload', () {
    test('code128 "12345" -> {B12345 mit Code-Set B', () {
      final bytes = gen().barcode(BarcodeType.code128, '12345');
      // GS k 73 n {B12345 ; payload = "{B12345" (7 Zeichen)
      final seq = <int>[
        0x1D, 0x6B, 73, 7, // GS k m=73 n=7
        0x7B, 0x42, // { B
        0x31, 0x32, 0x33, 0x34, 0x35, // 1 2 3 4 5
      ];
      expect(indexOfSeq(bytes, seq), greaterThanOrEqualTo(0));
      // GS h / GS w / GS H stehen davor
      final kIdx = indexOfSeq(bytes, [0x1D, 0x6B, 73]);
      expect(indexOfSeq(bytes.sublist(0, kIdx), [0x1D, 0x68]),
          greaterThanOrEqualTo(0));
      expect(indexOfSeq(bytes.sublist(0, kIdx), [0x1D, 0x77]),
          greaterThanOrEqualTo(0));
      expect(indexOfSeq(bytes.sublist(0, kIdx), [0x1D, 0x48]),
          greaterThanOrEqualTo(0));
    });

    test('code128 mit vorhandener {-Sequenz bleibt unveraendert', () {
      final bytes = gen().barcode(BarcodeType.code128, '{A12345');
      // payload = "{A12345" (7 Zeichen), kein zusaetzliches {B
      final seq = <int>[0x1D, 0x6B, 73, 7, 0x7B, 0x41, 0x31];
      expect(indexOfSeq(bytes, seq), greaterThanOrEqualTo(0));
    });

    test('ean13 "4006381333931" -> m=67, n=13', () {
      final bytes = gen().barcode(BarcodeType.ean13, '4006381333931');
      final kIdx = indexOfSeq(bytes, [0x1D, 0x6B, 67, 13]);
      expect(kIdx, greaterThanOrEqualTo(0));
      // Payload sind die 13 ASCII-Ziffern
      final payload = bytes.sublist(kIdx + 4, kIdx + 4 + 13);
      expect(payload, equals('4006381333931'.codeUnits));
    });
  });

  group('CustomPrintJob.barcode', () {
    test('liefert dieselben Bytes wie der direkte Generator-Aufruf', () {
      final direct = gen().barcode(BarcodeType.code128, '12345',
          height: 80, width: 3, hri: BarcodeHri.both);
      final job = CustomPrintJob().barcode(BarcodeType.code128, '12345',
          height: 80, width: 3, hri: BarcodeHri.both);
      expect(job.build(gen()), equals(direct));
    });
  });
}
