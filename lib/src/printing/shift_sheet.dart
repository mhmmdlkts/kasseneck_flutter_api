/// Bons der Schicht als Zeilenmodell: Z-Bon (`shift_close`), X-Bon
/// (`shift_interim`) und Kassenbewegung (`cash_movement`), aus den Bon-Daten der
/// Antwort (`receipt` von `closeMyShift`, `getMyShiftReport`,
/// `recordMyCashMovement`). Zwilling von `receipt/shift-sheet.ts` im JS-Paket
/// (npm 1.9.0); dieselben Goldens (`expected/shift-*`, `cash-movement*`).
/// Gezeichnet wird wie jeder Beleg: Raster, Blatt, ESC/POS.
///
/// Kein Registrierkassenbeleg: keine Signatur, kein QR, kein DEP. Jeder Bon
/// endet mit „Kein Registrierkassenbeleg“.
///
/// **Blind** (ohne Recht `cashView`) sind Soll, Ist, Differenz, Barumsatz und
/// die gezaehlte Stueckelung `null`: ihre Zeilen fallen weg, nie steht dort
/// „0,00“ oder ein Strich. Dasselbe gilt fuer jede andere leere Angabe; ein
/// echtes `0` wird gedruckt.
library;

import '../../models/receipt_layout.dart';
import '../../services/vienna_time.dart';
import '../kasse/einstellungen.dart' show PosPaperSize;
import '../kasse/schicht.dart';
import '../kasse/texte.dart';

/// Version des Layout-Regelwerks, mit dem diese Bons gebaut sind.
const int _regelwerk = 2;

// ---- Bauteile ------------------------------------------------------------------

LayoutTextLine _text(String t, {LayoutAlign align = LayoutAlign.left, bool bold = false}) =>
    LayoutTextLine(text: t, align: align, bold: bold);

/// Zwei Spalten: Name links, Wert rechts.
LayoutColumnsLine _paar(String links, String rechts, int linksBreite) => LayoutColumnsLine([
      LayoutColumn(text: links, width: linksBreite, align: LayoutAlign.left),
      LayoutColumn(text: rechts, width: 12 - linksBreite, align: LayoutAlign.right),
    ]);

/// Kopfzeilen (Kasse, Zeiten, Namen): breiter Wert fuer „25.09.2026 17:00“.
LayoutColumnsLine _kopf(String links, String rechts) => _paar(links, rechts, 5);

/// Betragszeilen: breiter Name, schmaler Betrag.
LayoutColumnsLine _betrag(String links, int cents) => _paar(links, _formatCents(cents), 8);

/// Betragszeile fett (Ergebnis, z. B. „Bleibt in der Kassenlade“).
LayoutColumnsLine _betragFett(String links, int cents) => LayoutColumnsLine(_betrag(links, cents).columns, bold: true);

LayoutColumnsLine _anzahl(String links, int n) => _paar(links, '$n', 8);

LayoutLine _regel() => const LayoutRuleLine(char: '-');

/// `1234` -> `12,34`, `-5` -> `-0,05`: dieselbe Schreibweise wie `formatCents` im
/// JS-Paket, aber rein ganzzahlig (Geld wird nie ueber Gleitkomma geformt).
String _formatCents(int cents) {
  final betrag = cents.abs();
  return '${cents < 0 ? '-' : ''}${betrag ~/ 100},${(betrag % 100).toString().padLeft(2, '0')}';
}

/// Zeit in Wien als `DD.MM.YYYY HH:mm`; unlesbar -> `null` (die Zeile faellt
/// weg, der Bon bleibt).
String? _zeit(String? iso) {
  if (iso == null) return null;
  try {
    final t = ViennaTime.toWallClock(ViennaTime.parseServerTimeStamp(iso));
    String zwei(int n) => n.toString().padLeft(2, '0');
    return '${zwei(t.day)}.${zwei(t.month)}.${t.year} ${zwei(t.hour)}:${zwei(t.minute)}';
  } catch (_) {
    return null;
  }
}

String _beschriftung(String schluessel, String sonst) =>
    posLabels.containsKey(schluessel) ? labelText(schluessel) : sonst;

String _artText(String art) => _beschriftung('cash_movement.type_$art', art);
String _ortText(String ort) => _beschriftung('shift_receipt.location_$ort', ort);

/// Zahlart unbar: `card` wie am Beleg „Kartenzahlung“, sonst der Wert, wie er kommt.
String _zahlartText(String methode) => methode == 'card' ? labelText('payment_method.card') : methode;

