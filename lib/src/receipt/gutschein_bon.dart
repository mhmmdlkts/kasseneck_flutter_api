import 'package:kasseneck_api/enums/voucher_action.dart';
import 'package:kasseneck_api/enums/voucher_type.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/keck_payment.dart';
import 'package:kasseneck_api/models/keck_voucher.dart';

import '../kasse/gutschein_wunsch.dart' show artOderNull;

/// Gutscheine der neuen Form am Bon des Rueckfalls ohne Server-Layout
/// (`PrintPaper.setKeckReceipt`, `KeckReceiptWidget`). Zwilling der
/// Gutscheinzeilen von `buildReceiptLayout` (npm `receipt/layout.ts` ab 1.12.0,
/// Spec 2026-10-14 „Bon und Beleg“); Texte und Spaltenbreiten (Zwoelftel)
/// wortgleich:
///
///   Verkauf Einzweck/Leistung  Positionszeile 7:5 „1  x Name Code“ | „50,00 A“
///   Verkauf Mehrzweck          dieselbe Zeile + Text „  USt bei Einlösung“
///   Einloesung Einzweck/       8:4 „Gutschein ····-9DWT“ | „-30,50 A“, nach der
///   Leistung                   letzten Zeile dieses Gutscheins der Vermerk
///                              („  Einzweck, versteuert mit Beleg K1-ID-4711“
///                              bzw. „…, befreit verkauft (Kleinunternehmer)“)
///                              und 8:4 „  Rest am Gutschein“ | „19,50 EUR“ bzw. „2 Stück“
///   Einloesung Mehrzweck       nach „Zwischensumme“ „Gutschein ····-9DWT“ und Rest
///   Auszahlung                 8:4 „Auszahlung Gutschein ····-9DWT“, Text „  Grund: …“
///   Fremdgutschein             wie der eigene, nur „Gutschein Nr. `<Nummer>`“ statt der
///   (`source: external`)       Maske: Verkauf aus dem Positionsnamen des Servers,
///                              Einloesung Einzweck 8:4 „Gutschein Nr. FG-1234“ und
///                              Text „  Einzweck, versteuert mit FG-1234-V“ (nur mit
///                              `taxedWith`), Mehrzweck nach „Zwischensumme“, Auszahlung
///                              „Auszahlung Gutschein Nr. …“; nie „Rest am Gutschein“
///                              (den Saldo kennt nur das fremde System)
///   Zahlungsart                entfaellt, wenn ein Gutschein eingeloest und 0 Cent
///                              bezahlt wurde (`paymentMethodText`)
///
/// Codes stehen am Bon immer in der kurzen Maske `····-XXXX` (`voucherShortCode`).
///
/// Paketintern: der Rueckfall ist veraltet, die Regeln gelten aber wie im
/// Server-Layout, damit ein Beleg ohne Layout denselben Bon zeigt.

/// Eine Zeile des Gutscheinteils.
sealed class VoucherBonLine {
  const VoucherBonLine();
}

/// Positionszeile wie jede andere Position (7:5); [name] traegt schon den Code.
class VoucherBonItemLine extends VoucherBonLine {
  const VoucherBonItemLine(this.name);
  final String name;
}

/// Zweispalter in der Breite der Rabattzeilen (8:4).
class VoucherBonPairLine extends VoucherBonLine {
  const VoucherBonPairLine(this.left, this.right);
  final String left;
  final String right;

  @override
  bool operator ==(Object other) => other is VoucherBonPairLine && other.left == left && other.right == right;

  @override
  int get hashCode => Object.hash(left, right);

  @override
  String toString() => '$left | $right';
}

/// Linksbuendiger Text; fuehrende Leerzeichen sind der Einzug, mit dem er umbricht.
class VoucherBonTextLine extends VoucherBonLine {
  const VoucherBonTextLine(this.text);
  final String text;
}

/// Text unter einem Mehrzweck-Verkauf.
const String multiPurposeVatNote = '  USt bei Einlösung';

const String _restText = '  Rest am Gutschein';

/// Zeile eines Fremdgutscheins `Gutschein Nr. <Nummer>`; `null` bei einem
/// eigenen Gutschein oder ohne Nummer (Zwilling von `fremdZeile` im npm-Layout).
String? externalVoucherLine(KeckVoucher v) {
  final n = v.number;
  return v.isExternal && n != null && n.isNotEmpty ? 'Gutschein Nr. $n' : null;
}

