import 'package:kasseneck_api/enums/receipt_type.dart';
import 'package:kasseneck_api/models/receipt_layout.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/services/vienna_time.dart';

import '../kasse/storno.dart' show cancellationReasons;
import '../kasse/testkennzeichen.dart' show signatureIsTest;

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
List<LayoutBannerLine> warnrahmen(KasseneckReceipt beleg) => [
      if (beleg.testCashregister) LayoutBannerLine(text: testkasseText, tone: LayoutBannerTone.warning),
      if (beleg.testSignature || (!beleg.testCashregister && signatureIsTest(beleg.qr)))
        LayoutBannerLine(text: testsignaturText, tone: LayoutBannerTone.warning),
    ];

/// Belegart unter dem Kopf: Titel als Banner, Untertitel zentriert.
/// Verkaufsbelege bekommen keinen Block.
List<LayoutLine> belegartBlock(KasseneckReceipt beleg) {
  LayoutTextLine mitte(String text) => LayoutTextLine(text: text, align: LayoutAlign.center);
  LayoutBannerLine banner(String text) => LayoutBannerLine(text: text, tone: LayoutBannerTone.receiptType);
  switch (beleg.receiptType) {
    case ReceiptType.cancellation:
      final bezug = beleg.cancellationOf;
      final datum = bezug?.timeStamp == null ? null : _originalDatum(bezug!.timeStamp!);
      final grund = beleg.cancellationReason;
      return [
        banner('STORNOBELEG'),
        mitte(bezug != null ? 'Stornobuchung zu Beleg ${bezug.receiptId}' : 'Stornobuchung'),
        if (datum != null) mitte('vom $datum'),
        if (grund != null && grund.isNotEmpty) mitte('Grund: ${cancellationReasons[grund] ?? grund}'),
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

/// Grund-Zeile nach einem Ausfall der Kasse; `other` druckt den eigenen Text.
const Map<String, String> _nacherfassungGrund = {
  'network_outage': 'Internet', 'power_outage': 'Strom', 'device_failure': 'Gerät defekt', 'system_outage': 'Störung',
};

/// `YYYY-MM-DD` als `TT.MM.JJJJ`; anderes bleibt, wie es kam.
String _handbelegDatum(String tag) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(tag);
  return m == null ? tag : '${m[3]}.${m[2]}.${m[1]}';
}

/// Block „NACHERFASSUNG“ (manualReceipt) unter dem Kopf: Art, Grund, Nummer und
/// Tag des Handbelegs bzw. der Handbelege eines Tagessammelbelegs, dazu der
/// Hinweis, dass der Beleg fuer die USt ein Duplikat ist
/// (Registrierkassenerlass 3.3 Faelle 5 und 6, 2.4.11); nicht bei
/// Kleinunternehmern. Leer ohne Handbeleg.
/// Zwilling von `nacherfassungBlock` im npm-Paket.
List<LayoutLine> nacherfassungBlock(KasseneckReceipt beleg) {
  final m = beleg.manualReceipt;
  if (m == null) return const [];
  LayoutTextLine mitte(String text) => LayoutTextLine(text: text, align: LayoutAlign.center);
  final grund = m.reason == 'other' ? m.note : _nacherfassungGrund[m.reason];
  final tag = _handbelegDatum(m.date);
  return [
    const LayoutBannerLine(text: 'NACHERFASSUNG', tone: LayoutBannerTone.receiptType),
    mitte(m.reason == 'outside_premises' ? 'Leistung außer Haus' : 'nach Ausfall der Kasse'),
    if (grund != null) mitte('Grund: $grund'),
    const LayoutSpaceLine(),
    if (m.isDailySummary) ...[
      mitte('Tagessammelbeleg'),
      mitte('Handbelege Nr. ${m.number} bis ${m.numberTo}'),
      mitte('${m.count != null ? '${m.count} Belege ' : ''}vom $tag'),
      if (!beleg.isSmallBusiness) mitte('USt: Duplikat der Handbelege'),
    ] else ...[
      mitte('Handbeleg Nr. ${m.number}'),
      mitte('vom $tag${m.time != null ? ', ${m.time} Uhr' : ''}'),
      if (!beleg.isSmallBusiness) mitte('USt: Duplikat des Handbelegs'),
    ],
  ];
}
