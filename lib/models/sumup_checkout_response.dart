import 'package:sumup/models/sumup_plugin_checkout_response.dart';

class SumupCheckoutResponse {
  final bool success;
  final String? transactionCode;
  final double? amount;
  final String? currency;
  final double? vatAmount;
  final double? tipAmount;
  final String? paymentType;
  final String? entryMode;
  final int? installments;
  final String? cardType;
  final String? cardLastDigits;

  SumupCheckoutResponse({
    required this.success,
    this.transactionCode,
    this.amount,
    this.currency,
    this.vatAmount,
    this.tipAmount,
    this.paymentType,
    this.entryMode,
    this.installments,
    this.cardType,
    this.cardLastDigits,
  });

  factory SumupCheckoutResponse.fromSumup(SumupPluginCheckoutResponse response) {
    return SumupCheckoutResponse(
      success: response.success ?? false,
      transactionCode: response.transactionCode,
      amount: response.amount,
      currency: response.currency,
      vatAmount: response.vatAmount,
      tipAmount: response.tipAmount,
      paymentType: response.paymentType,
      entryMode: response.entryMode,
      installments: response.installments,
      cardType: response.cardType,
      cardLastDigits: response.cardLastDigits,
    );
  }

  factory SumupCheckoutResponse.fromMap(Map<String, dynamic> response) {
    return SumupCheckoutResponse(
      success: response['success'] as bool,
      transactionCode: response['transactionCode'] as String?,
      amount: (response['amount'] as num?)?.toDouble(),
      currency: response['currency'] as String?,
      vatAmount: (response['vatAmount'] as num?)?.toDouble(),
      tipAmount: (response['tipAmount'] as num?)?.toDouble(),
      paymentType: response['paymentType'] as String?,
      entryMode: response['entryMode'] as String?,
      installments: int.tryParse(response['installments'].toString()),
      cardType: response['cardType'] as String?,
      cardLastDigits: response['cardLastDigits'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'transactionCode': transactionCode,
      'amount': amount,
      'currency': currency,
      'vatAmount': vatAmount,
      'tipAmount': tipAmount,
      'paymentType': paymentType,
      'entryMode': entryMode,
      'installments': installments?.toString(),
      'cardType': cardType,
      'cardLastDigits': cardLastDigits,
    };
  }
}