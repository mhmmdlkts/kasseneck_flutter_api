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
  ///
  /// Einzige gewollte Abweichung von 6.8.0: der native QR druckt seit dem
  /// Blatt mit Fehlerkorrektur **M** (Byte 49) statt L (48) -- dieselbe Stufe
  /// wie Blatt, ePOS und Bildweg. Damit die Digests ihr Zeugnis aus der Zeit
  /// vor dem Umbau behalten, wird genau dieser eine Befehl vor dem Hashen auf
  /// L zurueckgestellt; dass er genau einmal mit M im Strom steht, prueft der
  /// Test mit. Jede andere Verschiebung macht den Digest weiterhin rot.
  Future<String> belegDigest(KeckPaperSize size) async {
    final PrintPaper paper = PrintPaper(paperSize: size, profile: CapabilityProfile());
    await paper.setKeckReceipt(belegAbsolut(), qrMode: QrPrintMode.native);
    final List<int> bytes = paper.bytes.expand((e) => e).toList();
    final List<int> korrekturM = [...'\x1D(k'.codeUnits, 0x03, 0x00, 0x31, 0x45, 49];
    final List<int> treffer = [
      for (int i = 0; i + korrekturM.length <= bytes.length; i++)
        if (List.generate(korrekturM.length, (k) => bytes[i + k] == korrekturM[k]).every((g) => g)) i,
    ];
    expect(treffer, hasLength(1), reason: 'nativer QR-Befehl nicht genau einmal mit Korrektur M');
    bytes[treffer.single + korrekturM.length - 1] = 48;
    return sha256.convert(bytes).toString();
  }

  test('58 mm: Beleg ohne Wahl byteidentisch mit 6.8.0', () async {
    // Digest seit dem Ausrichtung-vor-Position-Umbau neu gezogen: `_text`
    // schreibt die Ausrichtung jetzt vor dem Positionsbefehl und laesst ihn
    // fuer volle Zeilen ganz weg (siehe Kommentar an `_text`). Der native QR
    // wird zentriert gesetzt; jede Zeile danach mit anderer Ausrichtung
    // verschiebt sich dadurch im Bytestrom -- gewollt, das ist genau die
    // Behebung des Versatzes vom Bon des 18.09.2026.
    expect(await belegDigest(KeckPaperSize.mm58),
        'c8bf21c625875f40715f979a568e39546f6c1f3d4b42333a53316cd86f0b3ff6');
  });

  test('80 mm: Beleg ohne Wahl byteidentisch mit 6.8.0', () async {
    // Der wichtigere der beiden: auf 80 mm passte das Symbol schon immer, und
    // die gerechnete Groesse waere hier 8 statt 6. Nur der Deckel bei `auto`
    // haelt den Bestand -- faellt er, faellt dieser Test.
    //
    // Digest ebenfalls neu gezogen, aus demselben Grund wie beim 58-mm-Fall.
    expect(await belegDigest(KeckPaperSize.mm80),
        'be54b3ea8a798c30fcd9ad82cc50e5fc65635f7c1e0747b88806faffd0a6c4c6');
  });
}
