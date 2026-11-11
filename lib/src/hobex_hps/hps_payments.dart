import 'dart:async';

import '../payments/card_payment_outcome.dart';
import 'exceptions.dart';
import 'hps_client.dart';
import 'hps_result.dart';
import 'observer.dart';
import 'response_codes.dart';
import 'transaction_response.dart';

/// Kartenzahlung, deren Ausgang immer bekannt ist.
///
/// Der Unterschied zu [HpsClient.payment]: die Transaktionskennung steht VOR
/// dem ersten Netzweg fest, und ein abgebrochener Vorgang wird ueber
/// [HpsClient.transactionStatus] geklaert statt als Fehlschlag gemeldet.
///
/// Regel, von der nicht abgewichen wird: [CardPaymentOutcome.declined] entsteht
/// ausschliesslich aus einer POSITIVEN Aussage -- einem GEMESSENEN
/// Ergebniscode des Terminals ungleich `'0'` (siehe
/// [TransactionResponse.isConclusive]) auf die Zahlung oder in der
/// Statusabfrage, der Zwei-`9027`-Regel nach einer Antwort MIT Code
/// ([_ausGeschlossenerAntwort]), einem `9011` (aufgehoben) in der
/// Statusabfrage nach einem nachgeschickten Storno oder dem gemessenen HTTP
/// 409 auf die erzeugende Anfrage. Ein Transportfehler, ein Zeitablauf, eine
/// Wissensluecke, ein quittierter [HpsClient.abort] und ein quittiertes Storno
/// fuehren NIE dorthin: keines davon ist eine Aussage darueber, dass nichts
/// belastet wurde. Ein Transportfehler trennt "nicht
/// angekommen" nicht von "angekommen, Antwort verloren" -- genau diese
/// Verwechslung hat am 24.08.2026 eine echte Belastung als unbelastet
/// ausgewiesen und den Kunden ein zweites Mal belastet.
///
/// Am 27.08.2026 zeigte eine Messung, dass "gemessen" woertlich zu nehmen
/// ist: [TransactionResponse.isConclusive] galt bis dahin fuer JEDEN Code
/// ausser `null` und [TransactionResponse.noStatementCode] -- eine
/// Negativliste, die sich als Positivliste ausgab. Ein neu aufgetretener
/// Code ([TransactionResponse.technicalErrorCode], `9900`) war darueber
/// schluessig und wurde `declined`, obwohl unter dem betroffenen Vorgang
/// Geld geflossen sein kann -- derselbe Fehler wie am 24.08.2026, nur an
/// anderer Stelle entstanden. [TransactionResponse.isConclusive] ist seither
/// eine echte Positivliste: schluessig ist nur ein Code, dessen Bedeutung
/// GEMESSEN und benannt ist. Jeder andere -- egal wie sehr er wie ein
/// Fehlercode aussieht -- ist eine Wissensluecke.
///
/// ## Der Klaerweg und was ihn traegt
///
/// Gemessen an einem hobex-HPS (TID 3600335, HPS 1.10.0, Firmware 7.3.6,
/// 26.08.2026; die letzte Zeile HPS 1.14.4, 10.11.2026):
///
/// | Lage | Zahlung | `transactionStatus` | `abort` |
/// |---|---|---|---|
/// | genehmigt | `0` | `0`, bleibt erhalten | `100010`, scheitert |
/// | Kartenfluss wartet auf die Karte | offen | `9027` | `0`, Zahlung endet `100002` |
/// | Karte nicht aufgelegt | `100003` | `9027` | -- |
/// | abgebrochen | `100002` | `9027` | -- |
/// | nie gesehen | -- | `9027` | -- |
/// | Abbruch 4 s nach dem Start, Zahlung laeuft (kontaktlos; ob die Karte schon gelesen war, ist ungemessen) | offen, endet `0` | danach `0` | `0`, greift NICHT |
///
/// Die Statusabfrage unterscheidet also NICHT zwischen "laeuft gerade", "nie
/// angekommen" und "abgebrochen": alle drei antworten `9027`. Wer diesen Code
/// ueber `!= '0'` als Ablehnung liest, meldet fuer einen laufenden Vorgang
/// "gefahrlos wiederholbar" -- der Kunde legt die Karte auf, und die
/// Wiederholung belastet ein zweites Mal.
///
/// Der Klaerweg, wenn die Antwort ausbleibt oder nichts sagt:
///
/// 1. [HpsClient.abort] einmalig versuchen. Die Absicht: ein Kartenfluss, der
///    noch auf die Karte wartet, soll enden, damit nach der Klaerung keine
///    spaet aufgelegte Karte mehr belastet wird. Eine Garantie ist das nicht
///    -- ob der Abbruch greift, sagt seine Quittung nicht.
/// 2. Die Antwort auf den Abbruch entscheidet NICHTS, auch `'0'` nicht (siehe
///    "Ein quittierter Abbruch ist keine Aussage"). Sie steht nur im
///    Nachweis.
/// 3. Dann die Statusabfrage pollen: `'0'` -> [CardPaymentOutcome.approved]
///    mit der Antwort des Status als Beleg; ein schluessiger Code (etwa
///    `9011` aufgehoben) -> [CardPaymentOutcome.declined]; `9027` ist kein
///    Ergebnis, sondern ein Grund weiterzumachen -- ausser nach einer Antwort
///    MIT Code auf die Zahlung, siehe [_ausGeschlossenerAntwort].
/// 4. Budget erschoepft -> [CardPaymentOutcome.unresolved].
///
/// Die Kennung ist in JEDEM Ergebnis gesetzt, auch bei
/// [CardPaymentOutcome.unresolved]: ohne sie sind Statusabfrage und Storno
/// unerreichbar.
///
/// ## Ein quittierter Abbruch ist keine Aussage (10.11.2026)
///
/// Bis 11.26.0 hiess `'0'` auf den Abbruch "der Vorgang war noch abbrechbar,
/// es ist nichts belastet" -- geschlossen aus der Messung vom 26.08.2026, bei
/// der der Abbruch WAEHREND des Wartens auf die Karte kam und die Zahlung
/// danach mit `100002` "Aborted" endete. Am 10.11.2026 widerlegt (TID
/// 3600335, HPS 1.14.4, Firmware 7.3.6, Testsystem): Abbruch vier Sekunden
/// nach dem Start einer Zahlung ueber 0,01 EUR, nach 0,18 s quittiert mit
/// `'0'` "Authorized" -- und die laufende Zahlung endete trotzdem GENEHMIGT
/// (kontaktlos), die Statusabfrage danach ebenso. `'0'`
/// heisst also nur, dass das Terminal die Abbruch-Anfrage angenommen hat,
/// nicht, dass die Zahlung abgebrochen ist. Als
/// [CardPaymentOutcome.declined] gelesen, haette die Kasse "nichts belastet,
/// noch einmal versuchen" gemeldet: der Weg zur Doppelbelastung vom
/// 24.08.2026.
///
/// Auch ein `9027` kurz nach einem angenommenen Abbruch ist keine Aussage:
/// solange eine Zahlung laeuft, antwortet die Statusabfrage `9027` (Tabelle
/// oben), und dass sie nach einem angenommenen Abbruch weiterlaufen kann,
/// zeigt die Messung. Wie lange danach noch eine Genehmigung kommen kann, ist
/// ungemessen. Ohne Antwort mit Code auf die Zahlung endet ein Abbruch mit
/// anhaltendem `9027` deshalb bei [CardPaymentOutcome.unresolved].
///
/// Bricht die KASSE eine laufende Zahlung ab (eigener [HpsClient.abort],
/// waehrend [pay] noch auf die Antwort wartet), entscheidet die Antwort auf
/// die Zahlung selbst -- genehmigt, wenn sie genehmigt meldet, abgelehnt mit
/// `100002`. [pay] liest die Quittung dieses fremden Abbruchs nicht.
///
/// [refund] bekommt exakt dieselbe Klaerung wie [pay], Abbruch eingeschlossen.
/// Die Kennung ist bei [refund] die des NEUEN Vorgangs (der Gutschrift
/// selbst), eine Statusabfrage darauf liefert also genau deren Ausgang, und
/// `POST /api/transaction/abort/{tid}/{tx}` kennt keinen Transaktionstyp --
/// er adressiert den laufenden Vorgang unter dieser Kennung. Am 26.08.2026
/// gemessen: `abort` auf eine LAUFENDE Gutschrift antwortet ebenfalls mit
/// `responseCode '0'`, und die Gutschrift endete daraufhin mit `100002`
/// "Aborted". Wie bei der Zahlung beweist die Quittung allein nichts: eine
/// Gutschrift, die nach dem angenommenen Abbruch doch durchgeht, als
/// [CardPaymentOutcome.declined] zu melden, laedt zu einer zweiten Gutschrift
/// ein. Bleibt die Statusabfrage danach bei `9027`, endet die Klaerung bei
/// [CardPaymentOutcome.unresolved].
///
/// [cancel] ist die Ausnahme, und zwar in beiden Richtungen -- siehe
/// [_resolveCancel]: die uebergebene Kennung ist die der URSPRUENGLICHEN
/// Zahlung. Ein Abbruch darauf waere sinnlos (der Vorgang ist laengst
/// abgeschlossen, gemessen: `100010`), und der `responseCode` dieser Kennung
/// bedeutet dort etwas anderes als bei [pay].
///
/// ## Stoerung beim Host: die Klaerung darf nichts schliessen (11.09.2026)
///
/// Die Antwortcodeliste von hobex benennt Codes, bei denen der Host beteiligt
/// war und das Terminal NICHT selbst storniert ([HpsCodeEffect.hostUncertain],
/// etwa `100007`). Fuer sie gilt zweierlei:
///
/// 1. Die Zwei-`9027`-Regel ([_ausGeschlossenerAntwort]) greift nicht. Sie
///    schliesst aus "das Terminal hat geantwortet und nichts gespeichert" auf
///    "nichts belastet" -- das stimmt fuer einen Vorgang, der am Terminal
///    endete, aber nicht fuer einen, dessen Ausgang beim Host liegt. Dasselbe
///    gilt sinngemaess fuer [cancel]: ein unveraendertes `'0'` auf die
///    Originalzahlung beweist dann nicht, dass die Aufhebung beim Host nicht
///    ankam.
/// 2. Die Klaerung wartet trotzdem nicht das ganze Budget ab. Sagt die
///    Statusabfrage zweimal in Folge nichts Neues (`9027` oder erneut ein
///    solcher Code), endet sie sofort als [CardPaymentOutcome.unresolved] --
///    das Terminal wird es auch in 90 Sekunden nicht wissen. Meldet sie
///    dagegen `'0'`, ist die Zahlung genehmigt, ganz normal.
///
/// ## Storno nach ausbleibender Host-Antwort (16.09.2026)
///
/// Fuer einen Teil dieser Codes -- der Host hat nicht oder nicht brauchbar
/// geantwortet, etwa `9908` "Time Out received from acquirer" -- gibt hobex
/// vor, ein Storno nachzuschicken ([HpsCode.sendReversal]). [pay] tut das
/// genau einmal, mit der Kennung der Zahlung und dem Betrag, den das Terminal
/// belastet: Betrag UND Trinkgeld (wie die Rueckbuchung der Web-Kasse).
/// Danach laeuft immer die Statusabfrage:
///
/// - `9011` (aufgehoben) -> [CardPaymentOutcome.declined], die einzige
///   Stelle, an der nach einem Storno ein Ausgang feststeht: mit
///   [HpsCodeReason.voidedAfterHostFault], wenn das Storno gewirkt haben
///   kann, sonst mit [HpsCodeReason.canceled] -- dann hat etwas anderes die
///   Zahlung aufgehoben.
/// - Ist das Storno nicht sicher abgewiesen ([_StornoAusgang]: quittiert mit
///   `'0'`, abgerissen, ohne Code, mit einem unbekannten oder einem
///   Storniert-Code wie `8009`), ist auch `'0'` in der Statusabfrage keine
///   Aussage: das Storno kann noch unterwegs sein, oder es hat nicht
///   gegriffen. Sie zaehlt dann wie `9027` als "nichts Neues", und nach zwei
///   solchen Antworten endet die Klaerung als
///   [CardPaymentOutcome.unresolved].
/// - Nur wenn das Storno nach einer ausdruecklichen Positivliste NICHT
///   ausgefuehrt wurde (nicht angenommen oder abgewiesen -- siehe
///   [_stornoAbgewiesen]), ist `'0'` in der Statusabfrage
///   [CardPaymentOutcome.approved]. Gemessen ist davon nur `9002` auf eine
///   unbekannte Kennung (27.08.2026); die uebrigen Eintraege stuetzen sich
///   auf die Codeliste von hobex und TECS.
///
/// Die Quittung `'0'` auf das Storno allein beweist nichts -- dieselbe Lehre
/// wie beim Abbruch (10.11.2026). Am Geraet ungemessen sind das Storno nach
/// einer Host-Stoerung und der Stornobetrag mit Trinkgeld; gemessen ist nur,
/// dass ein Void auf eine bestehende Kennung mit `'0'` antwortet und auf eine
/// unbekannte mit `9002` (27.08.2026).
///
/// [refund] schickt KEIN Storno nach: TECS erlaubt die Aufhebung einer
/// Gutschrift nicht (`9031`). [cancel] ebensowenig -- dort ist der Vorgang
/// selbst schon das Storno.
class HpsPayments {
  HpsPayments(
    this._client, {
    this.resolveBudget = const Duration(seconds: 90),
    this.maxBackoff = const Duration(seconds: 10),
    this.maxTransportFailures = 3,
    Future<void> Function(Duration)? sleep,
    Stopwatch Function()? clock,
    this._observer,
  })  : _sleep = sleep ?? _realSleep,
        _clock = clock ?? Stopwatch.new;

