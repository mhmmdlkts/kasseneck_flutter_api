/// Zahlbetrag eines Belegs in ganzen Cent: Zwilling von `receiptDueCents` in
/// `@kreiseck/kasseneck-api` 1.0 (`src/receipt/due.ts`) und damit von
/// `createReceipt` im Backend, also `receipt-toepfe.belegToepfe(...).zaehlerDeltaCents`
/// plus `payments-core.wertgutscheinFlussCents`, mit den Trinkgeld-Positionen,
/// die `tip-core.buildTipItems` aus `tip` bzw. aus `payments[].tipCents` baut.
///
/// `createReceipt` hat keinen Probelauf. Unter `/v3` ist `payments[]` Pflicht,
/// und die Summe der Zahlungen muss genau diesen Betrag treffen; wer die
/// Zahlungen baut (Kartenterminal, Rueckgeld), rechnet ihn hier vorher aus.
/// Trifft die Summe nicht, antwortet der Server mit `payments_sum_mismatch` und
/// `expectedCents`, ohne eine Belegnummer zu verbrauchen; das Paket wiederholt
/// nie selbst.
///
/// **Bewusst dieselbe Rechnung wie der Server, nicht die exakte.** Das Backend
/// rechnet die RKSV-Toepfe in Euro-Gleitkomma (Einzelpreis `Math.round(cents)/100`,
/// je Topf `priceOne * amount` in Positionsreihenfolge, Trinkgeld-Positionen
/// hinten angehaengt, gerundet mit `Math.round(euro * 100)`, Rabatt-Deckel in
/// Euro). Diese Reihenfolge ist signiert und aendert sich nicht; ein exakter
/// Zwilling wiche bei Bruchmengen auf halbem Cent ab (0,5 x 29 ct: Server 14,
/// exakt 15). Darum steht hier dieselbe Arithmetik, Schritt fuer Schritt, mit
/// IEEE-Doubles wie in JavaScript. Gerundet wird wie `Math.round` (halbe Werte
/// Richtung plus unendlich), nicht wie Darts `round()` (von null weg): am
/// Storno sind die Betraege negativ, und dort unterscheiden sich die beiden.
///
/// Geprueft gegen die Vertragsfaelle aus `v3/zahlbetrag-faelle.json`, gegen
/// die 1206 mit dem echten Backend-Code erzeugten Faelle aus
/// `receipt-due-generated.json` und gegen die 480 Gutscheinfaelle aus
/// `receipt-due-voucher-generated.json` (ebenfalls echter Backend-Code).
///
/// **Gutscheine der neuen Form** (Mehrzweck, Einzweck, Leistung, Aktion,
/// Auszahlung): der Server macht daraus Positionen und Eintraege
/// (`gutschein-beleg.plane`, Zwilling in `gutschein_plan.dart`). Was er dafuer
/// aus seinen Daten liest, gibt die Kasse mit: je Einloesung/Auszahlung die
/// Pruefung aus `checkVoucher` (`voucherInfo`, ueber den Code zugeordnet), fuer
/// einen Wertgutschein-Verkauf die Gutschein-Sorten (`voucherTypes`, Art, Satz,
/// Betrag; seit 11.8.0), fuer einen Leistungsgutschein-Verkauf den Artikel
/// (`voucherArticles`) und `smallBusiness` fuer ein Kleinunternehmer-Konto. Was fehlt oder was der
/// Server abwiese, wirft `invalid_voucher` mit dem erwarteten Server-Code in
/// [ReceiptDueError.voucherErrorCode]. Ein Beleg nur aus Auszahlungen hat
/// einen negativen Zahlbetrag (genau eine Barzahlung ueber diesen Betrag);
/// deckt ein Gutschein alles, ist der Zahlbetrag 0 (keine Zahlung, kein
/// Kartenterminal).
///
/// **Trinkgeld-Empfaenger:** Ohne `recipients` bucht der Server das Trinkgeld
/// auf den angemeldeten Kassen-Benutzer, und dessen Inhaber-Kennzeichen
/// entscheidet: Inhaber-Trinkgeld ist Umsatz (anteilig auf die Saetze der Ware,
/// mitrabattiert), Personal-Trinkgeld ein durchlaufender Posten (nie
/// rabattiert). Das weiss nur die Kasse; darum ist [ReceiptDueTipRecipient]
/// Pflicht, sobald Trinkgeld ohne `recipients` vorkommt. Ohne angemeldeten
/// Benutzer (Geraete-Schluessel) gilt `staff`.
library;

import '../../enums/keck_payment_method.dart';
import '../../enums/receipt_type.dart';
import '../../enums/voucher_action.dart';
import '../../enums/voucher_type.dart';
import '../../models/kasseneck_item.dart';
import '../../models/keck_payment.dart';
import '../../models/keck_tip.dart';
import '../../models/keck_voucher.dart';
import '../../services/vienna_time.dart';
import 'package:kreiseck_validator/kreiseck_validator.dart' show VoucherCode;
import '../kasse/gutschein.dart';
import '../register/fehler.dart' show ErrorOutcome;
import 'gutschein_plan.dart';

/// Stabiler Code von [ReceiptDueError], gleich fuer jede Ursache.
const String receiptDueErrorCode = 'receipt_due_unavailable';

/// Warum sich der Zahlbetrag nicht rechnen laesst ([ReceiptDueError.reason]).
/// Fest wie ein Backend-Code; dieselbe Liste im npm-Paket
/// (`RECEIPT_DUE_ERROR_REASONS`) und in `receipt-due-errors.json`.
///
/// `unknown_receipt_type` kann hier nicht entstehen: der Belegtyp ist ein
/// [ReceiptType], ein fremder Wert laesst sich gar nicht uebergeben. Der Name
/// steht trotzdem in der Liste, damit beide Pakete dieselben Gruende fuehren.
const List<String> receiptDueErrorReasons = [
  'unknown_receipt_type',
  'tip_not_allowed',
  'invalid_item',
  'invalid_voucher',
  'invalid_tip',
  'unknown_payment_method',
  'tip_conflict',
  'tip_recipient_missing',
  'tip_without_goods',
];