/// Ein gelesener Eintrag mit Wert: beim Fremdgutschein ganze positive Cent,
/// sonst wie [KeckVoucher.isValid] (Zwilling von `eintragGueltig` im
/// npm-Layout). Ein gelesener Fremdgutschein ist nie ein sendbarer Wunsch
/// (Serverfelder), traegt aber einen Wert.
bool voucherEntryValid(KeckVoucher v) => v.isExternal ? (v.valueCents ?? 0) > 0 : v.isValid;

/// Text der Verkaufszeile eines Wertgutscheins, der nur als Eintrag steht
/// (Mehrzweck vor dem Stichtag des 0-%-Topfs): Fremdgutschein mit Nummer,
/// Mehrzweck mit Code, sonst der Belegtext.
String voucherSaleText(KeckVoucher v) {
  final fremd = externalVoucherLine(v);
  if (fremd != null) return '$fremd (Mehrzweckgutschein)';
  return isMultiPurposeWithCode(v) ? 'Mehrzweckgutschein${voucherCodeSuffixText(v)}' : v.receiptText;
}

/// Steht der Betrag des Eintrags als Position am Beleg (Einzweck, Leistung, 0-%-Topf)?
bool voucherStandsAsItem(KeckVoucher v) =>
    artOderNull(v) == VoucherType.singlePurpose || artOderNull(v) == VoucherType.service || v.zeroRateBucket == true;

/// Mehrzweckgutschein mit Code (Altart `value`, vom Server als `multi_purpose` gekennzeichnet).
bool isMultiPurposeWithCode(KeckVoucher v) =>
    artOderNull(v) == VoucherType.value && v.voucherType == VoucherType.multiPurpose.wire;

/// Code fuer die Belegzeile mit fuehrendem Leerzeichen: immer die kurze Maske
/// `····-XXXX` aus dem Code-Ende (auch wenn ein alter Beleg die lange
/// `····-····-XXXX` im Eintrag traegt), ohne den Platzhalter `no-code`, den
/// der Server Alt-Eintraegen ohne Code setzt. Leer, wenn es keinen gibt.
String voucherCodeSuffixText(KeckVoucher v) {
  final code = v.code;
  return code != null && code.isNotEmpty && code != 'no-code' ? ' ${voucherShortCode(v)}' : '';
}

/// Maskierte Codes (`····-····-XXXX` alt, `····-XXXX` neu) drucken immer kurz;
/// ein Alt-Code ohne Maske (z. B. `GS-1`) bleibt, wie er ist. Zwilling von
/// `codeKurz` im npm-Layout.
String voucherShortCode(KeckVoucher v) {
  final code = v.code ?? '';
  final endung = voucherEnding(v);
  return code.contains('····') && endung != null ? '····-$endung' : code;
}

/// Die vier letzten Zeichen des Codes ([KeckVoucher.codeSuffix], sonst aus der Maske), oder `null`.
String? voucherEnding(KeckVoucher v) {
  final ende = v.codeSuffix;
  if (ende != null && ende.isNotEmpty) return ende;
  final code = v.code;
  return code != null && code.length >= 4 && code != 'no-code' ? code.substring(code.length - 4) : null;
}

/// Belegtext eines Gutscheins wie `gutscheinText` im npm-Layout: Gutscheinart
/// (Wert-/Aktionsgutschein), dann Code (kurze Maske) und Name; ein Name, der
/// die Art schon nennt, steht allein (auch das alte „Promotionsgutschein“
/// einer Aktion). Ohne Betrag (der steht rechts in der Zeile).
String layoutVoucherText(KeckVoucher v) {
  var text = switch (artOderNull(v)) {
    VoucherType.value => 'Wertgutschein',
    VoucherType.promo => 'Aktionsgutschein',
    _ => '',
  };
  final name = v.name;
  if (name != null && _nenntArt(v, name, text)) return name;
  final code = v.code;
  if (code != null && code.isNotEmpty) text += ' ${voucherShortCode(v)}';
  if (name != null && name.isNotEmpty) text += ' - $name';
  return text;
}

