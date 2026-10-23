import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/enums/voucher_type.dart';
import 'package:kasseneck_api/models/keck_payment.dart';
import 'package:kasseneck_api/models/keck_voucher.dart';
import 'package:kasseneck_api/pos.dart' show PosVoucherSettings, VoucherCheck, VoucherStatus, VoucherValidity;
import 'package:kasseneck_api/src/receipt/due.dart';

/// Die Welt eines Zahlbetrag-Falls (`setup` in `v3/zahlbetrag-faelle.json`,
/// deutsche Form der Server-Dokumente) in die Angaben, die eine Kasse an
/// `receiptDueCents` gibt: gepruefte Gutscheine (wie `checkVoucher` sie
/// liefert), die Gutschein-Einstellung der Kasse und die Artikel fuer
/// Leistungsgutscheine. Zwilling von `test/gutschein-setup.ts` im npm-Paket.

const _art = {'mehrzweck': 'multi_purpose', 'einzweck': 'single_purpose', 'leistung': 'service', 'aktion': 'promotion'};
const _status = {
  'aktiv': VoucherStatus.active,
  'aufgebraucht': VoucherStatus.usedUp,
  'abgelaufen': VoucherStatus.expired,
  'ausgezahlt': VoucherStatus.paidOut,
  'storniert': VoucherStatus.cancelled,
  'gesperrt': VoucherStatus.blocked,
};

/// Ein Gutschein-Dokument des Servers so, wie `checkVoucher` ihn der Kasse zeigt.
VoucherCheck pruefungAus(Map<String, dynamic> daten) {
  final artikel = daten['artikel'] as Map?;
  return VoucherCheck(
    type: VoucherType.fromWire(_art[daten['art']])!,
    status: _status[daten['status']]!,
    codeSuffix: daten['codeEnde'] as String,
    balanceCents: daten['saldoCents'] as int?,
    faceValueCents: daten['nennwertCents'] as int?,
    quantity: daten['stueck'] as int?,
    remainingQuantity: daten['stueckOffen'] as int?,
    vatRateBp: daten['satzBp'] as int?,
    discountCents: daten['rabattCents'] as int?,
    discountPercentBp: daten['rabattProzentBp'] as int?,
    exempt: daten['kleinunternehmer'] == true && daten['satzBp'] == 0 ? true : null,
    article: artikel == null
        ? null
        : VoucherArticle(
            id: artikel['id'] as String,
            name: artikel['name'] as String,
            vatRateBp: artikel['satzBp'] as int,
            priceCents: artikel['preisCents'] as int,
          ),
  );
}

/// Die Angaben eines Falls aus seinem `setup`.
({List<VoucherDueInfo>? info, PosVoucherSettings? settings, List<VoucherDueArticle>? articles}) angabenAusSetup(
    Map<String, dynamic>? setup) {
  if (setup == null) return (info: null, settings: null, articles: null);
  final gutscheine = setup['gutscheine'] as List?;
  final einstellung = setup['einstellung'] as Map?;
  final artikel = setup['artikel'] as List?;
  return (
    info: gutscheine == null
        ? null
        : [
            for (final g in gutscheine.cast<Map<String, dynamic>>())
              VoucherDueInfo(code: g['code'] as String, check: pruefungAus((g['daten'] as Map).cast())),
          ],
    settings: einstellung == null
        ? null
        : PosVoucherSettings(
            sale: true,
            valueVoucherType: einstellung['wertArt'] == 'einzweck' ? VoucherType.singlePurpose : VoucherType.multiPurpose,
            vatRateBp: einstellung['wertArt'] == 'einzweck' ? einstellung['satzBp'] as int : null,
          ),
    articles: artikel == null
        ? null
        : [
            for (final a in artikel.cast<Map<String, dynamic>>())
              VoucherDueArticle(
                id: a['id'] as String,
                priceCents: a['unitPriceCents'] as int,
                vatRateBp: ((a['vatRate'] as num) * 100).round(),
              ),
          ],
  );
}

/// Eine Pruefung in der Drahtform von `checkVoucher` (fuer die erzeugten
/// Faelle, die sie schon englisch fuehren).
VoucherCheck pruefungAusDraht(Map<String, dynamic> o) {
  final artikel = o['article'] as Map?;
  final g = o['validity'] as Map?;
  return VoucherCheck(
    type: VoucherType.fromWire(o['type'])!,
    status: VoucherStatus.fromWire(o['status'])!,
    codeSuffix: o['codeSuffix'] as String,
    balanceCents: o['balanceCents'] as int?,
    faceValueCents: o['faceValueCents'] as int?,
    quantity: o['quantity'] as int?,
    remainingQuantity: o['remainingQuantity'] as int?,
    vatRateBp: o['vatRateBp'] as int?,
    discountCents: o['discountCents'] as int?,
    discountPercentBp: o['discountPercentBp'] as int?,
    exempt: o['exempt'] as bool?,
    article: artikel == null
        ? null
        : VoucherArticle(
            id: artikel['id'] as String,
            name: artikel['name'] as String,
            vatRateBp: artikel['vatRateBp'] as int,
            priceCents: artikel['priceCents'] as int,
          ),
    validity: g == null
        ? null
        : VoucherValidity(
            pattern: g['pattern'] as String,
            redeemableUntil: g['redeemableUntil'] as String?,
            refundableUntil: g['refundableUntil'] as String?,
            validUntil: g['validUntil'] as String?,
          ),
  );
}

/// Trinkgeld eines Vertragsfalls (`input.tip` bzw. `input.payments[].tipCents`) in
/// die Angaben an `receiptDueCents`. `tip.owner: true` heisst: an einen
/// Kassen-Benutzer mit Inhaber-Kennzeichen; sonst (auch fuer `tipCents`) bucht
/// der Server ohne Kassen-Benutzer Personal-Trinkgeld. Zwilling von
/// `optionenDesFalls` in `test/gutschein-setup.ts`.
({ReceiptDueTip? tip, List<KeckPaymentInput>? payments, ReceiptDueTipRecipient? tipRecipient}) trinkgeldAus(
    Map<String, dynamic> input) {
  final tip = input['tip'] as Map<String, dynamic>?;
  final zahlungen = (input['payments'] as List?)?.cast<Map<String, dynamic>>();
  final mitTipCents = zahlungen?.any((z) => z['tipCents'] != null) ?? false;
  return (
    tip: tip == null ? null : ReceiptDueTip(tip['cents'] as int),
    payments: zahlungen == null
        ? null
        : [
            for (final z in zahlungen)
              KeckPaymentInput(
                method: KeckPaymentMethod.values.byName(z['method'] as String),
                amountCents: 1,
                tipCents: z['tipCents'] as int?,
              ),
          ],
    tipRecipient: tip != null
        ? (tip['owner'] == true ? ReceiptDueTipRecipient.owner : ReceiptDueTipRecipient.staff)
        : (mitTipCents ? ReceiptDueTipRecipient.staff : null),
  );
}

/// Der Server weist den Fall ab: in `expected` steht nur der /v3-Code (`errorCode`).
bool istAbgelehnt(Map<String, dynamic> fall) => (fall['expected'] as Map).containsKey('errorCode');
