/// Gutscheinwuensche eines Verkaufs vor dem Senden pruefen: Zwilling der
/// Regeln in `createReceiptParams`/`checkVoucherCombinationError` im
/// npm-Paket, die wiederum die Pruefung des Servers (`gutschein-beleg.plane`)
/// abbilden. Gemeinsam fuer den Weg mit API-Schluessel (`KasseneckApi`) und
/// den Kassenweg (`RegisterReceiptClient.sell`): was der Server abwiese, geht
/// gar nicht erst hinaus, und keine Belegnummer wird verbraucht.
library;

import 'package:kreiseck_validator/kreiseck_validator.dart' show Valid, VoucherCode;

import '../../enums/voucher_action.dart';
import '../../enums/voucher_type.dart';
import '../../models/kasseneck_item.dart';
import '../../models/keck_voucher.dart';
import '../register/fehler.dart';

/// Eine Gutscheinzeile (`kind` `voucher`/`voucher_float`) setzt nur der
/// Server; in einem Verkauf ist sie `voucher_invalid`, vor jeder anderen
/// Positionspruefung.
String? voucherItemError(List<KasseneckItem> items) => items.any((p) => p.isVoucher || p.isVoucherFloat)
    ? 'voucher_invalid: Gutschein-Positionen (kind voucher, voucher_float) setzt nur der Server.'
    : null;

/// Braucht dieser Verkauf keine Positionen? Ein Gutscheinverkauf ist ein
/// Umsatz ohne Positionen, eine Auszahlung der neuen Form ebenso.
bool vouchersWithoutItems(List<KeckVoucher> vouchers) =>
    vouchers.any((v) => v.action == VoucherAction.sell || v.action == VoucherAction.payout);

/// Was an den Gutscheinen nicht stimmt, oder `null`. [training]: ein
/// Schulungsbeleg kennt die neue Form nicht.
String? voucherWishError(List<KeckVoucher> vouchers, List<KasseneckItem> items, {required bool training}) {
  for (final v in vouchers) {
    final feld = v.serverFields;
    if (feld.isNotEmpty) return 'voucher_invalid: Das Feld ${feld.first} setzt nur der Server.';
  }
  if (training && vouchers.any((v) => v.isNewForm)) {
    return 'Gutscheine der neuen Form gibt es nicht auf Schulungsbelegen (receiptType training).';
  }
  if (vouchers.any((v) => !v.isValid)) return 'Ungültige Vouchers übergeben.';
  return voucherCombinationError(vouchers, items);
}

/// Ein Beleg nur aus Auszahlungen der neuen Form (Server
/// `gutschein-beleg.istNurAuszahlung`, erst nach dem Anhaengen des
/// Trinkgelds): genau eine Barzahlung ueber den negativen Zahlbetrag.
bool isPayoutOnly(List<KeckVoucher> vouchers, List<KasseneckItem> items, {required bool withTip}) =>
    vouchers.isNotEmpty && vouchers.every((v) => v.action == VoucherAction.payout) && items.isEmpty && !withTip;