/// Der Zahlbetrag laesst sich aus dieser Eingabe nicht rechnen, etwa
/// Trinkgeld mit Betrag ohne Ware ([reason] `tip_without_goods`). Zwilling von
/// `ReceiptDueError` im npm-Paket.
///
/// Eindeutig **nicht gesendet**: die Rechnung laeuft ganz im Paket, vor jedem
/// Aufruf. [outcome] ist darum immer [ErrorOutcome.rejected]; nichts ist
/// geschehen, keine Belegnummer verbraucht, keine Karte belastet. Die Kasse
/// sagt das dem Kassier, bevor sie ein Terminal anspricht. Entscheiden am
/// [code] bzw. [reason], nie an [message] (die ist fuers Protokoll).
///
/// Bis 10.0.0-rc.1 warf die Rechnung hier einen `ArgumentError` ohne Code.
class ReceiptDueError implements Exception {
  const ReceiptDueError(this.reason, this.message, [this.voucherErrorCode]);

  /// Die Ursache im Einzelnen, ein Wert aus [receiptDueErrorReasons].
  final String reason;

  /// Fuers Protokoll, nie zum Entscheiden. Nennt nie einen Gutscheincode.
  final String message;

  /// Nur bei `invalid_voucher`: der Gutschein-Code, mit dem der Server
  /// denselben Beleg abwiese (`voucher_rate_mismatch`, `voucher_exceeds_total`,
  /// `voucher_not_found` …), fuer die Meldung an der Kasse. Zwilling von
  /// `ReceiptDueError.voucherErrorCode` im npm-Paket.
  final String? voucherErrorCode;

  /// Immer [receiptDueErrorCode].
  String get code => receiptDueErrorCode;

  /// Immer [ErrorOutcome.rejected]: es ging nichts hinaus.
  ErrorOutcome get outcome => ErrorOutcome.rejected;

  @override
  String toString() => 'ReceiptDueError($reason): Zahlbetrag: $message';
}

/// Ist [error] ein [ReceiptDueError]?
bool isReceiptDueError(Object? error) => error is ReceiptDueError;

/// Wer das Trinkgeld ohne `recipients` bekommt (Kennzeichen des angemeldeten
/// Kassen-Benutzers). Auch die Art einer fertigen Trinkgeld-Position.
enum ReceiptDueTipRecipient { owner, staff }

/// Ein Anteil am Trinkgeld samt Inhaber-Kennzeichen des Empfaengers.
class ReceiptDueTipShare {
  const ReceiptDueTipShare({required this.cents, required this.owner});

  final int cents;
  final bool owner;
}

/// Trinkgeld wie `tip` am Verkauf: Betrag, optional mit Empfaengern samt
/// Inhaber-Kennzeichen (das Kennzeichen kennt nur die Kasse).
class ReceiptDueTip {
  const ReceiptDueTip(this.cents, {this.recipients});

  /// Bruecke vom Trinkgeld am Verkauf ([KeckTip], wie es `sellReceipt`
  /// nimmt) zum Trinkgeld der Rechnung. Ob ein Empfaenger Inhaber ist, weiss
  /// nur die Kasse: [isOwner] ist Pflicht, sobald [tip] Empfaenger nennt,
  /// sonst [ReceiptDueError] `invalid_tip`. Ohne Empfaenger (`recipients`
  /// fehlt) entscheidet `tipRecipient` an [receiptDueCents]; eine leere Liste
  /// ist wie in npm und am Server kein Trinkgeld ohne Empfaenger, sondern
  /// `invalid_tip`.
  factory ReceiptDueTip.fromKeckTip(KeckTip tip, {bool Function(String registerUserId)? isOwner}) {
    final empfaenger = tip.recipients;
    if (empfaenger == null) return ReceiptDueTip(tip.cents);
    if (empfaenger.isEmpty) throw const ReceiptDueError('invalid_tip', 'recipients darf nicht leer sein.');
    if (isOwner == null) {
      throw const ReceiptDueError('invalid_tip', 'isOwner ist Pflicht, wenn das Trinkgeld Empfaenger nennt.');
    }
    return ReceiptDueTip(tip.cents, recipients: [
      for (final r in empfaenger) ReceiptDueTipShare(cents: r.cents, owner: isOwner(r.registerUserId)),
    ]);
  }

  final int cents;
  final List<ReceiptDueTipShare>? recipients;
}

/// Eine Position fuer die Rechnung. Anders als [KasseneckItem] darf die Menge
/// hier ein Bruch sein (0,375 kg) und der Steuersatz jeder Wert, den ein
/// Beleg tragen kann; [ReceiptDueLine.of] macht aus einer Position eine Zeile.
class ReceiptDueLine {
  const ReceiptDueLine({
    required this.quantity,
    required this.priceCents,
    required this.vatRate,
    this.tip,
    this.kind,
    this.articleId,
  });

  /// Die Zeile einer Position; eine Trinkgeld-Position (`kind: 'tip'`) behaelt
  /// ihre Art (Inhaber, wenn `recipient.owner == true`, sonst Personal).
  ///
  /// Gemeint sind lokal gebaute Positionen. Eine vom Server gelesene Position
  /// mit Bruchmenge oder unbekanntem Satz hat [KasseneckItem.fromJson] nicht
  /// exakt uebernehmen koennen; dann wirft dieser Aufruf, statt still falsch zu
  /// rechnen. Solche Positionen gehen ueber [ReceiptDueLine.fromJson] und
  /// [receiptDueBreakdownForLines].
  factory ReceiptDueLine.of(KasseneckItem item) {
    final ungenau = item.lossyRead;
    if (ungenau != null) {
      throw ReceiptDueError('invalid_item', 'Position "${item.name}" ist nicht exakt gelesen ($ungenau); '
          'Serverpositionen ueber ReceiptDueLine.fromJson und receiptDueBreakdownForLines rechnen.');
    }
    return ReceiptDueLine(
        quantity: item.quantity,
        priceCents: item.priceCents,
        vatRate: item.vat.rate,
        tip: item.isTip ? (item.isOwnerTip ? ReceiptDueTipRecipient.owner : ReceiptDueTipRecipient.staff) : null,
        kind: item.kind,
        articleId: item.articleId,
      );
  }