  final HpsClient _client;

  /// Wie lange insgesamt geklaert wird, bevor der Ausgang offen bleibt.
  ///
  /// Die Zusage gilt fuer die Klaerung als Ganzes: sowohl jede Abfrage als
  /// auch jede Pause dazwischen wird mit der Restlaufzeit gedeckelt. Ohne das
  /// haette eine Pause die Zusage um bis zu [maxBackoff] ueberzogen und eine
  /// einzelne Abfrage haette bis
  /// [HpsClient.timeout] laufen duerfen (Vorgabe drei Minuten) und drei
  /// Zeitueberschreitungen in Folge haetten aus 90 Sekunden Budget neun
  /// Minuten gemacht. Die Zahlung selbst laeuft davor und unterliegt weiterhin
  /// [HpsClient.timeout] -- sie muss auf den Karteninhaber warten duerfen.
  final Duration resolveBudget;

  /// Obergrenze fuer den Abstand zwischen zwei Statusabfragen.
  final Duration maxBackoff;

  /// Nach so vielen Statusabfragen in Folge, die am Transport scheitern, wird
  /// abgebrochen -- ein offensichtlich unerreichbares Terminal soll den
  /// Mitarbeiter nicht das ganze Budget lang warten lassen. Das Ergebnis ist
  /// dann [CardPaymentOutcome.unresolved], niemals
  /// [CardPaymentOutcome.declined].
  final int maxTransportFailures;

  final Future<void> Function(Duration) _sleep;

  /// Quelle der Uhr fuer das Budget. Wie [_sleep] eine Naht fuer Tests: eine
  /// Uhr, die nur durch die Pausen vorrueckt, macht das Ablaufen des Budgets
  /// nachpruefbar, statt es der Wanduhr zu ueberlassen.
  final Stopwatch Function() _clock;

  final HpsObserver? _observer;

  static Future<void> _realSleep(Duration d) => Future<void>.delayed(d);

  /// Kartenzahlung mit geklaertem Ausgang.
  ///
  /// [amount] und [tip] sind in Hauptwaehrungseinheiten (25 = 25,00 Euro).
  /// [transactionId] kann vorgegeben werden, etwa um einen abgebrochenen
  /// Vorgang gezielt weiterzuverfolgen; sonst wird eine erzeugt und im
  /// Ergebnis zurueckgegeben.
  Future<HpsResult> pay({
    required num amount,
    num? tip,
    String? reference,
    String? transactionId,
  }) async {
    final String id = transactionId ?? HpsClient.newTransactionId();
    final steps = <String>[];
    // VOR dem ersten Netzweg: ein Betrag, der sich nicht in ganzen Cent
    // darstellen laesst, ist ein Aufruffehler und darf nie erst nach der
    // Zahlung auffallen -- dann bekaeme der Aufrufer kein Ergebnis.
    final stornoBetrag = _stornoBetrag(amount, tip);

    // Das try liegt bewusst ENG um den Netzweg: was danach kommt, ist unser
    // eigenes Auswerten und soll nicht stillschweigend als "Terminal hat nicht
    // geantwortet" durchgehen.
    TransactionResponse? res;
    try {
      res = await _client.payment(
        amount: amount,
        tip: tip,
        reference: reference,
        transactionId: id,
      );
    } on ArgumentError {
      // Einzige Ausnahme, die durchgereicht wird: die Laengenpruefung der
      // Kennung schlaegt zu, BEVOR etwas gesendet wurde. Hier ist nachweislich
      // nichts passiert, und ein Aufruffehler soll sichtbar bleiben statt als
      // offener Ausgang zu enden.
      rethrow;
    } catch (e) {
      // Bewusst ALLES andere, nicht nur [HpsException]. Eine 200-Antwort mit
      // unlesbarem Rumpf wirft eine FormatException, ein unerwarteter Feldtyp
      // einen TypeError -- beide erst, nachdem der Zahlungs-Request draussen
      // war und beantwortet wurde. Fiele so etwas an pay() vorbei, bekaeme der
      // Aufrufer kein Ergebnis und damit keine Kennung: genau der Mechanismus
      // des Vorfalls vom 24.08.2026, nur mit anderem Ausloeser.
      final busy = _fromTerminalBusy(e, id, steps);
      if (busy != null) return busy;
      steps.add('Zahlung abgebrochen: $e');
      _noteUnexpected(e, id);
    }

    if (res != null) {
      final settled = _fromResponse(res, id, steps);
      if (settled != null) return settled;
      steps.add(_offeneAntwort(res));
    }

    return _resolve(id, steps, antwort: res, stornoBetrag: stornoBetrag);
  }

  /// Was ein nachgeschicktes Storno aufheben muss: das, was das Terminal
  /// belastet hat, Betrag UND Trinkgeld, in Hauptwaehrungseinheiten.
  ///
  /// Ueber ganze Cent addiert -- eine Gleitkomma-Summe wie `0.1 + 0.2` ginge
  /// sonst als `0.30000000000000004` ans Terminal. Ohne Trinkgeld bleibt
  /// [amount] unveraendert, wie es [pay] bekam. Eine Summe in ganzen Euro geht
  /// als ganze Zahl hinaus (`28`, nicht `28.0`).
  ///
  /// Wirft [ArgumentError], wenn [amount] oder [tip] nicht endlich ist oder
  /// sich nicht exakt in ganzen Cent darstellen laesst (`round()` liefert fuer
  /// NaN/Unendlich einen Fehler und deckelt grosse Werte still). [pay] ruft
  /// das vor dem ersten Netzweg auf.
  static num _stornoBetrag(num amount, num? tip) {
    final betragCent = _cent(amount, 'amount');
    if (tip == null || tip == 0) return amount;
    final cent = betragCent + _cent(tip, 'tip');
    return cent % _centJeEinheit == 0
        ? cent ~/ _centJeEinheit
        : cent / _centJeEinheit;
  }

  /// [betrag] in ganzen Cent, oder [ArgumentError] -- siehe [_stornoBetrag].
  static int _cent(num betrag, String name) {
    final cent = betrag * _centJeEinheit;
    if (!cent.isFinite || cent.abs() > _maxExakteCent) {
      throw ArgumentError.value(
          betrag, name, 'kein endlicher Betrag in ganzen Cent');
    }
    return cent.round();
  }

  /// Cent je Hauptwaehrungseinheit (Euro).
  static const int _centJeEinheit = 100;

  /// Groesste ganze Zahl, die ein `double` exakt fasst (2^53 - 1). Darueber
  /// waeren Cent-Betraege nicht mehr exakt.
  static const int _maxExakteCent = 9007199254740991;

  /// Gutschrift mit geklaertem Ausgang.
  ///
  /// [amount] ist in Hauptwaehrungseinheiten. [transactionId] ist -- wie bei
  /// [pay] -- die Kennung des NEUEN Vorgangs (der Gutschrift selbst), nicht
  /// die der Zahlung, auf die sie sich ueber [originalTransactionId]
  /// referenzieren kann. Deshalb passt dieselbe Klaerung wie bei [pay]
  /// unveraendert: eine Statusabfrage auf [transactionId] liefert genau den
  /// Ausgang DIESER Gutschrift.
  Future<HpsResult> refund({
    required num amount,
    String? originalTransactionId,
    String? transactionId,
  }) async {
    final String id = transactionId ?? HpsClient.newTransactionId();
    final steps = <String>[];

    // Das try liegt bewusst ENG um den Netzweg -- siehe Begruendung in [pay].
    TransactionResponse? res;
    try {
      res = await _client.refund(
        amount: amount,
        originalTransactionId: originalTransactionId,
        transactionId: id,
      );
    } on ArgumentError {
      // Einzige Ausnahme, die durchgereicht wird: die Laengenpruefung der
      // Kennung schlaegt zu, BEVOR etwas gesendet wurde.
      rethrow;
    } catch (e) {
      final busy = _fromTerminalBusy(e, id, steps);
      if (busy != null) return busy;
      steps.add('Gutschrift abgebrochen: $e');
      _noteUnexpected(e, id);
    }

    if (res != null) {
      final settled = _fromResponse(res, id, steps);
      if (settled != null) return settled;
      steps.add(_offeneAntwort(res));
    }

    return _resolve(id, steps, antwort: res);
  }

  /// Aufhebung (Storno/Void) einer bestehenden Zahlung mit geklaertem
  /// Ausgang.
  ///
  /// [transactionId] ist die vom TERMINAL vergebene Kennung der
  /// URSPRUENGLICHEN Zahlung -- nicht die eines neuen Vorgangs. Der direkte
  /// Antwortweg wird trotzdem ueber [_fromResponse] eingeordnet: die
  /// Direktantwort auf einen Aufhebungs-Request traegt einen eigenen
  /// `responseCode` fuer die Aufhebung selbst (siehe [TransactionResponse]-Doku,
  /// die "void" ausdruecklich als Transaktionstyp mit eigener Antwort fuehrt).
  /// Erst wenn dieser direkte Weg abbricht und nachgefragt werden muss, aendert
  /// sich die Frage: siehe [_resolveCancel].
  Future<HpsResult> cancel({
    required String transactionId,
    required num amount,
  }) async {
    final steps = <String>[];

    TransactionResponse? res;
    try {
      res = await _client.cancel(transactionId: transactionId, amount: amount);
    } on ArgumentError {
      rethrow;
    } catch (e) {
      final busy = _fromTerminalBusy(e, transactionId, steps);
      if (busy != null) return busy;
      steps.add('Aufhebung abgebrochen: $e');
      _noteUnexpected(e, transactionId);
    }

    if (res != null) {
      final settled = _fromCancelResponse(res, transactionId, steps);
      if (settled != null) return settled;
      // Kein Sammel-Eintrag fuer 9011: [_fromCancelResponse] hat dafuer
      // bereits den zutreffenden Eintrag gesetzt.
      if (!res.isCanceled) steps.add(_offeneAntwort(res));
    }

    return _resolveCancel(transactionId, steps, antwort: res);
  }