/// Kombinationen der Gutscheine eines Belegs, wie der Server sie annimmt.
/// Altform wie bisher; dazu fuer die neue Form: Verkauf und Einloesung nie
/// zusammen, sobald einer davon die neue Form hat (eine Auszahlung zaehlt
/// hier nicht), der Aktionsgutschein steht allein, eine Auszahlung nie mit
/// einem Altform-Rabatt. Die Altform-Zaehler zaehlen die neue Form bewusst
/// nicht mit.
String? voucherCombinationError(List<KeckVoucher> vouchers, List<KasseneckItem> items) {
  var einloesenWert = 0;
  var verkaufenWert = 0;
  var einloesenPromo = 0;
  var verkaufenPromo = 0;
  for (final v in vouchers) {
    if (v.type == VoucherType.value && v.action == VoucherAction.redeem) {
      einloesenWert++;
    } else if (v.type == VoucherType.value && v.action == VoucherAction.sell) {
      verkaufenWert++;
    } else if (v.type == VoucherType.promo && v.action == VoucherAction.redeem) {
      einloesenPromo++;
    } else if (v.type == VoucherType.promo && v.action == VoucherAction.sell) {
      verkaufenPromo++;
    }
  }

  final neu = vouchers.where((v) => v.isNewForm).toList();
  final handel = vouchers.where((v) => v.action == VoucherAction.sell || v.action == VoucherAction.redeem).toList();
  if (handel.any((v) => v.action == VoucherAction.sell) &&
      handel.any((v) => v.action == VoucherAction.redeem) &&
      handel.any((v) => v.isNewForm)) {
    return 'Ungültige Daten: Ein Beleg kann Gutscheine der neuen Form nicht zugleich verkaufen und einlösen';
  }
  if (neu.any((v) => v.type == VoucherType.promotion) && vouchers.length > 1) {
    return 'Ungültige Daten: Ein Aktionsgutschein (type promotion) darf nicht mit anderen Gutscheinen kombiniert werden';
  }
  if (neu.any((v) => v.action == VoucherAction.payout) && vouchers.any((v) => !v.isNewForm && v.type == VoucherType.promo)) {
    return 'Ungültige Daten: Eine Auszahlung (action payout) darf nicht mit einem Gutschein mit type promo kombiniert werden';
  }
  final einloesenNeu = neu.where((v) => v.action == VoucherAction.redeem).length;

  final einloesenGesamt = einloesenWert + einloesenPromo;
  final verkaufenGesamt = verkaufenWert + verkaufenPromo;
  if (verkaufenPromo > 0) {
    return 'Ungültige Daten: Gutscheine mit type promo dürfen nicht verkauft werden';
  }
  if (einloesenPromo > 1) {
    return 'Ungültige Daten: Es darf nur ein Gutschein mit type promo eingelöst werden';
  }
  if (einloesenPromo > 0 && einloesenGesamt > 1) {
    return 'Ungültige Daten: Ein Gutschein mit type promo darf nicht mit anderen Gutscheinen kombiniert werden';
  }
  if (einloesenPromo > 0 && verkaufenGesamt > 0) {
    return 'Ungültige Daten: Mit einem Gutschein mit type promo dürfen nicht andere Gutscheine verkauft werden';
  }
  if ((einloesenGesamt > 0 || einloesenNeu > 0) && items.isEmpty) {
    return 'Ungültige Daten: Gutscheine mit action redeem benötigen mindestens ein item';
  }
  return null;
}


/// Die Schreibweisen der Gutscheincodes eines Verkaufs, die in keinem
/// Fehlertext stehen duerfen (Zwilling von `createReceiptRufen`): der Code, wie
/// er getippt wurde (getrimmt, ab 8 Zeichen, auch ungueltig), dazu Normalform
/// und formatierte Form eines gueltigen Codes. Kurze Reste (Endung mit vier
/// Zeichen) kommen nie vor. Laengste zuerst, damit ein Teilstueck keinen Rest
/// des laengeren Codes stehen laesst.
List<String> voucherSecrets(Iterable<KeckVoucher> vouchers) {
  final geheim = <String>{};
  for (final v in vouchers) {
    final code = v.code;
    if (code == null) continue;
    final geprueft = VoucherCode.validate(code);
    if (geprueft is Valid) {
      geheim.add(geprueft.normalized);
      geheim.add(VoucherCode.format(geprueft.normalized));
    }
    final roh = code.trim();
    if (roh.length >= 8) geheim.add(roh);
  }
  return geheim.toList()..sort((a, b) => b.length.compareTo(a.length));
}

/// Schwaerzt die [geheim]en Schreibweisen im Text eines Serverfehlers mit
/// `****`; Code und Daten bleiben, damit die Kasse am Code entscheidet. Ohne
/// Treffer kommt derselbe Fehler zurueck.
KasseneckApiError redactVoucherCodes(KasseneckApiError fehler, List<String> geheim) {
  if (!geheim.any(fehler.message.contains)) return fehler;
  final text = geheim.fold(fehler.message, (t, g) => t.split(g).join('****'));
  return KasseneckApiError(fehler.functionName, text, code: fehler.code, details: fehler.details);
}
