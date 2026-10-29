/// Storno-Regeln der Kasse — Zwilling von `models/cancellation.ts` und der
/// Storno-Regeln in `receipts.ts` der Browser-Kasse.
///
/// **Die Wahrheit hat der Server.** Er hält die Restmengen, die Reichweite des
/// Rechts und die Verkettung; er negiert und signiert. Was hier steht,
/// entscheidet nur, was die Kasse **anbietet** — ein Knopf, der sicher auf
/// einen Fehler läuft, gehört nicht auf den Schirm, und eine Menge, die es
/// nicht mehr gibt, auch nicht.
///
/// Ein Storno-Beleg ist ein eigener signierter Beleg nach RKSV. Es gibt kein
/// Zurücknehmen — nur einen weiteren Beleg.
library;

import '../../enums/credit_card_provider.dart';
import '../../enums/keck_payment_method.dart';
import '../../enums/voucher_action.dart';
import '../../enums/voucher_type.dart';
import '../../models/kasseneck_item.dart';
import '../../models/kasseneck_receipt.dart';
import '../../models/keck_payment.dart';
import '../../models/keck_voucher.dart';
import '../aufrufe.dart';
import '../register/fehler.dart' show KasseneckValidationError;
import '../receipt/codes.dart' show cancellationErrorCodes;
import '../register/pairing.dart' show RegisterScope;
import 'belege.dart';
import 'gutschein_wunsch.dart' show artOderNull;

/// Die Gründe, die das Backend annimmt – Codes wie unter `/v3` (Katalog
/// `STORNO_GRUND`), Beschriftung für den Bildschirm und den Bon (bleibt
/// deutsch, sie steht so am Beleg). Reihenfolge wie im Katalog des Backends.
const Map<String, String> cancellationReasons = {
  'input_error': 'Fehleingabe',
  'customer_cancelled': 'Kunde hat storniert',
  'wrong_payment_method': 'Falsche Zahlart',
  'duplicate': 'Doppelt erfasst',
  'other': 'Sonstiges',
};

/// Stabile Fehlercodes von `cancelReceipt` unter `/v3` – Zwilling von
/// `CANCELLATION_ERROR_CODES` in `@kreiseck/kasseneck-api` 1.0, in derselben
/// Reihenfolge (siehe `receipt/codes.dart`). Das Backend legt sie als `code`
/// neben die Meldung; sie kommen als `KasseneckApiError.code` an.
/// **Entscheide am Code, nie am Text.** Formfehler an `payments` selbst melden
/// die Codes aus `paymentErrorCodes`. `cancellation_outcome_unknown` heisst:
/// der Storno ist moeglicherweise gebucht; nie wiederholen, sondern das
/// Original nachlesen.

/// Ist [value] ein Code aus [cancellationErrorCodes]? Ein Anzeigetext ist keiner,
/// ein alter deutscher oder grosser Code aus `/v1` auch nicht.
bool isCancellationErrorCode(Object? value) => value is String && cancellationErrorCodes.contains(value);

/// Ab wann eine liegengebliebene Reservierung nicht mehr zählt (wie im
/// Backend). Ohne diese Grenze bliebe eine Position für immer gesperrt, weil
/// ein Abbruch irgendwann einmal eine Reservierung stehen ließ.
const int cancellationReservationMs = 120000;

/// Restmenge je Position: Belegmenge minus alles, was storniert oder **frisch**
/// reserviert ist; nie unter null.
List<int> remainingQuantities(KasseneckReceipt receipt, {int? nowMs}) {
  final rest = [for (final p in receipt.items) p.quantity];
  final zeit = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  for (final eintrag in receipt.cancellations) {
    final at = eintrag['at'];
    // Eine Reservierung zählt nur, solange sie frisch ist.
    if (eintrag['pending'] == true && (at is! num || at < zeit - cancellationReservationMs)) continue;
    for (final pos in (eintrag['items'] as List?) ?? const []) {
      if (pos is! Map) continue;
      final index = pos['index'];
      final menge = pos['quantity'];
      if (index is! int || index < 0 || index >= rest.length) continue;
      if (menge is! int) continue;
      rest[index] = rest[index] - menge < 0 ? 0 : rest[index] - menge;
    }
  }
  return rest;
}

/// Darf dieser Beleg storniert werden?
///
/// Kein Storno von einem Storno, keines von Null-, Start- oder
/// Trainingsbelegen, keines von einem bereits voll stornierten Beleg und keines
/// bei einem unbekannten Stornostand (ein kuenftiger Wert des Servers: die
/// Kasse bietet dann nichts an, statt zu raten) – und mit der Reichweite `own`
/// nur die eigenen. Fehlt der Stand in der Liste, entscheidet der Server.
bool canCancel(ReceiptSummary receipt, RegisterScope scope, String ownUid) {
  if (scope == RegisterScope.none) return false;
  if (!receipt.isSale) return false;
  if (receipt.cancellationState == CancellationState.full || receipt.cancellationState == CancellationState.unknown) return false;
  if (scope == RegisterScope.own && receipt.operator?.uid != ownUid) return false;
  return true;
}