  /// Fragt den Ausgang einer Zahlung SPAETER noch einmal ab -- etwa wenn der
  /// Kassier eine unklare Karte klaert. Liest nur: kein Abbruch, kein Storno,
  /// kein neuer Vorgang. Das Ergebnis hat dieselbe Form wie das von [pay].
  ///
  /// [transactionId] ist die Kennung der Zahlung aus [pay] -- keine
  /// Gutschrift, keine Aufhebung. [previous] ist, was ueber die bisherige
  /// Klaerung dieser Zahlung feststeht ([HpsClarifyPrevious]).
  ///
  /// Entschieden wird nur, was nach [previous] feststeht ([_nachfrageRegel]):
  ///
  /// | bisher | `'0'` | `9011` | andere Ablehnung |
  /// |---|---|---|---|
  /// | [HpsClarifyPrevious.beforeResolve], oder offen ohne Stoerung beim Host | approved | declined | declined |
  /// | Stoerung beim Host, Storno sicher versucht ([HpsCodeReason.hostFault], [HpsCodeReason.hostTimeout]) | offen | declined | offen |
  /// | andere Stoerung beim Host | offen | offen | offen |
  /// | [HpsClarifyPrevious.unknown], auch das Ergebnis einer frueheren Nachfrage ([HpsResult.clarified]) | offen | offen | offen |
  ///
  /// Nach einer Stoerung beim Host kann die Klaerung von [pay] ein Storno
  /// nachgeschickt haben -- auch wenn der erste Code keines verlangte, denn
  /// ein spaeterer Status kann es noch ausloesen. Ein `'0'` beweist dann
  /// nichts (siehe Klassendoku, "Storno nach ausbleibender Host-Antwort").
  /// `9011` (aufgehoben) heisst nur dann sicher "nichts belastet", wenn ein
  /// Storno sicher versucht wurde -- wie in der Klaerung von [pay]. `9027`
  /// bleibt hier immer ohne Aussage: die Zwei-`9027`-Regel braucht die
  /// Antwort auf die Zahlung selbst. Meldet der Status selbst eine Stoerung
  /// beim Host, entscheidet danach nur noch `'0'`.
  ///
  /// Sagt der Status zweimal in Folge nichts, endet die Nachfrage sofort als
  /// [CardPaymentOutcome.unresolved] -- die Zahlung ist laengst beendet, das
  /// Terminal wird es auch spaeter nicht wissen. Budget: ein Sechstel von
  /// [resolveBudget] ([_clarifyBudget], bei der Vorgabe 15 s).
  ///
  /// Jedes Ergebnis traegt [HpsResult.clarified]: es ist keine Vorgeschichte
  /// fuer eine weitere Nachfrage, sein Grund stammt aus der Nachfrage, nicht
  /// aus der Zahlung.
  ///
  /// Wirft wie [pay] nur [ArgumentError]: die Kennung ist keine gueltige
  /// HPS-Kennung, geprueft BEVOR etwas hinausgeht. Alles andere endet in
  /// einem Ergebnis mit Kennung.
  Future<HpsResult> clarifyPayment({
    required String transactionId,
    required HpsClarifyPrevious previous,
  }) async {
    final id = transactionId;
    final regel = _nachfrageRegel(previous);
    final vorherGrund = switch (previous) {
      HpsClarifyUnresolved(:final reason) => reason,
      HpsClarifyBeforeResolve() || HpsClarifyUnknown() => null,
    };
    final vorherGestoert = vorherGrund?.hostUncertain ?? false;
    final steps = <String>[_nachfrageAnfang(previous, regel)];
    _emit(HpsEventKind.resolving, steps.first, id);

    final clock = _clock()..start();
    final budget = _clarifyBudget;
    var wait = Duration.zero;
    var transportFailures = 0;
    var ohneAussage = 0;
    // Die erste Stoerung beim Host, die der Status in DIESER Nachfrage meldet.
    TransactionResponse? stoerung;
    TransactionResponse? letzteAntwort;

    // Ein schluessiger Code, der hier nicht entscheiden durfte (`'0'`,
    // `9011`, eine Ablehnung), erklaert den offenen Ausgang nicht -- sonst
    // stuende etwa "genehmigt" als Grund an einem offenen Ergebnis
    // (Geraetetest 11.11.2026, Vorgeschichte unbekannt).
    HpsResult offen() {
      final antwort = letzteAntwort;
      final erklaerend =
          antwort != null && !antwort.isConclusiveAsStatus ? antwort : null;
      return _alsNachfrage(_open(
        id,
        steps,
        letzteAntwort,
        vorherGrund ?? _offenerGrund(stoerung, erklaerend),
      ));
    }

    /// Warum eine Antwort, die sonst entschiede, hier nichts sagt.
    String vorbehalt() {
      if (previous is HpsClarifyUnknown) {
        return 'der bisherige Klaerweg ist nicht bekannt, ein Storno kann '
            'nachgeschickt sein';
      }
      if (vorherGestoert) {
        return 'nach der Stoerung beim hobex-Host (${vorherGrund!.name}) kann '
            'ein Storno nachgeschickt sein';
      }
      return 'das Terminal meldet eine Stoerung beim hobex-Host';
    }

    while (clock.elapsed < budget) {
      if (wait > Duration.zero) {
        final left = budget - clock.elapsed;
        await _sleep(wait < left ? wait : left);
        if (clock.elapsed >= budget) break;
      }

      TransactionResponse status;
      try {
        status = await _withinBudget(
          clock,
          () => _client.transactionStatus(transactionId: id),
          budget: budget,
        );
        transportFailures = 0;
        letzteAntwort = status;
      } on ArgumentError {
        // Wie bei [pay]: die Laengenpruefung der Kennung schlaegt zu, BEVOR
        // etwas gesendet wurde -- ein Aufruffehler, kein offener Ausgang.
        rethrow;
      } catch (e) {
        transportFailures++;
        steps.add('Statusabfrage gescheitert ($transportFailures): $e');
        _noteUnexpected(e, id);
        if (transportFailures >= maxTransportFailures) {
          steps.add('Terminal antwortet nicht -- Ausgang bleibt offen');
          return offen();
        }
        wait = _nextWait(wait);
        continue;
      }

      if (status.isHostUncertain) stoerung ??= status;
      // Wie in [_resolve]: nach einer Stoerung beim Host -- vorher oder jetzt
      // gemeldet -- entscheidet hoechstens noch die Genehmigung.
      final gestoert = vorherGestoert || stoerung != null;

      if (status.isApproved) {
        if (regel.genehmigt) {
          final settled = _fromResponse(status, id, steps);
          if (settled != null) return _alsNachfrage(settled);
        }
        steps.add('Status: genehmigt (${status.responseCode}) -- '
            '${vorbehalt()}, keine Aussage');
      } else if (status.isCanceled &&
          regel.aufgehoben &&
          (vorherGestoert || stoerung == null)) {
        steps.add('Status: Zahlung aufgehoben '
            '(${TransactionResponse.transactionCanceledCode}) -- es ist '
            'nichts belastet');
        _emit(HpsEventKind.resolved, steps.last, id);
        return HpsResult(
          outcome: CardPaymentOutcome.declined,
          transactionId: id,
          response: status,
          reason: HpsCodeReason.canceled,
          steps: List<String>.unmodifiable(steps),
          clarified: true,
        );
      } else if (regel.abgelehnt && !gestoert && status.isConclusiveAsStatus) {
        final settled = _fromResponse(status, id, steps);
        if (settled != null) return _alsNachfrage(settled);
      } else if (status.isConclusiveAsStatus) {
        final info = status.codeInfo!;
        final was = status.isCanceled ? 'aufgehoben' : 'abgelehnt';
        steps.add('Status: $was (${info.code} "${info.title}") -- '
            '${vorbehalt()}, keine Aussage');
      } else {
        steps.add(
            _statusOhneErgebnis(status) ?? 'Status: noch kein Ergebniscode');
      }

      ohneAussage++;
      if (ohneAussage >= 2) {
        steps.add('Statusabfrage zweimal ohne Aussage -- das Terminal kann es '
            'nicht sagen, Ausgang bleibt offen');
        return offen();
      }
      wait = _nextWait(wait);
    }

    steps.add('Ausgang bleibt offen');
    return offen();
  }

  /// Dasselbe Ergebnis mit der Marke [HpsResult.clarified]: es stammt aus
  /// einer Nachfrage und taugt nicht als deren Vorgeschichte.
  static HpsResult _alsNachfrage(HpsResult r) => HpsResult(
        outcome: r.outcome,
        transactionId: r.transactionId,
        response: r.response,
        lastResponse: r.lastResponse,
        reason: r.reason,
        steps: r.steps,
        clarified: true,
      );

  /// Teiler fuer das Budget von [clarifyPayment].
  static const int _clarifyBudgetDivisor = 6;

  /// Wie lange eine spaete Nachfrage hoechstens laeuft: ein Sechstel des
  /// [resolveBudget], bei der Vorgabe 15 s. Die Zahlung ist laengst beendet;
  /// was das Terminal nicht in zwei Abfragen sagt, sagt es auch spaeter nicht.
  Duration get _clarifyBudget => resolveBudget ~/ _clarifyBudgetDivisor;

  /// `true`, wenn die Klaerung von [pay] bei diesem Grund sicher ein Storno
  /// versucht hat: der Grund kommt von der ersten Stoerung beim Host
  /// ([_offenerGrund]), und JEDER Code mit diesem Grund verlangt ein Storno
  /// ([HpsCode.sendReversal]). Aus der Tabelle gerechnet, damit ein neuer
  /// Code ohne Storno die Regel nicht still bricht.
  static bool _stornoSicherVersucht(HpsCodeReason reason) {
    final codes = HpsCodes.all.where((c) => c.reason == reason);
    return codes.isNotEmpty && codes.every((c) => c.sendReversal);
  }

  /// Siehe Tabelle an [clarifyPayment].
  static _NachfrageRegel _nachfrageRegel(HpsClarifyPrevious previous) =>
      switch (previous) {
        HpsClarifyUnknown() => _NachfrageRegel.nichts,
        HpsClarifyBeforeResolve() => _NachfrageRegel.alles,
        HpsClarifyUnresolved(:final reason)
            when reason != null && reason.hostUncertain =>
          _NachfrageRegel(
            genehmigt: false,
            aufgehoben: _stornoSicherVersucht(reason),
            abgelehnt: false,
          ),
        HpsClarifyUnresolved() => _NachfrageRegel.alles,
      };

  /// Erster Eintrag im Nachweis einer spaeten Nachfrage: was sie entscheiden
  /// darf.
  static String _nachfrageAnfang(
    HpsClarifyPrevious previous,
    _NachfrageRegel regel,
  ) {
    const anfang = 'Spaete Nachfrage beim Terminal -- nur lesend, ohne '
        'Abbruch und ohne Storno';
    switch (previous) {
      case HpsClarifyUnknown(clarified: true):
        return '$anfang; als Vorgeschichte kam das Ergebnis einer frueheren '
            'Nachfrage, nicht das der Zahlung -- der Klaerweg der Zahlung '
            'bleibt unbekannt, keine Antwort entscheidet';
      case HpsClarifyUnknown():
        return '$anfang; der bisherige Klaerweg ist nicht bekannt, keine '
            'Antwort entscheidet';
      case HpsClarifyBeforeResolve():
        return '$anfang; die Klaerung der Zahlung hatte nicht begonnen, es '
            'wurde kein Storno nachgeschickt';
      case HpsClarifyUnresolved(:final reason):
        if (reason != null && reason.hostUncertain) {
          return regel.aufgehoben
              ? '$anfang; nach der Stoerung beim hobex-Host (${reason.name}) '
                  'wurde ein Storno versucht, entscheidet nur "aufgehoben" '
                  '(${TransactionResponse.transactionCanceledCode})'
              : '$anfang; nach der Stoerung beim hobex-Host (${reason.name}) '
                  'entscheidet keine Antwort';
        }
        return '$anfang; die Klaerung der Zahlung endete offen ohne Stoerung '
            'beim hobex-Host';
    }
  }

