import 'dart:async';

import '../../kasseneck_api.dart';

/// Ergebnis einer Cloud-Kartenzahlung. Traegt IMMER die Kennung, damit der
/// Ausgang spaeter noch geklaert werden kann.
class HobexCloudResult {
  const HobexCloudResult({
    required this.outcome,
    required this.transactionId,
    this.receipt,
    this.steps = const <String>[],
  });

  final CardPaymentOutcome outcome;
  final String transactionId;

  /// Der letzte gelesene Beleg, sofern einer vorlag.
  final HobexReceipt? receipt;

  /// Verlauf der Klaerung, in Reihenfolge -- fuer Anzeige und Protokoll.
  final List<String> steps;

  bool get isApproved => outcome == CardPaymentOutcome.approved;

  /// Nur bei [CardPaymentOutcome.declined] steht fest, dass nichts belastet
  /// wurde.
  bool get mayRetrySafely => outcome == CardPaymentOutcome.declined;

  bool get isUnresolved => outcome == CardPaymentOutcome.unresolved;

  @override
  String toString() =>
      'HobexCloudResult(${outcome.name}, tx=$transactionId, steps=${steps.length})';
}

/// Kartenzahlung ueber die Hobex-Cloud mit geklaertem Ausgang.
///
/// Aufbau und Semantik folgen `HpsPayments` (im lokalen HPS-Zahlweg, siehe
/// dort): eine Zahlung, deren Ausgang geklaert statt geraten wird, mit
/// derselben eisernen Regel -- [CardPaymentOutcome.declined] entsteht
/// ausschliesslich aus einem vorhandenen Ergebniscode ungleich `'0'`. Ein
/// Transportfehler, ein Zeitablauf oder eine Antwort ohne Ergebniscode
/// fuehren NIE zu declined, sondern zu [CardPaymentOutcome.unresolved].
/// Genau diese Vermischung von Nichtwissen und Aussage hat am 24.08.2026
/// eine durchgelaufene Zahlung als Fehlschlag gemeldet und den Kunden ein
/// zweites Mal belastet.
///
/// Anders als `HpsPayments` kennt der Cloud-Weg kein `abort()`: es gibt kein
/// lokales Terminal, das einen laufenden Vorgang quittieren koennte. Bleibt
/// die erste Antwort aus, bleibt nur Klaeren -- wiederholtes Abfragen des
/// Standes ueber [KasseneckApi.hobexGetStatus] -- oder, wenn das Budget
/// aufgebraucht ist, Offenlassen.
///
/// [KasseneckApi.hobexGetStatus] unterscheidet zwei Ausgaenge, die hier
/// unterschiedlich behandelt werden (siehe deren Doc-Kommentar): `null`
/// heisst, der Dienst hat geantwortet und kennt zur Kennung nichts -- eine
/// Aussage, die den Transportfehler-Zaehler NICHT erhoeht. Eine geworfene
/// Ausnahme heisst, wir konnten gar nicht erst fragen -- ein Transportfehler,
/// der den Zaehler erhoeht und nach [maxTransportFailures] in Folge die
/// Klaerung vorzeitig mit [CardPaymentOutcome.unresolved] beendet, damit ein
/// toter Dienst den Mitarbeiter nicht das volle Budget lang warten laesst.
///
/// Die Kennung ist in JEDEM zurueckgegebenen Ergebnis gesetzt, auch bei
/// [CardPaymentOutcome.unresolved] -- ohne sie ist der Vorgang unauffindbar.
///
/// [HpsObserver]: derselbe Typ wie beim HPS-Zwilling -- er ist zahlwegneutral
/// und meldet hier dieselben Ereignisse (`resolving`/`resolved` sowie
/// unerwartete Fehler). Die Begruendung des Beobachters gilt fuer den
/// Cloud-Weg genauso: ohne Protokoll gibt es beim naechsten Vorfall wieder
/// keine Daten. Ein werfender Beobachter darf den Zahlweg NIEMALS mitreissen
/// -- siehe [_emit].
class HobexCloudPayments {
  HobexCloudPayments(
    this._api, {
    this.resolveBudget = const Duration(seconds: 90),
    this.maxBackoff = const Duration(seconds: 10),
    this.maxTransportFailures = 3,
    Future<void> Function(Duration)? sleep,
    Stopwatch Function()? clock,
    HpsObserver? observer,
  })  : _sleep = sleep ?? ((d) => Future<void>.delayed(d)),
        _clock = clock ?? Stopwatch.new,
        _observer = observer;