/// Sieht dieser Kassier den Beleg überhaupt?
bool isReceiptVisible(ReceiptSummary receipt, RegisterScope scope, String ownUid) {
  if (scope == RegisterScope.none) return false;
  if (scope == RegisterScope.own) return receipt.operator?.uid == ownUid;
  return true;
}

/// Höchstzahl der Stellen, die eine Belegnummer hat.
const int receiptNumberMaxDigits = 7;

/// Die Nummer aus einer vollen Beleg-Kennung — für die Anzeige „ID 809".
/// Passt sie nicht auf das Muster, steht die Kennung selbst da; eine erfundene
/// Nummer wäre schlimmer als eine lange.
String receiptNumber(String receiptId) {
  final treffer = RegExp(r'-ID-(\d+)$').firstMatch(receiptId);
  return treffer?.group(1) ?? receiptId;
}

/// Aus der getippten Nummer die volle Kennung; `null`, wenn keine Ziffer dabei
/// ist. Der Kassier tippt nur die Nummer — das Kassenkürzel steht ohnehin fest.
String? fullReceiptIdFromNumber(String cashregisterId, String number) {
  final ziffern = number.replaceAll(RegExp(r'\D'), '');
  final gekuerzt = ziffern.length > receiptNumberMaxDigits ? ziffern.substring(0, receiptNumberMaxDigits) : ziffern;
  return gekuerzt.isEmpty ? null : '$cashregisterId-ID-$gekuerzt';
}

/// Kennung der Originalzahlung fuer die Rueckbuchung am Terminal (Hobex
/// `originalTransactionId`, SumUp-Transaktion …): `providerPaymentId` der
/// Zahlung [paymentId] des Originals. Die liefert nur der Kassenweg
/// (`kasse.kasseneck.at/api/v3`, Kanal `app`); am oeffentlichen Weg fehlt sie,
/// und dann wirft dieser Aufruf, statt `null` an ein Terminal weiterzugeben.
/// Zwilling von `cardRefundReference` im npm-Paket.
String cardRefundReference(KasseneckReceipt receipt, String paymentId) {
  final zahlung = (receipt.payments ?? const <KeckPayment>[]).where((z) => z.id == paymentId).firstOrNull;
  if (zahlung == null) {
    throw KasseneckValidationError(Aufrufe.cancelReceipt, 'Zahlung "$paymentId" gibt es am Beleg nicht', 'request');
  }
  if (zahlung.method?.needsCreditCard != true) {
    throw KasseneckValidationError(Aufrufe.cancelReceipt, 'Zahlung "$paymentId" ist keine Kartenzahlung', 'request');
  }
  final kennung = zahlung.providerPaymentId;
  if (kennung == null || kennung.isEmpty) {
    throw KasseneckValidationError(
      Aufrufe.cancelReceipt,
      'Kennung der Kartenzahlung "$paymentId" fehlt: sie kommt nur ueber den Kassenweg '
          '(kasse.kasseneck.at/api/v3), nicht ueber den oeffentlichen Weg',
      'request',
    );
  }
  return kennung;
}

/// Storno einer Gutschein-Auszahlung: genau eine positive Barzahlung ohne
/// `refundOf` (das Geld kommt in die Lade zurueck). Alles andere bleibt
/// Rueckzahlung mit negativem Betrag; ob der Beleg eine Auszahlung war,
/// entscheidet der Server. Liegt das [original] vor und traegt es keine
/// Auszahlung, bleibt es bei negativen Rueckzahlungen. Zwilling von
/// `istStornoAuszahlung` im npm-Paket.
bool isPayoutCancellation(List<KeckPaymentInput> payments, KasseneckReceipt? original) {
  if (payments.length != 1) return false;
  if (original != null && !(original.vouchers ?? const <KeckVoucher>[]).any((v) => v.action == VoucherAction.payout)) return false;
  final z = payments.single;
  return z.method == KeckPaymentMethod.cash && z.amountCents > 0 && z.refundOf == null;
}