  /// Ordnet die DIREKTE Antwort auf einen Aufhebungs-Request ein.
  ///
  /// Fast dasselbe wie [_fromResponse] -- diese Antwort betrifft ja die
  /// Aufhebung selbst und traegt deren eigenen `responseCode`. Mit genau einer
  /// Ausnahme: [TransactionResponse.transactionCanceledCode] (`9011`).
  ///
  /// Ueber [_fromResponse] wuerde `9011` als "Code ungleich '0'" zu
  /// [CardPaymentOutcome.declined] -- also zu "die Aufhebung hat nicht
  /// gegriffen, es ist weiterhin belastet". Das waere die teure Richtung: es
  /// meldet "belastet" fuer einen Vorgang, der aufgehoben ist, und laedt damit
  /// zu einer Rueckerstattung ein, die der Kunde ein zweites Mal bekaeme. Es
  /// widerspraeche ausserdem [_fromCancelStatus], die aus demselben Code das
  /// Gegenteil ableitet.
  ///
  /// Was `9011` auf dem DIREKTEN Weg genau heisst, ist ungemessen -- am
  /// naechstliegenden "der Vorgang ist (bereits) aufgehoben", aber das ist
  /// eine Lesart, keine Messung. Deshalb wird es hier weder als Erfolg noch
  /// als Ablehnung gewertet, sondern als NICHT SCHLUESSIG: die Klaerung fragt
  /// den Zustand der Originalzahlung ab und entscheidet ihn dort mit dem
  /// gemessenen Diskriminator, statt hier zu raten.
  HpsResult? _fromCancelResponse(
    TransactionResponse res,
    String id,
    List<String> steps,
  ) {
    if (res.isCanceled) {
      steps.add('Aufhebung mit '
          '${TransactionResponse.transactionCanceledCode} beantwortet -- '
          'mehrdeutig, der Zustand der Originalzahlung wird abgefragt');
      return null;
    }
    return _fromResponse(res, id, steps, aufhebung: true);
  }

  /// Verlaufseintrag fuer eine Antwort, die den Ausgang NICHT festschreibt.
  ///
  /// Unterscheidet die Gruende, weil [steps] der Nachweis ist, der im
  /// Belastungsstreit angezeigt wird -- eine Unwahrheit im Nachweis ist
  /// schlimmer als eine Luecke darin:
  /// - kein Code: "Antwort ohne Ergebniscode" -- es war wirklich keiner da.
  /// - [TransactionResponse.technicalErrorCode] (`9900`): ein technischer
  ///   Fehler des Terminals, keine Aussage ueber den Vorgang.
  /// - ein sonst unbekannter Code: "unbekannter Code" -- ein Code WAR da, wir
  ///   kennen nur seine Bedeutung nicht. Das ist etwas anderes als "ohne
  ///   Ergebniscode" und etwas anderes als [TransactionResponse.noStatementCode]
  ///   (`9027`), die unveraendert als "Antwort ohne Aussage" durchgeht.
  static String _offeneAntwort(TransactionResponse res) {
    if (res.responseCode == null) {
      return 'Antwort ohne Ergebniscode -- Ausgang wird geklaert';
    }
    if (res.isTechnicalError) {
      return 'Antwort mit technischem Fehler '
          '(${TransactionResponse.technicalErrorCode}) -- keine Aussage '
          'ueber den Vorgang, Ausgang wird geklaert';
    }
    if (res.isHostUncertain) {
      return '${_stoerung(res)} -- ob belastet wurde, weiss das Terminal '
          'nicht, Ausgang wird geklaert';
    }
    if (res.responseCode == TransactionResponse.notFoundCode) {
      return 'Terminal kennt den Vorgang nicht (${res.responseCode} "Not '
          'Found") -- keine Aussage, Ausgang wird geklaert';
    }
    if (res.isUnknownCode) {
      return 'Terminal nennt einen unbekannten Code (${res.responseCode})'
          '${_klartext(res)} -- Ausgang wird geklaert';
    }
    return 'Antwort ohne Aussage (${res.responseCode}) -- Ausgang wird '
        'geklaert';
  }

  /// Benennt einen Code mit [HpsCodeEffect.hostUncertain] fuer den Nachweis:
  /// was das Terminal meldet, mit Code und hobex-Titel. Die Folgerung ("ob
  /// belastet wurde, ist offen") setzt der Aufrufer dazu.
  static String _stoerung(TransactionResponse res) {
    final info = res.codeInfo!;
    final was = switch (info.reason) {
      HpsCodeReason.internalError => 'interner Fehler des Terminals',
      HpsCodeReason.approvedWithCondition => 'Genehmigung mit Vorbehalt',
      HpsCodeReason.hostTimeout =>
        'keine rechtzeitige Antwort des hobex-Hosts, das Terminal storniert '
            'nicht selbst',
      _ => 'Stoerung zwischen Terminal und hobex-Host, das Terminal storniert '
          'nicht selbst',
    };
    return 'Terminal meldet $was (${res.responseCode} "${info.title}")';
  }

  /// Der Grund eines offenen Ausgangs. [antwort] ist die Antwort auf die
  /// ERZEUGENDE Anfrage, [letzte] die zuletzt gelesene Statusabfrage.
  ///
  /// Eine gemeldete Stoerung beim Host geht vor -- aus welcher der beiden sie
  /// stammt: sie ist der Grund, warum der Ausgang offen bleibt, und fuer jede
  /// spaetere Nachfrage entscheidend ([HpsResult.isHostUncertain]). Sonst
  /// erklaert der Code der erzeugenden Anfrage mehr als ein `9027` danach;
  /// ohne ihn (die Leitung riss ab) bleibt nur die Statusabfrage.
  static HpsCodeReason? _offenerGrund(
    TransactionResponse? antwort,
    TransactionResponse? letzte,
  ) {
    if (antwort != null && antwort.isHostUncertain) return antwort.reason;
    if (letzte != null && letzte.isHostUncertain) return letzte.reason;
    if (antwort?.responseCode != null) return antwort!.reason;
    return letzte?.reason;
  }

  /// Verlaufseintrag fuer eine Statusabfrage, die NICHTS entscheidet -- oder
  /// `null`, wenn keiner der drei benannten Faelle zutrifft; der Aufrufer
  /// setzt dann seinen eigenen Fallback-Text (siehe [_resolve],
  /// [_resolveCancel]).
  ///
  /// Dieselbe Unterscheidung wie [_offeneAntwort], nur fuer den Nachweistext
  /// des Pollens: "wir kennen den Code nicht" (Wissensluecke ueber unser
  /// Modell) ist etwas anderes als "das Terminal kennt den Vorgang nicht"
  /// ([TransactionResponse.noStatementCode], `9027`) und wieder etwas
  /// anderes als "das Terminal meldet einen technischen Fehler"
  /// ([TransactionResponse.technicalErrorCode], `9900`).
  /// Ordnet einen Fehlschlag der ERZEUGENDEN Anfrage (Zahlung, Gutschrift,
  /// der DIREKTE Aufhebungs-Request) ein. `null`, wenn [error] nicht der
  /// gemessene "Terminal beschaeftigt"-Fall ist ([HpsHttpException.isTerminalBusy]).
  ///
  /// Bewusst KEIN Fall in [TransactionResponse.isConclusive]: `409` ist ein
  /// HTTP-Status, kein `responseCode` -- er entsteht, BEVOR ueberhaupt ein
  /// Antwortrumpf gelesen wird, und gehoert deshalb auf diese Ebene, nicht in
  /// die Code-Zuordnung. Siehe [HpsHttpException.terminalBusyStatusCode] fuer
  /// die Messung (87 ms, keine Spur).
  ///
  /// Gilt AUSDRUECKLICH nur hier, an den drei Aufrufstellen in [pay],
  /// [refund] und [cancel] -- niemals in [_tryAbort] oder beim Pollen der
  /// Statusabfrage ([_resolve], [_resolveCancel]). Dort sagt ein `409` nur,
  /// dass DIESE Anfrage nicht durchkam, nichts ueber den Vorgang, den sie
  /// klaeren sollte; ihn dort ebenso zu lesen, waere dieselbe Verwechslung
  /// von Nichtwissen und Aussage wie am 24.08.2026, nur mit `409` statt einem
  /// Zeitablauf.
  HpsResult? _fromTerminalBusy(Object error, String id, List<String> steps) {
    if (error is! HpsHttpException || !error.isTerminalBusy) return null;
    steps.add('Terminal beschaeftigt (HTTP ${error.statusCode}) -- die '
        'Anfrage wurde nicht angenommen, es ist nichts geschehen');
    _emit(HpsEventKind.resolved, steps.last, id);
    return HpsResult(
      outcome: CardPaymentOutcome.declined,
      transactionId: id,
      reason: HpsCodeReason.terminalBusy,
      steps: List<String>.unmodifiable(steps),
    );
  }

  static String? _statusOhneErgebnis(TransactionResponse status) {
    if (status.isNoStatement) {
      return 'Status: keine Auskunft '
          '(${TransactionResponse.noStatementCode})';
    }
    if (status.isTechnicalError) {
      return 'Status: technischer Fehler '
          '(${TransactionResponse.technicalErrorCode}) -- keine Aussage '
          'ueber den Vorgang';
    }
    if (status.isHostUncertain) {
      return 'Status: ${_stoerung(status)} -- keine Aussage';
    }
    // Bewusst NICHT "keine Auskunft": das Wort steht fuer das gemessene 9027,
    // und Aufrufer lesen es als solches (sastre, OpenCardPaymentService).
    if (status.responseCode == TransactionResponse.notFoundCode) {
      return 'Status: Vorgang nicht gefunden (${status.responseCode}) -- '
          'keine Aussage';
    }
    final info = status.codeInfo;
    if (info != null && info.rejectsRequest) {
      return 'Status: Abfrage abgewiesen (${info.code} "${info.title}") -- '
          'keine Aussage ueber den Vorgang';
    }
    if (info != null && info.conclusive && !status.isApproved) {
      // Nur erreichbar nach einer Stoerung beim Host, siehe [_resolve].
      return 'Status: abgelehnt (${info.code} "${info.title}") -- nach der '
          'Stoerung beim hobex-Host entscheidet nur eine Genehmigung';
    }
    if (status.isUnknownCode) {
      return 'Status: unbekannter Code (${status.responseCode})'
          '${_klartext(status)} -- keine Aussage';
    }
    return null;
  }

  /// Der Klartext des Terminals zu einem UNBEKANNTEN Code, als Zusatz fuer
  /// den Nachweis -- oder leer, wenn keiner mitkam. Nur hier, nicht bei den
  /// gemessenen Codes: deren Bedeutung ist benannt, der Klartext waere
  /// Wiederholung. Bei einem unbekannten Code ist er dagegen das Einzige,
  /// was ein Mensch lesen kann -- "PIN falsch" neben `55` haette am
  /// 02.09.2026 gereicht, um nicht "bezahlt" zu buchen.
  static String _klartext(TransactionResponse res) {
    final text = res.responseText?.trim();
    if (text == null || text.isEmpty) return '';
    return ' "$text"';
  }

  /// Ordnet eine Terminal-Antwort ein. `null`, wenn sie nichts entscheidet.
  ///
  /// Drei Antworten entscheiden nichts und fuehren zu weiterem Klaeren:
  /// - keine `responseCode` -- das heisst "laeuft noch", nicht "abgelehnt";
  /// - [TransactionResponse.noStatementCode] (`9027`) -- das heisst
  ///   "keine Auskunft" und steht am gemessenen Terminal gleichermassen fuer
  ///   einen laufenden, einen abgebrochenen und einen nie gesehenen Vorgang;
  /// - [TransactionResponse.isUnknownCode] -- ein Code, dessen Bedeutung wir
  ///   nie gemessen haben. Am 27.08.2026 war das genau die Luecke, die
  ///   [TransactionResponse.technicalErrorCode] (`9900`) aufgedeckt hat:
  ///   ohne diesen dritten Fall waere JEDER neue, unbenannte Code schluessig
  ///   gewesen.
  ///
  /// Alle drei zusammengefasst in [TransactionResponse.isConclusive]. Das ist
  /// die eine Codestelle, an der ein Ergebniscode zu einem Ausgang wird.
  ///
  /// [aufhebung]: die Antwort gehoert zu [cancel]. Ein `'0'` heisst dort
  /// "aufgehoben", und der Grund ist [HpsCodeReason.canceled] statt
  /// [HpsCodeReason.approved].
  HpsResult? _fromResponse(
    TransactionResponse res,
    String id,
    List<String> steps, {
    bool aufhebung = false,
  }) {
    if (!res.isConclusive) return null;
    final approved = res.isApproved;
    steps.add(approved
        ? 'Terminal: genehmigt'
        : 'Terminal: abgelehnt (${res.responseCode} '
            '"${res.codeInfo!.title}")');
    _emit(HpsEventKind.resolved, steps.last, id);
    return HpsResult(
      outcome:
          approved ? CardPaymentOutcome.approved : CardPaymentOutcome.declined,
      transactionId: id,
      response: res,
      reason: approved && aufhebung ? HpsCodeReason.canceled : res.reason,
      steps: List<String>.unmodifiable(steps),
    );
  }

