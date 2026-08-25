import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'diagnosis.dart';
import 'enums.dart';
import 'exceptions.dart';
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
  }) : baseUrl = baseUrl ?? Uri.parse('http://127.0.0.1:8080'),
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

  /// Laengengrenze der Transaktionskennung laut HPS-REST-Spezifikation.
  /// Bewusst NUR die Laenge: ob das Terminal eine nicht rein numerische
  /// Kennung annimmt, ist ungeprueft (der Bestandstest schickt 'TX-7').
  static const int _maxTransactionIdLength = 18;

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
      transactionId: transactionId ?? _newTransactionId(),
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
      transactionId: transactionId ?? _newTransactionId(),
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
      transactionId: transactionId ?? _newTransactionId(),
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
  /// `400 Missing amount` ab (am HPS empirisch bestaetigt). Die REST-PDF v1.13
  /// listet den Parameter zwar nicht, die Postman-Collection und die Firmware
  /// verlangen ihn. [currency]/[language] fallen auf die Client-Defaults zurueck.
  ///
  /// Set [technicalCancel] to indicate a technical cancellation.
  Future<TransactionResponse> cancel({
    required String transactionId,
    required num amount,
    String? currency,
    String? language,
    bool technicalCancel = false,
  }) {
    if (transactionId.isEmpty ||
        transactionId.length > _maxTransactionIdLength) {
      throw ArgumentError.value(
        transactionId,
        'transactionId',
        'HPS erlaubt 1 bis $_maxTransactionIdLength Zeichen',
      );
    }
    final lang = language ?? defaultLanguage;
    final uri = _uri('api/transaction/payment/$tid/$transactionId', {
      'amount': amount.toString(),
      'currency': currency ?? defaultCurrency,
      if (lang != null) 'language': lang,
      if (technicalCancel) 'technicalCancel': 'true',
    });
    return _sendTransactionUri('DELETE', uri, null);
  }

  /// **Aborts** an ongoing transaction *before* a card has been tapped.
  /// Returns the transaction id of the aborted transaction, if provided.
  Future<String?> abort({required String transactionId}) async {
    if (transactionId.isEmpty ||
        transactionId.length > _maxTransactionIdLength) {
      throw ArgumentError.value(
        transactionId,
        'transactionId',
        'HPS erlaubt 1 bis $_maxTransactionIdLength Zeichen',
      );
    }
    final uri = _uri('api/transaction/abort/$tid/$transactionId', null);
    final json = await _request('POST', uri, null);
    return json['transactionId'] as String?;
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
      transactionId: transactionId ?? _newTransactionId(),
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
  /// When the returned response has [TransactionResponse.isInProgress] `true`,
  /// the transaction is still running and should be polled again.
  Future<TransactionResponse> transactionStatus({
    required String transactionId,
  }) {
    if (transactionId.isEmpty ||
        transactionId.length > _maxTransactionIdLength) {
      throw ArgumentError.value(
        transactionId,
        'transactionId',
        'HPS erlaubt 1 bis $_maxTransactionIdLength Zeichen',
      );
    }
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
      if (transactionId.isEmpty ||
          transactionId.length > _maxTransactionIdLength) {
        throw ArgumentError.value(
          transactionId,
          'transactionId',
          'HPS erlaubt 1 bis $_maxTransactionIdLength Zeichen',
        );
      }
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
  ) => _sendTransactionUri(method, _uri(path, null), body);

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

    final http.Client client = _http ?? http.Client();
    try {
      // Die Frist deckt Verbindungsaufbau, Antwortkopf UND das Auslesen des
      // Rumpfes. Lag sie nur auf send(), hielt eine Gegenstelle, die den Kopf
      // schickt und den Rumpf stehen laesst, den Aufrufer unbegrenzt fest.
      return await _sendAndRead(client, request).timeout(timeout);
    } on HpsException {
      rethrow;
    } catch (error) {
      throw HpsConnectionException(error);
    } finally {
      if (_ownsHttpClient) client.close();
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

  /// A unique, numeric transaction id (≤ 18 digits) based on the current time.
  static String _newTransactionId() =>
      DateTime.now().millisecondsSinceEpoch.toString();

  /// Formats [dt] as `yyyy-MM-ddTHH:mm:ss` (no millis, no timezone), the form
  /// the batch endpoints expect.
  static String _isoSeconds(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year.toString().padLeft(4, '0')}-${two(dt.month)}-'
        '${two(dt.day)}T${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }
}
