import 'package:kasseneck_api/enums/voucher_action.dart';
import 'package:kasseneck_api/enums/voucher_type.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/models/keck_voucher.dart';

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
///                              und 8:4 „  Rest am Gutschein“ | „19,50  “ bzw. „2 Stück“
///   Einloesung Mehrzweck       nach „Zwischensumme“ „Gutschein ····-9DWT“ und Rest
///   Auszahlung                 8:4 „Auszahlung Gutschein ····-9DWT“, Text „  Grund: …“
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

/// Steht der Betrag des Eintrags als Position am Beleg (Einzweck, Leistung, 0-%-Topf)?
bool voucherStandsAsItem(KeckVoucher v) =>
    v.type == VoucherType.singlePurpose || v.type == VoucherType.service || v.zeroRateBucket == true;

/// Mehrzweckgutschein mit Code (Altart `value`, vom Server als `multi_purpose` gekennzeichnet).
bool isMultiPurposeWithCode(KeckVoucher v) =>
    v.type == VoucherType.value && v.voucherType == VoucherType.multiPurpose.wire;

/// Code fuer die Belegzeile: die Maske des Eintrags mit fuehrendem
/// Leerzeichen, ohne den Platzhalter `no-code`, den der Server Alt-Eintraegen
/// ohne Code setzt. Leer, wenn es keinen gibt.
String voucherCodeSuffixText(KeckVoucher v) {
  final code = v.code;
  return code != null && code.isNotEmpty && code != 'no-code' ? ' $code' : '';
}

/// Die vier letzten Zeichen des Codes ([KeckVoucher.codeSuffix], sonst aus der Maske), oder `null`.
String? voucherEnding(KeckVoucher v) {
  final ende = v.codeSuffix;
  if (ende != null && ende.isNotEmpty) return ende;
  final code = v.code;
  return code != null && code.length >= 4 && code != 'no-code' ? code.substring(code.length - 4) : null;
}

/// Belegtext eines Gutscheins wie `gutscheinText` im npm-Layout: Gutscheinart
/// (Wert-/Promotionsgutschein), dann Code und Name; ein Name, der die Art
/// schon nennt, steht allein. Ohne Betrag (der steht rechts in der Zeile).
String layoutVoucherText(KeckVoucher v) {
  var text = switch (v.type) {
    VoucherType.value => 'Wertgutschein',
    VoucherType.promo => 'Promotionsgutschein',
    _ => '',
  };
  final name = v.name;
  if (name != null && name.toLowerCase().contains(text.toLowerCase())) return name;
  final code = v.code;
  if (code != null && code.isNotEmpty) text += ' $code';
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
    final endung = voucherEnding(v);
    if (endung == null || (v.action != VoucherAction.redeem && v.action != VoucherAction.payout)) continue;
    final name = '${v.action == VoucherAction.payout ? 'Auszahlung ' : ''}Gutschein ····-$endung';
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
/// („-30,50 A“); [formatCents] formatiert den Rest.
List<VoucherBonLine> voucherItemLines(
  KasseneckItem item,
  VoucherItemMatch match, {
  required String amount,
  required String Function(int cents) formatCents,
}) {
  final v = match.voucher;
  if (v.action == VoucherAction.sell) {
    return [
      VoucherBonItemLine('${item.name}${voucherCodeSuffixText(v)}'),
      if (v.type == VoucherType.value) const VoucherBonTextLine(multiPurposeVatNote),
    ];
  }
  final zeilen = <VoucherBonLine>[VoucherBonPairLine(item.name, amount)];
  if (!match.last) return zeilen;
  if (v.action == VoucherAction.payout) {
    final grund = v.reason?.trim() ?? '';
    if (grund.isNotEmpty) zeilen.add(VoucherBonTextLine('  Grund: $grund'));
    return zeilen;
  }
  final art = v.type == VoucherType.service ? 'Leistung' : 'Einzweck';
  final belegt = v.taxedWith;
  if (belegt != null && belegt.isNotEmpty) {
    zeilen.add(VoucherBonTextLine('  $art, versteuert mit Beleg $belegt'));
  } else if (v.exempt == true) {
    zeilen.add(VoucherBonTextLine('  $art, befreit verkauft (Kleinunternehmer)'));
  }
  // Rest: Betrag fluchtet mit den Positionsbetraegen (zwei Zeichen statt
  // " A"), Stueck rechtsbuendig. Die Gesamtzahl kennt der Beleg nicht.
  if (v.type == VoucherType.service) {
    final rest = v.remainingQuantityAfter;
    if (rest != null) zeilen.add(VoucherBonPairLine(_restText, '$rest Stück'));
  } else if (v.balanceAfterCents case final saldo?) {
    zeilen.add(VoucherBonPairLine(_restText, '${formatCents(saldo)}  '));
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
  if (v.type != VoucherType.value || v.zeroRateBucket == true) return null;
  if (v.action != VoucherAction.redeem && v.action != VoucherAction.payout) return null;
  final wert = formatCents(v.valueCents ?? 0);
  final betrag = sign == 1 ? '-$wert $currency' : '$wert $currency';
  final endung = isMultiPurposeWithCode(v) ? voucherEnding(v) : null;
  // Auszahlung wie npm (layout.ts): „Auszahlung “ vor dem Text des Pakets
  // (gutscheinText); eine Einloesung der Altform behaelt ihren bisherigen
  // Dart-Text (receiptText), damit Altbelege byte-gleich bleiben.
  final String text;
  if (endung != null) {
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
