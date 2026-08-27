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

  /// Definitiv kein Geld geflossen. Wiederholung gefahrlos.
  ///
  /// Entsteht nur aus einer POSITIVEN Aussage: einem echten Ergebniscode, der
  /// ablehnt, oder -- allein auf dem HPS-Weg -- einem nachweislich gelungenen
  /// Abbruch (`HpsClient.abort` mit `responseCode '0'`). Niemals aus einem
  /// Transportfehler, einem Zeitablauf oder einer Wissensluecke; dafuer gibt
  /// es [unresolved].
  ///
  /// Ausnahme `HpsPayments.cancel()`: dort steht [declined] fuer eine
  /// AUFHEBUNG, die nicht gegriffen hat -- die Originalzahlung bleibt in
  /// diesem Fall weiterhin belastet, und gefahrlos wiederholbar ist die
  /// Aufhebung, nicht die Zahlung.
  declined,

  /// Ausgang unbekannt. Eine Wiederholung kann ein zweites Mal belasten.
  unresolved,
}