  /// Klaert einen offenen Ausgang: erst einmal abbrechen, dann abfragen --
  /// bis das Terminal etwas sagt oder das Budget aufgebraucht ist.
  ///
  /// Der Abbruch steht vorne in der Absicht, dass ein Kartenfluss, der noch
  /// auf die Karte wartet, endet, bevor die Klaerung ein Ergebnis meldet --
  /// sonst koennte eine spaet aufgelegte Karte danach noch belasten. Eine
  /// Garantie ist das nicht: seine Quittung entscheidet nichts (Klassendoku,
  /// "Ein quittierter Abbruch ist keine Aussage"); den Ausgang sagt erst die
  /// Statusabfrage.
  ///
  /// Was das fuer Budget, Backoff und Transportfehler bedeutet:
  /// - Der Abbruch laeuft ebenfalls unter [resolveBudget] (ueber
  ///   [_withinBudget]) -- sonst haette er die Zusage um bis zu
  ///   [HpsClient.timeout] ueberzogen, bevor die erste Abfrage ueberhaupt
  ///   losgeht. Zusaetzlich ist er auf [_abortBudget] gedeckelt: er startet
  ///   bei `elapsed == 0` und koennte sonst haengend das GANZE Budget
  ///   verbrauchen, sodass keine einzige Statusabfrage mehr stattfaende.
  /// - Die erste Statusabfrage kommt ohne Pause, direkt nach dem Abbruch. Der
  ///   Backoff beginnt erst danach (1 s, 2 s, 4 s, ...), wie bisher.
  /// - Ein am Transport gescheiterter Abbruch zaehlt NICHT in
  ///   [maxTransportFailures]. Der Zaehler soll ein Terminal erkennen, das auf
  ///   die Statusabfrage nicht antwortet; ihn hier vorzubelasten wuerde das
  ///   Klaerbudget um eine Runde kuerzen, obwohl ueber die Erreichbarkeit der
  ///   Statusabfrage noch gar nichts bekannt ist.
  /// [antwort] ist die Antwort auf die ERZEUGENDE Anfrage, sofern eine kam.
  /// Traegt sie einen Ergebniscode, dessen Bedeutung wir nur nicht kennen, ist
  /// der Vorgang am Geraet abgeschlossen -- und erst dadurch bekommt
  /// [TransactionResponse.noStatementCode] (`9027`) beim Pollen einen
  /// Aussagewert, den es sonst nicht hat. Siehe [_ausGeschlossenerAntwort].
  /// Meldet sie eine Stoerung beim Host ([TransactionResponse.isHostUncertain]),
  /// bekommt `9027` diesen Aussagewert gerade NICHT -- siehe Klassendoku,
  /// "Stoerung beim Host".
  ///
  /// [stornoBetrag] ist, was ein nachgeschicktes Storno aufheben muss: Betrag
  /// samt Trinkgeld der Zahlung -- nur [pay] setzt ihn. Ohne ihn wird kein
  /// Storno nachgeschickt, siehe Klassendoku.
  Future<HpsResult> _resolve(
    String id,
    List<String> steps, {
    TransactionResponse? antwort,
    num? stornoBetrag,
  }) async {
    _emit(HpsEventKind.resolving, 'Ausgang offen, Klaerung laeuft', id);

    final clock = _clock()..start();
    final antwortMitCode = antwort?.responseCode != null;
    // Einmal gemeldet, bleibt die Stoerung stehen -- auch wenn erst die
    // Statusabfrage sie nennt und danach 9027 kommt.
    var stoerung = (antwort?.isHostUncertain ?? false) ? antwort : null;
    var letzteAntwort = antwort;
    // Das Storno wird hoechstens einmal erwogen; versucht wird es nur mit
    // Betrag, also nur fuer eine Zahlung (siehe [_sendReversal]).
    var stornoErwogen = false;
    var stornoVersucht = false;
    // Was das Storno bewirkt haben kann; `kannGewirkt` nimmt auch einer
    // Genehmigung in der Statusabfrage die Aussage.
    _StornoAusgang? storno;

    if (stoerung == null) {
      // Entscheidet nichts, beendet nur einen noch wartenden Kartenfluss.
      await _tryAbort(id, steps, clock);
    } else {
      // Der Vorgang ist am Terminal schon beendet -- mit einer Stoerung beim
      // Host. Es gibt nichts mehr abzubrechen, und eine Quittung saehe
      // ohnehin nur das Terminal, nicht den Host.
      steps.add('Kein Abbruchversuch -- das Terminal hat den Vorgang mit einer '
          'Stoerung beim hobex-Host beendet');
      if (stoerung.needsReversal) {
        stornoErwogen = true;
        stornoVersucht = stornoBetrag != null;
        storno = await _sendReversal(id, steps, clock, stornoBetrag, stoerung);
      }
    }

    var wait = Duration.zero;
    var transportFailures = 0;
    var ohneAuskunft = 0;

    /// Beantwortete Statusabfragen in Folge, die zu einem Vorgang mit
    /// Host-Stoerung nichts Neues sagen -- `9027` nach einer gemeldeten
    /// Stoerung, oder die Stoerung selbst.
    var stoerungOhneNeues = 0;

    while (clock.elapsed < resolveBudget) {
      if (wait > Duration.zero) {
        // Auch die Pause zaehlt gegen das Budget: ungedeckelt haette eine
        // Pause von maxBackoff die Zusage um bis zu zehn Sekunden ueberzogen.
        final left = resolveBudget - clock.elapsed;
        await _sleep(wait < left ? wait : left);
        if (clock.elapsed >= resolveBudget) break;
      }

      TransactionResponse status;
      try {
        status = await _withinBudget(
          clock,
          () => _client.transactionStatus(transactionId: id),
        );
        transportFailures = 0;
        letzteAntwort = status;
      } catch (e) {
        // Bewusst jede Ausnahme, nicht nur [HpsException]: auch ein unlesbarer
        // Rumpf oder ein unerwarteter Feldtyp darf die Klaerung nur verzoegern,
        // niemals an pay() vorbei nach draussen.
        transportFailures++;
        steps.add('Statusabfrage gescheitert ($transportFailures): $e');
        _noteUnexpected(e, id);
        if (transportFailures >= maxTransportFailures) {
          steps.add('Terminal antwortet nicht -- Ausgang bleibt offen');
          break;
        }
        wait = _nextWait(wait);
        continue;
      }

      if (status.isHostUncertain) stoerung ??= status;
      final hostUngewiss = stoerung != null;

      if (stornoVersucht && status.isCanceled) {
        // Aufgehoben ist aufgehoben. Wer es war, behauptet der Nachweis nur so
        // weit, wie es feststeht: hat das Storno nachweislich nicht gewirkt,
        // war es ein anderer Vorgang, und der Grund ist `canceled`.
        final durchsStorno = storno == _StornoAusgang.kannGewirkt;
        steps.add(durchsStorno
            ? 'Status: Zahlung aufgehoben '
                '(${TransactionResponse.transactionCanceledCode}) nach dem '
                'nachgeschickten Storno -- es ist nichts belastet'
            : 'Status: Zahlung aufgehoben '
                '(${TransactionResponse.transactionCanceledCode}), obwohl das '
                'nachgeschickte Storno nicht ausgefuehrt wurde -- es ist '
                'nichts belastet');
        _emit(HpsEventKind.resolved, steps.last, id);
        return HpsResult(
          outcome: CardPaymentOutcome.declined,
          transactionId: id,
          response: status,
          reason: durchsStorno
              ? HpsCodeReason.voidedAfterHostFault
              : HpsCodeReason.canceled,
          steps: List<String>.unmodifiable(steps),
        );
      }

      if (!stornoErwogen && status.needsReversal) {
        // Die Zahlung selbst kam ohne Antwort zurueck, erst die Statusabfrage
        // nennt die ausgebliebene Host-Antwort -- dasselbe Storno wie oben.
        steps.add(_statusOhneErgebnis(status)!);
        stornoErwogen = true;
        stornoVersucht = stornoBetrag != null;
        storno = await _sendReversal(id, steps, clock, stornoBetrag, status);
        wait = _nextWait(wait);
        continue;
      }

      // Nach einem Storno, das gewirkt haben kann, sagt auch '0' nichts: das
      // Storno kann noch unterwegs sein oder nicht gegriffen haben. Es zaehlt
      // unten als "nichts Neues" -- siehe Klassendoku, "Storno nach
      // ausbleibender Host-Antwort".
      final genehmigtTrotzStorno =
          storno == _StornoAusgang.kannGewirkt && status.isApproved;

      // Auf die Statusabfrage entscheidet nur ein Code, der den gesuchten
      // Vorgang beschreibt -- nicht einer, der diese Abfrage abweist (siehe
      // TransactionResponse.isConclusiveAsStatus). Nach einer Stoerung beim
      // Host entscheidet nur noch eine Genehmigung: jede andere Aussage des
      // Terminals betrifft seinen Speicher, nicht den des Hosts.
      if (!genehmigtTrotzStorno &&
          (hostUngewiss ? status.isApproved : status.isConclusiveAsStatus)) {
        final settled = _fromResponse(status, id, steps);
        if (settled != null) return settled;
      }

      if (status.isNoStatement) {
        ohneAuskunft++;
        if (!hostUngewiss) {
          final geklaert = _ausGeschlossenerAntwort(
            id: id,
            steps: steps,
            status: status,
            antwort: antwortMitCode ? antwort : null,
            ohneAuskunft: ohneAuskunft,
          );
          if (geklaert != null) return geklaert;
        }
      } else {
        ohneAuskunft = 0;
      }

      // Nach einer Stoerung ist jede Antwort ausser '0' (die oben schon
      // entschieden hat) "nichts Neues" -- nach einem Storno auch '0'.
      stoerungOhneNeues = hostUngewiss ? stoerungOhneNeues + 1 : 0;

      steps.add(genehmigtTrotzStorno
          ? 'Status: Zahlung steht unveraendert (${status.responseCode}) -- '
              'das nachgeschickte Storno kann noch unterwegs sein oder nicht '
              'gegriffen haben, keine Aussage'
          : _statusOhneErgebnis(status) ?? 'Status: noch kein Ergebniscode');

      if (stoerungOhneNeues >= 2) {
        // Siehe Klassendoku, "Stoerung beim Host": das Terminal weiss es
        // nicht, und es wird es auch nicht wissen, wenn wir weiterfragen.
        steps.add('Statusabfrage zweimal ohne Neues nach einer Stoerung beim '
            'hobex-Host -- das Terminal kann nicht sagen, ob belastet wurde, '
            'Ausgang bleibt offen');
        return _open(id, steps, letzteAntwort,
            _offenerGrund(stoerung ?? antwort, letzteAntwort));
      }
      wait = _nextWait(wait);
    }

    steps.add('Ausgang bleibt offen');
    return _open(id, steps, letzteAntwort,
        _offenerGrund(stoerung ?? antwort, letzteAntwort));
  }