  final KasseneckApi _api;

  /// Wie lange insgesamt geklaert wird, bevor der Ausgang offen bleibt.
  final Duration resolveBudget;

  /// Obergrenze fuer den Abstand zwischen zwei Statusabfragen.
  final Duration maxBackoff;

  /// Nach so vielen Statusabfragen in Folge, die am Transport scheitern
  /// (also nicht abgefragt werden konnten), wird abgebrochen -- ein
  /// offensichtlich unerreichbarer Dienst soll den Mitarbeiter nicht das
  /// ganze Budget lang warten lassen. Das Ergebnis ist dann
  /// [CardPaymentOutcome.unresolved], niemals [CardPaymentOutcome.declined].
  /// Eine Antwort mit `null` (Dienst kennt die Kennung noch nicht) zaehlt
  /// NICHT dazu, siehe [KasseneckApi.hobexGetStatus].
  final int maxTransportFailures;

  final Future<void> Function(Duration) _sleep;

  /// Quelle der Uhr fuer das Budget. Wie [_sleep] eine Naht fuer Tests: eine
  /// Uhr, die nur durch die Pausen vorrueckt, macht das Ablaufen des Budgets
  /// nachpruefbar, statt es der Wanduhr zu ueberlassen.
  final Stopwatch Function() _clock;

  final HpsObserver? _observer;

  /// Kartenzahlung mit geklaertem Ausgang.
  ///
  /// [amount] und [tip] sind in Hauptwaehrungseinheiten (25 = 25,00 Euro).
  Future<HobexCloudResult> pay({
    required String transactionId,
    required num amount,
    num tip = 0,
    String? reference,
  }) async {
    if (transactionId.isEmpty) {
      // Ohne Kennung ist die Zusage "Kennung in JEDEM Ergebnis gesetzt"
      // wertlos -- geprueft, BEVOR ein Request hinausgeht.
      throw ArgumentError.value(
        transactionId,
        'transactionId',
        'darf nicht leer sein',
      );
    }

    final steps = <String>[];

    // Das try liegt bewusst ENG um den Netzweg: was danach kommt, ist unser
    // eigenes Auswerten und soll nicht stillschweigend als "Dienst hat nicht
    // geantwortet" durchgehen.
    HobexReceipt? receipt;
    try {
      receipt = await _api.hobexPay(
        transactionId: transactionId,
        amount: amount.toDouble(),
        tip: tip.toDouble(),
        reference: reference,
      );
    } catch (e) {
      // Bewusst JEDE Ausnahme, nicht nur einen bestimmten Typ: ein
      // Server-Fehler, ein Netzabbruch oder ein unlesbarer Rumpf duerfen die
      // Klaerung nur ausloesen, niemals an pay() vorbei als Fehlschlag nach
      // draussen dringen -- genau der Mechanismus des Vorfalls vom
      // 24.08.2026.
      steps.add('Zahlung abgebrochen: $e');
      _noteUnexpected(e, transactionId);
    }

    if (receipt != null) {
      final settled = _fromReceipt(receipt, transactionId, steps);
      if (settled != null) return settled;
      steps.add('Antwort ohne Ergebniscode -- Ausgang wird geklaert');
    }

    return _resolve(transactionId, steps);
  }

  /// Ordnet einen gelesenen Beleg ein. `null`, wenn er nichts entscheidet.
  ///
  /// Die eiserne Regel steht GENAU HIER und nirgends sonst: nur ein
  /// vorhandener, nicht-leerer `responseCode` ungleich `'0'` fuehrt zu
  /// [CardPaymentOutcome.declined]. Ein fehlender Code heisst "laeuft noch",
  /// nicht "abgelehnt".
  HobexCloudResult? _fromReceipt(
    HobexReceipt? receipt,
    String id,
    List<String> steps,
  ) {
    if (receipt == null) return null;
    final code = receipt.responseCode;
    if (code.isEmpty) return null;
    final approved = code == '0';
    steps.add(approved ? 'Hobex: genehmigt' : 'Hobex: abgelehnt ($code)');
    _emit(HpsEventKind.resolved, steps.last, id);
    return HobexCloudResult(
      outcome:
          approved ? CardPaymentOutcome.approved : CardPaymentOutcome.declined,
      transactionId: id,
      receipt: receipt,
      steps: List<String>.unmodifiable(steps),
    );
  }

