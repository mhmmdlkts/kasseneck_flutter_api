import 'dart:async';

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
/// Regel, von der nicht abgewichen wird: [HpsOutcome.declined] entsteht
/// ausschliesslich aus einer Aussage des Terminals oder einem gelungenen
/// [HpsClient.abort]. Ein Transportfehler fuehrt NIE zu declined -- er trennt
/// "nicht angekommen" nicht von "angekommen, Antwort verloren". Genau diese
/// Verwechslung hat am 24.08.2026 eine echte Belastung als unbelastet
/// ausgewiesen und den Kunden ein zweites Mal belastet.
///
/// Die Kennung ist in JEDEM Ergebnis gesetzt, auch bei
/// [HpsOutcome.unresolved]: ohne sie sind Statusabfrage und Storno
/// unerreichbar.
class HpsPayments {
  HpsPayments(
    this._client, {
    this.resolveBudget = const Duration(seconds: 90),
    this.maxBackoff = const Duration(seconds: 10),
    this.maxTransportFailures = 3,
    Future<void> Function(Duration)? sleep,
    HpsObserver? observer,
  })  : _sleep = sleep ?? _realSleep,
        _observer = observer;

  final HpsClient _client;

  /// Wie lange insgesamt geklaert wird, bevor der Ausgang offen bleibt.
  ///
  /// Die Zusage gilt fuer die Klaerung als Ganzes, nicht nur fuer die Pausen
  /// dazwischen: jede Abfrage der Klaerung wird zusaetzlich mit der
  /// Restlaufzeit gedeckelt. Ohne das haette eine einzelne Abfrage bis
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
  /// dann [HpsOutcome.unresolved], niemals [HpsOutcome.declined].
  final int maxTransportFailures;

  final Future<void> Function(Duration) _sleep;
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

    try {
      final res = await _client.payment(
        amount: amount,
        tip: tip,
        reference: reference,
        transactionId: id,
      );
      final settled = _fromResponse(res, id, steps);
      if (settled != null) return settled;
      steps.add('Antwort ohne Ergebniscode -- Ausgang wird geklaert');
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
    }