/// Zuordnung einer Gutscheinposition zu ihrem Eintrag.
class VoucherItemMatch {
  const VoucherItemMatch(this.voucher, {required this.last});
  final KeckVoucher voucher;

  /// Letzte Position dieses Gutscheins (darunter stehen Vermerk und Rest).
  final bool last;
}

int _betrag(KeckVoucher v) => (v.amountCents ?? v.valueCents ?? 0).abs();

/// Welche Gutscheinposition (`voucher`/`voucher_float`) gehoert zu welchem
/// Eintrag? Jede Position hoechstens einem Eintrag, Eintraege in ihrer
/// Reihenfolge (der Server haengt die Positionen in derselben Reihenfolge an).
/// Verkauf: erste freie Position der Art mit demselben Betrag und ohne Code im
/// Namen. Einloesung: freie Positionen mit genau dem Namen
/// `Gutschein ····-<Endung>`, Auszahlung: `Auszahlung Gutschein ····-<Endung>`
/// -- der Reihe nach, bis ihr Betrag den des Eintrags erreicht (ein
/// Kleinunternehmer-Einzweck oder eine Leistung ueber mehrere Saetze hat je
/// Satz eine Position; zwei Gutscheine mit derselben Endung teilen sich so nie
/// eine Position). Ohne Betrag am Eintrag genau eine Position.
Map<int, VoucherItemMatch> voucherItemMatches(List<KasseneckItem> items, List<KeckVoucher> vouchers) {
  final zuordnung = <int, VoucherItemMatch>{};
  bool gutscheinzeile(KasseneckItem it) => it.isVoucher || it.isVoucherFloat;
  for (final v in vouchers) {
    if (!voucherStandsAsItem(v)) continue;
    if (v.action == VoucherAction.sell) {
      final art = v.zeroRateBucket == true ? 'voucher_float' : 'voucher';
      final cents = _betrag(v);
      for (var k = 0; k < items.length; k++) {
        final it = items[k];
        if (!zuordnung.containsKey(k) && it.kind == art && it.totalCents.abs() == cents && !it.name.contains('····')) {
          zuordnung[k] = VoucherItemMatch(v, last: true);
          break;
        }
      }
      continue;
    }
    final fremd = externalVoucherLine(v);
    final endung = voucherEnding(v);
    if ((fremd == null && endung == null) || (v.action != VoucherAction.redeem && v.action != VoucherAction.payout)) continue;
    final name = '${v.action == VoucherAction.payout ? 'Auszahlung ' : ''}${fremd ?? 'Gutschein ····-$endung'}';
    final ziel = _betrag(v);
    final genommen = <int>[];
    var summe = 0;
    for (var k = 0; k < items.length; k++) {
      final it = items[k];
      if (zuordnung.containsKey(k) || !gutscheinzeile(it) || it.name != name) continue;
      if (genommen.isNotEmpty && (ziel <= 0 || summe >= ziel)) continue;
      genommen.add(k);
      summe += it.totalCents.abs();
    }
    for (final (n, k) in genommen.indexed) {
      zuordnung[k] = VoucherItemMatch(v, last: n == genommen.length - 1);
    }
  }
  return zuordnung;
}

