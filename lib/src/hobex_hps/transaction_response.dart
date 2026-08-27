import 'enums.dart';

/// Result of a transaction request (payment, refund, pre-auth, capture, void,
/// AVT) or of a transaction-status (v2) query.
///
/// A response object is returned even when a payment is **declined**: declines
/// are signalled in the body, not by an exception. Exceptions are only thrown
/// for HTTP/transport errors.
///
/// **Careful — `responseCode != "0"` is NOT the test for a decline.** That
/// reading is what caused the double charge of 2026-08-24: [noStatementCode]
/// (`9027`) is a code other than `"0"` and yet says nothing at all — it stands
/// for "still running" just as much as for "aborted" or "never seen". Reading
/// it as a decline reports "nothing was charged, safe to retry" for a payment
/// that is running right now.
///
/// A decline is a **conclusive** code other than `"0"`. Use [isConclusive] to
/// ask whether this response settles anything, and only then [isApproved] to
/// ask which way; [isNoStatement] names the gap. A response that is not
/// conclusive is a reason to keep clarifying, never an outcome.
///
/// **Zweite Lehre, am 27.08.2026: [isConclusive] darf keine Negativliste
/// sein, die sich als Positivliste ausgibt.** Bis dahin galt "jeder Code
/// ausser `null` und [noStatementCode] ist schluessig" -- das unterstellt,
/// wir kennten bereits alle Codes, die KEINE Aussage sind. Gemessen an einem
/// hobex-HPS (TID 3600335, HPS 1.10.0, Firmware 7.3.6): die Statusabfrage
/// antwortete auf eine nicht rein numerische Kennung mit einem bis dahin
/// unbenannten Code, [technicalErrorCode] (`9900`, "Technical Error
/// Database") -- ueber die alte Regel schluessig, und der Klaerweg machte
/// daraus `declined` fuer einen Vorgang, unter dem tatsaechlich Geld
/// geflossen sein kann. Jetzt gilt die Umkehrung: [isConclusive] ist wahr nur
/// fuer einen Code, dessen Bedeutung GEMESSEN und hier BENANNT ist. Jeder
/// andere -- ob er wie ein Fehlercode aussieht oder nicht, ob er neu ist oder
/// schlicht nie gemessen wurde -- ist eine Wissensluecke, siehe
/// [isUnknownCode].
class TransactionResponse {
  const TransactionResponse({
    required this.raw,
    this.transactionId,
    this.originalTransactionId,
    this.tid,
    this.receipt,
    this.approvalCode,
    this.reference,
    this.transactionDate,
    this.cardNumber,
    this.cardExpiry,
    this.brand,
    this.cardIssuer,
    this.transactionType,
    this.currency,
    this.amount,
    this.tip,
    this.responseCode,
    this.responseText,
    this.cvm,
    this.bin,
    this.statusCode,
    this.statusText,
    this.state,
    this.cleared,
    this.source,
    this.approvalDate,
    this.actionCode,
    this.aid,
    this.vu,
  });

  /// Unique transaction identifier (echoed / generated). Store this to later
  /// void or query the transaction.
  final String? transactionId;

  /// Identifier of the original transaction (for capture / refund / void).
  final String? originalTransactionId;

  /// Terminal identifier.
  final String? tid;

  /// Receipt number.
  final String? receipt;

  /// Authorization / approval code.
  final String? approvalCode;

  /// Reference echoed from the request (`null` if none was sent).
  final String? reference;

  /// Transaction date/time as returned by the terminal.
  final String? transactionDate;

  /// Masked card number (PAN).
  final String? cardNumber;

  /// Card expiry, format `YYMM`.
  final String? cardExpiry;

  /// Card brand, e.g. `Visa`, `MasterCard`, `Maestro`.
  final String? brand;

  /// Card issuer.
  final String? cardIssuer;

  /// Transaction type, e.g. `SELL`, `PREAUTH`, `CAPTURE`, `VOID`, `REFUND`.
  final String? transactionType;

  /// Currency (ISO 4217 alpha), e.g. `EUR`.
  final String? currency;

  /// Transaction amount.
  final num? amount;

  /// Tip amount.
  final num? tip;

  /// Response code. `"0"` means approved. `null` (status v2 only) means the
  /// transaction is still in progress — see [isInProgress]. An empty string
  /// from the terminal is normalised to `null` by [fromJson]: an empty code
  /// carries no more information than a missing one, and treating it as a
  /// real (non-`"0"`) code would misreport an unresolved outcome as
  /// declined.
  ///
  /// Nicht jeder vorhandene Code ungleich `"0"` ist eine Ablehnung:
  /// [noStatementCode] ist eine Wissensluecke, siehe [isConclusive].
  final String? responseCode;

  /// Human readable response text.
  final String? responseText;

