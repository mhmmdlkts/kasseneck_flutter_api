import '../enums/credit_card_provider.dart';
import '../src/hobex_hps/transaction_response.dart';

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

  /// Welcher Provider die Zahlung durchgefuehrt hat. Cloud-Hobex -> hobexCloudApi
  /// (Default), lokales HPS -> hobexHps. Steuert u.a. das Beleg-Rendering.
  CreditCardProvider creditCardProvider;


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
    this.creditCardProvider = CreditCardProvider.hobexCloudApi,
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

  /// Adaptiert ein lokales **HPS**-Ergebnis ([TransactionResponse]) auf das
  /// gemeinsame Beleg-Format. Provider = hobexHps (gleiche cardPaymentData-Keys
  /// wie Cloud -> selbes Beleg-Rendering).
  factory HobexReceipt.fromHps(TransactionResponse res) {
    String s(Object? v) => (v ?? '').toString();
    final String date = s(res.transactionDate).split('.').first.replaceAll('T', ' ');
    return HobexReceipt(
      transactionId: s(res.transactionId),
      tid: s(res.tid),
      receipt: s(res.receipt),
      approvalCode: s(res.approvalCode),
      reference: res.reference,
      transactionDate: date,
      cardNumber: s(res.cardNumber),
      cardExpiry: s(res.cardExpiry),
      brand: s(res.brand),
      cardIssuer: s(res.cardIssuer),
      responseCode: s(res.responseCode),
      transactionType: s(res.transactionType),
      currency: s(res.currency),
      amount: (res.amount ?? 0).toDouble(),
      tip: (res.tip ?? 0).toDouble(),
      cvm: s(res.raw['cvm']),
      creditCardProvider: CreditCardProvider.hobexHps,
    );
  }

  Map<String, String> toCardPaymentData() {
    final Map<String, String> data = {
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
    // HPS liefert mehr Felder als die Cloud -> zusaetzlich aufnehmen. Das
    // Rendering (case hobexHps in print_paper/keck_receipt_widget) liest genau
    // diese Keys.
    if (creditCardProvider == CreditCardProvider.hobexHps) {
      data['approvalCode'] = approvalCode;
      data['cardExpiry'] = cardExpiry;
      data['cardIssuer'] = cardIssuer;
      data['amount'] = amount.toStringAsFixed(2);
      data['currency'] = currency;
    }
    return data;
  }

  bool get needSignature => cvm == '1';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is HobexReceipt && other.transactionId == transactionId);

  @override
  int get hashCode => transactionId.hashCode;
}
