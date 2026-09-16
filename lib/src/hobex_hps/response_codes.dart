/// Die vollstaendige Codetabelle des hobex-HPS: jeder Ergebniscode, dessen
/// Bedeutung GEMESSEN oder von hobex DOKUMENTIERT ist, mit seiner Wirkung auf
/// den Ausgang und dem Grund, auf den eine Kasse reagiert.
///
/// **Zwilling:** `src/payments/hobex-hps/transaction-response.ts` im
/// npm-Paket, dort `HPS_CODES`. Das npm-Paket gibt die Tabelle als
/// `fixtures/hobex-hps-codes.json` aus; `test/hobex_hps_codes_vertrag_test.dart`
/// vergleicht sie mit dieser hier. Aenderungen gehoeren in beide.
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
///
/// ## Dritte Quelle: die TECS-Liste (16.09.2026)
///
/// hobex hat nachgereicht, dass das HPS die Codes der TECS-Plattform
/// durchreicht, und deren Liste geschickt -- rund 330 Codes, darunter die
/// ISO-8583-Antworten des Hosts. Eingeordnet sind sie in `tecs_codes.dart`,
/// nach derselben Regel. Neu kommt dazu:
///
/// - [HpsCode.sendReversal]: bei einem Code, der fuer "keine oder keine
///   brauchbare Antwort des Hosts" steht, schickt `HpsPayments.pay` ein Storno
///   nach. Das ist die Vorgabe von hobex zu `9908` ("ein Timeout wie jeder
///   andere. Richtigerweise sollte in dem Fall ein Storno nachgeschickt
///   werden") und gilt ebenso fuer die HPS-Codes, bei denen hobex "No
///   auto-reversal" vermerkt.
/// - Die Schreibweise: TECS fuehrt `0055`, das Terminal sendet `55`.
///   [HpsCodes.normalize] macht beides zu einem Code.
///
/// ## Einen neuen Code aufnehmen
///
/// 1. Eintrag hier (gemessen oder HPS-Liste) oder in `tecs_codes.dart`
///    (TECS-Liste) -- Wirkung nach der Regel oben, Grund aus
///    [HpsCodeReason]; nur wenn am Tresen etwas anderes zu tun ist, einen
///    neuen Grund anlegen.
/// 2. Denselben Eintrag im npm-Zwilling (`HPS_CODES`), dort
///    `npm run fixtures:hobex-hps-codes`, veroeffentlichen, hier
///    `tool/zwillinge.sh ziehen` -- der Vertragstest vergleicht beide.
/// 3. Ein neuer Grund braucht in jeder Kasse eine Uebersetzung
///    (sastre: `DIALOGS.CARD_PAYMENT_REASON.*`).
library;

import 'tecs_codes.dart';

/// Wie ein Ergebniscode den Ausgang eines Vorgangs bestimmt.
enum HpsCodeEffect {
  /// Der Code schreibt den Ausgang fest: `'0'` genehmigt, jeder andere
  /// abgelehnt (bei einer Aufhebung sinngemaess, siehe `HpsPayments.cancel`).
  conclusive,

  /// Gemessen oder dokumentiert, aber ausdruecklich KEINE Aussage ueber den
  /// Vorgang (`9027`, `100011`, die Codes anderer TECS-Produkte) -- ein Grund
  /// weiterzuklaeren.
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

  /// Von hobex dokumentiert: die HPS-Antwortcodeliste (erhalten 11.09.2026)
  /// oder die TECS-Liste (erhalten 16.09.2026, dann ist [HpsCode.tecsTitle]
  /// gesetzt).
  documented,