  /// Eine Position, wie der Server sie liefert (v1- oder v2-Form), roh: Menge
  /// als Bruch, Satz wie geliefert, Cent-Preis. Fehlt etwas oder ist es kein
  /// Zahlenwert, wirft der Aufruf.
  factory ReceiptDueLine.fromJson(Map<String, dynamic> json) {
    final menge = json['quantity'] ?? json['amount'];
    final cents = json['unitPriceCents'] ?? json['priceOneCents'];
    final satz = json['vatRate'] ?? json['vat'];
    if (menge is! num || cents is! num || cents != cents.toInt() || satz is! num) {
      throw ReceiptDueError('invalid_item', 'Position "${json['name']}" ohne Menge, ganzen Cent-Preis oder Steuersatz.');
    }
    final recipient = json['recipient'];
    final owner = recipient is Map && recipient['owner'] == true;
    return ReceiptDueLine(
      quantity: menge,
      priceCents: cents.toInt(),
      vatRate: satz,
      tip: json['kind'] == 'tip' ? (owner ? ReceiptDueTipRecipient.owner : ReceiptDueTipRecipient.staff) : null,
      kind: json['kind'] is String ? json['kind'] as String : null,
      articleId: json['articleId'] is String ? json['articleId'] as String : null,
    );
  }

  final num quantity;
  final int priceCents;
  final num vatRate;

  /// `null` fuer Ware; sonst die Art der Trinkgeld-Position.
  final ReceiptDueTipRecipient? tip;

  /// Kennzeichnung der Position (`tip`, `discount`, `voucher`,
  /// `voucher_float`); Ware hat keine. Ein Gutschein deckt nie eine
  /// Trinkgeld- oder Gutscheinzeile, ein Leistungsgutschein nur Ware.
  final String? kind;

  /// Artikel der Position: ein Leistungsgutschein deckt nur Positionen seines
  /// Artikels.
  final String? articleId;
}

/// Je Einloesung bzw. Auszahlung der neuen Form die gepruefte Sicht des
/// Gutscheins (aus `checkVoucher`), zugeordnet ueber den Code. Zwilling von
/// `VoucherDueInfo` im npm-Paket.
class VoucherDueInfo {
  const VoucherDueInfo({required this.code, required this.check});

  /// Der Code, wie er gesendet wird (tolerant: Gross/klein, Bindestriche,
  /// `O`/`0`, `I`/`L`/`1`). Lebt nur im Speicher; die Rechnung nennt ihn nie.
  final String code;
  final VoucherCheck check;
}

/// Artikel fuer den Verkauf eines Leistungsgutscheins: Preis und Satz wie im
/// Artikelstamm der Kasse.
class VoucherDueArticle {
  const VoucherDueArticle({required this.id, required this.priceCents, required this.vatRateBp, this.serviceVoucher});

  final String id;
  final int priceCents;

  /// Steuersatz in Basispunkten.
  final int vatRateBp;

  /// Als Leistungsgutschein freigegeben (`PosArticle.serviceVoucher`): bei
  /// `false` verkauft der Server den Artikel nicht
  /// (`voucher_service_not_allowed`); ohne Angabe rechnet der Zahlbetrag wie
  /// bisher.
  final bool? serviceVoucher;
}

/// Gutschein-Sorte fuer den Verkauf: Kennung, Art, Satz und Betrag wie in
/// `getKasseSettings` (`vouchers.types[]`). Zwilling von `VoucherDueType` im
/// npm-Paket; jede [PosVoucherType] ist eine.
class VoucherDueType {
  const VoucherDueType({required this.id, required this.kind, this.vatRateBp, required this.amount});

  final String id;

  /// [VoucherType.multiPurpose] oder [VoucherType.singlePurpose]; eine Sorte
  /// einer anderen Art verkauft der Server nicht.
  final VoucherType kind;

  /// Satz in Basispunkten, nur bei Einzweck (> 0); Mehrzweck `null`.
  final int? vatRateBp;

  /// Frei oder fest (dann traegt ein Verkauf genau diesen Betrag).
  final VoucherTypeAmount amount;
}

/// Stichtag des 0-%-Topfs fuer Mehrzweck-Verkaeufe (Backend
/// `gutschein-core.NULLTOPF_AB`). Solange er in der Zukunft liegt, zaehlt ein
/// Mehrzweck-Verkauf als Fluss; ab dem Tag als Position im 0-%-Satz. Der
/// Zahlbetrag bleibt gleich, Toepfe und Fluss verschieben sich.
const String voucherZeroRateBucketFrom = nullTopfAb;

/// Ergebnis von [receiptDueBreakdown].
class ReceiptDueBreakdown {
  const ReceiptDueBreakdown({
    required this.dueCents,
    required this.counterDeltaCents,
    required this.valueVoucherFlowCents,
    required this.bucketsCents,
  });

  /// Was die Zahlungen zusammen ergeben muessen.
  final int dueCents;

  /// Delta des Umsatzzaehlers (Summe der Toepfe).
  final int counterDeltaCents;

  /// Anteil der Wertgutscheine am Zahlbetrag.
  final int valueVoucherFlowCents;

  /// Die sechs RKSV-Toepfe je auf Cent gerundet, Namen wie am Beleg des
  /// Backends (`amountRateStandard` … `amountRatOthers`); `null` bei Start-
  /// und Nullbeleg.
  final Map<String, int>? bucketsCents;
}

