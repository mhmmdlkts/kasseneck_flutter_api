/// Die Belegliste: Zeitraum, Filter, Tagesgruppen – Zwilling von `receipts.ts`
/// der Browser-Kasse.
///
/// Reine Funktionen; das Laden macht [RegisterReceiptClient].
///
/// **Gerechnet wird in Wiener Kalendertagen**, nicht in denen des Geräts. Ein
/// Tablet mit falsch gestellter Zeitzone darf den Kassenschluss nicht
/// verschieben — und um halb eins nachts sind „die Belege von heute" die des
/// laufenden Wiener Tages, nicht die des UTC-Vortags.
library;

import '../../enums/keck_payment_method.dart';
import '../../services/vienna_time.dart';
import 'belege.dart';

enum ReceiptPeriod { today, yesterday, last7Days, last30Days }

enum ReceiptTypeFilter { all, sale, cancellation, other }

enum PaymentFilter { all, cash, card }

class ReceiptFilter {
  const ReceiptFilter({
    this.period = ReceiptPeriod.today,
    this.receiptType = ReceiptTypeFilter.all,
    this.payment = PaymentFilter.all,
    this.operator,
  });

  final ReceiptPeriod period;
  final ReceiptTypeFilter receiptType;
  final PaymentFilter payment;

  /// Bediener-Name; `null` heißt alle.
  final String? operator;

  ReceiptFilter copyWith({
    ReceiptPeriod? period,
    ReceiptTypeFilter? receiptType,
    PaymentFilter? payment,
    String? operator,
    bool clearOperator = false,
  }) =>
      ReceiptFilter(
        period: period ?? this.period,
        receiptType: receiptType ?? this.receiptType,
        payment: payment ?? this.payment,
        operator: clearOperator ? null : (operator ?? this.operator),
      );
}

String _zwei(int n) => n.toString().padLeft(2, '0');

/// Der Wiener Kalendertag eines Zeitpunkts als `YYYY-MM-DD`.
String viennaDate(DateTime instant) {
  final w = ViennaTime.toWallClock(instant);
  return '${w.year}-${_zwei(w.month)}-${_zwei(w.day)}';
}

/// `from`/`to` (Wiener Wanduhr, `YYYY-MM-DD`) für den Zeitraum.
({String from, String to}) periodRange(ReceiptPeriod period, [DateTime? now]) {
  final zeit = now ?? DateTime.now();
  final heute = viennaDate(zeit);
  DateTime zurueck(int tage) => zeit.subtract(Duration(days: tage));
  return switch (period) {
    ReceiptPeriod.today => (from: heute, to: heute),
    ReceiptPeriod.yesterday => (from: viennaDate(zurueck(1)), to: viennaDate(zurueck(1))),
    // Sieben Tage schließen heute mit ein — also sechs zurück.
    ReceiptPeriod.last7Days => (from: viennaDate(zurueck(6)), to: heute),
    ReceiptPeriod.last30Days => (from: viennaDate(zurueck(29)), to: heute),
  };
}

/// Lesbarer Name der Belegart — nie ein Rohwert.
String receiptTypeLabel(ReceiptSummary receipt) {
  if (receipt.isCancellation) return 'Storno';
  switch (receipt.receiptType) {
    case 'standard':
      return 'Verkauf';
    case 'start':
      return 'Startbeleg';
    case 'training':
      return 'Trainingsbeleg';
    case 'zero':
      return switch (receipt.zeroKind) {
        'monthly' => 'Monatsbeleg',
        'annual' => 'Jahresbeleg',
        'annual_replacement' => 'Jahresbeleg (Ersatz)',
        'outage_end' => 'Nullbeleg nach Ausfall',
        'final' => 'Schlussbeleg',
        // Auch ein künftiger, hier unbekannter Anlass bleibt ein Nullbeleg.
        _ => 'Nullbeleg (Prüfbeleg)',
      };
    default:
      return 'Beleg';
  }
}

List<ReceiptSummary> filterReceipts(List<ReceiptSummary> receipts, ReceiptFilter f) {
  return [
    for (final b in receipts)
      if (_passt(b, f)) b,
  ];
}

bool _passt(ReceiptSummary b, ReceiptFilter f) {
  switch (f.receiptType) {
    case ReceiptTypeFilter.sale:
      if (!b.isSale) return false;
    case ReceiptTypeFilter.cancellation:
      if (!b.isCancellation) return false;
    case ReceiptTypeFilter.other:
      if (b.isSale || b.isCancellation) return false;
    case ReceiptTypeFilter.all:
      break;
  }
  final bar = b.paymentMethod == KeckPaymentMethod.cash;
  if (f.payment == PaymentFilter.cash && !bar) return false;
  if (f.payment == PaymentFilter.card && bar) return false;
  if (f.operator != null && (b.operator?.name ?? '') != f.operator) return false;
  return true;
}

/// Bediener-Namen in der Liste, für den Filter — sortiert, ohne Doppelte.
List<String> operatorNames(List<ReceiptSummary> receipts) {
  final namen = <String>{
    for (final b in receipts)
      if ((b.operator?.name ?? '').isNotEmpty) b.operator!.name,
  }.toList();
  namen.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return namen;
}

class ReceiptDayGroup {
  const ReceiptDayGroup({required this.date, required this.receipts});

  /// Wiener Kalendertag `YYYY-MM-DD`.
  final String date;
  final List<ReceiptSummary> receipts;
}

/// Nach Wiener Kalendertag gruppiert, neueste zuerst.
List<ReceiptDayGroup> groupByDay(List<ReceiptSummary> receipts) {
  final sortiert = [...receipts]..sort((a, b) => b.timeStamp.compareTo(a.timeStamp));
  final aus = <ReceiptDayGroup>[];
  for (final b in sortiert) {
    final datum = viennaDate(ViennaTime.parseServerTimeStamp(b.timeStamp));
    if (aus.isNotEmpty && aus.last.date == datum) {
      aus.last.receipts.add(b);
    } else {
      aus.add(ReceiptDayGroup(date: datum, receipts: [b]));
    }
  }
  return aus;
}

/// Uhrzeit eines Belegs in Wiener Wanduhrzeit (`HH:MM`).
String receiptTime(String timestamp) {
  final w = ViennaTime.toWallClock(ViennaTime.parseServerTimeStamp(timestamp));
  return '${_zwei(w.hour)}:${_zwei(w.minute)}';
}
