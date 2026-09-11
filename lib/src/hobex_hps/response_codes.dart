/// Die vollstaendige Codetabelle des hobex-HPS: jeder Ergebniscode, dessen
/// Bedeutung GEMESSEN oder von hobex DOKUMENTIERT ist, mit seiner Wirkung auf
/// den Ausgang und dem Grund, auf den eine Kasse reagiert.
///
/// **Zwilling:** `src/payments/hobex-hps/transaction-response.ts` im
/// npm-Paket, dort `HPS_CODES`. Das npm-Paket gibt die Tabelle als
/// `fixtures/hobex-hps-codes.json` aus; Aenderungen gehoeren in beide.
///
/// ## Zwei Quellen, eine Regel
///
/// Bis 10.09.2026 standen hier nur GEMESSENE Codes (TID 3600335 und 3556988,
/// siehe `doc/kartenzahlung.md`). Am 11.09.2026 kam die Antwortcodeliste von
/// hobex selbst dazu: 31 Codes. Sie beantwortet, was drei Codes aus dem
/// Betrieb bedeuten (`100004`, `100005`, `100015`), bestaetigt fuenf
/// gemessene und benennt 23, die an keinem Geraet aufgetreten sind.
///
/// Die Regel aus [TransactionResponse.isConclusive] bleibt: ein Code wird nur
/// dann zu einem Ausgang, wenn seine Bedeutung FESTSTEHT. Die Liste von hobex
/// ist eine solche Feststellung -- sie ist die Beschreibung des Herstellers,
/// kein Raten aus der Codefamilie. Geraten wird weiterhin nicht: ein Code, der
/// in dieser Tabelle fehlt, bleibt eine Wissensluecke.
///
/// ## Welcher dokumentierte Code was bewirkt
///
/// Entscheidend ist, WO im Ablauf der Code entsteht:
///
/// - **Vor dem Host** (Anfrage, Kartenlesen, EMV-Kernel, Eingaben am Geraet,
///   Geraetezustand): es ist nachweislich keine Autorisierung beim Host
///   angekommen -- [HpsCodeEffect.conclusive], also `declined`.
/// - **`100029`**, Zeitueberschreitung zum Host MIT "auto-reversal": das
///   Terminal storniert selbst, laut hobex -- ebenfalls `declined`.
/// - **Beim oder nach dem Host, OHNE auto-reversal** (`100006`, `100007`,
///   `100023`, `100024`, `100026`, `100027`) und der Sammelcode `100999`:
///   [HpsCodeEffect.hostUncertain]. Das Terminal weiss selbst nicht, ob der
///   Host belastet hat -- hobex vermerkt bei `100006`/`100007` ausdruecklich,
///   dass es NICHT storniert. Eine Statusabfrage, die danach `9027` sagt,
///   beweist hier nichts: sie spiegelt nur, was das Terminal gespeichert hat,
///   nicht, was beim Host passiert ist. Genau deshalb greift die
///   Zwei-`9027`-Regel fuer diese Codes NICHT (siehe `HpsPayments`).
library;

/// Wie ein Ergebniscode den Ausgang eines Vorgangs bestimmt.
enum HpsCodeEffect {
  /// Der Code schreibt den Ausgang fest: `'0'` genehmigt, jeder andere
  /// abgelehnt (bei einer Aufhebung sinngemaess, siehe `HpsPayments.cancel`).
  conclusive,

  /// Gemessen oder dokumentiert, aber ausdruecklich KEINE Aussage ueber den
  /// Vorgang (`9027`, `9900`, `100011`) -- ein Grund weiterzuklaeren.
  noStatement,

  /// Der Host war beteiligt, das Terminal storniert nicht selbst -- ob belastet
  /// wurde, weiss das Terminal nicht. Ein Grund weiterzuklaeren, aber ohne dass
  /// ein spaeteres `9027` daraus "nichts belastet" machen darf.
  hostUncertain,
}

/// Woher die Bedeutung eines Codes stammt.
enum HpsCodeSource {
  /// Am Geraet gemessen (siehe `doc/kartenzahlung.md`).
  measured,

  /// Aus der Antwortcodeliste von hobex (erhalten 11.09.2026).
  documented,

  /// Beides: gemessen und von hobex bestaetigt.
  measuredAndDocumented,
}

