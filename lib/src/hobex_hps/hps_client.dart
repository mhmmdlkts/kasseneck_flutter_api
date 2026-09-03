import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'diagnosis.dart';
import 'enums.dart';
import 'exceptions.dart';
import 'observer.dart';
import 'terminal_info.dart';
import 'transaction_response.dart';

/// Client for the local **hobex Payment Service (HPS)** REST API.
///
/// By default it talks to `http://127.0.0.1:8080`, which is correct when the
/// app runs **on the terminal itself**. For remote testing from a dev machine,
/// pass a [baseUrl] pointing at the terminal's IP, e.g.
/// `Uri.parse('http://192.168.0.187:8080')`.
///
/// The [tid] is normalized by the client itself: a leading zero (e.g.
/// `03600335`) is stripped, so callers may pass the tid as printed on the
/// terminal without worrying about the format HPS expects.
class HpsClient {
  HpsClient({
    Uri? baseUrl,
    required String tid,
    this.defaultCurrency = 'EUR',
    this.defaultLanguage,
    this.timeout = const Duration(minutes: 3),
    http.Client? httpClient,
    this._observer,
  })  : baseUrl = baseUrl ?? Uri.parse('http://127.0.0.1:8080'),
        tid = _normalizeTid(tid),
        _http = httpClient,
        _ownsHttpClient = httpClient == null;

  /// Base URL of the HPS. Defaults to `http://127.0.0.1:8080`.
  final Uri baseUrl;

  /// Terminal identifier — normalisiert (ohne fuehrende Null).
  final String tid;

  /// Currency used when a request does not specify one. Defaults to `EUR`.
  final String defaultCurrency;

  /// Terminal UI language (`DE` / `IT` / `SI`) used when not specified.
  final String? defaultLanguage;

  /// Request timeout. Defaults to 3 minutes because card-present transactions
  /// block until the cardholder has interacted with the terminal.
  final Duration timeout;

  /// Injizierter HTTP-Client (Tests). `null`, wenn der Client selbst erzeugt
  /// wird -> dann pro Request eine frische, kurzlebige Verbindung.
  final http.Client? _http;
  final bool _ownsHttpClient;

  /// Beobachter fuer Ereignisse im Zahlweg (Protokoll der App). Optional.
  final HpsObserver? _observer;

  /// Laengengrenze der Transaktionskennung laut HPS-REST-Spezifikation --
  /// UND die Kennung muss rein numerisch sein, siehe [_checkTransactionId].
  static const int _maxTransactionIdLength = 18;

  static final RegExp _numericTransactionId = RegExp(r'^\d+$');