  /// Cardholder verification method.
  final Cvm? cvm;

  /// BIN — the first 6 digits of the PAN.
  final String? bin;

  // ---- transaction-status (v2) only ----

  /// Mapped status code (from HOC). Status v2 only.
  final String? statusCode;

  /// Mapped status text (from HOC). Status v2 only.
  final String? statusText;

  /// Transaction state, e.g. `OK`, `VOID`, `FAILED`. Status v2 only.
  final String? state;

  /// Whether the transaction has already been cleared. Status v2 only.
  final bool? cleared;

  /// What triggered the transaction, e.g. `API`, `ECR`. Status v2 only.
  final String? source;

  /// Approval date. Status v2 only.
  final String? approvalDate;

  /// Action code. Status v2 only.
  final String? actionCode;

  /// EMV Application Identifier. Status v2 only.
  final String? aid;

  /// Merchant id (Vertragsunternehmen). Status v2 only.
  final String? vu;

  /// The raw decoded JSON, for fields not modelled explicitly.
  final Map<String, dynamic> raw;

  /// Ergebniscode `9027` ("Original Tx not found"): das Terminal hat
  /// geantwortet, sagt zu dieser Kennung aber NICHTS aus.
  ///
  /// Am 26.08.2026 an einem hobex-HPS gemessen (TID 3600335, HPS 1.10.0,
  /// Firmware 7.3.6, Host `tecstest.hobex.at`): die Statusabfrage antwortet
  /// mit `9027` gleichermassen auf eine Kennung, die das Terminal nie gesehen
  /// hat, auf einen gerade LAUFENDEN Kartenfluss, auf einen Vorgang, bei dem
  /// die Karte nicht aufgelegt wurde, und auf einen abgebrochenen Vorgang.
  /// Nur eine bereits genehmigte Zahlung antwortet mit `"0"`, und dieser Wert
  /// bleibt danach erhalten.
  ///
  /// Die Zahl ist deshalb nicht willkuerlich gewaehlt: sie ist der einzige
  /// Code, mit dem diese Firmware "keine Auskunft" ausdrueckt. Sie ist
  /// ausdruecklich KEIN Ergebnis. `9027` ueber `!= "0"` als Ablehnung zu
  /// lesen, erklaert einen laufenden Vorgang zu "nichts belastet, Wiederholung
  /// gefahrlos" -- und erzeugt damit genau die Doppelbelastung vom
  /// 24.08.2026.
  static const String noStatementCode = '9027';

  /// Ergebniscode `9011` ("Transaction Canceled"): der Vorgang unter dieser
  /// Kennung wurde aufgehoben.
  ///
  /// Ebenfalls am 26.08.2026 gemessen: nach einem erfolgreichen Void
  /// antwortet die Statusabfrage auf die Kennung der ORIGINALZAHLUNG mit
  /// `9011` / "Transaction Canceled" -- waehrend [state] auf dieser Firmware
  /// `null` bleibt. Fuer die Zahlung selbst heisst `9011`: es steht nichts
  /// mehr belastet.
  static const String transactionCanceledCode = '9011';

  /// Ergebniscode `100010`: der Vorgang ist NICHT MEHR ABBRECHBAR.
  ///
  /// Am 26.08.2026 gemessen: [HpsClient.abort] antwortet damit, sobald der
  /// Vorgang abgeschlossen (genehmigt) ist -- die genehmigte Zahlung bleibt
  /// dabei unangetastet. Es ist der einzige gemessene Fehlschlagcode des
  /// Abbruchs; jeder ANDERE Code ungleich `"0"` auf dem Abbruchweg ist
  /// unbekannten Ursprungs und rechtfertigt keine Aussage ueber die Ursache.
  static const String notAbortableCode = '100010';

  /// Ergebniscode `100002` ("Aborted"): der Zahlungs- oder Gutschriftvorgang
  /// wurde abgebrochen, bevor er zu Ende gefuehrt wurde.
  ///
  /// Am 26.08.2026 gemessen: die DIREKTE Antwort einer Zahlung bzw.
  /// Gutschrift traegt diesen Code, wenn der Vorgang abgebrochen wurde (etwa
  /// durch [HpsClient.abort]). Fuer den Vorgang selbst heisst das: es steht
  /// nichts belastet.
  static const String abortedCode = '100002';

  /// Ergebniscode `100003` ("Card not present"): die Karte wurde nicht
  /// aufgelegt.
  ///
  /// Ebenfalls am 26.08.2026 gemessen: die DIREKTE Antwort einer Zahlung
  /// traegt diesen Code, wenn der Kartenfluss ohne aufgelegte Karte endete.
  static const String cardNotPresentCode = '100003';