/// Worauf eine Kasse reagiert -- der Grund hinter einem Ergebniscode.
///
/// Mehrere Codes teilen sich einen Grund, wenn am Tresen dasselbe zu tun ist
/// (`100004`, `100005` und `100012` heissen alle "Karte nicht gelesen, noch
/// einmal"). [hint] ist der Satz fuer den Bediener; eine Kasse mit eigener
/// Uebersetzung schluesselt stattdessen ueber [name].
enum HpsCodeReason {
  approved('Vom Terminal genehmigt.'),
  aborted('Der Vorgang wurde abgebrochen. Es wurde kein Geld bewegt.'),
  noCard(
    'Es wurde keine Karte vorgehalten. Es wurde kein Geld bewegt — '
    'bitte erneut versuchen.',
  ),
  cardReadFailed(
    'Die Karte konnte nicht gelesen werden. Es wurde kein Geld '
    'bewegt — bitte erneut versuchen, notfalls die Karte stecken statt '
    'auflegen.',
  ),
  cardDeclined(
    'Die Karte wurde vom Terminal abgelehnt. Es wurde kein Geld '
    'bewegt — bitte eine andere Karte oder Zahlungsart verwenden.',
  ),
  wrongPin(
    'Die PIN war falsch. Es wurde kein Geld bewegt — bitte erneut '
    'versuchen.',
  ),
  amountInvalid(
    'Das Terminal nimmt diesen Betrag nicht an. Es wurde kein '
    'Geld bewegt.',
  ),
  tipNotSelected(
    'Das Trinkgeld wurde nicht rechtzeitig gewählt. Es wurde '
    'kein Geld bewegt — bitte erneut versuchen.',
  ),
  terminalBusy(
    'Das Terminal ist noch mit einem anderen Vorgang beschäftigt. '
    'Es wurde kein Geld bewegt — kurz warten und erneut versuchen.',
  ),
  terminalBlocked(
    'Das Terminal ist gesperrt. Es wurde kein Geld bewegt — '
    'bitte hobex kontaktieren.',
  ),
  terminalSetup(
    'Das Terminal ist nicht richtig eingerichtet. Es wurde kein '
    'Geld bewegt — bitte die Terminal-ID in den Einstellungen prüfen, sonst '
    'hobex kontaktieren.',
  ),
  terminalFault(
    'Das Terminal meldet eine Störung. Es wurde kein Geld bewegt '
    '— bitte das Terminal neu starten und erneut versuchen.',
  ),
  requestRejected(
    'Das Terminal hat die Anfrage abgewiesen. Es wurde kein '
    'Geld bewegt — tritt das wieder auf, bitte den Support kontaktieren.',
  ),
  invalidTransaction(
    'Das Terminal kennt die ursprüngliche Zahlung nicht. Es '
    'wurde kein Geld bewegt.',
  ),
  refundPassword(
    'Das Passwort für die Gutschrift war falsch oder wurde nicht '
    'eingegeben. Es wurde nichts ausgezahlt.',
  ),
  refundDisabled(
    'Gutschriften sind an diesem Terminal abgeschaltet. Es wurde '
    'nichts ausgezahlt — bitte hobex kontaktieren.',
  ),
  hostTimeoutReversed(
    'hobex hat nicht rechtzeitig geantwortet, das Terminal '
    'hat den Vorgang selbst storniert. Es wird kein Geld bewegt — bitte '
    'erneut versuchen.',
  ),
  hostFault(
    'Die Verbindung zwischen Terminal und hobex ist gestört. Ob die '
    'Karte belastet wurde, weiß das Terminal nicht — bitte nicht erneut '
    'kassieren, bevor es geklärt ist.',
  ),
  internalError(
    'Das Terminal meldet einen internen Fehler. Ob die Karte '
    'belastet wurde, ist unklar — bitte nicht erneut kassieren, bevor es '
    'geklärt ist.',
  ),
  canceled('Die Zahlung ist aufgehoben.'),
  notAbortable(
    'Der Vorgang ist bereits abgeschlossen und lässt sich nicht '
    'mehr abbrechen.',
  ),
  noStatement('Das Terminal hat zu diesem Vorgang keine Auskunft.'),
  technicalError(
    'Das Terminal meldet einen technischen Fehler; über den '
    'Vorgang sagt das nichts.',
  ),
  unknown(
    'Das Terminal nennt einen Code, dessen Bedeutung nicht bekannt '
    'ist.',
  );

