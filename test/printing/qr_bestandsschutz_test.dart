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
/// Seit dem Ausrichtung-vor-Position-Umbau gibt es drei bekannte, gewollte
/// Abweichungen von 6.8.0 (Digests entsprechend neu gezogen):
/// 1. die QR-Fehlerkorrektur M statt L (siehe `belegDigest` unten),
/// 2. der Wegfall des ueberfluessigen `ESC $ 0 0` vor jeder von `text()`
///    gedruckten Zeile (`colInd=0, colWidth=12`, siehe `generator.dart:248`)
///    -- das ist der dominante Treiber, weil er quer durch den ganzen Beleg
///    wirkt, nicht nur an der einen Stelle nach dem QR-Code, und
/// 3. (Nachtrag aus der Schlusspruefung, § 7 Punkt 1+2 im Umsetzungsplan der
///    Marke) der Wegfall ueberfluessiger `ESC a 0`-Befehle vor der ersten
///    Spalte jeder von `addDoubleText`/`_addTable` gedruckten Zeile: eine
///    rechtsbuendige (oder sonst nicht-linke) Spalte ab Spalte 2 verwirft der
///    Drucker zwar wortlos, der Ausrichtungs-Zustand merkte sich den Wechsel
///    aber trotzdem -- die naechste Zeile hielt sich danach faelschlich fuer
///    schon umgestellt und sandte zur Korrektur ein ueberfluessiges
///    `ESC a 0`. Belegt (nicht aus dem eigenen Lauf uebernommen): Bytestrom
///    vor und nach den beiden Fixes unabhaengig gezogen, tokenisiert und per
///    diff verglichen -- einzige Abweichung sind 16 (58 mm) bzw. 14 (80 mm)
///    entfallene `ESC a 0`, keine einzige Zeile hinzugefuegt, Text- und
///    QR-Nutzlast-Token byteidentisch. Nachweis: .superpowers/sdd/
///    2026-09-21-marke-einheitlich/task-7-punkt1-2-digest-nachweis/
///    (separate Ablage, nicht in diesem Repo).
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
  /// Eine der beiden bekannten gewollten Abweichungen von 6.8.0 (siehe
  /// Kopfkommentar) wird hier vor dem Hashen zurueckgestellt: der native QR
  /// druckt seit dem Blatt mit Fehlerkorrektur **M** (Byte 49) statt L (48)
  /// -- dieselbe Stufe wie Blatt, ePOS und Bildweg. Damit die Digests ihr
  /// Zeugnis aus der Zeit vor dem Umbau behalten, wird genau dieser eine
  /// Befehl vor dem Hashen auf L zurueckgestellt; dass er genau einmal mit M
  /// im Strom steht, prueft der Test mit. Die zweite Abweichung (Wegfall des
  /// Positionsbefehls bei vollen Zeilen) steckt dagegen unveraendert in den
  /// unten erwarteten Digests -- sie laesst sich nicht punktuell zuruecksetzen,
  /// weil sie an jeder von `text()` gedruckten Zeile im Beleg auftritt. Jede
  /// andere Verschiebung macht den Digest weiterhin rot.
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
    // Digest seit dem Ausrichtung-vor-Position-Umbau neu gezogen. Haupttreiber
    // ist der Wegfall von `ESC $ 0 0`: `text()` ruft `_text` immer mit
    // `colInd=0, colWidth=12` auf (siehe `generator.dart:248`), also trug
    // bisher praktisch jede per `text()` gedruckte Zeile im Beleg diesen
    // ueberfluessigen Positionsbefehl -- sein flaechendeckender Wegfall
    // veraendert den Hash ueber den ganzen Bon. Dazu kommt an der einen
    // Stelle nach dem zentriert gesetzten QR-Code noch die eigentliche
    // Fehlerbehebung: die folgende Zeile bekommt jetzt tatsaechlich ihr
    // `ESC a 0`, statt zentriert zu bleiben -- das ist die Behebung des
    // Versatzes vom Bon des 18.09.2026.
    //
    // Belegt (nicht aus dem eigenen Lauf uebernommen): Bytestrom vor Commit
    // 35dbe21 und danach unabhaengig gezogen, tokenisiert und per diff
    // verglichen -- einzige Abweichung sind 8 entfallene `ESC$ 0,0` (volle
    // Zeile) und die unveraendert nur verschobenen uebrigen Positionsbefehle;
    // Text- und QR-Nutzlast-Token byteidentisch. Nachweis mit Skripten und
    // Rohprotokoll: .superpowers/sdd/2026-09-19-beleg-druck-logo-ausrichtung/
    // task-6-dart-digest-nachweis/ (separate Ablage, nicht in diesem Repo).
    //
    // Nachtrag Task 7, Punkt 1+2 (Schlusspruefung, siehe Kopfkommentar):
    // erneut neu gezogen, diesmal ausschliesslich wegen 16 entfallener
    // ueberfluessiger `ESC a 0` vor der ersten Spalte diverser
    // `addDoubleText`/`_addTable`-Zeilen. Nachweis: .superpowers/sdd/
    // 2026-09-21-marke-einheitlich/task-7-punkt1-2-digest-nachweis/.
    expect(await belegDigest(KeckPaperSize.mm58),
        '9faa4cd8c80bf710960e535e2b2dabf7a7990ab95a8377ffe1f9e8d5c3e8b800');
  });

  test('80 mm: Beleg ohne Wahl byteidentisch mit 6.8.0', () async {
    // Der wichtigere der beiden: auf 80 mm passte das Symbol schon immer, und
    // die gerechnete Groesse waere hier 8 statt 6. Nur der Deckel bei `auto`
    // haelt den Bestand -- faellt er, faellt dieser Test.
    //
    // Digest aus demselben Grund wie beim 58-mm-Fall neu gezogen: ueberwiegend
    // der flaechendeckende Wegfall von `ESC $ 0 0` bei vollen Zeilen, dazu die
    // eigentliche Fehlerbehebung an der Stelle nach dem QR-Code.
    //
    // Belegt (nicht aus dem eigenen Lauf uebernommen): wie beim 58-mm-Fall
    // unabhaengig gezogen und tokenisiert verglichen -- 8 entfallene
    // `ESC$ 0,0`, uebrige Positionsbefehle nur verschoben, Text/QR-Nutzlast
    // byteidentisch. Nachweis unter .superpowers/sdd/
    // 2026-09-19-beleg-druck-logo-ausrichtung/task-6-dart-digest-nachweis/.
    //
    // Nachtrag Task 7, Punkt 1+2: wie beim 58-mm-Fall erneut neu gezogen,
    // diesmal wegen 14 entfallener ueberfluessiger `ESC a 0`. Nachweis:
    // .superpowers/sdd/2026-09-21-marke-einheitlich/
    // task-7-punkt1-2-digest-nachweis/.
    expect(await belegDigest(KeckPaperSize.mm80),
        '105cbaa39f13d2fa2f42366808d4b14e7a212d17462c4bacbf181818eb34590b');
  });
}
