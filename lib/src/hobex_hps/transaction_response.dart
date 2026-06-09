import 'enums.dart';

/// Result of a transaction request (payment, refund, pre-auth, capture, void,
/// AVT) or of a transaction-status (v2) query.
///
/// A response object is returned even when a payment is **declined**: declines
/// are signalled by [isApproved] being `false` (i.e. [responseCode] != `"0"`),
/// not by an exception. Exceptions are only thrown for HTTP/transport errors.
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
  /// transaction is still in progress — see [isInProgress].
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

  /// `true` when the transaction was approved (`responseCode == "0"`).
  bool get isApproved => responseCode == '0';

  /// `true` when a status query reports the transaction is still running
  /// (`responseCode == null`).
  bool get isInProgress => responseCode == null;

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
      responseCode: json['responseCode']?.toString(),
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

  @override
  String toString() {
    final outcome = isInProgress
        ? 'IN_PROGRESS'
        : isApproved
        ? 'APPROVED'
        : 'DECLINED($responseCode)';
    return 'TransactionResponse($outcome, type=$transactionType, '
        'amount=$amount $currency, brand=$brand, card=$cardNumber, '
        'approval=$approvalCode, tx=$transactionId, text=$responseText)';
  }
}
