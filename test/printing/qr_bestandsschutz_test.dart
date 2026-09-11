import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/qr_print_mode.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/enums/voucher_action.dart';
import 'package:kasseneck_api/enums/voucher_type.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/keck_voucher.dart';
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
/// Die Digests unten stammen aus dem Stand **vor** dem Umbau (Fassung 6.8.0,
/// Commit 1f420ac) und sind daher kein Selbstportraet: wer die gerechnete
/// Groesse bei einem passenden Symbol auch nur um einen Punkt verschiebt, macht
/// sie rot. Sie haengen am gesamten Beleglayout, nicht nur am QR -- das ist
/// Absicht, denn die Zusage lautet "derselbe Bon", nicht "derselbe QR-Befehl".
///
/// **Der Zeitstempel ist absolut (UTC), nicht oertlich.** Der Bon druckt die
/// Wiener Wanduhrzeit (`ViennaTime.toWallClock`); ein oertlich gebautes
/// `DateTime` steht damit in Wien und auf einem UTC-Rechner zu verschiedenen
/// Uhrzeiten am Papier, und der Digest ueber den ganzen Bon wich ab. Der Test
/// war rot auf dem CI-Rechner und gruen hier -- der Fehler lag im Test, nicht
/// im Druck.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Derselbe Warenkorb wie `cartA()`, nur mit absolutem Zeitstempel.
  KasseneckReceipt belegAbsolut() => buildReceipt(
        timeStamp: DateTime.utc(2026, 6, 12, 10, 30, 5),
        items: [
          KasseneckItem(name: 'Klassiker', quantity: 3, vat: VatRate.vat20, priceCents: 1999),
          KasseneckItem(name: 'Brot', quantity: 1, vat: VatRate.vat4komma9, priceCents: 29),
          KasseneckItem(name: 'Milch', quantity: 2, vat: VatRate.vat10, priceCents: 105),
        ],
        vouchers: [
          KeckVoucher(name: 'Aktion', action: VoucherAction.redeem, type: VoucherType.promo, valueCents: 150),
        ],
      );

  /// SHA-256 ueber den gesamten Bytestrom eines nativ gedruckten Belegs.
  Future<String> belegDigest(KeckPaperSize size) async {
    final PrintPaper paper = PrintPaper(paperSize: size, profile: CapabilityProfile());
    await paper.setKeckReceipt(belegAbsolut(), qrMode: QrPrintMode.native);
    return sha256.convert(paper.bytes.expand((e) => e).toList()).toString();
  }

  test('58 mm: Beleg ohne Wahl byteidentisch mit 6.8.0', () async {
    expect(await belegDigest(KeckPaperSize.mm58),
        '14b1fbba1e9efcef0151328aad3dfa931a3300d8a1fd76b565f2e87b4cdbfc3d');
  });

  test('80 mm: Beleg ohne Wahl byteidentisch mit 6.8.0', () async {
    // Der wichtigere der beiden: auf 80 mm passte das Symbol schon immer, und
    // die gerechnete Groesse waere hier 8 statt 6. Nur der Deckel bei `auto`
    // haelt den Bestand -- faellt er, faellt dieser Test.
    expect(await belegDigest(KeckPaperSize.mm80),
        'ec97c75e93d05d58865ccdea5e1773fb1e6bf36c4c59de6c1825f96f7a9e1377');
  });
}
