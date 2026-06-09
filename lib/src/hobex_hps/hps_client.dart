import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'diagnosis.dart';
import 'enums.dart';
import 'exceptions.dart';
import 'transaction_response.dart';

/// Client for the local **hobex Payment Service (HPS)** REST API.
///
/// By default it talks to `http://127.0.0.1:8080`, which is correct when the
/// app runs **on the terminal itself**. For remote testing from a dev machine,
/// pass a [baseUrl] pointing at the terminal's IP, e.g.
/// `Uri.parse('http://192.168.0.187:8080')`.
///
/// The [tid] must be given **without a leading zero** (e.g. `3600335`, not
/// `03600335`).
class HpsClient {
  HpsClient({
    Uri? baseUrl,
    required this.tid,
    this.defaultCurrency = 'EUR',
    this.defaultLanguage,
    this.timeout = const Duration(minutes: 3),
    http.Client? httpClient,
  }) : baseUrl = baseUrl ?? Uri.parse('http://127.0.0.1:8080'),
       _http = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  /// Base URL of the HPS. Defaults to `http://127.0.0.1:8080`.
  final Uri baseUrl;

  /// Terminal identifier — **without leading zero**.
  final String tid;

  /// Currency used when a request does not specify one. Defaults to `EUR`.
  final String defaultCurrency;

  /// Terminal UI language (`DE` / `IT` / `SI`) used when not specified.
  final String? defaultLanguage;

  /// Request timeout. Defaults to 3 minutes because card-present transactions
  /// block until the cardholder has interacted with the terminal.
  final Duration timeout;

  final http.Client _http;
  final bool _ownsHttpClient;

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
  /// Set [technicalCancel] to indicate a technical cancellation.
  Future<TransactionResponse> cancel({
    required String transactionId,
    bool technicalCancel = false,
  }) {
    final uri = _uri(
      'api/transaction/payment/$tid/$transactionId',
      technicalCancel ? const {'technicalCancel': 'true'} : null,
    );
    return _sendTransactionUri('DELETE', uri, null);
  }

  /// **Aborts** an ongoing transaction *before* a card has been tapped.
  /// Returns the transaction id of the aborted transaction, if provided.
  Future<String?> abort({required String transactionId}) async {
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

  /// Releases the underlying HTTP client (only if it was created internally).
  void close() {
    if (_ownsHttpClient) _http.close();
  }

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

  Future<Map<String, dynamic>> _request(
    String method,
    Uri uri,
    Map<String, dynamic>? body,
  ) async {
    final request = http.Request(method, uri);
    request.headers['Content-Type'] = 'application/json';
    request.headers['Accept'] = 'application/json';
    if (body != null) request.body = jsonEncode(body);

    final http.Response response;
    try {
      final streamed = await _http.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed);
    } on HpsException {
      rethrow;
    } catch (error) {
      throw HpsConnectionException(error);
    }

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
