import 'enums.dart';
import 'response_codes.dart';

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

  /// Ergebniscode `9003` ("Invalid Amount"): das Terminal weist den Betrag ab,
  /// BEVOR es die Karte anfordert.
  ///
  /// Am 28.08.2026 gemessen (TID 3600335): eine Zahlung ueber 99999,99 EUR
  /// antwortet nach 15,7 s mit diesem Code, ohne dass jemals eine Karte
  /// verlangt wurde. Es ist damit eine positive Aussage: nichts belastet.
  static const String invalidAmountCode = '9003';

  /// Ergebniscode `100019` ("Amount is not in a valid range"): der Betrag
  /// liegt ausserhalb des zulaessigen Bereichs.
  ///
  /// Am 27.08.2026 mit einem negativen Betrag gemessen. Wie
  /// [invalidAmountCode] eine Abweisung vor dem Kartenfluss -- nichts
  /// belastet.
  static const String amountOutOfRangeCode = '100019';

  /// Ergebniscode `100108` ("Invalid TID"): die uebergebene Terminal-Kennung
  /// gibt es an diesem Geraet nicht.
  ///
  /// Am 27.08.2026 gemessen, und am 28.08.2026 erneut ueber
  /// `GET /api/terminals/0/diagnosis`. Der Vorgang wird abgewiesen, bevor
  /// irgendetwas geschieht -- nichts belastet.
  static const String invalidTidCode = '100108';

  /// Ergebniscode `55` ("PIN falsch"): der Host hat die Autorisierung
  /// abgelehnt, weil die eingegebene PIN falsch war -- nichts belastet.
  ///
  /// Am 02.09.2026 im BETRIEB gemessen, nicht am Testgeraet: TID 3556988,
  /// HPS 1.11.4, Firmware 2.3.9. Die erste echte Host-Ablehnung, die je
  /// beobachtet wurde -- bis dahin war kein Code fuer "der Host sagt nein"
  /// bekannt (siehe `doc/kartenzahlung.md`, "Was weiterhin ungemessen ist").
  ///
  /// Zwei Befunde aus dieser Messung:
  /// - Die DIREKTE Antwort der Zahlung trug den Code, und die Statusabfrage
  ///   antwortete danach elfmal in Folge ebenfalls `55`. Anders als ein
  ///   abgebrochener oder ohne Karte beendeter Vorgang (danach
  ///   [noStatementCode]) wird eine vom Host abgelehnte Zahlung am Terminal
  ///   also AUFBEWAHRT und ist mit ihrem Ablehnungscode abrufbar.
  /// - Der Code ist zweistellig: ein Antwortcode des HOSTS (ISO 8583, 55 =
  ///   "Incorrect PIN"), kein `9xxx`-Terminalcode und kein `100xxx`-Code der
  ///   HPS-Anwendung. Daraus folgt KEINE Regel fuer andere zweistellige
  ///   Codes: in derselben Familie stehen Genehmigungen (`08`, `10`, `11`,
  ///   `85`). Jeder andere Host-Code bleibt eine Wissensluecke, bis er
  ///   gemessen ist.
  ///
  /// Was der Fall ohne diesen Eintrag gekostet hat: 90 Sekunden Klaerung ins
  /// Budget, ein Vorfall mit ungeklaertem Ausgang, ein stehender Merker und
  /// eine Rueckfrage an den Bediener -- fuer eine falsch getippte PIN.
  static const String wrongPinCode = '55';

  // ---- Antwortcodeliste von hobex, erhalten 11.09.2026 ----
  //
  // Bedeutung, Wirkung und Grund jedes Codes stehen in [HpsCodes.all]; hier
  // nur die Namen, damit Aufrufer und Tests nicht mit nackten Zahlen
  // arbeiten. Siehe `response_codes.dart` fuer die Einordnung vor/nach dem
  // Host.

  /// `100001` "Bad Request": fehlerhafte Anfrage der Kasse -- nichts belastet.
  static const String badRequestCode = '100001';

  /// `100004` "Card read failed": Karte nicht lesbar -- nichts belastet. Im
  /// Betrieb am 28.08.2026 gesehen (TID 3556988), damals ungedeutet.
  static const String cardReadFailedCode = '100004';

  /// `100005` "App select failed": Anwendungsauswahl gescheitert -- nichts
  /// belastet. Im Betrieb am 28.08.2026 gesehen, damals ungedeutet.
  static const String appSelectFailedCode = '100005';

  /// `100006` "Communication with TecsXml failed" (No auto-reversal) --
  /// Ausgang ungewiss, siehe [isHostUncertain].
  static const String hostCommunicationFailedCode = '100006';

  /// `100007` "Processing of TecsXml step failed" (No auto-reversal) --
  /// Ausgang ungewiss, siehe [isHostUncertain].
  static const String hostStepFailedCode = '100007';

  /// `100008` "Invalid TID" laut hobex. Am Geraet gemessen wurde fuer
  /// dieselbe Lage [invalidTidCode] (`100108`); beide gelten.
  static const String invalidTidDocumentedCode = '100008';

  /// `100009` "Invalid Tx Type": Vorgangstyp unbekannt -- nichts belastet.
  static const String invalidTxTypeCode = '100009';

  /// `100011` "Not Found": keine Aussage ueber den Vorgang, siehe
  /// [isNoStatement] fuer den Unterschied zu `9027`.
  static const String notFoundCode = '100011';

  /// `100012` "Max retries exceeded": zu viele Kartenversuche -- nichts
  /// belastet.
  static const String maxRetriesExceededCode = '100012';

  /// `100013` "Diagnosis failed" -- nichts belastet.
  static const String diagnosisFailedCode = '100013';

  /// `100014` "Card information wasn't entered" (MOTO) -- nichts belastet.
  static const String cardInfoNotEnteredCode = '100014';

  /// `100015` "Card declined": vom EMV-Kernel abgelehnt, vor dem Host --
  /// nichts belastet. Im Betrieb am 28. und 31.08.2026 gesehen, damals
  /// ungedeutet.
  static const String cardDeclinedCode = '100015';

  /// `100017` "Card Not Supported" -- nichts belastet.
  static const String cardNotSupportedCode = '100017';

  /// `100018` "Scep enrollment failed" -- nichts belastet.
  static const String scepEnrollmentFailedCode = '100018';

  /// `100020` "Refund password is invalid" -- nichts ausgezahlt.
  static const String refundPasswordInvalidCode = '100020';

  /// `100021` "Failed to enter the password" -- nichts ausgezahlt.
  static const String passwordNotEnteredCode = '100021';

  /// `100022` "Terminal is blocked": nicht IN_OPERATION -- nichts belastet.
  static const String terminalBlockedCode = '100022';

  /// `100023` "Invalid message type": ungueltige Host-Antwort -- Ausgang
  /// ungewiss, siehe [isHostUncertain].
  static const String invalidMessageTypeCode = '100023';

  /// `100024` "Transaction completion has failed" -- Ausgang ungewiss, siehe
  /// [isHostUncertain].
  static const String completionFailedCode = '100024';

  /// `100025` "Refund transactions are disabled" -- nichts ausgezahlt.
  static const String refundDisabledCode = '100025';

  /// `100026` "Transaction was declined." (Chip-Daten fuer eine Karte ohne
  /// Chip) -- Ausgang ungewiss, siehe [isHostUncertain].
  static const String chipDataMismatchCode = '100026';

  /// `100027` "Unsupported UserData in TecsXml Response" -- Ausgang ungewiss,
  /// siehe [isHostUncertain].
  static const String unsupportedUserDataCode = '100027';

  /// `100028` "Tip selection process has failed." -- nichts belastet.
  static const String tipSelectionFailedCode = '100028';

  /// `100029` "Communication with TecsXml timeout" (auto-reversal): das
  /// Terminal storniert selbst -- nichts belastet.
  static const String hostTimeoutReversedCode = '100029';

  /// `100998` "Terminal is busy" -- die Anfrage wurde nicht angenommen. Als
  /// HTTP-Status gemessen: `409`, siehe `HpsHttpException.isTerminalBusy`.
  static const String terminalBusyCode = '100998';

  /// `100999` "Internal Error": Sammelcode -- Ausgang ungewiss, siehe
  /// [isHostUncertain].
  static const String internalErrorCode = '100999';

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
  ///
  /// Bewusst NUR `9027`, nicht auch [notFoundCode] (`100011`, "Not Found"):
  /// auf `9027` ruht die Zwei-`9027`-Regel in `HpsPayments`, und die ist fuer
  /// genau diesen Code gemessen. `100011` ist dokumentiert, aber an keinem
  /// Geraet gesehen -- er ist ebenso keine Aussage (siehe [isConclusive]),
  /// traegt aber keine Schlussregel.
  bool get isNoStatement => responseCode == noStatementCode;

  /// `true`, wenn der Code einen Ausgang meldet, den das Terminal selbst nicht
  /// kennt: der hobex-Host war beteiligt, und das Terminal storniert nicht von
  /// sich aus (siehe [HpsCodeEffect.hostUncertain]).
  ///
  /// Keine Aussage -- aber eine andere als [isNoStatement]: ein spaeteres
  /// `9027` auf die Statusabfrage heisst hier NICHT "nichts belastet", denn es
  /// spiegelt nur den Speicher des Terminals, nicht den des Hosts.
  bool get isHostUncertain =>
      HpsCodes.lookup(responseCode)?.hostUncertain ?? false;

  /// Der Eintrag dieses Codes in [HpsCodes.all], oder `null`, wenn seine
  /// Bedeutung nicht feststeht bzw. kein Code vorliegt.
  HpsCode? get codeInfo => HpsCodes.lookup(responseCode);

  /// Worauf eine Kasse bei dieser Antwort reagiert -- `null` ohne Code,
  /// [HpsCodeReason.unknown] fuer einen Code ausserhalb der Tabelle.
  HpsCodeReason? get reason => HpsCodes.reasonOf(responseCode);

  /// `true`, wenn das Terminal einen technischen Fehler meldet
  /// ([technicalErrorCode]) -- gemessen im Zusammenhang mit einer nicht rein
  /// numerischen Kennung, aber keine Aussage ueber den Vorgang selbst.
  bool get isTechnicalError => responseCode == technicalErrorCode;

  /// `true`, wenn das Terminal den Vorgang als ungueltig abgewiesen hat
  /// ([invalidTransactionCode]) -- eine positive Aussage: nichts geschehen.
  bool get isInvalid => responseCode == invalidTransactionCode;

  /// `true`, wenn der Vorgang aufgehoben wurde ([transactionCanceledCode]).
  bool get isCanceled => responseCode == transactionCanceledCode;

  /// `true`, wenn ein Ergebniscode VORHANDEN ist, dessen Bedeutung aber nicht
  /// feststeht -- er fehlt in [HpsCodes.all].
  ///
  /// Der Unterschied zu [isNoStatement], [isTechnicalError] und
  /// [isHostUncertain] ist im Nachweistext bedeutsam, der im Belastungsstreit
  /// gelesen wird: "das Terminal kennt den Vorgang nicht" (9027), "das
  /// Terminal meldet einen technischen Fehler" (9900) und "der Host war
  /// beteiligt, das Terminal weiss es nicht" (etwa 100007) sind Aussagen ueber
  /// eine Wissensluecke. "Wir kennen diesen Code nicht" ist etwas anderes --
  /// eine Wissensluecke ueber unser eigenes Modell, nicht ueber den Vorgang.
  bool get isUnknownCode =>
      responseCode != null && HpsCodes.lookup(responseCode) == null;

  /// `true`, wenn diese Antwort ueberhaupt eine Aussage ueber den Ausgang
  /// traegt -- also einen Ergebniscode nennt, dessen Bedeutung feststeht und
  /// der in [HpsCodes.all] als [HpsCodeEffect.conclusive] gefuehrt wird.
  ///
  /// Nur eine solche Antwort darf einen Ausgang festschreiben. Alles andere
  /// -- ein fehlender Code, eine Wissensluecke ([isNoStatement],
  /// [isTechnicalError], [notFoundCode]), ein ungewisser Host-Ausgang
  /// ([isHostUncertain]) oder ein Code ausserhalb der Tabelle
  /// ([isUnknownCode]) -- ist ein Grund weiterzuklaeren, niemals ein
  /// Ergebnis. Bis 27.08.2026 war das eine Negativliste, die sich als
  /// Positivliste ausgab ("jeder Code ausser `null` und [noStatementCode]
  /// ist schluessig"); siehe die Messung zu [technicalErrorCode] oben, die
  /// diese Annahme widerlegt hat. Seit 11.09.2026 speist sich die Positivliste
  /// aus Messung UND der Antwortcodeliste von hobex -- siehe
  /// `response_codes.dart`.
  bool get isConclusive => HpsCodes.lookup(responseCode)?.conclusive ?? false;

  /// Wie [isConclusive], aber fuer die Antwort auf eine STATUSABFRAGE: ein
  /// Code, der die Anfrage selbst abweist ([HpsCode.rejectsRequest], etwa
  /// `100022` "Terminal is blocked" oder `100108` "Invalid TID"), sagt dort
  /// nichts ueber den gesuchten Vorgang -- nur, dass diese Abfrage nicht
  /// bedient wurde. Als `declined` gelesen, hiesse ein gesperrtes Terminal
  /// "die Zahlung ist nicht belastet".
  bool get isConclusiveAsStatus =>
      isConclusive && !(codeInfo?.rejectsRequest ?? false);

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
                : isHostUncertain
                    ? 'HOST_UNCERTAIN($responseCode)'
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