/// Die Zeilen einer Gutscheinposition mit ihrem Eintrag. Verkauf als
/// gewoehnliche Positionszeile mit dem Code des Eintrags; Einloesung und
/// Auszahlung ohne Menge in der Breite der Rabattzeilen (8:4), damit
/// „Gutschein ····-9DWT“ auch auf 58 mm in einer Zeile steht. [amount] ist
/// der Betrag der Position, wie die Positionszeilen ihn rechts zeigen
/// („-30,50 A“); [formatCents] formatiert den Rest, [currency] ist die
/// Waehrungsangabe des Weges.
List<VoucherBonLine> voucherItemLines(
  KasseneckItem item,
  VoucherItemMatch match, {
  required String amount,
  required String Function(int cents) formatCents,
  required String currency,
}) {
  final v = match.voucher;
  if (v.action == VoucherAction.sell) {
    return [
      VoucherBonItemLine('${item.name}${voucherCodeSuffixText(v)}'),
      if (artOderNull(v) == VoucherType.value) const VoucherBonTextLine(multiPurposeVatNote),
    ];
  }
  final zeilen = <VoucherBonLine>[VoucherBonPairLine(item.name, amount)];
  if (!match.last) return zeilen;
  if (v.action == VoucherAction.payout) {
    final grund = v.reason?.trim() ?? '';
    if (grund.isNotEmpty) zeilen.add(VoucherBonTextLine('  Grund: $grund'));
    return zeilen;
  }
  final art = artOderNull(v) == VoucherType.service ? 'Leistung' : 'Einzweck';
  final belegt = v.taxedWith;
  if (v.isExternal) {
    // Fremdgutschein: Vermerk nur mit `taxedWith` (Beleg im fremden System, wie gesendet), kein Rest.
    if (belegt != null && belegt.isNotEmpty) zeilen.add(VoucherBonTextLine('  $art, versteuert mit $belegt'));
    return zeilen;
  }
  if (belegt != null && belegt.isNotEmpty) {
    zeilen.add(VoucherBonTextLine('  $art, versteuert mit Beleg $belegt'));
  } else if (v.exempt == true) {
    zeilen.add(VoucherBonTextLine('  $art, befreit verkauft (Kleinunternehmer)'));
  }
  // Rest: Betrag mit Waehrung wie beim Mehrzweckgutschein, Stueck
  // rechtsbuendig. Die Gesamtzahl kennt der Beleg nicht.
  if (artOderNull(v) == VoucherType.service) {
    final rest = v.remainingQuantityAfter;
    if (rest != null) zeilen.add(VoucherBonPairLine(_restText, '$rest Stück'));
  } else if (v.balanceAfterCents case final saldo?) {
    zeilen.add(VoucherBonPairLine(_restText, '${formatCents(saldo)} $currency'));
  }
  return zeilen;
}

/// Zeilen nach „Zwischensumme“: Wertgutscheine (Altform und Mehrzweck mit
/// Code) mit Einloesung oder Auszahlung ohne `zeroRateBucket`. [sign] ist
/// `KasseneckReceipt.valueVoucherSign` (am Storno geht der Wert ohne Minus auf
/// den Gutschein zurueck, ohne Rest); eine Altform behaelt ihre bisherige
/// Beschriftung ([KeckVoucher.receiptText]), [currency] ist die
/// Waehrungsangabe des Weges. `null` fuer einen Eintrag, der hier nicht steht.
List<VoucherBonPairLine>? voucherPaymentLines(
  KeckVoucher v, {
  required int sign,
  required String currency,
  required String Function(int cents) formatCents,
}) {
  if (artOderNull(v) != VoucherType.value || v.zeroRateBucket == true || isReturnVoucher(v)) return null;
  if (v.action != VoucherAction.redeem && v.action != VoucherAction.payout) return null;
  final wert = formatCents(v.valueCents ?? 0);
  final betrag = sign == 1 ? '-$wert $currency' : '$wert $currency';
  // Fremdgutschein: „Gutschein Nr. <Nummer>“, nie ein Rest (den Saldo kennt nur das fremde System).
  final fremd = externalVoucherLine(v);
  final endung = fremd == null && isMultiPurposeWithCode(v) ? voucherEnding(v) : null;
  // Auszahlung wie npm (layout.ts): „Auszahlung “ vor dem Text des Pakets
  // (gutscheinText); eine Einloesung der Altform behaelt ihren bisherigen
  // Dart-Text (receiptText), damit Altbelege byte-gleich bleiben.
  final String text;
  if (fremd != null) {
    text = fremd;
  } else if (endung != null) {
    text = 'Gutschein ····-$endung';
  } else if (v.action == VoucherAction.payout) {
    text = layoutVoucherText(v);
  } else {
    text = v.receiptText;
  }
  return [
    VoucherBonPairLine(v.action == VoucherAction.payout ? 'Auszahlung $text' : text, betrag),
    if (endung != null && sign == 1 && v.balanceAfterCents != null)
      VoucherBonPairLine(_restText, '${formatCents(v.balanceAfterCents!)} $currency'),
  ];
}

/// Eintrag einer Rueckgabe als Gutschein: Mehrzweck (`value`), `redeem` mit
/// `fromReturn` (Zwilling von `istRueckgabeGutschein` im npm-Layout).
bool isReturnVoucher(KeckVoucher v) =>
    v.fromReturn == true && v.action == VoucherAction.redeem && artOderNull(v) == VoucherType.value;

