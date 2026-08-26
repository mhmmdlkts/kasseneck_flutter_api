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
  /// Ausnahme `HpsPayments.cancel()`: dort bezieht sich [CardPaymentOutcome.declined]
  /// auf die AUFHEBUNG, nicht auf die Originalzahlung -- die Originalbelastung
  /// steht dann weiterhin, eine Wiederholung waere hier gerade NICHT
  /// gefahrlos.
  bool get mayRetrySafely => outcome == CardPaymentOutcome.declined;

  bool get isUnresolved => outcome == CardPaymentOutcome.unresolved;

  @override
  String toString() =>
      'HpsResult(${outcome.name}, tx=$transactionId, steps=${steps.length})';
}