  /// Liest `9027` beim Pollen als "nicht genehmigt" -- aber NUR, wenn das
  /// Terminal die erzeugende Anfrage bereits mit einem Ergebniscode
  /// beantwortet hat, und erst ab der ZWEITEN Abfrage in Folge.
  ///
  /// **Warum das ueberhaupt geht.** [TransactionResponse.noStatementCode] ist
  /// sonst eine reine Nicht-Aussage: dieselbe `9027` steht fuer einen
  /// laufenden, einen abgebrochenen und einen nie gesehenen Vorgang. Hat das
  /// Terminal aber eine Antwort MIT Code geliefert, faellt der Fall "laeuft
  /// noch" weg -- der Vorgang ist dort beendet -- und "nie gesehen" ebenso, denn
  /// zu genau dieser Kennung wurde uns gerade geantwortet. Uebrig bleibt
  /// "beendet und nicht genehmigt".
  ///
  /// **Gegenprobe, die das traegt** (28.08.2026, TID 3600335, jeweils nach
  /// abgeschlossenem Vorgang):
  ///
  /// | Zahlung endete | Statusabfrage danach |
  /// |---|---|
  /// | genehmigt | `0` "Genehmigt", dreimal wiederholt |
  /// | abgelehnt (`100003`) | `9027`, zweimal |
  /// | abgelehnt (`9003`) | `9027` |
  ///
  /// Eine genehmigte Zahlung antwortet also `0` und nicht `9027`. Genau darauf
  /// ruht die Regel.
  ///
  /// **Warum erst ab der zweiten Abfrage.** Die erste laeuft unmittelbar nach
  /// der Antwort -- das Fenster, in dem der Datensatz am Terminal noch nicht
  /// stehen koennte. Waere er es nicht und wir lesen `9027` als "abgelehnt",
  /// entstuende genau die Doppelbelastung vom 24.08.2026, nur an einer neuen
  /// Stelle. Dieselbe Absicherung traegt bereits [_fromCancelStatus]. Reicht
  /// das Budget nur fuer eine Abfrage, bleibt der Ausgang offen.
  ///
  /// [antwort] ist die Antwort MIT Code auf die erzeugende Anfrage -- oder
  /// `null`, wenn keine kam; dann greift die Regel nicht. Ihr Code ergibt den
  /// [HpsResult.reason]: er erklaert den Ausgang, das `9027` danach nicht.
  ///
  /// Der Aufrufer ruft diese Regel NICHT fuer eine Antwort mit
  /// [TransactionResponse.isHostUncertain] -- siehe Klassendoku.
  ///
  /// `null` heisst: nicht entschieden, weiter pollen.
  HpsResult? _ausGeschlossenerAntwort({
    required String id,
    required List<String> steps,
    required TransactionResponse status,
    required TransactionResponse? antwort,
    required int ohneAuskunft,
  }) {
    if (antwort == null) return null;
    if (ohneAuskunft < 2) return null;

    steps.add('Statusabfrage zweimal ohne Auskunft (${status.responseCode}), '
        'obwohl das Terminal den Vorgang bereits beantwortet hatte -- '
        'er ist beendet und nicht genehmigt, es ist nichts belastet');
    _emit(HpsEventKind.resolved, steps.last, id);
    return HpsResult(
      outcome: CardPaymentOutcome.declined,
      transactionId: id,
      response: status,
      reason: antwort.reason,
      steps: List<String>.unmodifiable(steps),
    );
  }

  /// Schickt zu einer Zahlung, deren Host-Antwort ausblieb ([anlass] traegt
  /// [HpsCode.sendReversal]), GENAU EINMAL ein Storno ueber [betrag] nach
  /// (Betrag samt Trinkgeld) und haelt im Nachweis fest, was das Terminal
  /// darauf sagt. Entscheidet NIE ueber den Ausgang, siehe Klassendoku,
  /// "Storno nach ausbleibender Host-Antwort".
  ///
  /// Liefert, was das Storno bewirkt haben kann ([_StornoAusgang]).
  /// `abgewiesen` bei HTTP 409: das Terminal nimmt waehrend eines anderen
  /// Vorgangs keine Anfrage an (gemessen, ohne Spur; dieselbe Lesart wie fuer
  /// die erzeugende Anfrage in [_fromTerminalBusy]).
  Future<_StornoAusgang> _sendReversal(
    String id,
    List<String> steps,
    Stopwatch clock,
    num? betrag,
    TransactionResponse anlass,
  ) async {
    if (betrag == null) {
      steps.add('Kein Storno nachgeschickt -- die Aufhebung einer Gutschrift '
          'laesst TECS nicht zu');
      return _StornoAusgang.nichtGesendet;
    }
    _emit(
      HpsEventKind.resolving,
      'Storno wird nachgeschickt (${anlass.responseCode})',
      id,
    );
    TransactionResponse res;
    try {
      res = await _withinBudget(
        clock,
        () => _client.cancel(transactionId: id, amount: betrag),
        cap: _reversalBudget,
      );
    } catch (e) {
      if (e is HpsHttpException && e.isTerminalBusy) {
        steps.add('Storno nicht angenommen (HTTP 409) -- das Terminal war '
            'beschaeftigt, es kann nicht gewirkt haben, Ausgang wird abgefragt');
        return _StornoAusgang.abgewiesen;
      }
      steps.add('Storno nachgeschickt, aber nicht bestaetigt ($e) -- ob es '
          'wirkte, ist offen, Ausgang wird abgefragt');
      _noteUnexpected(e, id);
      return _StornoAusgang.kannGewirkt;
    }
    if (res.isApproved) {
      steps.add('Storno nachgeschickt und quittiert (${res.responseCode}) -- '
          'das allein beweist nicht, dass die Zahlung aufgehoben ist, Ausgang '
          'wird abgefragt');
      return _StornoAusgang.kannGewirkt;
    }
    final titel = res.codeInfo?.title;
    final code = '${res.responseCode ?? 'ohne Ergebniscode'}'
        '${titel == null ? '' : ' "$titel"'}';
    if (_stornoAbgewiesen(res)) {
      steps.add('Storno abgewiesen ($code) -- es wurde nicht ausgefuehrt, '
          'Ausgang wird abgefragt');
      return _StornoAusgang.abgewiesen;
    }
    steps.add('Storno nachgeschickt, nicht bestaetigt ($code) -- ob es '
        'wirkte, ist offen, Ausgang wird abgefragt');
    return _StornoAusgang.kannGewirkt;
  }

  /// Gruende, die ein Storno als NICHT ausgefuehrt ausweisen -- Teil der
  /// Positivliste in [_stornoAbgewiesen], jeder Eintrag einzeln begruendet:
  /// - [HpsCodeReason.cancelDenied] (`9023` "Cancel Denied, TX already
  ///   cleared", `9222` "Offline Tx Cancellation Denied"): TECS lehnt genau
  ///   diese Aufhebung ab.
  /// - [HpsCodeReason.amountInvalid] (`9003`, `100019` gemessen an Zahlungen,
  ///   `9012`, `9026`, `13`, `64`, `87`, `3031` dokumentiert): der Vorgang
  ///   ueber diesen Betrag wird abgewiesen und nicht ausgefuehrt.
  static const Set<HpsCodeReason> _stornoAbgewiesenGruende = {
    HpsCodeReason.cancelDenied,
    HpsCodeReason.amountInvalid,
  };

  /// `true` nur, wenn die Antwort auf das Storno nach einer AUSDRUECKLICHEN
  /// Positivliste sagt, dass es nicht ausgefuehrt wurde:
  ///
  /// - jeder schluessige Code mit [HpsCode.rejectsRequest] -- die Anfrage
  ///   selbst wurde abgewiesen (Form, TID, Vorgangstyp, Geraetezustand,
  ///   `100998`/`8014` "beschaeftigt"), bevor etwas geschah. Gemessen ist davon
  ///   `9002` "Invalid Transaction" auf eine unbekannte Kennung (27.08.2026);
  ///   die uebrigen stehen so in der Codeliste von hobex bzw. TECS.
  /// - jeder Code mit einem Grund aus [_stornoAbgewiesenGruende].
  ///
  /// Alles andere kann gewirkt haben, ausdruecklich auch ein Code, der selbst
  /// "storniert" oder "aufgehoben" heisst (`8009` "Technical cancellation",
  /// `100029`, `3053`-`3063` "Reversed internally", `9032` "reversed
  /// automatically", `9011`), ein Abbruch-Code (`100002`, `17`, `8004`), eine
  /// Host-Ablehnung (etwa `05`) und jeder unbekannte Code.
  static bool _stornoAbgewiesen(TransactionResponse res) {
    final info = res.codeInfo;
    if (info == null || !info.conclusive || res.isApproved) return false;
    return info.rejectsRequest || _stornoAbgewiesenGruende.contains(info.reason);
  }

  /// Wie lange das nachgeschickte Storno hoechstens laufen darf: ein Drittel
  /// des [resolveBudget], bei der Vorgabe 30 s. Anders als der Abbruch geht
  /// ein Storno ueber den Host und darf Sekunden brauchen; der Rest bleibt
  /// fuer die Statusabfrage.
  Duration get _reversalBudget => resolveBudget ~/ 3;

  /// Schickt den Abbruch GENAU EINMAL und haelt im Nachweis fest, was das
  /// Terminal darauf sagt.
  ///
  /// Entscheidet NIE ueber den Ausgang -- auch nicht mit `'0'`: am 10.11.2026
  /// endete eine Zahlung nach angenommenem Abbruch genehmigt (Klassendoku,
  /// "Ein quittierter Abbruch ist keine Aussage"). Der Aufrufer fragt danach
  /// immer den Status ab.
  Future<void> _tryAbort(
    String id,
    List<String> steps,
    Stopwatch clock,
  ) async {
    TransactionResponse res;
    try {
      res = await _withinBudget(
        clock,
        () => _client.abort(transactionId: id),
        cap: _abortBudget,
      );
    } catch (e) {
      // Der Text darf keine Ursache behaupten, die nicht feststeht: [steps]
      // ist der Nachweis, der im Belastungsstreit angezeigt wird. Ein
      // Leitungsabriss, eine Zeitueberschreitung oder eine unlesbare Antwort
      // belegen ueber den Vorgang gar nichts. Ein 404 ist enger als das --
      // aber auch er hat zwei Lesarten, und wir kennen die richtige nicht.
      steps.add(e is HpsHttpException && e.isNotFound
          ? 'Abbruch nicht bestaetigt (HTTP 404) -- das Terminal kennt '
              'entweder diesen Vorgang nicht oder den Abbruch-Endpunkt nicht; '
              'beides sagt nichts ueber die Zahlung, Ausgang wird abgefragt'
          : 'Abbruch nicht bestaetigt ($e) -- ob er wirkte, ist offen, '
              'Ausgang wird abgefragt');
      _noteUnexpected(e, id);
      return;
    }
    steps.add(_abbruchQuittung(res));
  }

  /// Nachweistext zur Antwort auf den Abbruch -- keiner davon schliesst auf
  /// den Ausgang.
  ///
  /// Die Ursache wird nur fuer den GEMESSENEN Code benannt. Jeder andere
  /// Fehlschlagcode des Abbruchs ist unbekannten Ursprungs -- und [steps] ist
  /// der Nachweis, der im Belastungsstreit angezeigt wird.
  static String _abbruchQuittung(TransactionResponse res) {
    if (res.responseCode == null) {
      return 'Abbruch ohne Ergebniscode quittiert -- das beweist nichts, '
          'Ausgang wird abgefragt';
    }
    if (res.isApproved) {
      return 'Abbruch angenommen (${res.responseCode}) -- das sagt nicht, ob '
          'belastet wurde (am 10.11.2026 endete eine Zahlung nach '
          'angenommenem Abbruch genehmigt), Ausgang wird abgefragt';
    }
    if (res.isNotAbortable) {
      return 'Abbruch abgelehnt (${res.responseCode}) -- der Vorgang ist '
          'nicht mehr abbrechbar, Ausgang wird abgefragt';
    }
    return 'Abbruch abgelehnt (${res.responseCode}) -- Grund unbekannt, '
        'Ausgang wird abgefragt';
  }

