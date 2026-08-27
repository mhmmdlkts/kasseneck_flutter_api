import '../payments/card_payment_outcome.dart';
import 'transaction_response.dart';

/// Ergebnis eines Zahlvorgangs samt Kennung und Klaerungsverlauf.
///
/// [transactionId] ist IMMER gesetzt, auch bei [CardPaymentOutcome.unresolved]
/// -- ohne sie sind Statusabfrage und Storno unerreichbar, und genau daran ist
/// der Vorfall vom 24.08.2026 gescheitert.
class HpsResult {
  const HpsResult({
    required this.outcome,
    required this.transactionId,
    this.response,
    this.steps = const <String>[],
  });

  final CardPaymentOutcome outcome;
  final String transactionId;

  /// Die letzte Antwort des Terminals, sofern eine ankam.
  final TransactionResponse? response;

  /// Verlauf der Klaerung, in Reihenfolge -- fuer Anzeige und Protokoll.
  final List<String> steps;

  bool get isApproved => outcome == CardPaymentOutcome.approved;

  /// Nur bei [CardPaymentOutcome.declined] steht fest, dass nichts belastet
  /// wurde.
  ///
  /// Bei `HpsPayments.cancel()` ist der Bezug ein anderer, das Ergebnis aber
  /// dasselbe: [CardPaymentOutcome.declined] heisst dort, dass die AUFHEBUNG
  /// nicht gegriffen hat -- die Originalbelastung steht also weiterhin. Eine
  /// Wiederholung der Aufhebung ist trotzdem gefahrlos, gerade weil
  /// nachweislich noch keine gegriffen hat. Was NICHT gefahrlos ist: das als
  /// "der Kunde wurde nicht belastet" zu lesen.
  bool get mayRetrySafely => outcome == CardPaymentOutcome.declined;

  bool get isUnresolved => outcome == CardPaymentOutcome.unresolved;

  @override
  String toString() =>
      'HpsResult(${outcome.name}, tx=$transactionId, steps=${steps.length})';
}