  /// Beides: gemessen und von hobex bestaetigt (HPS- oder TECS-Liste).
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
  approvedWithCondition(
    'Das Terminal meldet eine Genehmigung mit Vorbehalt (etwa nur über '
    'einen Teilbetrag). Ob und in welcher Höhe belastet wurde, bitte am '
    'Terminalbeleg prüfen — nicht erneut kassieren, bevor es geklärt ist.',
  ),
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
  issuerDeclined(
    'Die Zahlung wurde von der Bank abgelehnt. Es wurde kein Geld bewegt — '
    'bitte eine andere Karte oder Zahlungsart verwenden.',
  ),
  cardBlocked(
    'Die Karte ist gesperrt. Es wurde kein Geld bewegt — bitte eine andere '
    'Karte oder Zahlungsart verwenden.',
  ),
  cardExpired(
    'Die Karte ist abgelaufen. Es wurde kein Geld bewegt — bitte eine andere '
    'Karte oder Zahlungsart verwenden.',
  ),
  insufficientFunds(
    'Das Konto ist nicht gedeckt oder das Kartenlimit ist erreicht. Es wurde '
    'kein Geld bewegt — bitte eine andere Karte oder Zahlungsart verwenden.',
  ),
  wrongPin(
    'Die PIN war falsch. Es wurde kein Geld bewegt — bitte erneut '
    'versuchen.',
  ),
  pinTriesExceeded(
    'Die PIN wurde zu oft falsch eingegeben. Es wurde kein Geld bewegt — '
    'bitte eine andere Karte oder Zahlungsart verwenden.',
  ),
  pinRequired(
    'Die Bank verlangt die PIN. Es wurde kein Geld bewegt — bitte erneut '
    'versuchen, die Karte stecken und die PIN eingeben.',
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
  acquirerSetup(
    'hobex nimmt dieses Terminal oder diesen Händler so nicht an. Es wurde '
    'kein Geld bewegt — bitte hobex kontaktieren.',
  ),
  terminalFault(
    'Das Terminal meldet eine Störung. Es wurde kein Geld bewegt '
    '— bitte das Terminal neu starten und erneut versuchen.',
  ),
  requestRejected(
    'Das Terminal hat die Anfrage abgewiesen. Es wurde kein '
    'Geld bewegt — tritt das wieder auf, bitte den Support kontaktieren.',
  ),
  hostRejected(
    'hobex hat die Zahlung abgewiesen. Es wurde kein Geld bewegt — bitte '
    'erneut versuchen; tritt das wieder auf, hobex kontaktieren.',
  ),
  hostUnavailable(
    'Die Bank oder hobex ist gerade nicht erreichbar. Es wurde kein Geld '
    'bewegt — bitte später erneut versuchen oder eine andere Zahlungsart '
    'verwenden.',
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
  refundRejected(
    'Die Gutschrift wurde abgewiesen (Betrag zu hoch, bereits erstattet oder '
    'zu viele Versuche). Es wurde nichts ausgezahlt.',
  ),
  hostTimeoutReversed(
    'hobex hat nicht rechtzeitig geantwortet, das Terminal '
    'hat den Vorgang selbst storniert. Es wird kein Geld bewegt — bitte '
    'erneut versuchen.',
  ),
  reversedByHost(
    'Die Zahlung wurde wegen einer Störung automatisch storniert. Es wurde '
    'kein Geld bewegt — bitte erneut versuchen.',
  ),
  voidedAfterHostFault(
    'hobex hat nicht sauber geantwortet, die Zahlung wurde deshalb '
    'sicherheitshalber storniert. Es wurde kein Geld bewegt — bitte erneut '
    'versuchen.',
  ),
  hostFault(
    'Die Verbindung zwischen Terminal und hobex ist gestört. Ob die '
    'Karte belastet wurde, weiß das Terminal nicht — bitte nicht erneut '
    'kassieren, bevor es geklärt ist.',
  ),
  hostTimeout(
    'hobex hat nicht rechtzeitig geantwortet. Ob die Karte belastet wurde, '
    'weiß das Terminal nicht — bitte nicht erneut kassieren, bevor es '
    'geklärt ist.',
  ),
  internalError(
    'Das Terminal meldet einen internen Fehler. Ob die Karte '
    'belastet wurde, ist unklar — bitte nicht erneut kassieren, bevor es '
    'geklärt ist.',
  ),
  canceled('Die Zahlung ist aufgehoben.'),
  cancelDenied(
    'Die Zahlung lässt sich nicht mehr aufheben und bleibt belastet — bitte '
    'stattdessen eine Gutschrift ausführen.',
  ),
  originalDeclined(
    'Die ursprüngliche Zahlung war abgelehnt; es gibt nichts aufzuheben.',
  ),
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

  /// Die Gruende, hinter denen ein Code mit [HpsCodeEffect.hostUncertain]
  /// steht: ob (und wie viel) Geld geflossen ist, weiss das Terminal nicht.
  bool get hostUncertain =>
      this == approvedWithCondition ||
      this == hostFault ||
      this == hostTimeout ||
      this == internalError;
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
    this.rejectsRequest = false,
    this.sendReversal = false,
    this.tecsTitle,
  });