/// Zahlbetrag in Cent, siehe Bibliothekskommentar.
///
/// Gutscheine der neuen Form: [voucherInfo] je Einloesung/Auszahlung die
/// Pruefung aus `checkVoucher` (fehlt sie fuer einen Code:
/// `voucher_not_found`; eine Auszahlung eines Gutscheins mit
/// [VoucherCheck.payout] `never`: `voucher_payout_not_allowed`);
/// [voucherTypes] die Gutschein-Sorten der Kasse (`getKasseSettings`,
/// `vouchers.types`, oder je Verkauf die gewaehlte): ein Wertgutschein wird
/// nur ueber eine Sorte verkauft ([KeckVoucher.typeId]), Art und Satz kommen
/// aus ihr (fehlt die Sorte hier oder verkauft der Server sie nicht:
/// `voucher_type_not_found`, ein anderer Fixbetrag oder eine andere Art am
/// Wunsch (die Sorte wurde umgestellt): `voucher_amount_mismatch`);
/// [voucherSettings] die alte Gutschein-Einstellung (bis 11.7): nur fuer einen
/// Wert-Verkauf ohne `typeId` – nennt sie eine Art, rechnet der Zahlbetrag wie
/// bisher, ohne sie oder ohne Art (so liest sich der Block jedes Servers ab
/// Stufe 4b) `voucher_type_required`; [voucherArticles] Preis und Satz fuer
/// einen Leistungsgutschein-Verkauf (fehlt der Artikel:
/// `voucher_item_mismatch`, ist er nicht freigegeben:
/// `voucher_service_not_allowed`);
/// [smallBusiness] fuer ein Kleinunternehmer-Konto (Verkauf zu 0 %, eine
/// Einzweck-Einloesung anteilig auf alle Saetze des Korbs, ebenso fuer einen
/// befreit verkauften Gutschein, [VoucherCheck.exempt]);
/// [zeroRateBucketFrom] der Stichtag des 0-%-Topfs (Vorgabe
/// [voucherZeroRateBucketFrom], nur fuer eine Test-Umgebung aendern) und
/// [today] der Wiener Tag des Belegs (`YYYY-MM-DD`, Vorgabe: heute).
int receiptDueCents(
  List<KasseneckItem> items,
  List<KeckVoucher> vouchers,
  ReceiptType receiptType, {
  ReceiptDueTip? tip,
  List<KeckPaymentInput>? payments,
  ReceiptDueTipRecipient? tipRecipient,
  List<VoucherDueInfo>? voucherInfo,
  PosVoucherSettings? voucherSettings,
  List<VoucherDueType>? voucherTypes,
  List<VoucherDueArticle>? voucherArticles,
  bool smallBusiness = false,
  String? zeroRateBucketFrom,
  String? today,
}) =>
    receiptDueBreakdown(items, vouchers, receiptType,
            tip: tip,
            payments: payments,
            tipRecipient: tipRecipient,
            voucherInfo: voucherInfo,
            voucherSettings: voucherSettings,
            voucherTypes: voucherTypes,
            voucherArticles: voucherArticles,
            smallBusiness: smallBusiness,
            zeroRateBucketFrom: zeroRateBucketFrom,
            today: today)
        .dueCents;

/// Wie [receiptDueCents], dazu Zaehler-Delta, Wertgutschein-Anteil und Toepfe.
ReceiptDueBreakdown receiptDueBreakdown(
  List<KasseneckItem> items,
  List<KeckVoucher> vouchers,
  ReceiptType receiptType, {
  ReceiptDueTip? tip,
  List<KeckPaymentInput>? payments,
  ReceiptDueTipRecipient? tipRecipient,
  List<VoucherDueInfo>? voucherInfo,
  PosVoucherSettings? voucherSettings,
  List<VoucherDueType>? voucherTypes,
  List<VoucherDueArticle>? voucherArticles,
  bool smallBusiness = false,
  String? zeroRateBucketFrom,
  String? today,
}) =>
    receiptDueBreakdownForLines([for (final i in items) ReceiptDueLine.of(i)], vouchers, receiptType,
        tip: tip,
        payments: payments,
        tipRecipient: tipRecipient,
        voucherInfo: voucherInfo,
        voucherSettings: voucherSettings,
        voucherTypes: voucherTypes,
        voucherArticles: voucherArticles,
        smallBusiness: smallBusiness,
        zeroRateBucketFrom: zeroRateBucketFrom,
        today: today);

/// Wie [receiptDueBreakdown], mit Zeilen statt Positionen (Bruchmengen).
///
/// [payments] zaehlen nur, soweit sie Trinkgeld tragen (`tipCents`): der
/// Server bucht je Zahlart so, als waere `tip` mit der Summe und dieser
/// Zahlart geschickt worden. [tip] und `payments[].tipCents` gehen nie
/// zugleich (`tip_conflict`).
ReceiptDueBreakdown receiptDueBreakdownForLines(
  List<ReceiptDueLine> lines,
  List<KeckVoucher> vouchers,
  ReceiptType receiptType, {
  ReceiptDueTip? tip,
  List<KeckPaymentInput>? payments,
  ReceiptDueTipRecipient? tipRecipient,
  List<VoucherDueInfo>? voucherInfo,
  PosVoucherSettings? voucherSettings,
  List<VoucherDueType>? voucherTypes,
  List<VoucherDueArticle>? voucherArticles,
  bool smallBusiness = false,
  String? zeroRateBucketFrom,
  String? today,
}) =>
    _rechne(
      lines,
      vouchers,
      receiptType,
      _Optionen(
        tip: tip,
        payments: payments,
        tipRecipient: tipRecipient,
        voucherInfo: voucherInfo,
        voucherSettings: voucherSettings,
        voucherTypes: voucherTypes,
        voucherArticles: voucherArticles,
        smallBusiness: smallBusiness,
        zeroRateBucketFrom: zeroRateBucketFrom,
        today: today,
      ),
    ).ergebnis;

/// Hoechstbetrag zum Vorbelegen einer Einloesung an der Kasse, in Cent, nie
/// negativ: der groesste Betrag, den der Server fuer diesen Gutschein annimmt.
///
/// Obergrenze: Saldo, offener Betrag ohne Trinkgeld (ein Gutschein deckt nie
/// das Trinkgeld, Personal wie Inhaber); bei Einzweck die deckbaren Positionen im
/// Topf seines Satzes abzueglich der schon gewaehlten Einloesungen dort. Befreit
/// verkauft bzw. als Kleinunternehmer verteilt der Server anteilig auf alle
/// Saetze (`kuTeile`); dann begrenzt jeder Topf: sein Anteil plus die schon
/// gewaehlten Einloesungen dort darf seine Positionen nicht uebersteigen.
///
/// Unter dieser Grenze wird jeder Kandidat mit genau der Rechnung von
/// [receiptDueCents] geprueft (Rundung halber Cent, groesster Rest), zuerst
/// Cent fuer Cent abwaerts (64 Schritte). Findet das nichts, sucht eine
/// Bisektion ueber [1, Grenze] und prueft danach 16 Cent aufwaerts: am Rand
/// des groessten Rests ist die Annahme nicht monoton. Leistung (wird ueber
/// Positionen eingeloest), Aktion (Rabatt rechnet der Server) und jeder nicht
/// aktive Gutschein: 0. Wirft nie [ReceiptDueError]: ist der Beleg ohne den
/// Gutschein nicht rechenbar (etwa `tip_without_goods`), ist das Ergebnis 0.
///
/// [vouchers] sind die schon gewaehlten Gutscheine des Belegs; die uebrigen
/// Angaben wie bei [receiptDueCents]. Zwilling von `voucherRedeemMaxCents` im
/// npm-Paket.
int voucherRedeemMaxCents(
  List<KasseneckItem> items,
  VoucherCheck voucher, {
  List<KeckVoucher> vouchers = const [],
  ReceiptDueTip? tip,
  List<KeckPaymentInput>? payments,
  ReceiptDueTipRecipient? tipRecipient,
  List<VoucherDueInfo>? voucherInfo,
  PosVoucherSettings? voucherSettings,
  List<VoucherDueType>? voucherTypes,
  List<VoucherDueArticle>? voucherArticles,
  bool smallBusiness = false,
  String? zeroRateBucketFrom,
  String? today,
}) =>
    voucherRedeemMaxCentsForLines([for (final i in items) ReceiptDueLine.of(i)], voucher,
        vouchers: vouchers,
        tip: tip,
        payments: payments,
        tipRecipient: tipRecipient,
        voucherInfo: voucherInfo,
        voucherSettings: voucherSettings,
        voucherTypes: voucherTypes,
        voucherArticles: voucherArticles,
        smallBusiness: smallBusiness,
        zeroRateBucketFrom: zeroRateBucketFrom,
        today: today);

