import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/qr_print_mode.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/src/printing/escpos/escpos.dart';

import '../helpers/test_receipts.dart';

/// Bestandsschutz fuer den nativen QR-Weg.
///
/// Die Modulgroesse wird seit diesem Zweig gerechnet statt fest auf 6 gesetzt.
/// Ein Geraet, an dem niemand etwas waehlt, muss danach **byteidentisch**
/// drucken wie davor -- ausser dort, wo heute gar nichts herauskommt, weil das
/// Symbol breiter ist als das Papier.
///
/// Die Digests unten stammen aus dem Stand **vor** dem Umbau (Fassung 6.8.0)
/// und sind daher kein Selbstportraet: wer die gerechnete Groesse bei einem
/// passenden Symbol auch nur um einen Punkt verschiebt, macht sie rot. Sie
/// haengen am gesamten Beleglayout, nicht nur am QR -- das ist Absicht, denn
/// die Zusage lautet "derselbe Bon", nicht "derselbe QR-Befehl".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// SHA-256 ueber den gesamten Bytestrom eines nativ gedruckten Belegs.
  Future<String> belegDigest(KeckPaperSize size) async {
    final PrintPaper paper = PrintPaper(paperSize: size, profile: CapabilityProfile());
    await paper.setKeckReceipt(cartA(), qrMode: QrPrintMode.native);
    return sha256.convert(paper.bytes.expand((e) => e).toList()).toString();
  }

  test('58 mm: Beleg ohne Wahl byteidentisch mit 6.8.0', () async {
    expect(await belegDigest(KeckPaperSize.mm58),
        '5f29070bdc5164187e4e697d0204f6adff7db32eaa8706dce2824066ac7a2e26');
  });

  test('80 mm: Beleg ohne Wahl byteidentisch mit 6.8.0', () async {
    // Der wichtigere der beiden: auf 80 mm passte das Symbol schon immer, und
    // die gerechnete Groesse waere hier 8 statt 6. Nur der Deckel bei `auto`
    // haelt den Bestand -- faellt er, faellt dieser Test.
    expect(await belegDigest(KeckPaperSize.mm80),
        '82a1ff9d342a0937ef1efe4d08cbc17844c79250dd77401bd1c66b4a0a28c932');
  });
}
