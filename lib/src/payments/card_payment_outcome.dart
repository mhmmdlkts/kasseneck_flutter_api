/// Ausgang eines Kartenzahlvorgangs -- die einzige Frage, die der Aufrufer
/// wirklich hat: darf ich es nochmal versuchen?
///
/// Geteilt zwischen dem lokalen HPS-Terminalweg (`HpsPayments`) und der
/// Hobex-Cloud (`HobexCloudPayments`): beide klaeren denselben dreiwertigen
/// Ausgang, nur ueber verschiedene Transportwege. Deshalb liegt der Typ hier,
/// nicht in einem der beiden Zahlweg-Baeume -- ein "Hps"-Praefix waere fuer
/// den Cloud-Weg irrefuehrend gewesen.
enum CardPaymentOutcome {
  /// Geld ist geflossen. Buchen, nicht wiederholen.
  approved,

  /// Definitiv kein Geld geflossen: ein echter Ergebniscode hat abgelehnt,
  /// oder der Vorgang wurde nachweislich abgebrochen. Wiederholung gefahrlos.
  declined,

  /// Ausgang unbekannt. Eine Wiederholung kann ein zweites Mal belasten.
  unresolved,
}