/// Je Schein und Muenze eine eingerueckte Zeile, vom groessten Wert abwaerts;
/// Anzahl 0 faellt weg.
List<LayoutLine> _stueckelungZeilen(Map<String, int>? karte) {
  if (karte == null) return const [];
  final eintraege = [
    for (final e in karte.entries)
      if (e.value > 0 && int.tryParse(e.key) != null) (wert: int.parse(e.key), n: e.value),
  ]..sort((a, b) => b.wert.compareTo(a.wert));
  return [for (final e in eintraege) _betrag('  ${e.n} x ${_formatCents(e.wert)}', e.wert * e.n)];
}

void _wennText(List<LayoutLine> zeilen, String links, String? wert) {
  if (wert != null && wert.isNotEmpty) zeilen.add(_kopf(links, wert));
}

void _kopfblock(List<LayoutLine> zeilen, ShiftReceiptHeader bon, String titel) {
  zeilen.add(LayoutBannerLine(text: labelText(titel), tone: LayoutBannerTone.receiptType));
  final betrieb = bon.businessName;
  if (betrieb != null && betrieb.isNotEmpty) zeilen.add(_text(betrieb, align: LayoutAlign.center, bold: true));
  _wennText(zeilen, labelText('shift_receipt.cashregister'), bon.cashregisterName);
  _wennText(zeilen, labelText('shift_receipt.drawer'), bon.drawerName);
}

/// Nach der Zaehlung beim Abschluss, durch eine Linie vom Zaehlblock getrennt:
/// „Entnommen“ (negativ) bzw. „Eingelegt“, dann „Bleibt in der Kassenlade“
/// (fett). Nur wenn Geld bewegt wurde
/// (`afterCount`); sonst keine Zeile, der Bon bleibt wie bisher. Blind fehlt
/// „Bleibt“ (`null`), die Entnahme selbst bleibt sichtbar. Eine unbekannte Art
/// (kuenftiger Katalogwert) druckt keine Betragszeile.
List<LayoutLine> _nachZaehlungZeilen(ShiftSummaryReceipt bon) {
  final n = bon.afterCount;
  if (n == null) return const [];
  final zeilen = <LayoutLine>[];
  if (n.type == 'cash_drop') {
    zeilen.add(_betrag(labelText('shift_receipt.taken_out'), -n.amountCents));
  } else if (n.type == 'change_in') {
    zeilen.add(_betrag(labelText('shift_receipt.put_in'), n.amountCents));
  }
  final bleibt = bon.leftInDrawerCents;
  if (bleibt != null) zeilen.add(_betragFett(labelText('shift_receipt.left_in_drawer'), bleibt));
  return zeilen.isEmpty ? const [] : [_regel(), ...zeilen];
}

// ---- Bons ----------------------------------------------------------------------