  /// Klaert eine offene Aufhebung -- eigene Fassung statt [_resolve], weil
  /// die Kennung hier die der URSPRUENGLICHEN Zahlung ist.
  ///
  /// Zwei Unterschiede zu [_resolve]:
  ///
  /// 1. Die Antwort der Statusabfrage wird ueber [_fromCancelStatus]
  ///    eingeordnet, NICHT ueber [_fromResponse]. Der `responseCode` der
  ///    Originalkennung bedeutet hier etwas anderes als bei [pay] -- siehe
  ///    dort.
  /// 2. Kein [HpsClient.abort]-Versuch. Der Abbruch greift nur, solange ein
  ///    Vorgang noch abbrechbar ist; die Originalzahlung, deren Kennung hier
  ///    vorliegt, ist laengst abgeschlossen und antwortet gemessen mit
  ///    `100010`. Ein Abbruchversuch darauf waere sinnlos und koennte
  ///    hoechstens fehlleiten.
  ///
  /// Budget, Backoff und Transportfehler-Deckelung sind unveraendert aus
  /// [_resolve] uebernommen.
  ///
  /// [antwort] ist die direkte Antwort auf den Aufhebungs-Request, sofern eine
  /// kam. Meldete sie eine Stoerung beim Host, entscheidet ein unveraendertes
  /// `'0'` nichts -- siehe Klassendoku, "Stoerung beim Host".
  Future<HpsResult> _resolveCancel(
    String id,
    List<String> steps, {
    TransactionResponse? antwort,
  }) async {
    _emit(HpsEventKind.resolving, 'Ausgang offen, Klaerung laeuft', id);

    final clock = _clock()..start();
    final hostUngewiss = antwort?.isHostUncertain ?? false;
    var letzteAntwort = antwort;
    var wait = Duration.zero;
    var transportFailures = 0;

    /// Zaehlt nur BEANTWORTETE Statusabfragen -- Grundlage der Karenz fuer
    /// den `'0'`-Fall, siehe [_fromCancelStatus].
    var beantworteteAbfragen = 0;

    while (clock.elapsed < resolveBudget) {
      if (wait > Duration.zero) {
        final left = resolveBudget - clock.elapsed;
        await _sleep(wait < left ? wait : left);
        if (clock.elapsed >= resolveBudget) break;
      }

      TransactionResponse status;
      try {
        status = await _withinBudget(
          clock,
          () => _client.transactionStatus(transactionId: id),
        );
        transportFailures = 0;
        beantworteteAbfragen++;
        letzteAntwort = status;
      } catch (e) {
        transportFailures++;
        steps.add('Statusabfrage gescheitert ($transportFailures): $e');
        _noteUnexpected(e, id);
        if (transportFailures >= maxTransportFailures) {
          steps.add('Terminal antwortet nicht -- Ausgang bleibt offen');
          break;
        }
        wait = _nextWait(wait);
        continue;
      }

      if (hostUngewiss && status.isApproved && beantworteteAbfragen >= 2) {
        // Siehe Klassendoku, "Stoerung beim Host": das unveraenderte '0'
        // spiegelt nur den Speicher des Terminals. Ob die Aufhebung beim
        // Host ankam, sagt es nicht -- und "hat nicht gegriffen" fuehrte nach
        // dem Tagesabschluss zu einer Rueckerstattung, die der Kunde doppelt
        // bekaeme.
        steps.add('Terminal: Originalzahlung steht unveraendert (0), aber die '
            'Aufhebung endete mit einer Stoerung beim hobex-Host -- ob sie '
            'dort gewirkt hat, kann das Terminal nicht sagen, Ausgang bleibt '
            'offen');
        return _open(
            id, steps, letzteAntwort, _offenerGrund(antwort, letzteAntwort));
      }

      final settled = _fromCancelStatus(
        status,
        id,
        steps,
        ersteAbfrage: beantworteteAbfragen == 1,
      );
      if (settled != null) return settled;

      // Der `'0'`-Karenzfall hat seinen eigenen, aussagekraeftigeren Eintrag
      // schon in [_fromCancelStatus] gesetzt.
      if (!status.isApproved) {
        steps.add(_statusOhneErgebnis(status) ??
            'Status: Aufhebung noch nicht bestaetigt');
      }
      wait = _nextWait(wait);
    }

    steps.add('Ausgang bleibt offen');
    return _open(
        id, steps, letzteAntwort, _offenerGrund(antwort, letzteAntwort));
  }

  /// Ordnet die Statusabfrage einer OFFENEN AUFHEBUNG ein. `null`, wenn sie
  /// nichts entscheidet.
  ///
  /// Die Abfrage laeuft auf die Kennung der ORIGINALZAHLUNG. Ihr
  /// `responseCode` beschreibt deshalb den Zustand DIESER Zahlung, nicht den
  /// Ausgang der Aufhebung -- er wird hier uebersetzt, nicht wie bei [pay]
  /// gelesen. Am 26.08.2026 gemessen (HPS 1.10.0, Firmware 7.3.6), nachdem
  /// eine genehmigte Zahlung per Void aufgehoben wurde:
  ///
  /// - [TransactionResponse.transactionCanceledCode] (`9011`, "Transaction
  ///   Canceled") -> die Aufhebung hat gewirkt -> fuer die Operation [cancel]
  ///   ein Erfolg, [CardPaymentOutcome.approved].
  /// - `'0'` -> die Originalzahlung steht unveraendert da, die Aufhebung hat
  ///   also NICHT gewirkt -> [CardPaymentOutcome.declined]. Das ist hier keine
  ///   schlechte Nachricht ueber die Zahlung, sondern eine ueber die
  ///   Aufhebung: es ist weiterhin belastet, und die Aufhebung muss wiederholt
  ///   werden. ABER erst ab der ZWEITEN beantworteten Abfrage, siehe
  ///   [ersteAbfrage].
  /// - [TransactionResponse.noStatementCode] (`9027`) und jeder andere oder
  ///   fehlende Code -> keine Auskunft, weiter klaeren; am Ende
  ///   [CardPaymentOutcome.unresolved], niemals ein geratenes Ergebnis.
  ///
  /// Die Verwechslungsgefahr, die diese eigene Fassung ueberhaupt noetig macht,
  /// bleibt damit ausgeschlossen: der `responseCode` der Originalzahlung wird
  /// NIE als Erfolg der Aufhebung gelesen -- `'0'` heisst hier ausdruecklich
  /// das Gegenteil.
  ///
  /// ## Warum `'0'` eine Karenz braucht
  ///
  /// Die Klaerung startet unmittelbar, nachdem der Void-Request abgerissen
  /// ist, und ihre erste Abfrage laeuft ohne Pause (`wait == Duration.zero`).
  /// Anders als bei [pay] liegt kein Abbruch-Roundtrip dazwischen, der Zeit
  /// verstreichen liesse. Genau in diesem Fenster kann der Void beim Terminal
  /// noch unterwegs sein und die Abfrage trotzdem schon `'0'` melden.
  ///
  /// Ein voreiliges "hat nicht gegriffen" ist NICHT harmlos. Was der
  /// Mitarbeiter danach tut, ist nicht zwingend ein zweiter Void: nach dem
  /// Tagesabschluss ist die Folgehandlung eine RUECKERSTATTUNG -- und dann
  /// bekommt der Kunde sein Geld zweimal. (Die naheliegende Beruhigung, das
  /// Terminal weise eine Wiederholung ohnehin als "bereits aufgehoben" ab,
  /// ist eine ANNAHME: sie steht in keiner Messtabelle und in keinem Test.
  /// Auf so einer Annahme zu bauen, ist die Fehlerklasse, gegen die dieses
  /// Vorhaben gebaut ist.)
  ///
  /// Deshalb entscheidet `'0'` erst ab der zweiten beantworteten Abfrage. Ein
  /// tatsaechlich nicht gelandeter Void antwortet eine Sekunde spaeter wieder
  /// `'0'`; der Preis ist diese eine Sekunde. Reicht das Budget nur fuer eine
  /// einzige Abfrage, endet die Klaerung bei
  /// [CardPaymentOutcome.unresolved] -- wir sagen dann, dass wir es nicht
  /// wissen, statt es zu raten.
  ///
  /// AUCH DAS IST EINE ANNAHME, und sie ist als solche zu lesen: die Karenz
  /// deckt das plausible Fenster ab, nicht das garantierte. Einen Nachlauf
  /// gibt es nicht -- gemessen schlaegt die Statusabfrage sofort auf `9011`
  /// um, sobald der Void am Terminal durch ist (`doc/kartenzahlung.md`,
  /// "Nach einem gelandeten Void schlaegt der Status sofort um"). Das
  /// `'0'`-Fenster ist genau die AUSFUEHRUNGSDAUER eines noch UNTERWEGS
  /// befindlichen Voids, und die ist ungemessen: er laeuft ueber einen
  /// Host-Roundtrip (auf dem Testgeraet `tecstest.hobex.at`) und nicht nur
  /// ueber das lokale Terminal. Dauert seine Ausfuehrung laenger als die
  /// erste Backoff-Pause, meldet auch die zweite Abfrage noch `'0'`, und das
  /// voreilige "hat nicht gegriffen" entsteht doch. Die Karenz macht diesen
  /// Fall unwahrscheinlich, nicht unmoeglich; abschliessen laesst er sich nur
  /// mit einer Messung dieser Dauer.
  ///
  /// [TransactionResponse.state] `== 'VOID'` gilt zusaetzlich als Beleg, aber
  /// niemals als notwendige Bedingung. Bis 26.08.2026 war es die einzige
  /// Bedingung -- ein Fehler: auf dieser Firmware ist `state` in JEDER
  /// bisher gesehenen Antwort `null`, bei genehmigten, abgebrochenen,
  /// unbekannten und aufgehobenen Vorgaengen gleichermassen. Die Bedingung
  /// wurde damit nie wahr, und jede Storno-Klaerung lief ins Budget und endete
  /// als [CardPaymentOutcome.unresolved], egal was tatsaechlich geschah. Es
  /// bleibt nur mitgelesen, weil ein ausdrueckliches `'VOID'` -- wo eine
  /// Firmware es denn liefert -- eine unmissverstaendliche positive Aussage
  /// ist, die kein falsches `approved` erzeugen kann.
  ///
  /// [ersteAbfrage] ist `true`, wenn dies die erste BEANTWORTETE Statusabfrage
  /// dieser Klaerung ist. Gescheiterte Abfragen zaehlen nicht mit: sie lassen
  /// zwar Zeit verstreichen, liefern aber keine Auskunft, an der sich ein
  /// `'0'` bestaetigen liesse.
  HpsResult? _fromCancelStatus(
    TransactionResponse status,
    String id,
    List<String> steps, {
    required bool ersteAbfrage,
  }) {
    final voided = status.isCanceled ||
        // Gross-/Kleinschreibung und Leerzeichen toleriert: eine tolerantere
        // Erkennung von 'VOID' fuehrt hoechstens frueher zu einer ohnehin
        // zutreffenden Bestaetigung.
        status.state?.trim().toUpperCase() == 'VOID';
    if (voided) {
      steps.add('Terminal: Aufhebung bestaetigt '
          '(${status.responseCode ?? status.state})');
      _emit(HpsEventKind.resolved, steps.last, id);
      return HpsResult(
        outcome: CardPaymentOutcome.approved,
        transactionId: id,
        response: status,
        reason: HpsCodeReason.canceled,
        steps: List<String>.unmodifiable(steps),
      );
    }

    if (status.isApproved) {
      if (ersteAbfrage) {
        // Karenz: der Void kann noch unterwegs sein. Siehe oben, "Warum '0'
        // eine Karenz braucht".
        steps.add('Terminal: Originalzahlung noch unveraendert (0) -- die '
            'Aufhebung koennte noch unterwegs sein, wird erneut abgefragt');
        return null;
      }
      steps.add('Terminal: Originalzahlung steht unveraendert (0) -- die '
          'Aufhebung hat nicht gegriffen');
      _emit(HpsEventKind.resolved, steps.last, id);
      return HpsResult(
        outcome: CardPaymentOutcome.declined,
        transactionId: id,
        response: status,
        steps: List<String>.unmodifiable(steps),
      );
    }

    return null;
  }