/// Karten-Rueckbuchung am Storno, geprueft **bevor** etwas hinausgeht
/// (Zwilling von `assertCardRefunds` im npm-Paket):
/// - Sie nennt ihren Anbieter (`provider`; `custom` fuer eine Erstattung ohne
///   angebundenes Terminal). Ganz ohne Anbieterfelder faellt sie.
/// - Ueber einen Anbieter (nicht `custom`) braucht sie einen Bezug: ihre eigene
///   Terminal-Kennung (`providerPaymentId` der Erstattung) oder, liegt das
///   [original] vor, die Kennung der erstatteten Kartenzahlung dort. Erst wenn
///   beides fehlt, wirft sie.
void assertCardRefunds(List<KeckPaymentInput> payments, KasseneckReceipt? original) {
  for (final (i, z) in payments.indexed) {
    if (!z.method.needsCreditCard) continue;
    if (z.provider == null && z.providerPaymentId == null) {
      throw KasseneckValidationError(
        Aufrufe.cancelReceipt,
        'Zahlung ${i + 1}: Karten-Rueckbuchung ohne Anbieter und ohne Kennung '
            '(provider angeben, custom fuer eine Erstattung ohne angebundenes Terminal)',
        'request',
      );
    }
    if (z.provider == CreditCardProvider.custom || z.providerPaymentId != null) continue;
    final bezug = z.refundOf;
    final orig = original != null && bezug != null
        ? (original.payments ?? const <KeckPayment>[]).where((o) => o.id == bezug).firstOrNull
        : null;
    final kennung = orig?.providerPaymentId;
    if (kennung != null && kennung.isNotEmpty) continue;
    throw KasseneckValidationError(
      Aufrufe.cancelReceipt,
      'Zahlung ${i + 1}: Karten-Rueckbuchung ohne Bezug: providerPaymentId der Erstattung am Terminal angeben '
          '(oder das Original ueber den Kassenweg lesen, dort traegt es die Kennung der Kartenzahlung)',
      'request',
    );
  }
}

// --- Trinkgeld beim Storno (Schichten-Spec, Nachtrag 5) ----------------------
//
// Enthaelt ein Beleg noch nicht storniertes Mitarbeiter-Trinkgeld, fragt die
// Kasse „Trinkgeld auch zurueckgeben?" (`refundTip`) und bei Barrueckgabe
// „Woher kommt das Trinkgeld zurueck?" (`tipRefundSource`). Zwilling der
// gleichnamigen Funktionen in `models/cancellation.ts`; gemeinsame Faelle in
// `cancellation-tip-cases.json` des Vertrags.

/// Woher das Trinkgeld beim Storno zurueckkommt: `drawer` – die Lade zahlt es
/// aus; `employee` – die Mitarbeiterin gibt es selbst. Nur bei Barrueckgabe.
const List<String> tipRefundSources = ['drawer', 'employee'];

/// Ist [value] ein Wert aus [tipRefundSources]?
bool isTipRefundSource(Object? value) => value is String && tipRefundSources.contains(value);

/// Barzahlarten – Zwilling von `BAR_ZAHLARTEN` (functions/gemeinsam/tip-core.js).
const List<String> _barZahlarten = ['cash', 'uberCash', 'boltCash'];

bool _mitarbeiterTrinkgeld(KasseneckItem item) => item.kind == 'tip' && item.recipient?['owner'] != true;

/// Hatte die Mitarbeiterin dieses Trinkgeld schon (sofort erhalten, mit
/// Empfaenger)? Ohne Merkmal (Altbestand) gilt wie im Backend: bar = erhalten.
bool _hatteSie(KasseneckItem item, KasseneckReceipt receipt) {
  final id = item.recipient?['registerUserId'];
  if (id is! String || id.isEmpty) return false;
  final sofort = item.receivedImmediately;
  if (sofort != null) return sofort;
  return _barZahlarten.contains(item.paymentMethod ?? receipt.paymentMethod.name);
}

List<CancellationItem> _offenesTrinkgeld(KasseneckReceipt receipt, int? nowMs) {
  final rest = remainingQuantities(receipt, nowMs: nowMs);
  return [
    for (final (i, item) in receipt.items.indexed)
      if (rest[i] > 0 && _mitarbeiterTrinkgeld(item)) (index: i, quantity: rest[i]),
  ];
}

/// Noch nicht storniertes Mitarbeiter-Trinkgeld in Cent. Groesser 0 heisst: das
/// Storno fragt „Trinkgeld auch zurueckgeben?" (auch beim Teilstorno).
/// Inhaber-Trinkgeld ist Umsatz und folgt der Ware.
int openStaffTipCents(KasseneckReceipt receipt, {int? nowMs}) => _offenesTrinkgeld(receipt, nowMs)
    .fold(0, (s, p) => s + p.quantity * receipt.items[p.index].priceCents);