/// Z-Bon bzw. X-Bon der Schicht. Titel nach `kind`: „Schichtabschluss“ oder
/// „Zwischenbericht“. Wirft ([KasseneckValidationError], `kind: request`),
/// wenn die Bon-Daten keine Z- oder X-Bon-Daten sind. [paperSize] ist die
/// Breite des Bauplans (Vorgabe `mm58`); die Druckbreite waehlt der Druckweg.
ReceiptLayout shiftReceiptLayout(ShiftSummaryReceipt receipt, {PosPaperSize paperSize = PosPaperSize.mm58}) {
  zBonPruefen('shiftReceiptLayout', receipt);
  final bon = receipt;
  final zeilen = <LayoutLine>[];
  _kopfblock(zeilen, bon, bon.kind == 'shift_close' ? 'shift_receipt.title_close' : 'shift_receipt.title_interim');
  zeilen.add(_kopf(labelText('shift_receipt.shift'), labelText('shift_receipt.number', {'number': bon.number})));
  final von = labelText('shift_receipt.by');
  _wennText(zeilen, labelText('shift_receipt.opened'), _zeit(bon.openedAt));
  _wennText(zeilen, von, bon.openedByName);
  _wennText(zeilen, labelText('shift_receipt.closed'), _zeit(bon.closedAt));
  _wennText(zeilen, von, bon.closedByName);

  // Bargeld: Startgeld, Barumsatz, Bewegungen, Soll, Ist, Differenz.
  zeilen.add(_regel());
  final start = labelText(bon.openingFloatTakenOver ? 'shift_receipt.opening_float_taken_over' : 'shift_receipt.opening_float');
  if (bon.openingFloatCents != null) {
    zeilen.add(_betrag(start, bon.openingFloatCents!));
  } else if (bon.openingFloatTakenOver) {
    zeilen.add(_text(start));
  }
  zeilen.addAll(_stueckelungZeilen(bon.openingDenominations));
  if (bon.cashSalesCents != null) zeilen.add(_betrag(labelText('shift_receipt.cash_sales'), bon.cashSalesCents!));
  if (bon.cashCancellationsCents != null) {
    zeilen.add(_betrag(labelText('shift_receipt.cash_cancellations'), bon.cashCancellationsCents!));
  }
  if (bon.movements.isNotEmpty) {
    zeilen.add(_text(labelText('shift_receipt.movements'), bold: true));
    for (final m in bon.movements) {
      zeilen.add(_betrag('${labelText('shift_receipt.number', {'number': m.number})} ${_artText(m.type)}', m.amountCents));
      final note = m.note;
      if (note != null && note.isNotEmpty) zeilen.add(_text('  $note'));
    }
  }
  if (bon.expectedCents != null) zeilen.add(_betrag(labelText('shift_receipt.expected'), bon.expectedCents!));
  if (bon.countedCents != null) {
    zeilen.add(_betrag(labelText('shift_receipt.counted'), bon.countedCents!));
    zeilen.addAll(_stueckelungZeilen(bon.countedDenominations));
  }
  if (bon.differenceCents != null) zeilen.add(_betrag(labelText('shift_receipt.difference'), bon.differenceCents!));
  final kommentar = bon.comment;
  if (kommentar != null && kommentar.isNotEmpty) zeilen.add(_text('${labelText('shift_receipt.comment')}: $kommentar'));
  zeilen.addAll(_nachZaehlungZeilen(bon));

  // Zur Information: unbar, Zaehler.
  zeilen.add(_regel());
  if (bon.nonCashByMethod.isNotEmpty) {
    zeilen.add(_text(labelText('shift_receipt.non_cash'), bold: true));
    for (final u in bon.nonCashByMethod) {
      zeilen.add(_betrag(_zahlartText(u.method), u.cents));
    }
  }
  zeilen.add(_anzahl(labelText('shift_receipt.receipts'), bon.receiptCount));
  zeilen.add(_anzahl(labelText('shift_receipt.cancellations'), bon.cancellationCount));
  zeilen.add(_anzahl(labelText('shift_receipt.openings_without_sale'), bon.openingsWithoutSale));

  // Trinkgeld je Mitarbeiter (shiftTipLines): verdient immer, ueber Lohn, schon genommen und offen
  // nur ungleich 0; wer ueberall 0 hat, entfaellt, ohne Mitarbeiter auch die Ueberschrift.
  final trinkgeld = [
    for (final t in bon.tips)
      if (shiftTipLines(t) case final z when z.isNotEmpty) (t, z),
  ];
  if (trinkgeld.isNotEmpty) {
    zeilen.add(_regel());
    zeilen.add(_text(labelText('shift_receipt.tips'), bold: true));
    for (final (t, z) in trinkgeld) {
      zeilen.add(_text(t.name ?? t.registerUserId));
      for (final zeile in z) {
        zeilen.add(_betrag('  ${zeile.text}', zeile.cents));
      }
    }
  }
  return ReceiptLayout(lines: zeilen, paperSize: paperSize.value, ruleset: _regelwerk);
}

/// Bon einer Kassenbewegung (Einzahlung, Auszahlung, Umbuchung). Wirft
/// ([KasseneckValidationError], `kind: request`), wenn die Bon-Daten keine
/// Kassenbewegung sind.
ReceiptLayout cashMovementLayout(CashMovementReceipt receipt, {PosPaperSize paperSize = PosPaperSize.mm58}) {
  bewegungsBonPruefen('cashMovementLayout', receipt);
  final bon = receipt;
  final zeilen = <LayoutLine>[];
  _kopfblock(zeilen, bon, 'shift_receipt.title_movement');
  if (bon.shiftNumber != null) {
    zeilen.add(_kopf(labelText('shift_receipt.shift'), labelText('shift_receipt.number', {'number': bon.shiftNumber!})));
  }
  zeilen.add(_regel());
  zeilen.add(_kopf(labelText('shift_receipt.movement_number'), '${bon.number}'));
  zeilen.add(_kopf(labelText('shift_receipt.type'), _artText(bon.type)));
  zeilen.add(_betrag(labelText('shift_receipt.amount'), bon.amountCents));
  _wennText(zeilen, labelText('shift_receipt.location'), bon.location == null ? null : _ortText(bon.location!));
  _wennText(zeilen, labelText('shift_receipt.recipient'), bon.recipientName);
  _wennText(zeilen, labelText('shift_receipt.target_drawer'), bon.targetDrawerName);
  _wennText(zeilen, labelText('shift_receipt.note'), bon.note);
  _wennText(zeilen, labelText('shift_receipt.operator'), bon.byName);
  _wennText(zeilen, labelText('shift_receipt.time'), _zeit(bon.at));
  return ReceiptLayout(lines: zeilen, paperSize: paperSize.value, ruleset: _regelwerk);
}
