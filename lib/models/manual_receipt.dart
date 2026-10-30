/// Nacherfassung eines Handbelegs (`manualReceipt` am Beleg): Nach einem
/// Ausfall der Kasse oder einer Leistung ausser Haus wird der
/// handschriftliche Beleg (Paragon) in der Kasse nacherfasst. Der Beleg traegt
/// dann Nummer, Datum und Grund des Handbelegs; sein eigener Zeitstempel bleibt
/// der Zeitpunkt der Nacherfassung (kein Rueckdatieren).
///
/// Rechtsgrundlage: § 17 Abs 5 RKSV, Registrierkassenerlass Abschnitt 3.6.1
/// (Ausfall, Tagessammelbeleg erlaubt) und 6.7 (ausser Haus, jeder Beleg
/// einzeln; nicht fuer Taxi und Mietwagen, § 7 Abs 2 BarUV).
/// Geprueft wird am Server. Zwilling von `models/manual-receipt.ts` im npm-Paket.
library;

/// Gruende einer Nacherfassung: fuenf Ausfall-Gruende und die Leistung ausser Haus.
const List<String> manualReceiptReasons = [
  'network_outage', 'power_outage', 'device_failure', 'system_outage', 'other', 'outside_premises',
];

/// Fehlercodes von `createReceipt` zur Nacherfassung (Vertrag `errorCodes.manualReceipt`).
/// `manual_receipt_duplicate` traegt in `details.receiptId` den Beleg, der den
/// Handbeleg schon nacherfasst hat: nicht erneut senden, sondern diesen nehmen.
const List<String> manualReceiptErrorCodes = [
  'invalid_manual_receipt',
  'manual_receipt_not_allowed',
  'manual_receipt_date_in_future',
  'manual_receipt_range_not_allowed',
  'manual_receipt_duplicate',
];

bool isManualReceiptErrorCode(Object? value) => value is String && manualReceiptErrorCodes.contains(value);

class ManualReceipt {
  const ManualReceipt({required this.number, this.numberTo, this.count, required this.date, this.time, required this.reason, this.note});

  /// Nummer des Handbelegs (eigene Nummernreihe des Paragons, nie die Kassennummer).
  final String number;

  /// Letzte Nummer: macht den Beleg zum Tagessammelbeleg (nur nach einem Ausfall).
  final String? numberTo;

  /// Zahl der Handbelege im Tagessammelbeleg.
  final int? count;

  /// Tag des Handbelegs, `YYYY-MM-DD` (Wiener Tag).
  final String date;

  /// Uhrzeit des Handbelegs, `HH:MM`.
  final String? time;

  /// Grund aus [manualReceiptReasons]; ein unbekannter bleibt als roher Text lesbar.
  final String reason;

  /// Eigener Text, nur beim Grund `other`.
  final String? note;

  /// Tagessammelbeleg (erste bis letzte Nummer).
  bool get isDailySummary => numberTo != null;

  /// `null`, wenn Nummer, Datum oder Grund fehlen; ein Zusatzfeld in falscher
  /// Form faellt weg, statt den Beleg scheitern zu lassen.
  static ManualReceipt? fromJson(Object? raw) {
    if (raw is! Map) return null;
    String? text(String k) => raw[k] is String && (raw[k] as String).isNotEmpty ? raw[k] as String : null;
    final number = text('number');
    final date = text('date');
    final reason = text('reason');
    if (number == null || date == null || reason == null) return null;
    final count = raw['count'];
    return ManualReceipt(
      number: number,
      numberTo: text('numberTo'),
      count: count is int ? count : null,
      date: date,
      time: text('time'),
      reason: reason,
      note: text('note'),
    );
  }

  Map<String, Object> toJson() => {
        'number': number,
        'numberTo': ?numberTo,
        'count': ?count,
        'date': date,
        'time': ?time,
        'reason': reason,
        'note': ?note,
      };
}
