import 'dart:async';

import '../payments/card_payment_outcome.dart';
import 'exceptions.dart';
import 'hps_client.dart';
import 'hps_result.dart';
import 'observer.dart';
import 'transaction_response.dart';

/// Kartenzahlung, deren Ausgang immer bekannt ist.
///
/// Der Unterschied zu [HpsClient.payment]: die Transaktionskennung steht VOR
/// dem ersten Netzweg fest, und ein abgebrochener Vorgang wird ueber
/// [HpsClient.transactionStatus] geklaert statt als Fehlschlag gemeldet.
///
/// Regel, von der nicht abgewichen wird: [CardPaymentOutcome.declined] entsteht
/// ausschliesslich aus einer POSITIVEN Aussage -- entweder einem echten
/// Ergebniscode des Terminals, der weder `'0'` noch
/// [TransactionResponse.noStatementCode] ist, oder einem nachweislich
/// gelungenen [HpsClient.abort]. Ein Transportfehler, ein Zeitablauf oder eine
/// Wissensluecke fuehren NIE dorthin: keines davon ist eine Aussage darueber,
/// dass nichts belastet wurde. Ein Transportfehler trennt "nicht angekommen"
/// nicht von "angekommen, Antwort verloren" -- genau diese Verwechslung hat am
/// 24.08.2026 eine echte Belastung als unbelastet ausgewiesen und den Kunden
/// ein zweites Mal belastet.
///
/// ## Der Klaerweg, wie er am 26.08.2026 gemessen wurde
///
/// Gemessen an einem hobex-HPS (TID 3600335, HPS 1.10.0, Firmware 7.3.6):
///
/// | Lage | Zahlung | `transactionStatus` | `abort` |
/// |---|---|---|---|
/// | genehmigt | `0` | `0`, bleibt erhalten | `100010`, scheitert |
/// | Kartenfluss laeuft | offen | `9027` | `0`, gelingt |
/// | Karte nicht aufgelegt | `100003` | `9027` | -- |
/// | abgebrochen | `100002` | `9027` | -- |
/// | nie gesehen | -- | `9027` | -- |
///
/// Die Statusabfrage unterscheidet also NICHT zwischen "laeuft gerade", "nie
/// angekommen" und "abgebrochen": alle drei antworten `9027`. Wer diesen Code
/// ueber `!= '0'` als Ablehnung liest, meldet fuer einen laufenden Vorgang
/// "gefahrlos wiederholbar" -- der Kunde legt die Karte auf, und die
/// Wiederholung belastet ein zweites Mal.
///
/// Der Abbruch trennt, was die Statusabfrage nicht trennt. Deshalb steht er
/// jetzt VORNE, nicht mehr hinter einer Statusabfrage, die den Zustand "laeuft
/// noch" nie meldet:
///
/// 1. [HpsClient.abort] einmalig versuchen.
/// 2. `responseCode == '0'` -> der Vorgang war noch abbrechbar, also nicht
///    abgeschlossen -> [CardPaymentOutcome.declined], beweisbar.
/// 3. jeder andere Code (gemessen `100010`) -> der Vorgang ist ueber den
///    abbrechbaren Punkt hinaus -> JETZT die Statusabfrage pollen, sie
///    liefert nun eine echte Aussage.
/// 4. Abbruch scheitert am Transport -> pollen wie in 3.
/// 5. Beim Pollen ist `9027` kein Ergebnis, sondern ein Grund
///    weiterzumachen. Budget erschoepft -> [CardPaymentOutcome.unresolved].
///
/// **Bewusst in Kauf genommen:** gelingt der Abbruch in dem Moment, in dem der
/// Kunde die Karte auflegt, reisst er dessen Zahlung ab. Geldseitig ist das
/// die sichere Richtung -- es ist dann nachweislich nichts belastet, und der
/// Vorgang kann gefahrlos wiederholt werden. Die Alternative waere, den
/// Ausgang offen zu lassen und den Mitarbeiter raten zu lassen; das hat am
/// 24.08.2026 zur Doppelbelastung gefuehrt. Der Abbruch wird nur ausgeloest,
/// wenn die Zahlung ohnehin schon ohne Antwort dasteht -- im Normalfall
/// passiert er nie.
///
/// Die Kennung ist in JEDEM Ergebnis gesetzt, auch bei
/// [CardPaymentOutcome.unresolved]: ohne sie sind Statusabfrage und Storno
/// unerreichbar.
///
/// [refund] bekommt exakt dieselbe Klaerung wie [pay], Abbruch eingeschlossen
/// -- und das ist GEMESSEN, nicht nur analog geschlossen. Am 26.08.2026
/// nachgemessen: `abort` auf eine LAUFENDE Gutschrift antwortet ebenfalls mit
/// `responseCode '0'`, und die Gutschrift endet daraufhin mit `100002`
/// "Aborted". Der Abbruch ist dort also derselbe Diskriminator wie bei einer
/// Zahlung.
///
/// Dazu passt der Aufbau: die Kennung ist bei [refund] die des NEUEN Vorgangs
/// (der Gutschrift selbst), eine Statusabfrage darauf liefert also genau deren
/// Ausgang, und `POST /api/transaction/abort/{tid}/{tx}` kennt keinen
/// Transaktionstyp -- er adressiert den laufenden Vorgang unter dieser
/// Kennung. Ohne Abbruch haette die Klaerung einer Gutschrift gar keinen
/// Diskriminator mehr und endete fast immer bei `unresolved`, weil die
/// Statusabfrage auch hier `9027` antwortet. Ein abgerissener Gutschriftlauf
/// kostet den Kunden nichts: er bekommt sein Geld einen Vorgang spaeter,
/// waehrend eine falsche "gefahrlos wiederholbar"-Meldung eine doppelte
/// Gutschrift ausloesen wuerde.
///
/// [cancel] ist die Ausnahme, und zwar in beiden Richtungen -- siehe
/// [_resolveCancel]: die uebergebene Kennung ist die der URSPRUENGLICHEN
/// Zahlung. Ein Abbruch darauf waere sinnlos (der Vorgang ist laengst
/// abgeschlossen, gemessen: `100010`), und der `responseCode` dieser Kennung
/// bedeutet dort etwas anderes als bei [pay].
class HpsPayments {
  HpsPayments(
    this._client, {
    this.resolveBudget = const Duration(seconds: 90),
    this.maxBackoff = const Duration(seconds: 10),
    this.maxTransportFailures = 3,
    Future<void> Function(Duration)? sleep,
    Stopwatch Function()? clock,
    HpsObserver? observer,
  })  : _sleep = sleep ?? _realSleep,
        _clock = clock ?? Stopwatch.new,
        _observer = observer;

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
      steps.add('Zahlung abgebrochen: $e');
      _noteUnexpected(e, id);
    }

    if (res != null) {
      final settled = _fromResponse(res, id, steps);
      if (settled != null) return settled;
      steps.add('Antwort ohne Ergebniscode -- Ausgang wird geklaert');
    }

    return _resolve(id, steps);
  }

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
      steps.add('Gutschrift abgebrochen: $e');
      _noteUnexpected(e, id);
    }

    if (res != null) {
      final settled = _fromResponse(res, id, steps);
      if (settled != null) return settled;
      steps.add('Antwort ohne Ergebniscode -- Ausgang wird geklaert');
    }

    return _resolve(id, steps);
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
      steps.add('Aufhebung abgebrochen: $e');
      _noteUnexpected(e, transactionId);
    }

    if (res != null) {
      final settled = _fromCancelResponse(res, transactionId, steps);
      if (settled != null) return settled;
      steps.add('Antwort ohne Ergebniscode -- Ausgang wird geklaert');
    }

    return _resolveCancel(transactionId, steps);
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
    return _fromResponse(res, id, steps);
  }

  /// Ordnet eine Terminal-Antwort ein. `null`, wenn sie nichts entscheidet.
  ///
  /// Zwei Antworten entscheiden nichts und fuehren zu weiterem Klaeren:
  /// - keine `responseCode` -- das heisst "laeuft noch", nicht "abgelehnt";
  /// - [TransactionResponse.noStatementCode] (`9027`) -- das heisst
  ///   "keine Auskunft" und steht am gemessenen Terminal gleichermassen fuer
  ///   einen laufenden, einen abgebrochenen und einen nie gesehenen Vorgang.
  ///
  /// Beides zusammengefasst in [TransactionResponse.isConclusive]. Das ist die
  /// eine Codestelle, an der ein Ergebniscode zu einem Ausgang wird.
  HpsResult? _fromResponse(
    TransactionResponse res,
    String id,
    List<String> steps,
  ) {
    if (!res.isConclusive) return null;
    final approved = res.isApproved;
    steps.add(approved
        ? 'Terminal: genehmigt'
        : 'Terminal: abgelehnt (${res.responseCode})');
    _emit(HpsEventKind.resolved, steps.last, id);
    return HpsResult(
      outcome:
          approved ? CardPaymentOutcome.approved : CardPaymentOutcome.declined,
      transactionId: id,
      response: res,
      steps: List<String>.unmodifiable(steps),
    );
  }

  /// Klaert einen offenen Ausgang: erst einmal abbrechen, dann abfragen --
  /// bis das Terminal etwas sagt oder das Budget aufgebraucht ist.
  ///
  /// Die Reihenfolge ist die gemessene, nicht die naheliegende. Zuerst zu
  /// pollen und erst abzubrechen, wenn der Status "laeuft noch" meldet, war
  /// wirkungslos: diesen Zustand meldet die Statusabfrage nie -- sie antwortet
  /// auf alles, was nicht genehmigt ist, mit
  /// [TransactionResponse.noStatementCode]. Der Abbruch ist der einzige
  /// Diskriminator und steht deshalb vorne.
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
  Future<HpsResult> _resolve(String id, List<String> steps) async {
    _emit(HpsEventKind.resolving, 'Ausgang offen, Klaerung laeuft', id);

    final clock = _clock()..start();

    final aborted = await _tryAbort(id, steps, clock);
    if (aborted != null) return aborted;

    var wait = Duration.zero;
    var transportFailures = 0;

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

      final settled = _fromResponse(status, id, steps);
      if (settled != null) return settled;

      steps.add(status.isNoStatement
          ? 'Status: keine Auskunft (${TransactionResponse.noStatementCode})'
          : 'Status: noch kein Ergebniscode');
      wait = _nextWait(wait);
    }

    steps.add('Ausgang bleibt offen');
    return _open(id, steps);
  }

  /// Versucht den Abbruch GENAU EINMAL.
  ///
  /// Liefert ein Ergebnis nur im einen beweisbaren Fall: das Terminal quittiert
  /// den Abbruch mit `responseCode == '0'`. Gemessen gelingt der Abbruch
  /// ausschliesslich, solange der Vorgang noch abbrechbar ist -- ein
  /// abgeschlossener (genehmigter) Vorgang antwortet mit `100010` und bleibt
  /// unangetastet. Ein quittierter Abbruch ist damit die positive Aussage
  /// "dieser Vorgang war nicht abgeschlossen und ist es jetzt auch nicht mehr":
  /// [CardPaymentOutcome.declined].
  ///
  /// In jedem anderen Fall `null` -- der Aufrufer pollt dann weiter. Das gilt
  /// ausdruecklich auch fuer eine Antwort OHNE Ergebniscode: eine Quittung
  /// allein hat keinen Beweiswert, sie koennte auch ein Zwischenstand sein.
  Future<HpsResult?> _tryAbort(
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
      // belegen ueber den Vorgang gar nichts.
      steps.add('Abbruch nicht bestaetigt ($e) -- ob er wirkte, ist offen, '
          'Ausgang wird abgefragt');
      _noteUnexpected(e, id);
      return null;
    }

    if (res.responseCode == null) {
      steps.add('Abbruch ohne Ergebniscode quittiert -- das beweist nichts, '
          'Ausgang wird abgefragt');
      return null;
    }
    if (!res.isApproved) {
      steps.add('Abbruch abgelehnt (${res.responseCode}) -- der Vorgang ist '
          'nicht mehr abbrechbar, Ausgang wird abgefragt');
      return null;
    }

    steps.add('Abbruch bestaetigt -- der Vorgang war noch abbrechbar, es ist '
        'nichts belastet');
    _emit(HpsEventKind.resolved, steps.last, id);
    return HpsResult(
      outcome: CardPaymentOutcome.declined,
      transactionId: id,
      response: res,
      steps: List<String>.unmodifiable(steps),
    );
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
  Future<HpsResult> _resolveCancel(String id, List<String> steps) async {
    _emit(HpsEventKind.resolving, 'Ausgang offen, Klaerung laeuft', id);

    final clock = _clock()..start();
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
        steps.add(status.isNoStatement
            ? 'Status: keine Auskunft (${TransactionResponse.noStatementCode})'
            : 'Status: Aufhebung noch nicht bestaetigt');
      }
      wait = _nextWait(wait);
    }

    steps.add('Ausgang bleibt offen');
    return _open(id, steps);
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
  HpsResult _open(String id, List<String> steps) {
    _emit(HpsEventKind.resolved, steps.last, id);
    return HpsResult(
      outcome: CardPaymentOutcome.unresolved,
      transactionId: id,
      steps: List<String>.unmodifiable(steps),
    );
  }

  /// Fuehrt [call] aus, aber hoechstens so lange, wie vom [resolveBudget]
  /// uebrig ist -- sonst waere die Klaerung nicht durch das Budget begrenzt,
  /// sondern durch [HpsClient.timeout] je einzelnem Request.
  ///
  /// [cap] deckelt zusaetzlich, wenn ein einzelner Schritt nicht das ganze
  /// verbleibende Budget verbrauchen darf -- siehe [_abortBudget].
  Future<T> _withinBudget<T>(
    Stopwatch clock,
    Future<T> Function() call, {
    Duration? cap,
  }) {
    var left = resolveBudget - clock.elapsed;
    if (cap != null && cap < left) left = cap;
    if (left <= Duration.zero) {
      throw TimeoutException('Klaerungsbudget aufgebraucht', resolveBudget);
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
