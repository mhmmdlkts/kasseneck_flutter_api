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
  // Gutscheine Stufe 4b: ein Wertgutschein nur ueber eine Sorte, die Sorte nur an einem solchen Verkauf.
  if (vouchers.any((v) => istWertVerkauf(v) && v.typeId == null)) {
    return 'voucher_type_required: Ein Mehrzweck- oder Einzweckgutschein wird nur ueber eine Gutschein-Sorte verkauft '
        '(typeId aus getKasseSettings vouchers.types).';
  }
  if (vouchers.any((v) => v.typeId != null && !istWertVerkauf(v))) {
    return 'voucher_invalid: typeId gehoert nur an den Verkauf eines Mehrzweck- oder Einzweckgutscheins.';
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
    final art = artOderNull(v);
    if (art == VoucherType.value && v.action == VoucherAction.redeem) {
      einloesenWert++;
    } else if (art == VoucherType.value && v.action == VoucherAction.sell) {
      verkaufenWert++;
    } else if (art == VoucherType.promo && v.action == VoucherAction.redeem) {
      einloesenPromo++;
    } else if (art == VoucherType.promo && v.action == VoucherAction.sell) {
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
  if (neu.any((v) => artOderNull(v) == VoucherType.promotion) && vouchers.length > 1) {
    return 'Ungültige Daten: Ein Aktionsgutschein (type promotion) darf nicht mit anderen Gutscheinen kombiniert werden';
  }
  if (neu.any((v) => v.action == VoucherAction.payout) && vouchers.any((v) => !v.isNewForm && artOderNull(v) == VoucherType.promo)) {
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

/// Die Art des Gutscheins, oder `null`, wenn er keine bekannte hat
/// ([KeckVoucher.hasType]): ein Verkauf ueber eine Sorte ohne Art oder mit
/// einer unbekannten Art.
VoucherType? artOderNull(KeckVoucher v) => v.hasType ? v.type : null;

/// Wert-Verkauf: ein Mehrzweck- oder Einzweckgutschein wird verkauft, mit Art
/// oder nur ueber die Sorte (Zwilling von `istWertVerkauf` im npm-Paket).
/// Ohne bekannte Art zaehlt nur der Verkauf ueber eine Sorte, bei dem die Art
/// fehlt ([KeckVoucher.isNewForm]); einer mit unbekannter Art nicht.
bool istWertVerkauf(KeckVoucher v) {
  if (v.action != VoucherAction.sell) return false;
  final art = artOderNull(v);
  return art == null ? v.isNewForm : art == VoucherType.multiPurpose || art == VoucherType.singlePurpose;
}

/// Grenzen wie der Server (gutschein-beleg).
const int _maxBetragCents = 1000000;
const int _maxStueck = 100;
const int _maxGrund = 200;

/// Form einer Sorten-Kennung am Wunsch (gutschein-core.ID_MUSTER ohne den
/// Ausschluss): eine reservierte `__…__` ist der Form nach gueltig, der Server
/// kennt sie nur nicht (`voucher_type_not_found`), ebenso der Zahlbetrag.
final RegExp _sorteIdForm = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

bool _istCent(int? n) => n != null && n >= 1 && n <= _maxBetragCents;
bool _istMenge(int? n) => n != null && n >= 1 && n <= _maxStueck;
bool _hatText(String? t) => t != null && t.trim().isNotEmpty;

/// Die Form eines Wunschs der neuen Form ([KeckVoucher.isValid], Zwilling von
/// `wunschFormGueltig` im npm-Paket). [sorteNoetig] `false` laesst einen
/// Wert-Verkauf ohne `typeId` zu: so rechnet der Zahlbetrag den Verkauf eines
/// Aufrufers von 11.5 mit der alten Gutschein-Einstellung weiter (der Server
/// ab Stufe 4b antwortet darauf `voucher_type_required`).
bool wunschFormGueltig(KeckVoucher v, {required bool sorteNoetig}) {
  if (v.serverFields.isNotEmpty) return false;
  if (v.vatRateBp != null ||
      v.article != null ||
      v.balanceAfterCents != null ||
      v.remainingQuantityAfter != null ||
      v.taxedWith != null ||
      v.exempt != null) {
    return false;
  }
  if (v.valueCents != null) return false;
  // Die Sorte gehoert nur an einen Wert-Verkauf (Server: sorteId sonst voucher_invalid).
  if (istWertVerkauf(v)) {
    final id = v.typeId;
    if (id == null ? sorteNoetig : !_sorteIdForm.hasMatch(id)) return false;
    return v.articleId == null && v.quantity == null && v.positions == null && v.reason == null && _istCent(v.amountCents);
  }
  if (v.typeId != null) return false;
  final art = artOderNull(v);
  final allein = art == VoucherType.multiPurpose || art == VoucherType.singlePurpose;
  if (v.action == VoucherAction.payout) {
    final grund = v.reason?.trim() ?? '';
    return allein &&
        _hatText(v.code) &&
        _istCent(v.amountCents) &&
        grund.isNotEmpty &&
        grund.length <= _maxGrund &&
        v.articleId == null &&
        v.quantity == null &&
        v.positions == null;
  }
  if (v.reason != null) return false;
  if (allein) {
    if (v.articleId != null || v.quantity != null || v.positions != null) return false;
    // Ein Verkauf ist oben als Wert-Verkauf erledigt; hier bleibt die Einloesung.
    return v.action == VoucherAction.redeem && _hatText(v.code) && _istCent(v.amountCents);
  }
  if (art == VoucherType.service) {
    if (v.amountCents != null) return false;
    if (v.action == VoucherAction.sell) {
      return _hatText(v.articleId) && _istMenge(v.quantity) && v.positions == null;
    }
    final p = v.positions;
    return _hatText(v.code) &&
        p != null &&
        p.isNotEmpty &&
        p.every((i) => i >= 0) &&
        p.toSet().length == p.length &&
        v.articleId == null &&
        v.quantity == null;
  }
  // Aktion: nur einloesen, nur mit Code. (Altart mit Auszahlung ist oben schon raus.)
  return art == VoucherType.promotion &&
      v.action == VoucherAction.redeem &&
      _hatText(v.code) &&
      v.amountCents == null &&
      v.articleId == null &&
      v.quantity == null &&
      v.positions == null;
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
