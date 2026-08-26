import 'transaction_response.dart';

/// Ausgang eines Zahlvorgangs -- die einzige Frage, die der Aufrufer wirklich
/// hat: darf ich es nochmal versuchen?
enum CardPaymentOutcome {
  /// Geld ist geflossen. Buchen, nicht wiederholen.
  approved,

  /// Definitiv kein Geld geflossen: das Terminal hat abgelehnt, oder der
  /// Vorgang wurde nachweislich abgebrochen. Wiederholung gefahrlos.
  declined,

  /// Ausgang unbekannt. Eine Wiederholung kann ein zweites Mal belasten.
  unresolved,
}

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
  bool get mayRetrySafely => outcome == CardPaymentOutcome.declined;

  bool get isUnresolved => outcome == CardPaymentOutcome.unresolved;

  @override
  String toString() =>
      'HpsResult(${outcome.name}, tx=$transactionId, steps=${steps.length})';
}
