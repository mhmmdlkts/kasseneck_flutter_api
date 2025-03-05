import '../enums/credit_card_provider.dart';

class HobexReceipt {

  String transactionId;
  String tid;
  String receipt;
  String approvalCode;
  String? reference;
  String transactionDate;
  String cardNumber;
  String cardExpiry;
  String brand;
  String cardIssuer;
  String responseCode;
  String transactionType;
  String currency;
  double amount;
  double tip;
  String cvm;


  HobexReceipt({
    required this.transactionId,
    required this.tid,
    required this.receipt,
    required this.approvalCode,
    required this.reference,
    required this.transactionDate,
    required this.cardNumber,
    required this.cardExpiry,
    required this.brand,
    required this.cardIssuer,
    required this.responseCode,
    required this.transactionType,
    required this.currency,
    required this.amount,
    required this.tip,
    required this.cvm,
  });

  factory HobexReceipt.fromJson(Map<String, dynamic> json) {
    return HobexReceipt(
      transactionId: json['transactionId'],
      tid: json['tid'],
      receipt: json['receipt'],
      approvalCode: json['approvalCode'],
      reference: json['reference'],
      transactionDate: json['transactionDate'].split('.')[0].replaceAll('T', ' '),
      cardNumber: json['cardNumber'],
      cardExpiry: json['cardExpiry'],
      brand: json['brand'],
      cardIssuer: json['cardIssuer'],
      responseCode: json['responseCode'],
      transactionType: json['transactionType'],
      currency: json['currency'],
      amount: json['amount'] + 0.0,
      tip: json['tip'] + 0.0,
      cvm: json['cvm'].toString(),
    );
  }

  Map<String, String> toCardPaymentData() {
    return {
      'transactionId': transactionId,
      'date': transactionDate,
      'tid': tid,
      'no': receipt,
      'type': transactionType,
      'cardBrand': brand,
      'cardNumber': cardNumber,
      'responseCode': responseCode,
      'cvm': cvm,
    };
  }

  bool get needSignature => cvm == '1';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is HobexReceipt && other.transactionId == transactionId);

  @override
  int get hashCode => transactionId.hashCode;

  CreditCardProvider get creditCardProvider => CreditCardProvider.hobexCloudApi;
}