  /// Ergebniscode `9002` ("Invalid Transaction"): das Terminal hat den
  /// Vorgang als UNGUELTIG abgewiesen -- eine positive Aussage, dass nichts
  /// geschehen ist.
  ///
  /// Am 27.08.2026 an einem hobex-HPS gemessen (TID 3600335, HPS 1.10.0,
  /// Firmware 7.3.6): eine Gutschrift auf eine unbekannte, REIN NUMERISCHE
  /// Original-Kennung antwortet nach 1,2 Sekunden mit `9002` -- ohne
  /// Kartenfluss, ohne Auszahlung, die Karte wurde nie angefordert. Anders
  /// als bei [noStatementCode] (`9027`, "ich habe dazu keinen Eintrag")
  /// verwirft das Terminal hier den Vorgang selbst als unzulaessig, BEVOR
  /// irgendetwas in Bewegung kommt.
  ///
  /// Bemerkenswert zur Einordnung: dieselbe Lage mit einer NICHT rein
  /// numerischen Kennung ergab [technicalErrorCode] (`9900`) statt `9002` --
  /// derselbe abgelehnte Vorgang, aber ein anderer Code, weil die Kennung
  /// selbst schon den frueheren Fehler ausloeste. `9002` ist deshalb nur fuer
  /// eine Kennung gemessen, die [HpsClient]s Ziffernpruefung besteht.
  static const String invalidTransactionCode = '9002';

  /// Ergebniscode `9900` ("Technical Error Database").
  ///
  /// Am 27.08.2026 an einem hobex-HPS gemessen (TID 3600335, HPS 1.10.0,
  /// Firmware 7.3.6): eine Statusabfrage auf eine nicht rein numerische
  /// Kennung antwortet DAUERHAFT mit diesem Code -- auch dann, wenn unter
  /// dieser Kennung eine echte Zahlung lief (Karte gelesen, Kryptogramm
  /// vorhanden). Siehe [HpsClient] fuer die Ziffernpruefung, die das fuer
  /// jede selbst geschickte Kennung ausschliesst.
  ///
  /// Was hier NICHT feststeht: ob `9900` AUSSCHLIESSLICH bei einer
  /// nicht-numerischen Kennung auftritt, oder ob dieselbe "Technical Error
  /// Database"-Meldung auch andere Ursachen haben kann (der Name legt einen
  /// allgemeineren Datenbankfehler nahe). Gemessen ist nur der EINE
  /// Zusammenhang oben -- der Nachweistext darf deshalb keine Ursache
  /// behaupten, siehe `HpsPayments`.
  static const String technicalErrorCode = '9900';

  /// Ergebniscodes, deren Bedeutung GEMESSEN und hier benannt ist, und die
  /// einen Ausgang FESTSCHREIBEN -- siehe [isConclusive]. [noStatementCode]
  /// (`9027`) gehoert bewusst NICHT dazu: er ist zwar ebenso gemessen und
  /// benannt, sagt aber ausdruecklich NICHTS aus (siehe [isNoStatement]).
  /// Ebenso [technicalErrorCode] (`9900`): gemessen, benannt, aber keine
  /// Aussage ueber den Vorgang (siehe [isTechnicalError]).
  static const Set<String> _knownOutcomeCodes = <String>{
    '0',
    transactionCanceledCode,
    notAbortableCode,
    abortedCode,
    cardNotPresentCode,
    invalidTransactionCode,
  };

  /// `true` when the transaction was approved (`responseCode == "0"`).
  bool get isApproved => responseCode == '0';

  /// `true` when a status query reports the transaction is still running
  /// (`responseCode == null`).
  ///
  /// Achtung: die gemessene Firmware nutzt dafuer NICHT den fehlenden Code,
  /// sondern [noStatementCode]. Ein fehlender Code bleibt trotzdem eine
  /// Nicht-Aussage und wird genauso behandelt -- siehe [isConclusive].
  bool get isInProgress => responseCode == null;

  /// `true`, wenn ein [HpsClient.abort] daran scheiterte, dass der Vorgang
  /// nicht mehr abbrechbar war ([notAbortableCode]).
  bool get isNotAbortable => responseCode == notAbortableCode;

  /// `true`, wenn das Terminal zu dieser Kennung keine Auskunft gibt
  /// ([noStatementCode]).
  bool get isNoStatement => responseCode == noStatementCode;

  /// `true`, wenn das Terminal einen technischen Fehler meldet
  /// ([technicalErrorCode]) -- gemessen im Zusammenhang mit einer nicht rein
  /// numerischen Kennung, aber keine Aussage ueber den Vorgang selbst.
  bool get isTechnicalError => responseCode == technicalErrorCode;

  /// `true`, wenn das Terminal den Vorgang als ungueltig abgewiesen hat
  /// ([invalidTransactionCode]) -- eine positive Aussage: nichts geschehen.
  bool get isInvalid => responseCode == invalidTransactionCode;

