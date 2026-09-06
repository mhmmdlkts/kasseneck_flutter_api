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
    this.lastResponse,
    this.steps = const <String>[],
  });

  final CardPaymentOutcome outcome;
  final String transactionId;

  /// Die Antwort des Terminals, die den Ausgang FESTGESCHRIEBEN hat -- nur
  /// bei [CardPaymentOutcome.approved] und [CardPaymentOutcome.declined].
  /// Bei [CardPaymentOutcome.unresolved] bleibt sie `null`: eine
  /// Nicht-Aussage darf nicht als Beleg mitgegeben werden. Was das Terminal
  /// zuletzt gesagt hat, steht dann in [lastResponse].
  final TransactionResponse? response;

  /// Die letzte Antwort des Terminals bei [CardPaymentOutcome.unresolved],
  /// sofern ueberhaupt eine ankam -- auch wenn sie nichts entschied (`9027`,
  /// `9900`, ein unbekannter Code). NIE ein Beleg, sondern Material fuer
  /// Anzeige und Katalog: am 02.09.2026 sah der Bediener bei einer Antwort
  /// `55` "PIN falsch" nur "Ausgang unklar", musste raten und buchte eine
  /// abgelehnte Zahlung als bezahlt. Der Klartext des Terminals haette die
  /// Entscheidung getragen. Bei schluessigem Ausgang `null` -- die Antwort
  /// steht dann in [response].
  final TransactionResponse? lastResponse;

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