/// Wie [voucherRedeemMaxCents], mit Zeilen statt Positionen (Bruchmengen).
int voucherRedeemMaxCentsForLines(
  List<ReceiptDueLine> lines,
  VoucherCheck voucher, {
  List<KeckVoucher> vouchers = const [],
  ReceiptDueTip? tip,
  List<KeckPaymentInput>? payments,
  ReceiptDueTipRecipient? tipRecipient,
  List<VoucherDueInfo>? voucherInfo,
  PosVoucherSettings? voucherSettings,
  List<VoucherDueType>? voucherTypes,
  List<VoucherDueArticle>? voucherArticles,
  bool smallBusiness = false,
  String? zeroRateBucketFrom,
  String? today,
}) {
  if (voucher.status != VoucherStatus.active) return 0;
  if (voucher.type != VoucherType.multiPurpose && voucher.type != VoucherType.singlePurpose) return 0;
  final saldo = voucher.balanceCents ?? 0;
  final o = _Optionen(
    tip: tip,
    payments: payments,
    tipRecipient: tipRecipient,
    voucherInfo: voucherInfo,
    voucherSettings: voucherSettings,
    voucherTypes: voucherTypes,
    voucherArticles: voucherArticles,
    smallBusiness: smallBusiness,
    zeroRateBucketFrom: zeroRateBucketFrom,
    today: today,
  );
  final _Rechnung r;
  try {
    r = _rechne(lines, vouchers, ReceiptType.standard, o);
  } on ReceiptDueError {
    // Nicht rechenbar (etwa Trinkgeld ohne Ware): nichts vorbelegen, die Kasse meldet es beim Zahlbetrag.
    return 0;
  }
  // Rundung je Topf: hoechstens ein halber Cent je Topf ueber dem offenen Betrag. Das Trinkgeld deckt nie ein Gutschein.
  var oben = _min(_min(saldo, r.ergebnis.dueCents + r.auszahlungCents - trinkgeldCents(r.kunde) + 6), _hoechstbetragCents);
  if (voucher.type == VoucherType.singlePurpose) {
    int topfBasis(String topf) => centSumme(r.kunde.where((it) => istDeckbar(it) && topfFuerSatz(it.vat) == topf));
    if (voucher.exempt == true || smallBusiness) {
      oben = _min(oben, _kuGrenze(r.kunde, topfBasis, r.minusJeTopf));
    } else {
      final satz = voucher.vatRateBp;
      if (satz == null) return 0;
      final topf = topfFuerSatz(satz / 100);
      oben = _min(oben, topfBasis(topf) - (r.minusJeTopf[topf] ?? 0));
    }
  }
  if (oben <= 0) return 0;
  final code = _probeCode(vouchers);
  final probe = o.mit(voucherInfo: [...?voucherInfo, VoucherDueInfo(code: code, check: voucher)]);
  bool passt(int cents) {
    try {
      _rechne(lines, [...vouchers, KeckVoucher(action: VoucherAction.redeem, type: voucher.type, code: code, amountCents: cents)],
          ReceiptType.standard, probe);
      return true;
    } on ReceiptDueError {
      return false;
    }
  }

  return _groessterBetrag(oben, passt);
}

/// Schritte der linearen Suche, bevor die Bisektion uebernimmt.
const _linearSchritte = 64;

/// Cent, die nach der Bisektion aufwaerts geprueft werden (nicht monotoner Rand).
const _nachpruefen = 16;

/// Groesster Betrag in [1, oben], den [passt] annimmt; 0, wenn keiner gefunden wird.
int _groessterBetrag(int oben, bool Function(int cents) passt) {
  final untenLinear = oben - _linearSchritte < 0 ? 0 : oben - _linearSchritte;
  for (var cents = oben; cents > untenLinear; cents--) {
    if (passt(cents)) return cents;
  }
  // Bisektion ueber [1, untenLinear]: `ja` angenommen (0 gilt als angenommen), `nein` abgewiesen.
  var ja = 0;
  var nein = untenLinear + 1;
  while (nein - ja > 1) {
    final mitte = ja + (nein - ja) ~/ 2;
    if (passt(mitte)) {
      ja = mitte;
    } else {
      nein = mitte;
    }
  }
  var bester = ja;
  for (var cents = ja + 1; cents <= _min(untenLinear, ja + _nachpruefen); cents++) {
    if (passt(cents)) bester = cents;
  }
  return bester;
}