/// Summe der Rueckgabe-Gutscheine eines Belegs in Cent (0 ohne Rueckgabe).
int returnVoucherCents(KasseneckReceipt r) =>
    (r.vouchers ?? const <KeckVoucher>[]).where(isReturnVoucher).fold(0, (s, v) => s + (v.valueCents ?? 0));

/// Betrag der Zeile „Gesamt:“: wie [KasseneckReceipt.sumCents], bei einer
/// Rueckgabe als Gutschein ohne den Gutschein -- der Storno zeigt wie ein
/// Bar-Storno den Betrag der Waren (npm-Layout 1.25.0).
int displayedTotalCents(KasseneckReceipt r) => r.sumCents - returnVoucherCents(r);

/// Zahlwege unter „Gesamt:“ bei einer Rueckgabe als Gutschein, je mit Betrag
/// (8:4): jeder neue Gutschein „Gutschein ····-XXXX“ | „-24,90 €“, dann jede
/// Zahlung ausser 0 Cent (Mitarbeiter-Trinkgeld bar zurueck). `null` ohne
/// Rueckgabe -- dann gilt die Zeile „Zahlungsart:“ ([paymentMethodText]).
List<VoucherBonPairLine>? returnPaymentLines(
  KasseneckReceipt r, {
  required String currency,
  required String Function(int cents) formatCents,
}) {
  final rueckgaben = (r.vouchers ?? const <KeckVoucher>[]).where(isReturnVoucher).toList();
  if (rueckgaben.isEmpty) return null;
  return [
    for (final v in rueckgaben)
      VoucherBonPairLine(_rueckgabeText(v), '${formatCents(-(v.valueCents ?? 0))} $currency'),
    for (final z in r.payments ?? const <KeckPayment>[])
      if (z.amountCents != 0) VoucherBonPairLine(z.method?.label ?? r.paymentMethod.label, '${formatCents(z.amountCents)} $currency'),
  ];
}

String _rueckgabeText(KeckVoucher v) {
  final endung = voucherEnding(v);
  return endung != null ? 'Gutschein ····-$endung' : 'Gutschein';
}

/// Nennt [name] die Gutscheinart [art] schon? Alte Belege nennen den
/// Aktionsgutschein noch „Promotionsgutschein“: auch dieser Name steht allein.
bool _nenntArt(KeckVoucher v, String name, String art) {
  final klein = name.toLowerCase();
  return klein.contains(art.toLowerCase()) || (artOderNull(v) == VoucherType.promo && klein.contains('promotionsgutschein'));
}

/// Text rechts in der Zeile „Zahlungsart:“ am Bon des Rueckfalls, oder `null`,
/// wenn die Zeile entfaellt (Zwilling von `zahlungsZeilen` im npm-Layout).
///
/// Traegt der Beleg eine Gutschein-Einloesung (nicht die Aktion, die ist keine
/// Zahlung), entfaellt, was 0 Cent kostet (§ 132a Abs. 3 BAO: die Zahlungsart
/// ist kein Pflichtinhalt, der Betrag bleibt): ohne Zahlungsliste bei Summe 0,
/// bei einer Zahlung mit 0 Cent die Zeile, bei mehreren die Zahlungen mit
/// 0 Cent -- bleibt dann eine Zahlart, steht sie da, sonst die des Belegs.
/// Ohne Gutschein-Einloesung (Null-, Startbeleg) bleibt alles wie bisher.
String? paymentMethodText(KasseneckReceipt r) {
  final mitGutschein = (r.vouchers ?? const <KeckVoucher>[])
      .any((v) => v.action == VoucherAction.redeem && artOderNull(v) != VoucherType.promo);
  final label = r.paymentMethod.label;
  if (!mitGutschein) return label;
  final zahlungen = r.payments ?? const <KeckPayment>[];
  if (zahlungen.isEmpty) return r.sumCents == 0 ? null : label;
  final bezahlt = zahlungen.where((z) => z.amountCents != 0).toList();
  if (bezahlt.isEmpty) return null;
  if (zahlungen.length == 1) return label;
  final arten = {for (final z in bezahlt) z.method};
  final art = arten.length == 1 ? arten.single : null;
  return art?.label ?? label;
}
