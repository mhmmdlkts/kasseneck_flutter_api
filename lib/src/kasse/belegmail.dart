/// Beleg per E-Mail an den Endkunden — der Vertrag des Endpunkts
/// `sendReceiptEmail`.
///
/// Verschickt wird ein **Link auf die oeffentliche Belegseite**, kein PDF: die
/// Belegseite setzt dasselbe Zeilenmodell wie Bildschirm und Bondrucker und
/// gibt dort auf Wunsch ein PDF aus. Ein mitgeschicktes waere dieselbe Sache
/// ein zweites Mal, nur unveraenderlich veraltet.
///
/// Zwilling von `BELEG_MAIL_FEHLER` (`src/kasse/texte.ts`) im JS-Paket und von
/// `FEHLERCODES` in `functions/beleg-mail-core.js` des Backends.
library;

/// Stabile Fehlercodes von `sendReceiptEmail`, in der Reihenfolge des
/// Backend-Katalogs. Sie kommen als `KasseneckApiError.code` an —
/// **entscheide am Code, nie am Text**, der deutsche Satz darf sich jederzeit
/// aendern.
///
/// Was sie bedeuten:
///   * `adresse_ungueltig` — die Adresse, nicht der Beleg: verbessern lassen.
///   * `beleg_nicht_gefunden` — es gibt ihn nicht **oder** er gehoert einer
///     anderen Kasse. Das Backend unterscheidet das nach aussen bewusst nicht,
///     sonst waere der Endpunkt ein Auskunftsdienst ueber fremde Belege.
///   * `zu_oft` — die Schleuse: hoechstens fuenf Mails je Beleg (24 h) und 30
///     je Kasse und Stunde. Spaeter noch einmal, nicht sofort wieder.
///   * `versand_fehlgeschlagen` — hinaus ging nichts; ein zweiter Versuch ist
///     hier erlaubt und sinnvoll.
const List<String> belegMailFehlercodes = [
  'adresse_ungueltig',
  'beleg_nicht_gefunden',
  'zu_oft',
  'versand_fehlgeschlagen',
];

/// Ist [wert] ein Code aus [belegMailFehlercodes]? Ein Anzeigetext ist keiner.
bool istBelegMailFehlercode(Object? wert) =>
    wert is String && belegMailFehlercodes.contains(wert);

/// Was das Backend ueber einen **erfolgten** Versand sagt.
///
/// Die drei Felder heissen wie in der Antwort (`data.to`, `data.at`,
/// `data.via`) — dieselben Namen fuehrt der JS-Zwilling, und so sagt in beiden
/// Paketen dasselbe Wort dasselbe.
class Belegmailergebnis {
  const Belegmailergebnis({required this.to, this.at, this.via});

  /// Die Adresse, an die es ging — normalisiert, wie das Backend sie
  /// protokolliert (getrimmt, kleingeschrieben). Fehlt sie in der Antwort,
  /// steht hier die gesendete Adresse: der Versand ist geschehen, und eine
  /// leere Zeile am Bildschirm waere schlechter als die eigene Eingabe.
  final String to;

  /// Zeitpunkt des Versands als ISO-Text in **Wiener** Zeit, so wie ihn das
  /// Backend setzt. Bewusst der Text und kein `DateTime`: der Offset ist Teil
  /// der Aussage, und ein Umbau in Ortszeit des Geraets machte aus 21:12 in
  /// Wien eine andere Uhrzeit am Tresen.
  final String? at;

  /// Der Weg, auf dem die Mail hinausging: `eigen` (Postfach des Betriebs),
  /// `plattform` oder `plattform-fallback` (eigenes Postfach hinterlegt, aber
  /// gescheitert — dann ist am Konto etwas zu richten).
  final String? via;

  /// Liest die Antwort **defensiv**: was fehlt oder den falschen Typ hat, wird
  /// zu `null` statt zu einem Wurf.
  ///
  /// Das ist Absicht und nicht Nachlaessigkeit. An dieser Stelle ist die Mail
  /// bereits draussen; ein Wurf sagte der Kasse „nicht gesendet", und der
  /// Kassier schickte sie noch einmal. Fuer `at` und `via` hinge daran nur eine
  /// Zeile Anzeige — fuer den Gast eine zweite Mail.
  factory Belegmailergebnis.aus(Object? daten, {required String gesendetAn}) {
    final map = daten is Map ? daten : const {};
    final to = map['to'];
    final at = map['at'];
    final via = map['via'];
    return Belegmailergebnis(
      to: to is String && to.trim().isNotEmpty ? to : gesendetAn,
      at: at is String && at.isNotEmpty ? at : null,
      via: via is String && via.isNotEmpty ? via : null,
    );
  }

  @override
  String toString() => 'Belegmailergebnis($to, at: $at, via: $via)';
}