/// Obergrenze fuer eine anteilige Einloesung (`kuTeile`): je Satz ist der Anteil
/// mindestens `floor(c * basis / summe)`, je Topf also mehr als
/// `c * basisTopf / summe - saetzeImTopf`. Mit dem freien Rest des Topfs
/// (Positionen minus schon gewaehlte Einloesungen) folgt
/// `c <= (frei + saetzeImTopf) * summe / basisTopf`.
int _kuGrenze(List<Innen> kunde, int Function(String topf) topfBasis, Map<String, int> minusJeTopf) {
  final saetze = kuSaetze(kunde);
  final summe = saetze.fold(0, (a, x) => a + x.basis);
  var grenze = summe;
  final jeTopf = <String, ({int basis, int anzahl})>{};
  for (final x in saetze) {
    final topf = topfFuerSatz(x.satzBp / 100);
    final t = jeTopf[topf] ?? (basis: 0, anzahl: 0);
    jeTopf[topf] = (basis: t.basis + x.basis, anzahl: t.anzahl + 1);
  }
  for (final MapEntry(key: topf, value: t) in jeTopf.entries) {
    final frei = topfBasis(topf) - (minusJeTopf[topf] ?? 0);
    grenze = _min(grenze, _abgerundet((frei + t.anzahl) * summe, t.basis));
  }
  return grenze < 0 ? 0 : grenze;
}

/// Ganzzahlige Division mit Abrundung (wie `Math.floor(a / b)` fuer b > 0); `~/`
/// schnitte bei negativem Zaehler zur Null hin ab.
int _abgerundet(int a, int b) => a >= 0 ? a ~/ b : -((-a + b - 1) ~/ b);

const _hoechstbetragCents = 1000000;

int _min(int a, int b) => a < b ? a : b;

/// Ein gueltiger Code, der unter den schon gewaehlten Gutscheinen nicht
/// vorkommt (nur fuer die Probe-Rechnung; geht nie hinaus).
String _probeCode(List<KeckVoucher> vorher) {
  final belegt = {for (final v in vorher) normalerCode(v.code)};
  for (var i = 0;; i++) {
    final code = VoucherCode.generate([for (var k = 0; k < 11; k++) (i + k * 7) & 31]);
    if (!belegt.contains(code)) return code;
  }
}

/// Die Angaben einer Rechnung (alle benannten Parameter von [receiptDueCents]).
class _Optionen {
  const _Optionen({
    this.tip,
    this.payments,
    this.tipRecipient,
    this.voucherInfo,
    this.voucherSettings,
    this.voucherTypes,
    this.voucherArticles,
    this.smallBusiness = false,
    this.zeroRateBucketFrom,
    this.today,
  });

  final ReceiptDueTip? tip;
  final List<KeckPaymentInput>? payments;
  final ReceiptDueTipRecipient? tipRecipient;
  final List<VoucherDueInfo>? voucherInfo;
  final PosVoucherSettings? voucherSettings;
  final List<VoucherDueType>? voucherTypes;
  final List<VoucherDueArticle>? voucherArticles;
  final bool smallBusiness;
  final String? zeroRateBucketFrom;
  final String? today;

  _Optionen mit({required List<VoucherDueInfo> voucherInfo}) => _Optionen(
        tip: tip,
        payments: payments,
        tipRecipient: tipRecipient,
        voucherInfo: voucherInfo,
        voucherSettings: voucherSettings,
        voucherTypes: voucherTypes,
        voucherArticles: voucherArticles,
        smallBusiness: smallBusiness,
        zeroRateBucketFrom: zeroRateBucketFrom,
        today: today,
      );
}

class _Rechnung {
  const _Rechnung(this.ergebnis, this.kunde, this.minusJeTopf, this.auszahlungCents);
  final ReceiptDueBreakdown ergebnis;

  /// Ware und Trinkgeld in innerer Form (ohne Gutscheinzeilen).
  final List<Innen> kunde;

  /// Summe der Einloese-Minuszeilen je Topf.
  final Map<String, int> minusJeTopf;

  /// Summe der Auszahlungen in Cent.
  final int auszahlungCents;
}

_Rechnung _rechne(List<ReceiptDueLine> lines, List<KeckVoucher> vouchers, ReceiptType receiptType, _Optionen o) {
  final trinkgelder = _trinkgeldAuftraege(o.tip, o.payments);
  if (trinkgelder.isNotEmpty && !_trinkgeldErlaubt.contains(receiptType)) {
    throw ReceiptDueError('tip_not_allowed', 'Trinkgeld gibt es nur bei standard und training, nicht bei "${receiptType.name}".');
  }
  if (!_umsatz.contains(receiptType)) {
    return const _Rechnung(
      ReceiptDueBreakdown(dueCents: 0, counterDeltaCents: 0, valueVoucherFlowCents: 0, bucketsCents: null),
      [],
      {},
      0,
    );
  }

  final positionen = [for (final (i, z) in lines.indexed) _innen(z, i)];
  // index.js createReceipt: erst `tip`, dann je Zahlart aus payments[].tipCents;
  // jede Runde haengt ihre Positionen hinten an (die Basis bleibt die Ware).
  for (final auftrag in trinkgelder) {
    positionen.addAll(_trinkgeldPositionen(auftrag, positionen, o.tipRecipient));
  }

  // Danach der Gutschein-Plan (gutschein-beleg.plane): seine Positionen stehen hinter Ware und Trinkgeld.
  final Plan plan;
  try {
    plan = planeGutscheine(
      positionen,
      vouchers,
      storno: receiptType == ReceiptType.cancellation,
      training: receiptType == ReceiptType.training,
      o: PlanOptionen(
        voucherInfo: o.voucherInfo == null ? null : [for (final i in o.voucherInfo!) (code: i.code, check: i.check)],
        voucherSettings: o.voucherSettings,
        voucherTypes: o.voucherTypes == null
            ? null
            : [for (final t in o.voucherTypes!) (id: t.id, kind: t.kind, vatRateBp: t.vatRateBp, amount: t.amount)],
        voucherArticles: o.voucherArticles == null
            ? null
            : [
                for (final a in o.voucherArticles!)
                  (id: a.id, priceCents: a.priceCents, vatRateBp: a.vatRateBp, serviceVoucher: a.serviceVoucher),
              ],
        smallBusiness: o.smallBusiness,
        zeroRateBucketFrom: o.zeroRateBucketFrom,
        today: o.today ?? ViennaTime.dayKey(DateTime.now()),
      ),
    );
  } on PlanFehler catch (f) {
    throw ReceiptDueError('invalid_voucher', f.text, f.fehler);
  }
  final kunde = List<Innen>.unmodifiable(positionen);
  positionen.addAll(plan.zusatz);
  // gutschein-beleg.zahlbetrag: nur Wert und Rabatt, ohne Mehrzweck-Verkaeufe im 0-%-Topf.
  final gutscheine = [
    for (final g in plan.gutscheine)
      if (!(g.action == VoucherAction.sell && g.imNullTopf)) g,
  ];

  final t = _belegToepfe(positionen, gutscheine);
  final fluss = _wertgutscheinFlussCents(gutscheine, receiptType);
  final dueCents = t.zaehlerDeltaCents + fluss;
  // Ohne Auszahlungen darf der Zahlbetrag nicht negativ werden (Einloesung hoeher als die Summe).
  if (plan.mitPlan && dueCents + plan.auszahlungCents < 0) {
    throw const ReceiptDueError('invalid_voucher', 'die Gutscheine uebersteigen die Summe des Belegs.', 'voucher_exceeds_total');
  }
  // Ein Gutschein deckt nie das Trinkgeld (Personal wie Inhaber): der Zahlbetrag nach den Gutscheinen
  // muss die Trinkgeldzeilen tragen. Storno ausgenommen (dort gibt es keinen Plan).
  final trinkgeld = trinkgeldCents(kunde);
  if (plan.mitPlan && receiptType != ReceiptType.cancellation && trinkgeld > 0 && dueCents + plan.auszahlungCents < trinkgeld) {
    throw const ReceiptDueError('invalid_voucher', 'die Gutscheine decken das Trinkgeld.', 'voucher_exceeds_total');
  }
  return _Rechnung(
    ReceiptDueBreakdown(
      dueCents: dueCents,
      counterDeltaCents: t.zaehlerDeltaCents,
      valueVoucherFlowCents: fluss,
      bucketsCents: {for (final n in topfReihenfolge) n: _euroToCent(t.toepfe[n]!)},
    ),
    kunde,
    plan.minusJeTopf,
    plan.auszahlungCents,
  );
}