  /// Ein Code, der nur aus der TECS-Liste stammt -- [title] ist der Titel
  /// dort. Positional, damit `tecs_codes.dart` eine Zeile je Code bleibt.
  const HpsCode.tecs(
    this.code,
    String this.tecsTitle,
    this.meaning,
    this.effect,
    this.reason, {
    this.rejectsRequest = false,
    this.sendReversal = false,
  })  : title = tecsTitle,
        source = HpsCodeSource.documented;

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

  /// Der Code weist die ANFRAGE selbst ab (TID, Form, Geraetezustand) und
  /// sagt damit nur etwas ueber die Anfrage, die er beantwortet.
  ///
  /// Auf eine Zahlung ist das eine Ablehnung dieser Zahlung. Auf eine
  /// STATUSABFRAGE heisst es dagegen nur, dass diese Abfrage nicht bedient
  /// wurde -- ueber den gesuchten Vorgang sagt es nichts. Gemessen ist das fuer
  /// `100108`: die Statusabfrage mit falscher TID antwortet damit. Siehe
  /// [TransactionResponse.isConclusiveAsStatus].
  final bool rejectsRequest;

  /// Bei diesem Code wird ein Storno nachgeschickt: der Host hat nicht oder
  /// nicht brauchbar geantwortet, und das Terminal nimmt den Vorgang nicht
  /// selbst zurueck. Nur bei [HpsCodeEffect.hostUncertain].
  ///
  /// Vorgabe von hobex (16.09.2026) zu `9908`: "ein Timeout wie jeder andere.
  /// Richtigerweise sollte in dem Fall ein Storno nachgeschickt werden."
  /// Siehe `HpsPayments.pay`.
  final bool sendReversal;

