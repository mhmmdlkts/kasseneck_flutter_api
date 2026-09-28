import 'package:kasseneck_api/enums/receipt_type.dart';
import 'package:kasseneck_api/models/beleg_layout.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/services/vienna_time.dart';

import '../kasse/storno.dart' show stornogruende;
import '../kasse/testkennzeichen.dart' show signaturIstTest;

/// Aufdruck eines Belegs, der ohne Server-Layout gezeichnet wird: Warnrahmen
/// (TESTKASSE/TESTSIGNATUR) und Belegart-Block (STORNOBELEG, TRAININGSBELEG,
/// STARTBELEG, Nullbeleg-Arten). Zwilling der Regeln in `buildReceiptLayout`
/// (npm `receipt/layout.ts`, `belegartBlock` und die Warnungen) und in
/// `layoutFuerBeleg` des Backends. Texte wortgleich, damit der Rueckfall
/// denselben Beleg zeigt wie das Server-Layout.
///
/// Grund: eine Storno-Antwort traegt kein Layout. Ohne diesen Aufdruck kaeme
/// ein Storno einer Testkasse als gewoehnlicher, gueltig aussehender Bon aus
/// dem Drucker.

/// Gedankenstrich als Escape: der Server-Text traegt ihn, der Quelltext nicht.
const String _strich = '\u2014';

const String testkasseText = 'TESTKASSE $_strich kein gültiger Beleg';
const String testsignaturText = 'TESTSIGNATUR $_strich kein gültiger Beleg';

const List<String> _trainingErklaerung = [
  'Trainingsbuchung $_strich kein Kauf, keine Zahlung, keine steuerliche Buchung.',
  'Sollten Sie diesen Beleg als Kunde erhalten haben, sagen Sie bitte dem Betrieb Bescheid.',
];

/// Warnrahmen ueber dem Kopf. TESTKASSE aus `testCashregister`, TESTSIGNATUR
/// aus `testSignature`. Tragen die Kennzeichen nichts (die Storno-Antwort und
/// der Bericht senden sie nicht), der QR aber eine Test-Signatur (`AT100`),
/// steht TESTSIGNATUR: ein solcher Beleg ist in keinem Fall gueltig, und das
/// muss er zeigen.
List<BelegBanner> warnrahmen(KasseneckReceipt beleg) => [
      if (beleg.testCashregister) BelegBanner(text: testkasseText, tone: LayoutBannerTone.warning),
      if (beleg.testSignature || (!beleg.testCashregister && signaturIstTest(beleg.qr)))
        BelegBanner(text: testsignaturText, tone: LayoutBannerTone.warning),
    ];

/// Belegart unter dem Kopf: Titel als Banner, Untertitel zentriert.
/// Verkaufsbelege bekommen keinen Block.
List<BelegZeile> belegartBlock(KasseneckReceipt beleg) {
  BelegText mitte(String text) => BelegText(text: text, align: BelegAlign.center);
  BelegBanner banner(String text) => BelegBanner(text: text, tone: LayoutBannerTone.receiptType);
  switch (beleg.receiptType) {
    case ReceiptType.cancellation:
      final bezug = beleg.cancellationOf;
      final datum = bezug?.timeStamp == null ? null : _originalDatum(bezug!.timeStamp!);
      final grund = beleg.cancellationReason;
      return [
        banner('STORNOBELEG'),
        mitte(bezug != null ? 'Stornobuchung zu Beleg ${bezug.receiptId}' : 'Stornobuchung'),
        if (datum != null) mitte('vom $datum'),
        if (grund != null && grund.isNotEmpty) mitte('Grund: ${stornogruende[grund] ?? grund}'),
      ];
    case ReceiptType.training:
      return [banner('TRAININGSBELEG'), for (final z in _trainingErklaerung) mitte(z)];
    case ReceiptType.start:
      return [banner('STARTBELEG'), mitte('Nullbeleg zur Inbetriebnahme')];
    case ReceiptType.zero:
      final wand = ViennaTime.toWallClock(beleg.timeStamp);
      final monat = wand.month.toString().padLeft(2, '0');
      final jahr = wand.year;
      return switch (beleg.zeroKind) {
        'monthly' => [banner('MONATSBELEG'), mitte('Nullbeleg $monat/$jahr')],
        'annual' => [banner('JAHRESBELEG'), mitte('Nullbeleg $jahr $_strich Prüfung mit BMF-App')],
        'annual_replacement' => [
            banner('JAHRESBELEG'),
            mitte('Nullbeleg ${jahr - 1} $_strich Prüfung mit BMF-App (Ersatzbeleg)'),
          ],
        'final' => [banner('SCHLUSSBELEG'), mitte('Nullbeleg zur Außerbetriebnahme')],
        'outage_end' => [banner('NULLBELEG'), mitte('Prüfbeleg nach Signaturausfall')],
        _ => [banner('NULLBELEG'), mitte('Prüfbeleg')],
      };
    case ReceiptType.standard:
      return const [];
  }
}

String? _originalDatum(String roh) {
  try {
    final t = ViennaTime.toWallClock(ViennaTime.parseServerTimeStamp(roh));
    String zwei(int n) => n.toString().padLeft(2, '0');
    return '${zwei(t.day)}.${zwei(t.month)}.${t.year}, ${zwei(t.hour)}:${zwei(t.minute)} Uhr';
  } catch (_) {
    return null;
  }
}