  /// Klaert einen offenen Ausgang: abfragen, warten, wieder abfragen -- bis
  /// der Dienst etwas sagt oder das Budget aufgebraucht ist. Kein Abbruch:
  /// den kennt der Cloud-Weg nicht.
  Future<HobexCloudResult> _resolve(String id, List<String> steps) async {
    _emit(HpsEventKind.resolving, 'Ausgang offen, Klaerung laeuft', id);

    final clock = _clock()..start();
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

      HobexReceipt? receipt;
      try {
        // Ueber [_withinBudget]: sonst waere die Klaerung nicht durch
        // [resolveBudget] begrenzt, sondern durch den vollen readTimeout je
        // einzelner Abfrage -- eine kurz vor Budgetende gestartete Abfrage
        // haette die Zusage um bis zu readTimeout ueberziehen koennen.
        receipt = await _withinBudget(
          clock,
          () => _api.hobexGetStatus(transactionId: id),
        );
        // Nur eine BEANTWORTETE Abfrage setzt den Zaehler zurueck -- egal, ob
        // sie einen Beleg lieferte oder `null` (Dienst kennt die Kennung
        // noch nicht). Beides ist eine Aussage des Dienstes, kein
        // Transportfehler.
        transportFailures = 0;
      } catch (e) {
        // Wir konnten gar nicht erst fragen: Server-Fehler, Netz oder ein
        // unerwartetes Antwortformat. Das ist NIE eine Aussage ueber den
        // Vorgang und darf niemals als "nicht belastet" gelesen werden.
        transportFailures++;
        steps.add('Statusabfrage gescheitert ($transportFailures): $e');
        _noteUnexpected(e, id);
        if (transportFailures >= maxTransportFailures) {
          steps.add('Dienst antwortet nicht -- Ausgang bleibt offen');
          break;
        }
        wait = _nextWait(wait);
        continue;
      }

      final settled = _fromReceipt(receipt, id, steps);
      if (settled != null) return settled;

      steps.add('Status: laeuft noch');
      wait = _nextWait(wait);
    }

    steps.add('Ausgang bleibt offen');
    _emit(HpsEventKind.resolved, steps.last, id);
    return HobexCloudResult(
      outcome: CardPaymentOutcome.unresolved,
      transactionId: id,
      steps: List<String>.unmodifiable(steps),
    );
  }

  Duration _nextWait(Duration current) {
    if (current == Duration.zero) return const Duration(seconds: 1);
    final doubled = current * 2;
    return doubled > maxBackoff ? maxBackoff : doubled;
  }

  /// Meldet einen Fehler, der beim Netzweg oder beim eigenen Auswerten
  /// auftrat. Anders als beim HPS-Zwilling gibt es hier keine typisierte
  /// Ausnahme, die einen erwarteten Terminal-Fehler von einem eigenen Bug
  /// unterscheidet -- jede Ausnahme, die hier ankommt, ist deshalb meldenswert.
  void _noteUnexpected(Object error, String id) {
    final observer = _observer;
    if (observer == null) return;
    try {
      observer(HpsEvent(
        HpsEventKind.requestFailed,
        'Unerwarteter Fehler im Cloud-Zahlweg',
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

  /// Fuehrt [call] aus, aber hoechstens so lange, wie vom [resolveBudget]
  /// uebrig ist -- sonst waere die Klaerung nicht durch das Budget begrenzt,
  /// sondern durch den readTimeout je einzelnem Request.
  Future<T> _withinBudget<T>(Stopwatch clock, Future<T> Function() call) {
    final left = resolveBudget - clock.elapsed;
    if (left <= Duration.zero) {
      throw TimeoutException('Klaerungsbudget aufgebraucht', resolveBudget);
    }
    return call().timeout(left);
  }
}