const _umsatz = {ReceiptType.standard, ReceiptType.cancellation, ReceiptType.training};
const _trinkgeldErlaubt = {ReceiptType.standard, ReceiptType.training};
const _zahlarten = {
  KeckPaymentMethod.cash,
  KeckPaymentMethod.creditCard,
  KeckPaymentMethod.online,
  KeckPaymentMethod.uberApp,
  KeckPaymentMethod.uberCard,
  KeckPaymentMethod.uberCash,
  KeckPaymentMethod.boltApp,
  KeckPaymentMethod.boltCard,
  KeckPaymentMethod.boltCash,
};

/// `receipt-toepfe.euroToCent`.
int _euroToCent(double euro) => jsRound(euro * 100).toInt();

TrinkgeldArt? _art(ReceiptDueTipRecipient? r) => switch (r) {
      ReceiptDueTipRecipient.owner => TrinkgeldArt.owner,
      ReceiptDueTipRecipient.staff => TrinkgeldArt.staff,
      null => null,
    };

/// Einzelpreis `Math.round(cents) / 100` wie `interneForm`; `-0` wird `0`
/// (in JavaScript fallen beide Saetze als Schluessel `"0"` zusammen).
Innen _innen(ReceiptDueLine z, int i) {
  final satz = z.vatRate.toDouble();
  if (!satz.isFinite) throw ReceiptDueError('invalid_item', 'Position ${i + 1} ohne Steuersatz.');
  final menge = z.quantity.toDouble();
  if (!menge.isFinite) throw ReceiptDueError('invalid_item', 'Position ${i + 1} hat keine gueltige Menge.');
  return Innen(menge, z.priceCents / 100, satz == 0 ? 0.0 : satz, _art(z.tip), kind: z.kind, articleId: z.articleId);
}

/// Empfaenger eines Trinkgeld-Auftrags; `owner == null` heisst: wie der angemeldete Benutzer.
typedef _Auftrag = List<({int cents, bool? owner})>;

/// Trinkgeld-Auftraege in der Reihenfolge des Servers: `tip`, dann je Zahlart die Summe der `tipCents`.
List<_Auftrag> _trinkgeldAuftraege(ReceiptDueTip? tip, List<KeckPaymentInput>? payments) {
  final raus = <_Auftrag>[];
  final mitTipCents = (payments ?? const []).any((z) => z.tipCents != null);
  if (tip != null && mitTipCents) {
    throw const ReceiptDueError('tip_conflict', 'tip und payments[].tipCents gehen nicht zugleich (tip_conflict).');
  }
  if (tip != null) {
    _pruefeCent(tip.cents, 'Trinkgeld');
    final recipients = tip.recipients;
    if (recipients != null) {
      if (recipients.isEmpty) throw const ReceiptDueError('invalid_tip', 'recipients darf nicht leer sein.');
      var summe = 0;
      for (final r in recipients) {
        _pruefeCent(r.cents, 'Trinkgeld-Anteil');
        summe += r.cents;
      }
      if (summe != tip.cents) throw const ReceiptDueError('invalid_tip', 'die Anteile des Trinkgelds ergeben nicht den Betrag.');
      raus.add([for (final r in recipients) (cents: r.cents, owner: r.owner)]);
    } else {
      raus.add([(cents: tip.cents, owner: null)]);
    }
  }
  // zahlungen-core.tipsJeZahlart: Summe je bekannter Zahlart, Reihenfolge des ersten Auftretens.
  final je = <KeckPaymentMethod, int>{};
  for (final z in payments ?? const <KeckPaymentInput>[]) {
    final cents = z.tipCents;
    if (cents == null) continue;
    _pruefeCent(cents, 'tipCents');
    if (!_zahlarten.contains(z.method)) throw ReceiptDueError('unknown_payment_method', 'unbekannte Zahlart "${z.method.name}".');
    je[z.method] = (je[z.method] ?? 0) + cents;
  }
  for (final cents in je.values) {
    raus.add([(cents: cents, owner: null)]);
  }
  return raus;
}

void _pruefeCent(int wert, String was) {
  if (wert <= 0) throw ReceiptDueError('invalid_tip', '$was muss eine ganze Zahl in Cent > 0 sein.');
}

