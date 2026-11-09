/// Pfand und Leergut auf dem Bon: die Regeln, die der Ersatz-Bon
/// (`setKeckReceipt`) und das Beleg-Widget teilen. Zwilling der Pfand-Hilfen in
/// `receipt/layout.ts` des npm-Pakets (`pfandZuPosition`, `mitPfandReihenfolge`,
/// `einwegPfandCents`, `istReinerLeergutBeleg`); die Goldens `deposit` und
/// `deposit-return` sind der Vertrag.
library;

import '../../enums/keck_payment_method.dart';
import '../../models/kasseneck_item.dart';
import '../../models/kasseneck_receipt.dart';
import '../kasse/zusaetze.dart';
import 'gutschein_bon.dart' show VoucherBonPairLine;

/// Ueberschrift eines reinen Leergutbelegs (nur Leergut-Positionen).
const String returnHeading = 'Leergut-Rückgabe';

/// Zahlungszeile eines reinen Leergutbelegs: das Pfand geht bar zurueck.
const String returnPayoutLabel = 'Bar ausgezahlt';

/// Zeile unter der Steuertabelle, wenn Einwegpfand auf dem 0-%-Satz liegt.
const String depositNotTaxableLabel = 'Pfand, nicht steuerbar';

/// Vorsatz der Fusszeile mit der gemeinsamen Ruecknahmestelle.
const String returnPointPrefix = 'Leergut-Rückgabe: ';

/// Reiner Leergutbeleg: mindestens eine Leergutzeile und sonst nichts.
bool isReturnOnlyReceipt(KasseneckReceipt receipt) =>
    receipt.items.isNotEmpty && receipt.items.any((i) => i.isDepositReturn) && receipt.items.every((i) => i.isDepositReturn);

bool _istWare(KasseneckItem i) => !(i.isTip || i.isDiscount || i.isDeposit || i.isDepositReturn);

/// Pfandzeilen, die unter ihrer Warenposition stehen (`depositFor` zeigt auf
/// eine Ware, nicht auf Trinkgeld, Rabatt, Pfand oder Leergut und nicht auf sich
/// selbst), je Warenposition. Alle anderen Pfandzeilen bleiben an ihrem Platz.
Map<int, List<int>> depositByPosition(List<KasseneckItem> items) {
  final zu = <int, List<int>>{};
  for (var i = 0; i < items.length; i++) {
    final it = items[i];
    if (!it.isDeposit) continue;
    final ziel = it.depositFor;
    if (ziel == null || ziel < 0 || ziel >= items.length || ziel == i) continue;
    if (!_istWare(items[ziel])) continue;
    (zu[ziel] ??= []).add(i);
  }
  return zu;
}

/// Bon-Reihenfolge mit Pfand: Hauptposition, ihre Zusaetze, dann die Pfandzeilen
/// der Hauptposition (ein Zusatz traegt seine eigene Pfandzeile direkt unter
/// sich). Ohne Pfandverweise bleibt [reihe] unveraendert.
List<int> depositDisplayOrder(List<KasseneckItem> items, List<int> reihe, Map<int, List<int>> zu) {
  if (zu.isEmpty) return reihe;
  final gebunden = {for (final l in zu.values) ...l};
  final raus = <int>[];
  var offen = <int>[];
  for (final i in reihe) {
    if (gebunden.contains(i)) continue;
    if (isValidAddOnAt(items, i)) {
      raus
        ..add(i)
        ..addAll(zu[i] ?? const []);
      continue;
    }
    raus
      ..addAll(offen)
      ..add(i);
    offen = zu[i] ?? const [];
  }
  raus.addAll(offen);
  return raus;
}

/// Die Anzeigereihenfolge eines Belegs (Zusaetze und Pfand eingerechnet) und
/// die Zeilen, die als gebundene Pfandzeile eingerueckt stehen.
({List<int> order, Set<int> boundDeposit}) receiptDisplayOrder(List<KasseneckItem> items) {
  final zu = depositByPosition(items);
  final gebunden = {for (final l in zu.values) ...l};
  return (order: depositDisplayOrder(items, addOnDisplayOrder(items), zu), boundDeposit: gebunden);
}

/// Einwegpfand und -leergut auf dem 0-%-Satz in Cent (Pfandzeilen minus
/// Leergut); `null`, wenn keins darauf liegt.
int? singleUseDepositCents(List<KasseneckItem> items) {
  var summe = 0;
  var gefunden = false;
  for (final it in items) {
    if (!(it.isDeposit || it.isDepositReturn) || it.depositKind != 'single_use') continue;
    if (it.vat.rate != 0) continue;
    summe += it.totalCents;
    gefunden = true;
  }
  return gefunden ? summe : null;
}

/// Die Fusszeile mit der gemeinsamen Ruecknahmestelle; `null`, wenn der Beleg
/// keine traegt.
String? returnPointLine(KasseneckReceipt receipt) {
  final stelle = receipt.sharedReturnPoint;
  if (stelle == null) return null;
  final angabe = [stelle.name, stelle.address].where((t) => t.isNotEmpty).join(', ');
  return angabe.isEmpty ? null : '$returnPointPrefix$angabe';
}

/// Zahlzeilen eines reinen Leergutbelegs: das Pfand geht bar zurueck an den
/// Kunden („Bar ausgezahlt“ mit dem negativen Betrag, 8:4). `null` bei jedem
/// anderen Beleg und wenn nicht ausschliesslich bar zurueckgezahlt wird; dann
/// gelten die uebrigen Zahlzeilen.
List<VoucherBonPairLine>? returnOnlyPayoutLines(
  KasseneckReceipt receipt, {
  required String Function(int cents) formatCents,
  String currency = 'EUR',
}) {
  if (!isReturnOnlyReceipt(receipt)) return null;
  final zahlungen = receipt.payments;
  if (zahlungen == null || zahlungen.isEmpty) {
    final summe = receipt.items.fold<int>(0, (s, i) => s + i.totalCents);
    if (receipt.paymentMethod == KeckPaymentMethod.cash && summe < 0) {
      return [VoucherBonPairLine(returnPayoutLabel, '${formatCents(summe)} $currency')];
    }
    return null;
  }
  final bar = [for (final z in zahlungen) if (z.methodValue == 'cash' && z.amountCents < 0) z];
  if (bar.length != zahlungen.length) return null;
  return [for (final z in bar) VoucherBonPairLine(returnPayoutLabel, '${formatCents(z.amountCents)} $currency')];
}