    return _resolve(id, steps);
  }

  /// Ordnet eine Terminal-Antwort ein. `null`, wenn sie nichts entscheidet.
  ///
  /// Eine Antwort ohne `responseCode` entscheidet nichts: sie heisst "laeuft
  /// noch", nicht "abgelehnt".
  HpsResult? _fromResponse(
    TransactionResponse res,
    String id,
    List<String> steps,
  ) {
    if (res.isInProgress) return null;
    final approved = res.isApproved;
    steps.add(approved
        ? 'Terminal: genehmigt'
        : 'Terminal: abgelehnt (${res.responseCode})');
    _emit(HpsEventKind.resolved, steps.last, id);
    return HpsResult(
      outcome: approved ? HpsOutcome.approved : HpsOutcome.declined,
      transactionId: id,
      response: res,
      steps: List<String>.unmodifiable(steps),
    );
  }

  /// Klaert einen offenen Ausgang: abfragen, einmal abbrechen, weiter
  /// abfragen -- bis das Terminal etwas sagt oder das Budget aufgebraucht ist.
  Future<HpsResult> _resolve(String id, List<String> steps) async {
    _emit(HpsEventKind.resolving, 'Ausgang offen, Klaerung laeuft', id);

    final clock = Stopwatch()..start();
    var wait = Duration.zero;
    var transportFailures = 0;
    var abortTried = false;

    while (clock.elapsed < resolveBudget) {
      if (wait > Duration.zero) await _sleep(wait);

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
        if (transportFailures >= maxTransportFailures) {
          steps.add('Terminal antwortet nicht -- Ausgang bleibt offen');
          break;
        }
        wait = _nextWait(wait);
        continue;
      }

      final settled = _fromResponse(status, id, steps);
      if (settled != null) return settled;

      steps.add('Status: laeuft noch');

      if (!abortTried) {
        abortTried = true;
        try {
          await _withinBudget(clock, () => _client.abort(transactionId: id));
        } catch (e) {
          // Der Text darf keine Ursache behaupten, die nicht feststeht:
          // [steps] ist der Nachweis, der im Belastungsstreit angezeigt wird.
          steps.add(e is HpsConnectionException
              ? 'Abbruch nicht zugestellt ($e) -- ob er wirkte, ist offen, '
                  'weiter abfragen'
              : 'Abbruch abgelehnt ($e) -- Karte lag bereits an, weiter '
                  'abfragen');
          wait = _nextWait(wait);
          continue;
        }
        return _confirmAbort(id, steps, clock);
      }

      wait = _nextWait(wait);
    }

    steps.add('Ausgang bleibt offen');
    return _open(id, steps);
  }

  /// Prueft einen quittierten Abbruch mit einer zusaetzlichen Statusabfrage
  /// nach, bevor daraus [HpsOutcome.declined] wird.
  ///
  /// Ein 2xx auf dem Abbruchweg allein beweist NICHT, dass nichts belastet
  /// wurde. Dass das Terminal einen Abbruch nach dem Auflegen der Karte mit
  /// einem Fehler quittiert, ist mangels Testterminal ungeprueft. Traefe das
  /// nicht zu, wuerde hier eine echte Belastung zu "nichts belastet" erklaert
  /// -- genau der Schaden, den dieses Paket verhindern soll. Deshalb entsteht
  /// [HpsOutcome.declined] erst, wenn auch die Abfrage nichts Genehmigtes
  /// zeigt; scheitert sie, bleibt der Ausgang offen.
  Future<HpsResult> _confirmAbort(
    String id,
    List<String> steps,
    Stopwatch clock,
  ) async {
    steps.add('Abbruch quittiert -- wird durch eine Statusabfrage bestaetigt');

    TransactionResponse status;
    try {
      status = await _withinBudget(
        clock,
        () => _client.transactionStatus(transactionId: id),
      );
    } catch (e) {
      steps.add('Bestaetigung gescheitert ($e) -- Ausgang bleibt offen');
      return _open(id, steps);
    }

    if (status.isApproved) {
      steps.add('Trotz quittiertem Abbruch meldet das Terminal: genehmigt');
      _emit(HpsEventKind.resolved, steps.last, id);
      return HpsResult(
        outcome: HpsOutcome.approved,
        transactionId: id,
        response: status,
        steps: List<String>.unmodifiable(steps),
      );
    }

    steps.add('Abbruch bestaetigt -- es lag keine Karte an, nichts belastet');
    _emit(HpsEventKind.resolved, steps.last, id);
    return HpsResult(
      outcome: HpsOutcome.declined,
      transactionId: id,
      response: status,
      steps: List<String>.unmodifiable(steps),
    );
  }

  /// Der Ausgang bleibt offen. Die Kennung ist gesetzt, damit Statusabfrage
  /// und Storno erreichbar bleiben.
  HpsResult _open(String id, List<String> steps) {
    _emit(HpsEventKind.resolved, steps.last, id);
    return HpsResult(
      outcome: HpsOutcome.unresolved,
      transactionId: id,
      steps: List<String>.unmodifiable(steps),
    );
  }

  /// Fuehrt [call] aus, aber hoechstens so lange, wie vom [resolveBudget]
  /// uebrig ist -- sonst waere die Klaerung nicht durch das Budget begrenzt,
  /// sondern durch [HpsClient.timeout] je einzelnem Request.
  Future<T> _withinBudget<T>(Stopwatch clock, Future<T> Function() call) {
    final left = resolveBudget - clock.elapsed;
    if (left <= Duration.zero) {
      throw TimeoutException('Klaerungsbudget aufgebraucht', resolveBudget);
    }
    return call().timeout(left);
  }

  Duration _nextWait(Duration current) {
    if (current == Duration.zero) return const Duration(seconds: 1);
    final doubled = current * 2;
    return doubled > maxBackoff ? maxBackoff : doubled;
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
