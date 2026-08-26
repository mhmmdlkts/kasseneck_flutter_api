import '../../kasseneck_api.dart';
import '../../models/hobex_receipt.dart';
import '../hobex_hps/hps_result.dart';

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
class HobexCloudPayments {
  HobexCloudPayments(
    this._api, {
    this.resolveBudget = const Duration(seconds: 90),
    this.maxBackoff = const Duration(seconds: 10),
    this.maxTransportFailures = 3,
    Future<void> Function(Duration)? sleep,
  }) : _sleep = sleep ?? ((d) => Future<void>.delayed(d));

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

  /// Kartenzahlung mit geklaertem Ausgang.
  ///
  /// [amount] und [tip] sind in Hauptwaehrungseinheiten (25 = 25,00 Euro).
  Future<HobexCloudResult> pay({
    required String transactionId,
    required num amount,
    num tip = 0,
    String? reference,
  }) async {
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
    final code = receipt?.responseCode;
    if (receipt == null || code == null || code.isEmpty) return null;
    final approved = code == '0';
    steps.add(approved ? 'Hobex: genehmigt' : 'Hobex: abgelehnt ($code)');
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
    final clock = Stopwatch()..start();
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
        receipt = await _api.hobexGetStatus(transactionId: id);
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
}