  /// Prueft eine Kennung, die ans Terminal geht: nicht leer, hoechstens
  /// [_maxTransactionIdLength] Zeichen, UND rein numerisch. Wirft
  /// [ArgumentError], BEVOR irgendetwas hinausgeht.
  ///
  /// Die HPS-Schnittstelle verlangt laut hobex-Dokumentation eine NUMERISCHE
  /// Kennung -- das war schon immer so. Bis zu dieser Pruefung wurde nur die
  /// Laenge kontrolliert; ein Aufrufer konnte diesen dokumentierten Vertrag
  /// also verletzen, ohne dass irgendetwas widersprach (der Bestandstest
  /// schickte ungeprueft 'TX-7').
  ///
  /// Was das Verletzen kostet, am 27.08.2026 an einem hobex-HPS gemessen (TID
  /// 3600335, HPS 1.10.0, Firmware 7.3.6): eine nicht rein numerische
  /// Kennung (z.B. 'A1787860907') wird von einer ECHTEN Kartenzahlung
  /// anstandslos angenommen -- panEntryMode CTLS, PAN gelesen, Kryptogramm
  /// vorhanden, transactionType SELL, Geld kann geflossen sein --, doch jede
  /// spaetere Statusabfrage auf GENAU diese Kennung antwortet DAUERHAFT mit
  /// [TransactionResponse.technicalErrorCode] (`9900`, "Technical Error
  /// Database"), egal was am Terminal tatsaechlich geschah. Eine rein
  /// numerische, nie gesehene Kennung bekommt dagegen die erwartbare Antwort
  /// (`9027`, siehe [transactionStatus]). Der Vorgang unter einer
  /// nicht-numerischen Kennung ist damit fuer IMMER unauffindbar -- erst wird
  /// das Geld bewegt, dann der Nachweis vernichtet. Derselbe Mechanismus wie
  /// beim Vorfall vom 24.08.2026 (Faden zur Kennung zerstoert), nur
  /// ausgeloest durch einen Eingabewert statt durch eine ausbleibende
  /// Antwort. Deshalb steht die Pruefung HIER, vor jedem Netzweg -- nicht
  /// erst, wenn eine Statusabfrage schon ins Leere laeuft.
  ///
  /// Das Risiko in der Praxis ist gering, nicht abstrakt: jeder Erzeuger im
  /// Oekosystem liefert bereits rein numerische Kennungen
  /// ([newTransactionId], `Order.createTransactionId()` in sastre, der
  /// JS-Zwilling). Der Fall greift nur, wenn ein Aufrufer eine EIGENE Kennung
  /// uebergibt -- das erlaubt `CreditCardProvider.custom` ausdruecklich.
  /// Diese Pruefung schliesst genau diese Luecke, sie ist keine allgemeine
  /// Warnung vor einem instabilen Geraet.
  static void _checkTransactionId(String value, String paramName) {
    if (value.isEmpty ||
        value.length > _maxTransactionIdLength ||
        !_numericTransactionId.hasMatch(value)) {
      throw ArgumentError.value(
        value,
        paramName,
        'HPS erlaubt 1 bis $_maxTransactionIdLength Ziffern (rein '
        'numerisch)',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Transactions
  // ---------------------------------------------------------------------------

  /// Triggers a **sale / purchase**. The terminal prompts for a card and this
  /// call resolves once the card flow is complete.
  ///
  /// [amount] is in major units (e.g. `1.50` for € 1,50). A [transactionId] is
  /// generated automatically when omitted; it is returned on the response so
  /// you can store it for a later void or status query.
  Future<TransactionResponse> payment({
    required num amount,
    num? tip,
    String? forceTip,
    String? reference,
    String? transactionId,
    String? currency,
    String? language,
  }) {
    final body = _txBody(
      amount: amount,
      tip: tip,
      forceTip: forceTip,
      reference: reference,
      transactionId: transactionId ?? newTransactionId(),
      currency: currency,
      language: language,
      transactionType: HpsTransactionType.sale.code,
    );
    return _sendTransaction('POST', 'api/transaction/payment', body);
  }

  /// Triggers a **pre-authorization** (blocks an amount on the card).
  /// Must be activated by hobex.
  Future<TransactionResponse> preAuth({
    required num amount,
    String? reference,
    String? transactionId,
    String? currency,
    String? language,
  }) {
    final body = _txBody(
      amount: amount,
      reference: reference,
      transactionId: transactionId ?? newTransactionId(),
      currency: currency,
      language: language,
    );
    return _sendTransaction('POST', 'api/transaction/preauth', body);
  }

  /// **Captures** a former pre-authorization identified by
  /// [preAuthTransactionId]. Must be activated by hobex.
  Future<TransactionResponse> preAuthCapture({
    required String preAuthTransactionId,
    required num amount,
    String? reference,
    String? currency,
    String? language,
  }) {
    final body = _txBody(
      amount: amount,
      reference: reference,
      transactionId: preAuthTransactionId,
      currency: currency,
      language: language,
    );
    return _sendTransaction('POST', 'api/transaction/preauthcapture', body);
  }

  /// **Cancels** a former pre-authorization (releases the blocked amount).
  /// Must be activated by hobex.
  Future<TransactionResponse> preAuthCancel({
    required String preAuthTransactionId,
    required num amount,
    String? reference,
    String? currency,
  }) {
    final body = _txBody(
      amount: amount,
      reference: reference,
      transactionId: preAuthTransactionId,
      currency: currency,
    );
    return _sendTransaction('DELETE', 'api/transaction/preauth', body);
  }

  /// Triggers a **refund** (credit). Pass [originalTransactionId] for a
  /// referenced refund. Must be activated by hobex; the terminal asks for a
  /// password.
  Future<TransactionResponse> refund({
    required num amount,
    String? originalTransactionId,
    String? reference,
    String? transactionId,
    String? currency,
    String? language,
  }) {
    final body = _txBody(
      amount: amount,
      reference: reference,
      transactionId: transactionId ?? newTransactionId(),
      currency: currency,
      language: language,
      originalTransactionId: originalTransactionId,
    );
    return _sendTransaction('POST', 'api/transaction/refund', body);
  }

  /// **Voids / cancels / reverses** an existing transaction identified by
  /// [transactionId]. Must be activated by hobex.
  ///
  /// [amount] ist ERFORDERLICH: das Terminal weist einen Void ohne Betrag mit
  /// `400 Missing amount` ab. Die REST-PDF v1.13 listet den Parameter zwar
  /// nicht, die Postman-Collection und die Firmware verlangen ihn; am
  /// 26.08.2026 am HPS nachgemessen und bestaetigt.
  /// [currency]/[language] fallen auf die Client-Defaults zurueck.
  ///
  /// Die Antwort auf diesen Aufruf betrifft die AUFHEBUNG selbst: gemessen
  /// `responseCode '0'`, `transactionType 'VOID'`, eigener Beleg,
  /// `originalTransactionId` auf die Originalzahlung -- und eine EIGENE, neue
  /// `transactionId` fuer die Aufhebung. Die hier uebergebene
  /// [transactionId] bleibt die der Originalzahlung; eine spaetere
  /// Statusabfrage darauf liefert deren Zustand, nicht den der Aufhebung
  /// (siehe `HpsPayments.cancel`).
  ///
  /// Set [technicalCancel] to indicate a technical cancellation.
  Future<TransactionResponse> cancel({
    required String transactionId,
    required num amount,
    String? currency,
    String? language,
    bool technicalCancel = false,
  }) {
    _checkTransactionId(transactionId, 'transactionId');
    final lang = language ?? defaultLanguage;
    final uri = _uri('api/transaction/payment/$tid/$transactionId', {
      'amount': amount.toString(),
      'currency': currency ?? defaultCurrency,
      'language': ?lang,
      if (technicalCancel) 'technicalCancel': 'true',
    });
    return _sendTransactionUri('DELETE', uri, null);
  }

  /// **Aborts** an ongoing transaction, as long as it has not passed the point
  /// where the terminal can still take it back.
  ///
  /// Liefert die volle [TransactionResponse] -- der `responseCode` ist die
  /// eigentliche Auskunft, nicht der HTTP-Status.
  ///
  /// Am 26.08.2026 an einem hobex-HPS gemessen (TID 3600335, HPS 1.10.0,
  /// Firmware 7.3.6):
  ///
  /// - laeuft der Kartenfluss noch, antwortet der Abbruch mit
  ///   `responseCode == '0'` und greift;
  /// - ist der Vorgang abgeschlossen (genehmigt), antwortet er mit
  ///   `responseCode == '100010'` und greift NICHT -- die genehmigte Zahlung
  ///   bleibt dabei unangetastet.
  ///
  /// Und zwar beides mit **HTTP 200**. Deshalb reicht es nicht, nur bei
  /// Nicht-2xx zu werfen und sonst die `transactionId` herauszugeben: ein
  /// gescheiterter Abbruch saehe dann aus wie ein geglueckter, und aus einer
  /// echten Belastung wuerde "nichts belastet".
  ///
  /// Der Abbruch ist damit der Diskriminator, den die Statusabfrage nicht
  /// liefert: sie antwortet auf jeden nicht genehmigten Vorgang mit
  /// [TransactionResponse.noStatementCode].
  Future<TransactionResponse> abort({required String transactionId}) {
    _checkTransactionId(transactionId, 'transactionId');
    final uri = _uri('api/transaction/abort/$tid/$transactionId', null);
    return _sendTransactionUri('POST', uri, null);
  }

  /// Starts an **account verification transaction** (AVT) — a zero-amount check
  /// of the card.
  Future<TransactionResponse> accountVerification({
    String? reference,
    String? transactionId,
    String? currency,
  }) {
    final body = _txBody(
      amount: 0,
      reference: reference,
      transactionId: transactionId ?? newTransactionId(),
      currency: currency,
    );
    return _sendTransaction('POST', 'api/transaction/avt/', body);
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  /// Queries the **status** of a transaction (v2). Useful to recover the result
  /// after a connection dropped mid-payment.
  ///
  /// Achtung, am 26.08.2026 gemessen: diese Abfrage unterscheidet WENIGER, als
  /// ihr Name nahelegt. Sie antwortet nur fuer eine genehmigte Zahlung mit
  /// `'0'`; auf alles andere -- laufender Kartenfluss, Karte nicht aufgelegt,
  /// abgebrochen, Kennung nie gesehen -- antwortet sie einheitlich mit
  /// [TransactionResponse.noStatementCode] (`9027`, "Original Tx not found").
  /// Nach einer Aufhebung antwortet sie auf die Kennung der Originalzahlung
  /// mit [TransactionResponse.transactionCanceledCode] (`9011`).
  ///
  /// `9027` ist deshalb KEIN Ergebnis, sondern ein Grund, weiterzufragen --
  /// siehe [TransactionResponse.isConclusive]. Wer einen laufenden Vorgang
  /// vom abgebrochenen trennen will, braucht [abort], nicht diese Abfrage.
  ///
  /// [TransactionResponse.isInProgress] (`responseCode == null`) wurde auf
  /// dieser Firmware nie beobachtet, bleibt aber ebenfalls eine Nicht-Aussage.
  ///
  /// Eine dritte Nicht-Aussage, am 27.08.2026 gemessen: fragt man eine nicht
  /// rein numerische Kennung ab, antwortet diese Abfrage DAUERHAFT mit
  /// [TransactionResponse.technicalErrorCode] (`9900`, "Technical Error
  /// Database") -- unabhaengig davon, ob unter der Kennung tatsaechlich Geld
  /// floss. [_checkTransactionId] verhindert das fuer jede Kennung, die
  /// dieser Client selbst erzeugt oder entgegennimmt; unangetastet bleibt
  /// eine Kennung, die vor dieser Pruefung entstanden ist.
  Future<TransactionResponse> transactionStatus({
    required String transactionId,
  }) {
    _checkTransactionId(transactionId, 'transactionId');
    final uri = _uri('api/v2/transactions/$tid/$transactionId', null);
    return _sendTransactionUri('GET', uri, null);
  }

  /// Reads the terminal **diagnosis** (device status, HPS version, host, …).
  /// This is a safe, non-financial health check.
  Future<Diagnosis> diagnosis() async {
    final uri = _uri('api/terminals/$tid/diagnosis', null);
    final json = await _request('GET', uri, null);
    return Diagnosis.fromJson(json);
  }

  /// Lightweight readiness check: `GET /api/terminals/{tid}/status`.
  ///
  /// Returns `true` when the terminal is ready (HTTP 200) and `false` when it
  /// reports *not operable* (HTTP 503). Other status codes / transport failures
  /// throw ([HpsHttpException] / [HpsConnectionException]).
  ///
  /// This endpoint carries no response body — the state is signalled purely via
  /// the HTTP status code. For a richer, field-based health snapshot use
  /// [diagnosis].
  Future<bool> terminalStatus() async {
    final response =
        await _send('GET', _uri('api/terminals/$tid/status', null), null);
    if (response.statusCode == 200) return true;
    if (response.statusCode == 503) return false;
    throw HpsHttpException(
      response.statusCode,
      _errorMessage(response.body, response.statusCode),
      body: response.body,
    );
  }

  /// Lists the **terminals** known to this device: `GET /api/terminals`.
  ///
  /// Returns the configured terminal objects (id, merchant/company, receipt
  /// header lines, type, …) as [TerminalInfo]. The REST spec and its example
  /// disagree on the exact field set, so every field is optional; unmodelled
  /// keys stay available via [TerminalInfo.raw].
  ///
  /// Nicht ueberall vorhanden: am 26.08.2026 antwortete HPS 1.10.0 /
  /// Firmware 7.3.6 hier mit `404 Endpoint not implemented`. Der Aufruf
  /// wirft dann eine [HpsHttpException] -- er ist kein verlaesslicher
  /// Bestandteil des Zahlwegs.
  Future<List<TerminalInfo>> terminals() async {
    final response = await _send('GET', _uri('api/terminals', null), null);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HpsHttpException(
        response.statusCode,
        _errorMessage(response.body, response.statusCode),
        body: response.body,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is List) {
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(TerminalInfo.fromJson)
          .toList();
    }
    return const <TerminalInfo>[];
  }

  /// Returns the **batch totals** (reconciliation sums) for the period starting
  /// at [since].
  ///
  /// This endpoint is documented in hobex's Postman collection but not in the
  /// REST specification PDF, so the response is returned as the raw decoded
  /// JSON rather than a typed model.
  Future<Map<String, dynamic>> batchTotals(DateTime since) {
    final uri = _uri(
      'api/terminals/$tid/batchtotal/${_isoSeconds(since)}',
      null,
    );
    return _request('GET', uri, null);
  }

  /// **Closes the batch** (end-of-day settlement) for the period starting at
  /// [since]. Returned as the raw decoded JSON (shape not in the REST PDF).
  Future<Map<String, dynamic>> closeBatch(DateTime since) {
    final uri = _uri(
      'api/terminals/$tid/closebatch/${_isoSeconds(since)}',
      null,
    );
    return _request('GET', uri, null);
  }

  /// Gibt Ressourcen frei. Selbst erzeugte Verbindungen werden bereits pro
  /// Request geschlossen; ein injizierter Client gehoert dem Aufrufer und wird
  /// hier NICHT geschlossen. Bleibt aus API-Kompatibilitaet als sicherer No-op.
  void close() {}

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _txBody({
    required num amount,
    num? tip,
    String? forceTip,
    String? reference,
    String? transactionId,
    String? currency,
    String? language,
    String? originalTransactionId,
    int? transactionType,
  }) {
    if (transactionId != null) {
      _checkTransactionId(transactionId, 'transactionId');
    }
    // originalTransactionId geht bei [refund] ebenso ans Terminal wie
    // transactionId -- bis 27.08.2026 ungeprueft. Ohne diese Pruefung waere
    // eine Gutschrift auf eine nicht-numerische Originalkennung derselben
    // Falle ausgesetzt: die spaetere Statusabfrage darauf antwortet
    // ebenfalls dauerhaft mit [TransactionResponse.technicalErrorCode].
    if (originalTransactionId != null) {
      _checkTransactionId(originalTransactionId, 'originalTransactionId');
    }
    final tx = <String, dynamic>{
      'tid': tid,
      'amount': amount,
      'currency': currency ?? defaultCurrency,
    };
    if (transactionType != null) tx['transactionType'] = transactionType;
    if (transactionId != null) tx['transactionId'] = transactionId;
    if (reference != null) tx['reference'] = reference;
    if (originalTransactionId != null) {
      tx['originalTransactionId'] = originalTransactionId;
    }
    if (tip != null) tx['tip'] = tip;
    if (forceTip != null) tx['forceTip'] = forceTip;
    final lang = language ?? defaultLanguage;
    if (lang != null) tx['language'] = lang;
    return {'transaction': tx};
  }

  Future<TransactionResponse> _sendTransaction(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) =>
      _sendTransactionUri(method, _uri(path, null), body);

  Future<TransactionResponse> _sendTransactionUri(
    String method,
    Uri uri,
    Map<String, dynamic>? body,
  ) async {
    final json = await _request(method, uri, body);
    return TransactionResponse.fromJson(json);
  }

  /// Sendet einen HTTP-Request und liefert die ROHE Antwort (ohne Status-/
  /// JSON-Auswertung). Fuer die JSON-Variante siehe [_request].
  ///
  /// Das hobex-Terminal schliesst inaktive Keep-Alive-Verbindungen. Ein
  /// wiederverwendeter (bereits geschlossener) Socket fuehrt sonst zu
  /// "Connection closed before full header was received" -- und das
  /// http-Paket wiederholt nicht. Deshalb bei selbst erzeugtem Client pro
  /// Request eine FRISCHE Verbindung; ein injizierter Client (Tests) bleibt
  /// unveraendert. Bewusst KEIN Auto-Retry: bei Zahlung/Refund waere ein
  /// Wiederholen gefaehrlich (Doppelbuchung).
  Future<http.Response> _send(
    String method,
    Uri uri,
    Map<String, dynamic>? body,
  ) async {
    final request = http.Request(method, uri);
    request.headers['Content-Type'] = 'application/json';
    request.headers['Accept'] = 'application/json';
    if (body != null) request.body = jsonEncode(body);

    _emit(
        HpsEvent(HpsEventKind.requestStarted, '${request.method} ${uri.path}'));

    final http.Client client = _http ?? http.Client();
    try {
      // Die Frist deckt Verbindungsaufbau, Antwortkopf UND das Auslesen des
      // Rumpfes. Lag sie nur auf send(), hielt eine Gegenstelle, die den Kopf
      // schickt und den Rumpf stehen laesst, den Aufrufer unbegrenzt fest.
      final response = await _sendAndRead(client, request).timeout(timeout);
      _emit(HpsEvent(HpsEventKind.requestSucceeded,
          '${request.method} ${uri.path} -> ${response.statusCode}'));
      return response;
    } on HpsException catch (error) {
      _emit(HpsEvent(
          HpsEventKind.requestFailed, '${request.method} ${uri.path}',
          error: error));
      rethrow;
    } catch (error) {
      _emit(HpsEvent(
          HpsEventKind.requestFailed, '${request.method} ${uri.path}',
          error: error));
      throw HpsConnectionException(error);
    } finally {
      if (_ownsHttpClient) client.close();
    }
  }

  /// Meldet ein Ereignis. Ein werfender Beobachter wird geschluckt: das
  /// Protokoll darf den Zahlweg niemals mitreissen.
  void _emit(HpsEvent event) {
    final observer = _observer;
    if (observer == null) return;
    try {
      observer(event);
    } catch (_) {
      // bewusst still
    }
  }

  static Future<http.Response> _sendAndRead(
    http.Client client,
    http.Request request,
  ) async {
    final streamed = await client.send(request);
    return http.Response.fromStream(streamed);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Uri uri,
    Map<String, dynamic>? body,
  ) async {
    final response = await _send(method, uri, body);
    final text = response.body;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HpsHttpException(
        response.statusCode,
        _errorMessage(text, response.statusCode),
        body: text,
      );
    }

    if (text.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) return decoded;
    return <String, dynamic>{'value': decoded};
  }

  static String _errorMessage(String body, int statusCode) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] != null) {
        return decoded['message'].toString();
      }
    } catch (_) {
      // not JSON — fall through
    }
    return body.trim().isEmpty ? 'HTTP $statusCode' : body.trim();
  }

  Uri _uri(String path, Map<String, String>? query) {
    final basePath = baseUrl.path.endsWith('/')
        ? baseUrl.path.substring(0, baseUrl.path.length - 1)
        : baseUrl.path;
    final suffix = path.startsWith('/') ? path : '/$path';
    return baseUrl.replace(path: '$basePath$suffix', queryParameters: query);
  }

  /// HPS verlangt die TID OHNE fuehrende Null (z.B. 3600335, nicht 03600335).
  /// Eine Kennung aus lauter Nullen bleibt unveraendert, statt leer zu werden.
  static String _normalizeTid(String raw) {
    final stripped = raw.replaceFirst(RegExp(r'^0+'), '');
    return stripped.isEmpty ? raw : stripped;
  }

  /// Letzte vergebene Millisekunde bzw. laufender Zaehler innerhalb dieser
  /// Millisekunde -- Prozessweiter Zustand fuer [newTransactionId].
  static int? _lastTransactionMs;
  static int _transactionCounter = 0;

  /// Eine eindeutige, numerische Kennung mit hoechstens 18 Stellen:
  /// 13 Stellen Zeitstempel in Millisekunden, dazu ein 5-stelliger Zaehler
  /// je Millisekunde (statt Zufall). Der Zeitstempel allein reichte nicht --
  /// zwei Vorgaenge in derselben Millisekunde bekamen dieselbe Kennung, und
  /// ein Zufallsanteil kann (selten, aber nachweislich geschehen) genauso
  /// kollidieren.
  ///
  /// Die Zaehlung ist eine logische Uhr, angelehnt an das Snowflake-Verfahren:
  /// die zuletzt vergebene Millisekunde [_lastTransactionMs] laeuft niemals
  /// rueckwaerts. Liefert die Systemuhr (oder das injizierte [nowMillis])
  /// keinen groesseren Wert als beim letzten Aufruf -- egal ob wegen
  /// derselben Millisekunde oder einer zurueckspringenden Uhr (Zeitumstellung,
  /// NTP-Korrektur) -- bleibt die Millisekunde stehen und nur der Zaehler
  /// steigt. Ist der Zaehler einer Millisekunde ausgeschoepft (100000
  /// Kennungen), schaltet die Millisekunde gedanklich um eins weiter und der
  /// Zaehler beginnt neu bei 0; dieser Sprung nach vorn wird zur neuen
  /// Referenz, gegen die weiter verglichen wird. So liefert diese Methode
  /// innerhalb EINES Prozesses garantiert nie zweimal dieselbe Kennung --
  /// unabhaengig von Aufrufrate oder Uhrsprung.
  ///
  /// Diese Garantie gilt ausdruecklich nur innerhalb des einen Prozesses, der
  /// den statischen Zustand haelt: zwei getrennte Prozesse oder Geraete, die
  /// in derselben Millisekunde eine Kennung bilden, koennen weiterhin
  /// kollidieren, weil sie voneinander nichts wissen. Fuer den Einsatz hier
  /// passt das: die App laeuft je Terminal in genau einem Prozess.
  ///
  /// Oeffentlich, damit ein Aufrufer die Kennung VOR dem Request festlegen
  /// kann -- ohne das ist sie nach einem Abbruch verloren, und damit sind
  /// Statusabfrage und Storno unerreichbar.
  ///
  /// [nowMillis] ersetzt die Systemuhr; ausschliesslich fuer Tests gedacht,
  /// die eine feste oder rueckwaerts springende Zeit erzwingen wollen.
  static String newTransactionId({int? nowMillis}) {
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    final lastMs = _lastTransactionMs;
    int ms;
    if (lastMs == null || now > lastMs) {
      ms = now;
      _transactionCounter = 0;
    } else {
      ms = lastMs;
      _transactionCounter++;
      if (_transactionCounter >= 100000) {
        ms++;
        _transactionCounter = 0;
      }
    }
    _lastTransactionMs = ms;
    final suffix = _transactionCounter.toString().padLeft(5, '0');
    return '$ms$suffix';
  }

  /// Formats [dt] as `yyyy-MM-ddTHH:mm:ss` (no millis, no timezone), the form
  /// the batch endpoints expect.
  static String _isoSeconds(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year.toString().padLeft(4, '0')}-${two(dt.month)}-'
        '${two(dt.day)}T${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }
}