/// Fragt das Storno „Trinkgeld auch zurueckgeben?" – nur bei offenem
/// Mitarbeiter-Trinkgeld und ohne Wertgutschein am Beleg (Ruling R59). Einen
/// Wertgutschein spiegelt nur ein Storno, der alles nimmt; dort geht das
/// Trinkgeld immer mit (der Server weist `refundTip: false` mit
/// `tip_keep_not_possible_with_voucher` ab), die Kasse zeigt
/// `cancellation.tip_refunded_with_voucher` und sendet `refundTip: true`. Die
/// Frage nach der Quelle bleibt ([asksTipRefundSource]). Zwilling von
/// `asksRefundTip` im npm-Paket.
bool asksRefundTip(KasseneckReceipt receipt, {int? nowMs}) =>
    openStaffTipCents(receipt, nowMs: nowMs) > 0 && !(receipt.vouchers ?? const []).any((v) => artOderNull(v) == VoucherType.value);

/// Die Positionen, die nach der Antwort auf „Trinkgeld auch zurueckgeben?"
/// hinausgehen – dieselbe Regel wie im Backend. [items] `null` = ganzer Beleg.
/// Ja: zum Teilstorno kommt das offene Trinkgeld dazu, der ganze Beleg bleibt
/// `null`. Nein: ohne das Mitarbeiter-Trinkgeld; der ganze Beleg wird zur Liste
/// aller Restmengen ausser dem Trinkgeld (leer = nichts mehr zu stornieren).
/// Ist kein Mitarbeiter-Trinkgeld mehr offen (keines oder schon storniert),
/// bleibt der Wunsch, wie er ist – „Nein" wirkt dann wie keine Wahl (R61).
List<CancellationItem>? cancellationItemsForTip(
  KasseneckReceipt receipt,
  List<CancellationItem>? items, {
  required bool refundTip,
  int? nowMs,
}) {
  final trinkgeld = {for (final (i, item) in receipt.items.indexed) if (_mitarbeiterTrinkgeld(item)) i};
  if (trinkgeld.isEmpty) return items == null ? null : [...items];
  if (refundTip) {
    if (items == null) return null;
    final genannt = {for (final p in items) p.index};
    return [...items, ..._offenesTrinkgeld(receipt, nowMs).where((p) => !genannt.contains(p.index))];
  }
  if (items != null) return [for (final p in items) if (!trinkgeld.contains(p.index)) p];
  if (_offenesTrinkgeld(receipt, nowMs).isEmpty) return null;
  final rest = remainingQuantities(receipt, nowMs: nowMs);
  return [
    for (final (i, menge) in rest.indexed)
      if (menge > 0 && !trinkgeld.contains(i)) (index: i, quantity: menge),
  ];
}

/// Was dieses Storno bar zurueckgibt (positiv, Cent): mit Rueckzahlungen deren
/// Barteil; ohne (der Server spiegelt die eine Zahlung des Originals) alles,
/// wenn das Original bar bezahlt war. Bei mehr als einer Zahlung ohne Angabe 0:
/// welcher Teil bar zurueckgeht, ist dann offen (ein Teilstorno verlangt
/// ohnehin `payments`). Beide Kassen schicken bei mehr als einer Zahlung darum
/// immer die Rueckzahlungen mit und rechnen hier mit ihnen.
int cancellationCashRefundCents(KasseneckReceipt receipt, List<KeckPaymentInput>? payments, int dueCents) {
  if (payments != null) {
    return payments.fold(0, (s, z) => z.method == KeckPaymentMethod.cash ? s - z.amountCents : s);
  }
  final zahlungen = receipt.payments ?? const <KeckPayment>[];
  if (zahlungen.length > 1) return 0;
  final methode = zahlungen.length == 1 ? zahlungen.single.methodValue : receipt.paymentMethod.name;
  return methode == 'cash' ? dueCents : 0;
}

/// Fragt das Storno nach „Ja" auch „Woher kommt das Trinkgeld zurueck?" – nur,
/// wenn das Bargeld des Stornos ([cashRefundCents], siehe
/// [cancellationCashRefundCents]) das offene Mitarbeiter-Trinkgeld deckt und die
/// Mitarbeiterin wenigstens eines davon schon hatte. Bei Kartenrueckgabe geht
/// es auf die Karte zurueck; ueber Lohn behaltenes Trinkgeld kommt immer aus
/// der Lade. Ohne diese Frage gilt beim Server fuer `refundTip: true`: aus der
/// Lade, kein „gibt die Mitarbeiterin direkt".
bool asksTipRefundSource(KasseneckReceipt receipt, int cashRefundCents, {int? nowMs}) {
  final offen = _offenesTrinkgeld(receipt, nowMs);
  if (offen.isEmpty) return false;
  if (!offen.any((p) => _hatteSie(receipt.items[p.index], receipt))) return false;
  return cashRefundCents >= openStaffTipCents(receipt, nowMs: nowMs);
}