  /// Der Ausgang bleibt offen. Die Kennung ist gesetzt, damit Statusabfrage
  /// und Storno erreichbar bleiben.
  ///
  /// [letzteAntwort] ist die letzte Antwort, die das Terminal in dieser
  /// Klaerung gab -- als [HpsResult.lastResponse] fuer Anzeige und Katalog,
  /// ausdruecklich NICHT als [HpsResult.response].
  ///
  /// [reason] siehe [_offenerGrund].
  HpsResult _open(String id, List<String> steps,
      [TransactionResponse? letzteAntwort, HpsCodeReason? grund]) {
    _emit(HpsEventKind.resolved, steps.last, id);
    return HpsResult(
      outcome: CardPaymentOutcome.unresolved,
      transactionId: id,
      lastResponse: letzteAntwort,
      reason: grund,
      steps: List<String>.unmodifiable(steps),
    );
  }

  /// Fuehrt [call] aus, aber hoechstens so lange, wie vom [resolveBudget]
  /// uebrig ist -- sonst waere die Klaerung nicht durch das Budget begrenzt,
  /// sondern durch [HpsClient.timeout] je einzelnem Request.
  ///
  /// [cap] deckelt zusaetzlich, wenn ein einzelner Schritt nicht das ganze
  /// verbleibende Budget verbrauchen darf -- siehe [_abortBudget]. [budget]
  /// ersetzt [resolveBudget], wenn ein Weg ein eigenes, kuerzeres Budget hat
  /// -- siehe [_clarifyBudget].
  Future<T> _withinBudget<T>(
    Stopwatch clock,
    Future<T> Function() call, {
    Duration? cap,
    Duration? budget,
  }) {
    final gesamt = budget ?? resolveBudget;
    var left = gesamt - clock.elapsed;
    if (cap != null && cap < left) left = cap;
    if (left <= Duration.zero) {
      throw TimeoutException('Klaerungsbudget aufgebraucht', gesamt);
    }
    return call().timeout(left);
  }

  /// Teiler, mit dem [_abortBudget] aus [resolveBudget] entsteht.
  static const int _abortBudgetDivisor = 6;

  /// Wie lange der einmalige Abbruchversuch hoechstens laufen darf: ein
  /// Sechstel des [resolveBudget], bei der Vorgabe also 15 s von 90 s.
  ///
  /// Ohne diesen Deckel haette ein HAENGENDER Abbruch das gesamte Budget
  /// aufgebraucht -- er startet bei `elapsed == 0`, also mit dem vollen
  /// Budget im Ruecken. Danach waere die Schleife sofort vorbei, ohne eine
  /// einzige Statusabfrage, und das Ergebnis stets
  /// [CardPaymentOutcome.unresolved]. Das ist zwar die sichere Richtung, aber
  /// der Klaerweg waere dabei komplett verloren: gerade die Statusabfrage
  /// haette den Ausgang noch feststellen koennen.
  ///
  /// Ein Sechstel, weil der Abbruch ein einzelner lokaler Roundtrip ist -- er
  /// braucht Millisekunden, nicht Sekunden. Was darueber liegt, ist ein
  /// haengendes Terminal, und dann ist die Zeit in Statusabfragen besser
  /// angelegt.
  ///
  /// Der Deckel hat einen Preis, und der gehoert benannt: ein Abbruch, der
  /// laenger als [_abortBudget] braucht, wird aufgegeben -- ob er einen noch
  /// wartenden Kartenfluss beendet hat, ist dann offen. Am Ausgang aendert
  /// das nichts: den sagt seit dem 10.11.2026 ohnehin nur die Statusabfrage,
  /// nie die Quittung des Abbruchs.
  ///
  /// Und: `Future.timeout` bricht den HTTP-Request NICHT ab, es gibt ihn nur
  /// auf. Die verlassene Abbruch-Anfrage laeuft am Terminal weiter. Faellt
  /// die unmittelbar folgende Statusabfrage in dieses Fenster, kann das
  /// Terminal sie mit `409` beantworten ("ein anderer Request laeuft") --
  /// das bleibt BEWUSST ein Transportfehler wie jeder andere, zaehlt in
  /// [maxTransportFailures] und wird nie zu einem Ausgang. Seit dem
  /// 27.08.2026 hat `409` zwar eine eigene, benannte Behandlung
  /// ([_fromTerminalBusy]) -- die gilt aber ausdruecklich nur fuer die
  /// ERZEUGENDE Anfrage (siehe dort). Hier waere die Statusabfrage, nicht der
  /// urspruengliche Vorgang, abgewiesen worden -- ein `409` an dieser Stelle
  /// sagt nichts darueber aus, ob DER VORGANG selbst glückte. Sicher, aber
  /// ungenau.
  Duration get _abortBudget => resolveBudget ~/ _abortBudgetDivisor;

  Duration _nextWait(Duration current) {
    if (current == Duration.zero) return const Duration(seconds: 1);
    final doubled = current * 2;
    return doubled > maxBackoff ? maxBackoff : doubled;
  }

  /// Meldet eine Ausnahme, die KEINE [HpsException] ist -- also einen Fehler
  /// im eigenen Auswerten statt einen am Terminal.
  ///
  /// Der Zahlweg laeuft trotzdem konservativ weiter (der Ausgang bleibt offen,
  /// statt geraten zu werden), aber stumm bleiben darf so etwas nicht: sonst
  /// sieht niemand, dass hier ein eigener Fehler und nicht das Terminal die
  /// Klaerung ausgeloest hat.
  void _noteUnexpected(Object error, String id) {
    if (error is HpsException) return;
    final observer = _observer;
    if (observer == null) return;
    try {
      observer(HpsEvent(
        HpsEventKind.requestFailed,
        'Unerwarteter Fehler beim Auswerten der Terminal-Antwort',
        transactionId: id,
        error: error,
      ));
    } catch (_) {
      // bewusst still -- das Protokoll darf den Zahlweg nie mitreissen
    }
  }

  void _emit(HpsEventKind kind, String message, String id) {
    final observer = _observer;
    if (observer == null) return;
    try {
      observer(HpsEvent(kind, message, transactionId: id));
    } catch (_) {
      // bewusst still -- das Protokoll darf den Zahlweg nie mitreissen
    }
  }
}

/// Was ueber die bisherige Klaerung einer Zahlung feststeht -- Eingabe fuer
/// [HpsPayments.clarifyPayment]. Davon haengt ab, was eine Antwort des
/// Terminals jetzt noch beweist, siehe dort.
///
/// Drei Faelle, als eigene Typen statt als Zeichenketten, damit ein Aufrufer
/// keinen vierten erfinden kann:
///
/// - [HpsClarifyPrevious.unresolved]: das offene Ergebnis von
///   [HpsPayments.pay] -- es zaehlt nur [HpsResult.reason];
///   [HpsClarifyPrevious.fromResult] nimmt ihn aus dem Ergebnis. NIE das
///   Ergebnis einer Nachfrage ([HpsResult.clarified]): dessen Grund stammt
///   aus der Nachfrage, nicht aus der Zahlung, und wuerde eine unbekannte
///   Vorgeschichte reinwaschen -- [fromResult] bildet es deshalb auf
///   [HpsClarifyPrevious.unknown] ab.
/// - [HpsClarifyPrevious.beforeResolve]: die Zahlung wurde gestartet, ihre
///   Klaerung hat aber nie begonnen -- etwa weil die App waehrend des
///   Kartenflows abriss. Es wurde dann sicher kein Storno nachgeschickt. Nur
///   angeben, wenn das Beobachter-Ereignis [HpsEventKind.resolving]
///   nachweislich nie kam (es wird vor dem ersten Abbruch- oder
///   Storno-Aufruf gemeldet); im Zweifel [HpsClarifyPrevious.unknown].
/// - [HpsClarifyPrevious.unknown]: nicht bekannt (etwa ein Eintrag aus einer
///   aelteren Fassung, oder die App riss waehrend der Klaerung ab).
sealed class HpsClarifyPrevious {
  const HpsClarifyPrevious();

  /// Das offene Ergebnis von [HpsPayments.pay]; es zaehlt nur [reason].
  const factory HpsClarifyPrevious.unresolved({HpsCodeReason? reason}) =
      HpsClarifyUnresolved;

  /// Die Vorgeschichte aus [result], dem Ergebnis von [HpsPayments.pay]:
  /// [HpsClarifyPrevious.unresolved] mit dessen Grund -- oder
  /// [HpsClarifyPrevious.unknown], wenn [result] selbst aus einer Nachfrage
  /// stammt ([HpsResult.clarified]); die Nachfrage sagt dann im ersten
  /// Schritt, dass keine Antwort entscheidet.
  ///
  /// Wirft [ArgumentError], wenn [result] nicht
  /// [CardPaymentOutcome.unresolved] ist: ein entschiedener Ausgang hat keine
  /// Nachfrage mehr noetig, und ihn als Vorgeschichte zu uebergeben, ist ein
  /// Aufruffehler, der sichtbar bleiben soll.
  factory HpsClarifyPrevious.fromResult(HpsResult result) {
    if (!result.isUnresolved) {
      throw ArgumentError.value(
        result,
        'result',
        'nur ein offenes Ergebnis (unresolved) ist eine Vorgeschichte, '
            'dieses ist ${result.outcome.name}',
      );
    }
    if (result.clarified) return const HpsClarifyUnknown(clarified: true);
    return HpsClarifyUnresolved(reason: result.reason);
  }

  /// Die Klaerung der Zahlung hat nie begonnen; sicher kein Storno. Siehe
  /// Klassendoku: nur, wenn [HpsEventKind.resolving] nachweislich nie kam.
  const factory HpsClarifyPrevious.beforeResolve() = HpsClarifyBeforeResolve;

  /// Der bisherige Klaerweg ist nicht bekannt.
  const factory HpsClarifyPrevious.unknown() = HpsClarifyUnknown;
}

/// Siehe [HpsClarifyPrevious.unresolved].
final class HpsClarifyUnresolved extends HpsClarifyPrevious {
  const HpsClarifyUnresolved({this.reason});

  /// [HpsResult.reason] des offenen Ergebnisses; `null`, wenn kein Code
  /// etwas erklaerte (die Leitung riss ab, bevor das Terminal etwas sagte).
  final HpsCodeReason? reason;
}

/// Siehe [HpsClarifyPrevious.beforeResolve].
final class HpsClarifyBeforeResolve extends HpsClarifyPrevious {
  const HpsClarifyBeforeResolve();
}

/// Siehe [HpsClarifyPrevious.unknown].
final class HpsClarifyUnknown extends HpsClarifyPrevious {
  const HpsClarifyUnknown({this.clarified = false});

  /// `true`, wenn als Vorgeschichte das Ergebnis einer frueheren Nachfrage
  /// kam ([HpsResult.clarified], ueber [HpsClarifyPrevious.fromResult]). Die
  /// Regel ist dieselbe wie ohne Vorgeschichte; der Nachweis benennt es.
  final bool clarified;
}

/// Welche Antworten eine spaete Nachfrage entscheiden duerfen, siehe
/// [HpsPayments.clarifyPayment].
class _NachfrageRegel {
  const _NachfrageRegel({
    required this.genehmigt,
    required this.aufgehoben,
    required this.abgelehnt,
  });

  /// Jede schluessige Antwort entscheidet.
  static const alles =
      _NachfrageRegel(genehmigt: true, aufgehoben: true, abgelehnt: true);

  /// Keine Antwort entscheidet.
  static const nichts =
      _NachfrageRegel(genehmigt: false, aufgehoben: false, abgelehnt: false);

  /// `'0'` heisst belastet.
  final bool genehmigt;

  /// `9011` heisst nichts belastet.
  final bool aufgehoben;

  /// Jeder andere schluessige Code ungleich `'0'` heisst nichts belastet.
  final bool abgelehnt;
}

/// Was ein nachgeschicktes Storno bewirkt haben kann, siehe Klassendoku von
/// [HpsPayments], "Storno nach ausbleibender Host-Antwort".
enum _StornoAusgang {
  /// Keines gesendet: eine Gutschrift hat keinen Stornobetrag.
  nichtGesendet,

  /// Das Terminal hat es nachweislich nicht ausgefuehrt: HTTP 409 oder ein
  /// Code aus [HpsPayments._stornoAbgewiesen].
  abgewiesen,

  /// Alles andere -- auch die Quittung `'0'`.
  kannGewirkt,
}