  /// `true`, wenn der Vorgang aufgehoben wurde ([transactionCanceledCode]).
  bool get isCanceled => responseCode == transactionCanceledCode;

  /// `true`, wenn ein Ergebniscode VORHANDEN ist, aber weder ein GEMESSENES
  /// Ergebnis benennt ([isConclusive]) noch eine der beiden gemessenen
  /// Wissensluecken ist ([isNoStatement], [isTechnicalError]).
  ///
  /// Der Unterschied zu [isNoStatement] und [isTechnicalError] ist im
  /// Nachweistext bedeutsam, der im Belastungsstreit gelesen wird: "das
  /// Terminal kennt den Vorgang nicht" (9027) und "das Terminal meldet einen
  /// technischen Fehler" (9900) sind beides GEMESSENE Aussagen ueber eine
  /// Wissensluecke. "Wir kennen diesen Code nicht" ist etwas anderes -- eine
  /// Wissensluecke ueber unser eigenes Modell, nicht ueber den Vorgang.
  bool get isUnknownCode =>
      responseCode != null &&
      !isConclusive &&
      !isNoStatement &&
      !isTechnicalError;

  /// `true`, wenn diese Antwort ueberhaupt eine Aussage ueber den Ausgang
  /// traegt -- also einen Ergebniscode nennt, dessen Bedeutung GEMESSEN und
  /// in [_knownOutcomeCodes] benannt ist.
  ///
  /// Nur eine solche Antwort darf einen Ausgang festschreiben. Alles andere
  /// -- ein fehlender Code, eine gemessene Wissensluecke ([isNoStatement],
  /// [isTechnicalError]) oder ein schlicht nie gemessener Code
  /// ([isUnknownCode]) -- ist ein Grund weiterzuklaeren, niemals ein
  /// Ergebnis. Bis 27.08.2026 war das eine Negativliste, die sich als
  /// Positivliste ausgab ("jeder Code ausser `null` und [noStatementCode]
  /// ist schluessig"); siehe die Messung zu [technicalErrorCode] oben, die
  /// diese Annahme widerlegt hat.
  bool get isConclusive => _knownOutcomeCodes.contains(responseCode);

  factory TransactionResponse.fromJson(Map<String, dynamic> json) {
    return TransactionResponse(
      raw: json,
      transactionId: json['transactionId'] as String?,
      originalTransactionId: json['originalTransactionId'] as String?,
      tid: json['tid'] as String?,
      receipt: json['receipt'] as String?,
      approvalCode: json['approvalCode'] as String?,
      reference: json['reference'] as String?,
      transactionDate: json['transactionDate'] as String?,
      cardNumber: json['cardNumber'] as String?,
      cardExpiry: json['cardExpiry'] as String?,
      brand: json['brand'] as String?,
      cardIssuer: json['cardIssuer'] as String?,
      transactionType: json['transactionType'] as String?,
      currency: json['currency'] as String?,
      amount: _num(json['amount']),
      tip: _num(json['tip']),
      responseCode: _nonEmpty(json['responseCode']?.toString()),
      responseText: json['responseText'] as String?,
      cvm: Cvm.fromValue(json['cvm']),
      bin: json['bin'] as String?,
      statusCode: json['statusCode']?.toString(),
      statusText: json['statusText'] as String?,
      state: json['state'] as String?,
      cleared: json['cleared'] as bool?,
      source: json['source'] as String?,
      approvalDate: json['approvalDate'] as String?,
      actionCode: json['actionCode'] as String?,
      aid: json['aid'] as String?,
      vu: json['vu'] as String?,
    );
  }

  static num? _num(Object? v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  /// Ein leerer String ist kein Ergebniscode -- er traegt keine Aussage und
  /// wird deshalb wie ein fehlendes Feld behandelt (`isInProgress == true`),
  /// statt ueber `!= '0'` faelschlich als Ablehnung durchzugehen.
  static String? _nonEmpty(String? v) => (v == null || v.isEmpty) ? null : v;

  @override
  String toString() {
    final outcome = isInProgress
        ? 'IN_PROGRESS'
        : isNoStatement
            ? 'NO_STATEMENT($responseCode)'
            : isTechnicalError
                ? 'TECHNICAL_ERROR($responseCode)'
                : isApproved
                    ? 'APPROVED'
                    : isConclusive
                        ? 'DECLINED($responseCode)'
                        : 'UNKNOWN_CODE($responseCode)';
    return 'TransactionResponse($outcome, type=$transactionType, '
        'amount=$amount $currency, brand=$brand, card=$cardNumber, '
        'approval=$approvalCode, tx=$transactionId, text=$responseText)';
  }
}