  const HpsCodeReason(this.hint);

  /// Der Satz fuer den Bediener, deutsch.
  final String hint;

  /// Die beiden Gruende, hinter denen ein Code mit
  /// [HpsCodeEffect.hostUncertain] steht: ob Geld geflossen ist, weiss das
  /// Terminal nicht.
  bool get hostUncertain => this == hostFault || this == internalError;
}

/// Ein Ergebniscode, dessen Bedeutung feststeht.
class HpsCode {
  const HpsCode({
    required this.code,
    required this.title,
    required this.meaning,
    required this.effect,
    required this.reason,
    required this.source,
  });

  /// Der Ergebniscode, wie ihn das Terminal im Feld `responseCode` sendet.
  final String code;

  /// Der Titel, wie hobex ihn fuehrt bzw. wie das Terminal ihn als
  /// `responseText` sendet -- englisch, unveraendert.
  final String title;

  /// Bedeutung, deutsch, fuer Nachweis und Protokoll.
  final String meaning;

  final HpsCodeEffect effect;
  final HpsCodeReason reason;
  final HpsCodeSource source;

  /// Schreibt den Ausgang fest -- Teil der Positivliste von
  /// [TransactionResponse.isConclusive].
  bool get conclusive => effect == HpsCodeEffect.conclusive;

  /// Siehe [HpsCodeEffect.hostUncertain].
  bool get hostUncertain => effect == HpsCodeEffect.hostUncertain;
}