/// `tip-core.buildTipItems`: Personal in den Null-%-Satz, Inhaber anteilig auf die Saetze der Ware.
List<Innen> _trinkgeldPositionen(_Auftrag auftrag, List<Innen> positionen, ReceiptDueTipRecipient? standard) {
  final basis = _warenCentsJeSatz(positionen);
  final summe = basis.values.fold<int>(0, (s, c) => s + c);
  if (summe <= 0) throw const ReceiptDueError('tip_without_goods', 'Trinkgeld braucht mindestens eine Position mit Betrag.');
  final raus = <Innen>[];
  for (final e in auftrag) {
    var owner = e.owner;
    if (owner == null) {
      if (standard == null) {
        throw const ReceiptDueError(
            'tip_recipient_missing', "tipRecipient fehlt ('owner' oder 'staff', wie der angemeldete Kassen-Benutzer).");
      }
      owner = standard == ReceiptDueTipRecipient.owner;
    }
    if (!owner) {
      raus.add(Innen(1, e.cents / 100, 0, TrinkgeldArt.staff));
      continue;
    }
    final teile = _splitOwnerTip(e.cents, basis);
    if (teile.isEmpty) throw const ReceiptDueError('tip_without_goods', 'Inhaber-Trinkgeld braucht mindestens eine Position mit Betrag.');
    for (final teil in teile) {
      if (teil.cents != 0) raus.add(Innen(1, teil.cents / 100, teil.vat, TrinkgeldArt.owner));
    }
  }
  return raus;
}

/// `tip-core.warenCentsJeSatz`: Summe je Satz in Euro, dann einmal runden.
Map<double, int> _warenCentsJeSatz(List<Innen> positionen) {
  final roh = <double, double>{};
  for (final p in positionen) {
    if (p.tip != null) continue;
    roh[p.vat] = (roh[p.vat] ?? 0) + p.amount * p.priceOne;
  }
  return {for (final MapEntry(:key, :value) in roh.entries) key: _euroToCent(value)};
}

/// `tip-core.splitOwnerTip`.
List<({double vat, int cents})> _splitOwnerTip(int cents, Map<double, int> jeSatz) {
  final saetze = [
    for (final MapEntry(key: vat, value: basis) in jeSatz.entries)
      if (basis > 0) (vat: vat, basis: basis),
  ]..sort((a, b) => b.vat.compareTo(a.vat));
  final basis = saetze.fold<int>(0, (s, x) => s + x.basis);
  if (basis <= 0) return const [];
  var vergeben = 0;
  final verteilt = <({double vat, int cents, double frac})>[];
  for (final s in saetze) {
    final exakt = (cents * s.basis) / basis;
    final anteil = exakt.floor();
    vergeben += anteil;
    verteilt.add((vat: s.vat, cents: anteil, frac: exakt - anteil));
  }
  final rest = cents - vergeben;
  if (rest > 0) {
    var bester = 0;
    for (var i = 0; i < verteilt.length; i++) {
      final e = verteilt[i];
      final b = verteilt[bester];
      if (e.frac > b.frac || (e.frac == b.frac && e.vat > b.vat)) bester = i;
    }
    final b = verteilt[bester];
    verteilt[bester] = (vat: b.vat, cents: b.cents + rest, frac: b.frac);
  }
  return [for (final e in verteilt) (vat: e.vat, cents: e.cents)];
}

const _fuenf = [topfStandard, topfReduced1, topfReduced2, topfZero, topfSpecial];

/// `receipt-toepfe.belegToepfe`, Schritt fuer Schritt.
({Map<String, double> toepfe, int zaehlerDeltaCents}) _belegToepfe(List<Innen> positionen, List<PlanGutschein> gutscheine) {
  final t = {for (final n in topfReihenfolge) n: 0.0};
  var personal = 0.0;
  for (final p in positionen) {
    if (p.tip == TrinkgeldArt.staff) {
      personal += p.amount * p.priceOne;
    } else {
      final n = topfFuerSatz(p.vat);
      t[n] = t[n]! + p.priceOne * p.amount;
    }
  }
  final gesamt = t[topfStandard]! + t[topfReduced1]! + t[topfReduced2]! + t[topfZero]! + t[topfSpecial]!;

  if (gutscheine.isNotEmpty) {
    var rabatt = 0.0;
    for (final v in gutscheine) {
      if (v.action == VoucherAction.redeem && v.type == VoucherType.promo) rabatt += v.value;
    }
    final nutzbarCents = _euroToCent(rabatt > gesamt ? gesamt : rabatt);
    final cents = [for (final n in _fuenf) _euroToCent(t[n]!)];
    final basis = cents.fold<int>(0, (s, c) => s + c);
    final anteil = List<int>.filled(cents.length, 0);
    if (basis > 0 && nutzbarCents > 0) {
      for (var i = 0; i < cents.length; i++) {
        anteil[i] = ((nutzbarCents * cents[i]) / basis).floor();
      }
      final rest = nutzbarCents - anteil.fold<int>(0, (s, a) => s + a);
      if (rest > 0) {
        // Groesster Topf; bei Gleichstand der erste.
        var groesster = 0;
        for (var i = 1; i < cents.length; i++) {
          if (cents[i] > cents[groesster]) groesster = i;
        }
        if (cents[groesster] > 0) anteil[groesster] += rest;
      }
    }
    for (var i = 0; i < _fuenf.length; i++) {
      t[_fuenf[i]] = (cents[i] - anteil[i]) / 100;
    }
  }
  t[topfZero] = t[topfZero]! + personal;
  var delta = 0;
  for (final n in topfReihenfolge) {
    delta += _euroToCent(t[n]!);
  }
  return (toepfe: t, zaehlerDeltaCents: delta);
}

/// `zahlungen-core.wertgutscheinFlussCents`: Eintraege im 0-%-Topf
/// (`imNullTopf`) stehen schon als Position; eine Auszahlung ohne
/// Topf-Position mindert den Zahlbetrag.
int _wertgutscheinFlussCents(List<PlanGutschein> gutscheine, ReceiptType art) {
  final vz = art == ReceiptType.cancellation ? -1 : 1;
  var cents = 0;
  for (final v in gutscheine) {
    if (v.type != VoucherType.value || v.imNullTopf || !v.value.isFinite) continue;
    final c = _euroToCent(v.value);
    if (v.action == VoucherAction.sell) {
      cents += c;
    } else if (v.action == VoucherAction.redeem || v.action == VoucherAction.payout) {
      cents -= c;
    }
  }
  return vz * cents;
}