  /// Der Titel in der TECS-Liste (16.09.2026), wenn der Code dort steht --
  /// sonst `null`. Bei gemessenen Codes weicht er vom [title] ab, den das
  /// Terminal sendet (`55`: "PIN falsch" gegen "Incorrect PIN").
  final String? tecsTitle;

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
  /// HPS-Liste von hobex aufsteigend, zuletzt die TECS-Liste
  /// ([tecsCodes]) in ihrer eigenen Reihenfolge.
  static const List<HpsCode> all = <HpsCode>[
    HpsCode(
      code: '0',
      title: 'Authorized',
      meaning: 'genehmigt',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.approved,
      source: HpsCodeSource.measuredAndDocumented,
      tecsTitle: 'Approved Transaction / OK',
    ),
    HpsCode(
      code: '9002',
      title: 'Invalid Transaction',
      meaning:
          'ungueltiger Vorgang -- das Terminal hat den Vorgang selbst '
          'als unzulaessig verworfen, bevor irgendetwas in Bewegung kam',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.invalidTransaction,
      source: HpsCodeSource.measuredAndDocumented,
      rejectsRequest: true,
      tecsTitle: 'Invalid Transaction',
    ),
    HpsCode(
      code: '9011',
      title: 'Transaction Canceled',
      meaning:
          'aufgehoben ("Transaction Canceled") -- der Vorgang unter '
          'dieser Kennung wurde storniert',
      effect: HpsCodeEffect.conclusive,
      reason: HpsCodeReason.canceled,
      source: HpsCodeSource.measuredAndDocumented,
      tecsTitle: 'Transaction cancelled',
    ),
    HpsCode(
      code: '9027',
      title: 'Original Tx not found',
      meaning:
          'keine Aussage -- steht gleichermassen fuer "nie gesehen", '
          '"laeuft gerade", "Karte nicht aufgelegt" und "abgebrochen"',
      effect: HpsCodeEffect.noStatement,
      reason: HpsCodeReason.noStatement,
      source: HpsCodeSource.measuredAndDocumented,
      tecsTitle: 'Original Transaction not found',
    ),
    HpsCode(
      code: '9900',
      title: 'Technical Error Database',
      meaning:
          '"Technical Error Database" -- gemessen im Zusammenhang mit '
          'einer nicht rein numerischen Kennung, NACHDEM die Karte verarbeitet '
          'war; laut TECS ein Datenbankfehler im Backend -- ob belastet wurde, '
          'ist offen',
      effect: HpsCodeEffect.hostUncertain,
      reason: HpsCodeReason.internalError,
      source: HpsCodeSource.measuredAndDocumented,
      tecsTitle: 'Technical Error: Database (General)',
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
      source: HpsCodeSource.measuredAndDocumented,
      tecsTitle: 'Invalid Amount',
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
      rejectsRequest: true,
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
      rejectsRequest: true,
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
      source: HpsCodeSource.measuredAndDocumented,
      tecsTitle: 'Incorrect PIN',
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
      rejectsRequest: true,
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
      sendReversal: true,
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
      sendReversal: true,
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
      rejectsRequest: true,
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
      rejectsRequest: true,
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
      rejectsRequest: true,
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
      rejectsRequest: true,
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
      rejectsRequest: true,
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
      sendReversal: true,
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
      sendReversal: true,
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
      sendReversal: true,
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
      sendReversal: true,
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
      rejectsRequest: true,
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
    ...tecsCodes,
  ];

  static final Map<String, HpsCode> _byCode = <String, HpsCode>{
    for (final c in all) c.code: c,
  };

  /// Eintraege, die eine ganze Familie abdecken (`81xx`: Feld xx der Anfrage
  /// nicht lesbar), nach ihrem Praefix.
  static final Map<String, HpsCode> _byPrefix = <String, HpsCode>{
    for (final c in all)
      if (c.code.endsWith(_platzhalter))
        c.code.substring(0, c.code.length - _platzhalter.length): c,
  };

  static const String _platzhalter = 'xx';
  static final RegExp _ziffern = RegExp(r'^\d+$');

  /// Die Schreibweise, unter der [code] in der Tabelle steht: ein rein
  /// numerischer Code ohne fuehrende Nullen (`0055` -> `55`, `0000` -> `0`),
  /// jeder andere unveraendert.
  ///
  /// TECS fuehrt die Host-Antworten vierstellig, das Terminal sendet sie
  /// gemessen ohne Nullen (`55`, `0`). Ohne diese Angleichung waere ein
  /// `0000` kein `0` -- und damit ueber [HpsCode.conclusive] eine ABLEHNUNG
  /// einer genehmigten Zahlung. `TransactionResponse.fromJson` gleicht
  /// deshalb schon beim Einlesen an.
  static String normalize(String code) {
    final c = code.trim();
    if (!_ziffern.hasMatch(c)) return c;
    final ohneNullen = c.replaceFirst(RegExp('^0+'), '');
    return ohneNullen.isEmpty ? '0' : ohneNullen;
  }

  /// Der Eintrag zu [code], oder `null`, wenn seine Bedeutung nicht
  /// feststeht. Findet beide Schreibweisen ([normalize]) und die Familien
  /// mit Platzhalter (`8105` -> `81xx`).
  static HpsCode? lookup(String? code) {
    if (code == null) return null;
    final c = normalize(code);
    final genau = _byCode[c];
    if (genau != null) return genau;
    if (c.length == 4 && _ziffern.hasMatch(c)) {
      return _byPrefix[c.substring(0, 2)];
    }
    return null;
  }

  /// Der Grund zu [code]; [HpsCodeReason.unknown] fuer einen Code, der in der
  /// Tabelle fehlt, `null` ohne Code.
  static HpsCodeReason? reasonOf(String? code) {
    if (code == null) return null;
    return lookup(code)?.reason ?? HpsCodeReason.unknown;
  }
}