/// Die Tabelle selbst und die Abfrage darauf.
abstract final class HpsCodes {
  /// Alle Codes, deren Bedeutung feststeht. Reihenfolge wie im Zwilling:
  /// zuerst die gemessenen in der Reihenfolge des Messprotokolls, dann die
  /// von hobex dokumentierten aufsteigend.
  static const List<HpsCode> all = <HpsCode>[
    HpsCode(
      code: '0',
      title: 'Authorized',
      meaning: 'genehmigt',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.approved,
      source: HpsCodeSource.measuredAndDocumented,
    ),
    HpsCode(
      code: '9002',
      title: 'Invalid Transaction',
      meaning:
          'ungueltiger Vorgang -- das Terminal hat den Vorgang selbst '
          'als unzulaessig verworfen, bevor irgendetwas in Bewegung kam',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.invalidTransaction,
      source: HpsCodeSource.measured,
    ),
    HpsCode(
      code: '9011',
      title: 'Transaction Canceled',
      meaning:
          'aufgehoben ("Transaction Canceled") -- der Vorgang unter '
          'dieser Kennung wurde storniert',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.canceled,
      source: HpsCodeSource.measured,
    ),
    HpsCode(
      code: '9027',
      title: 'Original Tx not found',
      meaning:
          'keine Aussage -- steht gleichermassen fuer "nie gesehen", '
          '"laeuft gerade", "Karte nicht aufgelegt" und "abgebrochen"',
      effect: HpsCodeEffect.noStatement,
      reason: HpsCodeReason.noStatement,
      source: HpsCodeSource.measured,
    ),
    HpsCode(
      code: '9900',
      title: 'Technical Error Database',
      meaning:
          '"Technical Error Database" -- gemessen im Zusammenhang mit '
          'einer nicht rein numerischen Kennung; keine Aussage ueber den '
          'Vorgang selbst',
      effect: HpsCodeEffect.noStatement,
      reason: HpsCodeReason.technicalError,
      source: HpsCodeSource.measured,
    ),
    HpsCode(
      code: '9003',
      title: 'Invalid Amount',
      meaning:
          '"Invalid Amount" -- der Betrag wird abgewiesen, BEVOR eine '
          'Karte verlangt wird (28.08.2026: 99999,99 EUR, Antwort nach 15,7 s '
          'ohne Kartenaufforderung); nichts belastet',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.amountInvalid,
      source: HpsCodeSource.measured,
    ),
    HpsCode(
      code: '100002',
      title: 'Aborted',
      meaning:
          'abgebrochen ("Aborted") -- ueber die Kasse oder am Terminal; '
          'nichts belastet',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.aborted,
      source: HpsCodeSource.measuredAndDocumented,
    ),
    HpsCode(
      code: '100003',
      title: 'Card not present',
      meaning:
          'Karte nicht aufgelegt ("Card not present") -- innerhalb der '
          'Frist (gemessen rund 60 s) keine Karte; nichts belastet',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.noCard,
      source: HpsCodeSource.measuredAndDocumented,
    ),
    HpsCode(
      code: '100010',
      title: 'Unable to abort transaction',
      meaning:
          'nicht mehr abbrechbar -- der Vorgang ist bereits '
          'abgeschlossen',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.notAbortable,
      source: HpsCodeSource.measuredAndDocumented,
    ),
    HpsCode(
      code: '100019',
      title: 'Amount is not in a valid range',
      meaning:
          '"Amount is not in a valid range" -- Betrag ausserhalb des '
          'zulaessigen Bereichs, gemessen mit negativem Betrag; Abweisung vor '
          'dem Kartenfluss, nichts belastet',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.amountInvalid,
      source: HpsCodeSource.measuredAndDocumented,
    ),
    HpsCode(
      code: '100108',
      title: 'Invalid TID',
      meaning:
          '"Invalid TID" -- die Terminal-Kennung gibt es an diesem '
          'Geraet nicht; der Vorgang wird abgewiesen, bevor etwas geschieht',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.terminalSetup,
      source: HpsCodeSource.measured,
    ),
    HpsCode(
      code: '55',
      title: 'PIN falsch',
      meaning:
          '"PIN falsch" -- Host-Ablehnung wegen falscher PIN, die erste '
          'gemessene Host-Ablehnung ueberhaupt (02.09.2026 im Betrieb, TID '
          '3556988, HPS 1.11.4, Firmware 2.3.9): die Zahlung antwortete direkt '
          'damit, die Statusabfrage danach elfmal in Folge ebenso -- eine '
          'Host-Ablehnung bleibt am Terminal abrufbar; nichts belastet',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.wrongPin,
      source: HpsCodeSource.measured,
    ),
    // ---- ab hier: Antwortcodeliste von hobex, erhalten 11.09.2026 ----
    HpsCode(
      code: '100001',
      title: 'Bad Request',
      meaning:
          'fehlerhafte Anfrage der Kasse ("Bad Request") -- Abweisung '
          'vor dem Kartenfluss; nichts belastet',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.requestRejected,
      source: HpsCodeSource.documented,
    ),
    HpsCode(
      code: '100004',
      title: 'Card read failed',
      meaning:
          'Karte nicht lesbar ("Card read failed") -- Fehler beim Umgang '
          'mit der Karte, vor jeder Autorisierung; im Betrieb (TID 3556988, '
          '28.08.2026) danach dauerhaft 9027; nichts belastet',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.cardReadFailed,
      source: HpsCodeSource.documented,
    ),
    HpsCode(
      code: '100005',
      title: 'App select failed',
      meaning:
          'Anwendungsauswahl gescheitert ("App select failed") -- die '
          'Karte bietet keine passende Anwendung, vor jeder Autorisierung; im '
          'Betrieb danach dauerhaft 9027; nichts belastet',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.cardReadFailed,
      source: HpsCodeSource.documented,
    ),
    HpsCode(
      code: '100006',
      title: 'Communication with TecsXml failed',
      meaning:
          'keine Verbindung zum hobex-Host ("Communication with TecsXml '
          'failed") -- das Terminal storniert NICHT selbst; ob beim Host etwas '
          'angekommen ist, weiss das Terminal nicht',
      effect: HpsCodeEffect.hostUncertain,
      reason: HpsCodeReason.hostFault,
      source: HpsCodeSource.documented,
    ),
    HpsCode(
      code: '100007',
      title: 'Processing of TecsXml step failed',
      meaning:
          'Schritt beim hobex-Host gescheitert ("Processing of TecsXml '
          'step failed") -- das Terminal storniert NICHT selbst; ob beim Host '
          'belastet wurde, weiss das Terminal nicht',
      effect: HpsCodeEffect.hostUncertain,
      reason: HpsCodeReason.hostFault,
      source: HpsCodeSource.documented,
    ),
    HpsCode(
      code: '100008',
      title: 'Invalid TID',
      meaning:
          'Terminal-Kennung passt nicht ("Invalid TID") -- die TID der '
          'Anfrage ist nicht die eingerichtete; Abweisung vor dem '
          'Kartenfluss, nichts belastet (am Geraet gemessen wurde dafuer '
          '100108)',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.terminalSetup,
      source: HpsCodeSource.documented,
    ),
    HpsCode(
      code: '100009',
      title: 'Invalid Tx Type',
      meaning:
          'Vorgangstyp unbekannt oder nicht moeglich ("Invalid Tx '
          'Type") -- Abweisung vor dem Kartenfluss; nichts belastet',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.requestRejected,
      source: HpsCodeSource.documented,
    ),
    HpsCode(
      code: '100011',
      title: 'Not Found',
      meaning:
          'nicht gefunden ("Not Found") -- das Terminal kennt den '
          'Vorgang nicht; keine Aussage ueber den Vorgang, anders als 9027 '
          'aber nie gemessen und deshalb ohne dessen Schlussregel',
      effect: HpsCodeEffect.noStatement,
      reason: HpsCodeReason.noStatement,
      source: HpsCodeSource.documented,
    ),
    HpsCode(
      code: '100012',
      title: 'Max retries exceeded',
      meaning:
          'zu viele Kartenversuche ("Max retries exceeded") -- die Karte '
          'wurde mehrfach (Vorgabe 3) erfolglos vorgehalten; nichts belastet',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.cardReadFailed,
      source: HpsCodeSource.documented,
    ),
    HpsCode(
      code: '100013',
      title: 'Diagnosis failed',
      meaning:
          'Diagnose gescheitert ("Diagnosis failed") -- das Terminal '
          'konnte die Daten des EMV-Kernels nicht lesen; kein Kartenfluss, '
          'nichts belastet',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.terminalFault,
      source: HpsCodeSource.documented,
    ),
    HpsCode(
      code: '100014',
      title: "Card information wasn't entered",
      meaning:
          'Kartendaten nicht eingegeben ("Card information wasn\'t '
          'entered") -- die MOTO-Eingabe kam nicht innerhalb der Frist; '
          'nichts belastet',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.noCard,
      source: HpsCodeSource.documented,
    ),
    HpsCode(
      code: '100015',
      title: 'Card declined',
      meaning:
          'Karte vom EMV-Kernel abgelehnt ("Card declined") -- Ablehnung '
          'im Terminal, vor jeder Autorisierung beim Host; im Betrieb danach '
          'dauerhaft 9027; nichts belastet',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.cardDeclined,
      source: HpsCodeSource.documented,
    ),
    HpsCode(
      code: '100017',
      title: 'Card Not Supported',
      meaning:
          'Karte nicht unterstuetzt ("Card Not Supported") -- der '
          'EMV-Kernel kennt die Karte nicht; nichts belastet',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.cardDeclined,
      source: HpsCodeSource.documented,
    ),
    HpsCode(
      code: '100018',
      title: 'Scep enrollment failed',
      meaning:
          'Zertifikatsanmeldung gescheitert ("Scep enrollment failed") '
          '-- falscher Code oder keine Verbindung; das Terminal kann den Host '
          'nicht ansprechen, nichts belastet',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.terminalSetup,
      source: HpsCodeSource.documented,
    ),
    HpsCode(
      code: '100020',
      title: 'Refund password is invalid',
      meaning:
          'Passwort fuer die Gutschrift falsch ("Refund password is '
          'invalid") -- die Gutschrift wird nicht ausgefuehrt, nichts '
          'ausgezahlt',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.refundPassword,
      source: HpsCodeSource.documented,
    ),
    HpsCode(
      code: '100021',
      title: 'Failed to enter the password',
      meaning:
          'Passwort nicht eingegeben ("Failed to enter the password") -- '
          'nicht innerhalb der Frist; nichts ausgefuehrt',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.refundPassword,
      source: HpsCodeSource.documented,
    ),
    HpsCode(
      code: '100022',
      title: 'Terminal is blocked',
      meaning:
          'Terminal gesperrt ("Terminal is blocked") -- das Geraet ist '
          'nicht IN_OPERATION; nichts belastet',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.terminalBlocked,
      source: HpsCodeSource.documented,
    ),
    HpsCode(
      code: '100023',
      title: 'Invalid message type',
      meaning:
          'ungueltige Antwort des hobex-Hosts ("Invalid message type") -- '
          'Nachricht und Antwortcode in den UserData ungueltig; ob beim Host '
          'belastet wurde, weiss das Terminal nicht',
      effect: HpsCodeEffect.hostUncertain,
      reason: HpsCodeReason.hostFault,
      source: HpsCodeSource.documented,
    ),
    HpsCode(
      code: '100024',
      title: 'Transaction completion has failed',
      meaning:
          'Abschluss des Online-Vorgangs gescheitert ("Transaction '
          'completion has failed") -- NACH der Anfrage beim Host; ob belastet '
          'bleibt, weiss das Terminal nicht',
      effect: HpsCodeEffect.hostUncertain,
      reason: HpsCodeReason.hostFault,
      source: HpsCodeSource.documented,
    ),
    HpsCode(
      code: '100025',
      title: 'Refund transactions are disabled',
      meaning:
          'Gutschriften abgeschaltet ("Refund transactions are '
          'disabled") -- in der Geraeteeinstellung; nichts ausgezahlt',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.refundDisabled,
      source: HpsCodeSource.documented,
    ),
    HpsCode(
      code: '100026',
      title: 'Transaction was declined.',
      meaning:
          'Host-Antwort passt nicht zur Karte ("Transaction was '
          'declined.") -- Chip-Daten fuer eine Karte ohne Chip; das Terminal '
          'lehnt ab, ob der Host zuvor belastet hat, ist offen',
      effect: HpsCodeEffect.hostUncertain,
      reason: HpsCodeReason.hostFault,
      source: HpsCodeSource.documented,
    ),
    HpsCode(
      code: '100027',
      title: 'Unsupported UserData in TecsXml Response',
      meaning:
          'unbekannte Daten in der Antwort des hobex-Hosts ("Unsupported '
          'UserData in TecsXml Response") -- ob beim Host belastet wurde, '
          'weiss das Terminal nicht',
      effect: HpsCodeEffect.hostUncertain,
      reason: HpsCodeReason.hostFault,
      source: HpsCodeSource.documented,
    ),
    HpsCode(
      code: '100028',
      title: 'Tip selection process has failed.',
      meaning:
          'Trinkgeld nicht gewaehlt ("Tip selection process has '
          'failed.") -- nicht innerhalb der Frist; nichts belastet',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.tipNotSelected,
      source: HpsCodeSource.documented,
    ),
    HpsCode(
      code: '100029',
      title: 'Communication with TecsXml timeout',
      meaning:
          'Zeitueberschreitung zum hobex-Host ("Communication with '
          'TecsXml timeout") -- das Terminal storniert den Vorgang SELBST '
          '(auto-reversal); nichts belastet',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.hostTimeoutReversed,
      source: HpsCodeSource.documented,
    ),
    HpsCode(
      code: '100998',
      title: 'Terminal is busy',
      meaning:
          'Terminal beschaeftigt ("Terminal is busy") -- ein anderer '
          'Vorgang laeuft oder das Geraet ist nicht bereit; die Anfrage wurde '
          'nicht angenommen, nichts belastet',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.terminalBusy,
      source: HpsCodeSource.documented,
    ),
    HpsCode(
      code: '100999',
      title: 'Internal Error',
      meaning:
          'interner Fehler des Terminals ("Internal Error") -- '
          'Sammelcode fuer jeden sonst nicht benannten Fehler, an jeder Stelle '
          'des Ablaufs moeglich; ob belastet wurde, ist offen',
      effect: HpsCodeEffect.hostUncertain,
      reason: HpsCodeReason.internalError,
      source: HpsCodeSource.documented,
    ),
  ];

  static final Map<String, HpsCode> _byCode = <String, HpsCode>{
    for (final c in all) c.code: c,
  };

  /// Der Eintrag zu [code], oder `null`, wenn seine Bedeutung nicht
  /// feststeht.
  static HpsCode? lookup(String? code) => code == null ? null : _byCode[code];

  /// Der Grund zu [code]; [HpsCodeReason.unknown] fuer einen Code, der in der
  /// Tabelle fehlt, `null` ohne Code.
  static HpsCodeReason? reasonOf(String? code) {
    if (code == null) return null;
    return lookup(code)?.reason ?? HpsCodeReason.unknown;
  }
}
