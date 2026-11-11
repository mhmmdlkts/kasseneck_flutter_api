/// Zahlung auf Rechnung (`invoicePayments` am Beleg, Backend `rechnungszahlung`): Ein Zahlungsbeleg
/// nimmt in der Kasse Geld fuer eine oder mehrere Rechnungen entgegen (bar oder mit Karte vor Ort) bzw.
/// gibt es zu einer Gutschrift zurueck. Seine Positionen tragen `kind: 'invoice_payment'` und zaehlen im
/// RKSV-Feld „Null“; die Umsatzsteuer steht auf der Rechnung, nicht am Beleg.
///
/// Je Rechnung ein Bezug, in der Reihenfolge der Positionen (eine Zeile je Rechnung). Der Bezug ist nicht
/// signiert (wie `cancellationOf`), die Rechnungsnummer steht zusaetzlich im Text der Position.
///
/// Nur der Server legt solche Belege an; dieses Paket liest sie nur. Zwilling von `InvoicePaymentRef`
/// im npm-Paket (1.38.0).
class InvoicePaymentRef {
  const InvoicePaymentRef({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.paymentId,
    this.customerId,
    required this.amountCents,
    this.partial = false,
    this.paidOn,
    this.includesVat = false,
  });

  final String invoiceId;

  /// Nummer der Rechnung bzw. Gutschrift aus ihrem Rechnungskreis (`2026-0042`).
  final String invoiceNumber;

  /// Kennung des Zahlungseintrags an der Rechnung.
  final String paymentId;
  final String? customerId;

  /// Betrag dieser Zeile in Cent; bei einer Rueckzahlung zu einer Gutschrift negativ.
  final int amountCents;

  /// Teilzahlung: weniger als der Rechnungsbetrag.
  final bool partial;

  /// Zahlungstag `YYYY-MM-DD` (Wiener Tag), `null` wenn unbekannt.
  final String? paidOn;

  /// Weist die Rechnung Umsatzsteuer aus? Nur dann steht „inkl. USt“ am Beleg.
  final bool includesVat;

  /// Liest `invoicePayments` vom Draht. Ein Eintrag ohne Rechnungs-ID, Nummer, Zahlungs-ID oder
  /// ganzzahligen Betrag faellt weg (lesen tolerant, der Beleg bleibt anzeigbar); ohne brauchbaren
  /// Eintrag gibt es keinen Bezug (`null`). `includesVat` gilt nur bei ausdruecklichem `true`: ein Beleg
  /// behauptet nie eine Steuer, die er nicht kennt.
  static List<InvoicePaymentRef>? fromJsonList(Object? raw) {
    if (raw is! List) return null;
    String? text(Object? w) => w is String && w.isNotEmpty ? w : null;
    final raus = <InvoicePaymentRef>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final id = text(e['invoiceId']);
      final nummer = text(e['invoiceNumber']);
      final zahlung = text(e['paymentId']);
      final betrag = e['amountCents'];
      if (id == null || nummer == null || zahlung == null) continue;
      if (betrag is! num || betrag != betrag.truncate()) continue;
      raus.add(InvoicePaymentRef(
        invoiceId: id,
        invoiceNumber: nummer,
        paymentId: zahlung,
        customerId: text(e['customerId']),
        amountCents: betrag.toInt(),
        partial: e['partial'] == true,
        paidOn: text(e['paidOn']),
        includesVat: e['includesVat'] == true,
      ));
    }
    return raus.isEmpty ? null : raus;
  }

  Map<String, dynamic> toJson() => {
        'invoiceId': invoiceId,
        'invoiceNumber': invoiceNumber,
        'paymentId': paymentId,
        'customerId': customerId,
        'amountCents': amountCents,
        'partial': partial,
        'paidOn': paidOn,
        'includesVat': includesVat,
      };
}
