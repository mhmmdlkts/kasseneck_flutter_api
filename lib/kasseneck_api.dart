import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:http/http.dart' as http;
import 'package:kasseneck_api/enums/credit_card_provider.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/models/hobex_receipt.dart';
import 'package:kasseneck_api/models/report_month.dart';
import 'package:kasseneck_api/services/printer_service.dart';

import 'enums/payment_method.dart';
import 'enums/receipt_type.dart';
import 'models/kasseneck_item.dart';
import 'models/kasseneck_receipt.dart';

/// Hauptklasse für Kasseneck-API-Aufrufe
class KasseneckApi {
  static final String _baseUrl = 'https://europe-west1-kasseneck.cloudfunctions.net';
  static final String downloadBaseUrl = 'https://europe-west1-kasseneck.cloudfunctions.net/downloadReceipt';
  final String apiKey;
  final String cashregisterToken;
  String? printerAddress;

  KasseneckApi({
    required this.apiKey,
    required this.cashregisterToken
  });

  Future<dynamic> _kasseneckPostRequest(
      {required String endpoint, Map<String, dynamic> params = const {}}) async {
    Uri uri = Uri.parse('$_baseUrl/$endpoint');

    final headers = {
      'Authorization': 'Bearer $apiKey',
      'cashregister-token': cashregisterToken,
      'Content-Type': 'application/json',
    };

    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({
        'params': params,
      }),
    );

    if (response.statusCode == 200 && response.body.isNotEmpty) {
      return response.body;
    } else {
      throw Exception(
        'Server-Fehler beim Aufruf von $endpoint: ${response.statusCode} - ${response.body}',
      );
    }
  }

  Future<Uint8List?> downloadReport(ReportMonth reportMonth) async => _kasseneckPostRequest(
    endpoint: 'downloadReport',
    params: {
      'month': reportMonth.month.id,
      'year': reportMonth.year
    }).then((value) => Uint8List.fromList(value.codeUnits));

  Future<ReportMonth?> getFirstReceiptDate() async {
    final resJson = await _kasseneckPostRequest(endpoint: 'getFirstReceiptDate').then((value) => json.decode(value));

    if (resJson['status'] == 'success') {
      DateTime dateTime = DateTime.parse(resJson['data']);
      return ReportMonth.fromDateTime(dateTime);
    } else {
      final msg = resJson['message'] ?? 'Unbekannter Fehler';
      throw Exception('getFirstReceiptDate fehlgeschlagen: $msg');
    }
  }

  Future<KasseneckReceipt?> cancelReceipt({
    required KasseneckReceipt receipt,
    PaymentMethod? paymentMethod,
    CreditCardProvider? creditCardProvider,
    String? customProjectId,
    String? cardPaymentId,
    Map<String, dynamic>? cardPaymentData,
    List<String>? legalMessage,
  }) async {
    paymentMethod ??= receipt.paymentMethod;
    return _createReceipt(
      receiptType: ReceiptType.cancellation,
      customerDetails: receipt.customerDetails,
      items: receipt.items.map((item) => item.negative).toList(),
      paymentMethod: paymentMethod,
      cardPaymentData: cardPaymentData,
      cardPaymentId: cardPaymentId,
      creditCardProvider: creditCardProvider,
      customProjectId: customProjectId,
      legalMessage: legalMessage
    );
  }

  Future<KasseneckReceipt?> zeroReceipt() async {
    return _createReceipt(receiptType: ReceiptType.zero);
  }

  Future<KasseneckReceipt?> sellReceipt({
    required PaymentMethod paymentMethod,
    required List<KasseneckItem> items,
    List<String>? customerDetails,
    List<String>? legalMessage,
    CreditCardProvider? creditCardProvider,
    String? cardPaymentId,
    String? customProjectId,
    Map<String, dynamic>? cardPaymentData,
  }) async {
    return _createReceipt(
      receiptType: ReceiptType.standard,
      customerDetails: customerDetails,
      items: items,
      paymentMethod: paymentMethod,
      cardPaymentData: cardPaymentData,
      cardPaymentId: cardPaymentId,
      creditCardProvider: creditCardProvider,
      customProjectId: customProjectId,
      legalMessage: legalMessage
    );
  }

  Future<KasseneckReceipt?> _createReceipt({
    required ReceiptType receiptType,
    PaymentMethod? paymentMethod,
    CreditCardProvider? creditCardProvider,
    String? customProjectId,
    String? cardPaymentId,
    List<KasseneckItem>? items,
    List<String>? customerDetails,
    List<String>? legalMessage,
    Map<String, dynamic>? cardPaymentData
  }) async {

    if (receiptType.needsItems) {
      if (items == null || items.isEmpty) {
        throw ArgumentError(
          'Items sind Pflicht bei receiptType "$receiptType" und dürfen nicht leer sein.',
        );
      }

      if (items.any((item) => !item.isValid)) {
        throw ArgumentError('Ungültige Items übergeben.');
      }
    }

    final Map<String, dynamic> params = {
      'receiptType': receiptType.name,
    };

    if (items != null && items.isNotEmpty) {
      params['items'] = items.map((e) => e.toJson()).toList();
    }
    if (paymentMethod != null) {
      params['paymentMethod'] = paymentMethod.name;
      creditCardProvider ??= CreditCardProvider.custom;
      if (paymentMethod == PaymentMethod.creditCard) {
        if (cardPaymentId != null) {
          params['cardPaymentId'] = cardPaymentId;
          params['creditCardProvider'] = creditCardProvider.name;
          params['cardPaymentData'] = cardPaymentData;
        } else if (creditCardProvider != CreditCardProvider.custom) {
          throw ArgumentError(
              'cardPaymentId ist Pflicht bei creditCardProvider "$creditCardProvider".');
        }
      }
    }
    if (customProjectId != null) {
      params['customProjectId'] = customProjectId;
    }
    if (customerDetails != null) {
      params['customerDetails'] = customerDetails.join('\n');
    }
    if (legalMessage != null) {
      params['legalMessage'] = legalMessage.join('\n');
    }

    final Map<String, dynamic> resJson = await _kasseneckPostRequest(endpoint: 'createReceipt', params: params).then((value) => json.decode(value));

    if (resJson['status'] == 'success') {
      KasseneckReceipt receipt = KasseneckReceipt.fromJson(resJson['data'] as Map<String, dynamic>);
      await receipt.init();
      return receipt;
    } else {
      final msg = resJson['message'] ?? 'Unbekannter Fehler';
      throw Exception('createReceipt fehlgeschlagen: $msg');
    }
  }

  Future<KasseneckReceipt?> getReceipt(String receiptId) async {
    final Map<String, dynamic> resJson = await _kasseneckPostRequest(endpoint: 'getReceipt', params: {
      'receiptId': receiptId
    }).then((value) => json.decode(value));

    if (resJson['status'] == 'success') {
      KasseneckReceipt receipt = KasseneckReceipt.fromJson(resJson['data']);
      await receipt.init();
      return receipt;
    } else {
      final msg = resJson['message'] ?? 'Unbekannter Fehler';
      throw Exception('getReceipt fehlgeschlagen: $msg');
    }
  }

  Future<List<KasseneckReceipt>> getReceipts(DateTime start, DateTime end) async {
    if (start.isAfter(end)) {
      throw ArgumentError('start darf nicht nach end sein.');
    }

    final Map<String, dynamic> resJson = await _kasseneckPostRequest(endpoint: 'getReportV2', params: {
      'start': start.toIso8601String().split('.').first,
      'end': end.toIso8601String().split('.').first
    }).then((value) => json.decode(value));
    if (resJson['status'] == 'success') {
      Map<String, dynamic> metadata = resJson['data']['metadata'];
      return (resJson['data']['receipts'] as List).map((r) {
        KasseneckReceipt receipt = KasseneckReceipt.fromMetadata(r, metadata);
        receipt.init();
        return receipt;
      }).toList();
    } else {
      final msg = resJson['message'] ?? 'Unbekannter Fehler';
      throw Exception('getReceipts fehlgeschlagen: $msg');
    }
  }

  Future initPrinter(String macAddress, KeckPaperSize size) async {
    printerAddress = macAddress;
    return PrinterService.initPrinter(macAddress, size.paperSize);
  }

  static Future openCashDrawer() => PrinterService.openCashDrawer();

  Future<HobexReceipt> hobexPay({required String transactionId, required double amount, double tip = 0, String? reference}) async {
    final Map<String, dynamic> resJson = await _kasseneckPostRequest(
        endpoint: 'hobexPayApi',
        params: {
          'transactionId': transactionId,
          'amount': amount,
          'tip': tip,
          'reference': reference
        }
    ).then((value) => json.decode(value));
    try {
      return HobexReceipt.fromJson(resJson['data']);
    } catch (e) {
      throw Exception('Fehler beim Parsen des Hobex-Belegs: $e');
    }
  }

  Future<bool> hobexRefund({required String transactionId, required double amount, double tip = 0}) async {
    final Map<String, dynamic> resJson = await _kasseneckPostRequest(
        endpoint: 'hobexRefundApi',
        params: {
          'transactionId': transactionId,
          'amount': amount,
          'tip': tip,
        }
    ).then((value) => json.decode(value));
    return resJson['status'] == 'success';
  }

  static String newHobexTransactionId() {
    String date = DateTime.now().toString().replaceAll('-', '').replaceAll(':', '').replaceAll(' ', '').replaceAll('.', '');
    date = date.substring(2, date.length) + (Random().nextInt(90) + 10).toString();
    return date.substring(0, 19);
  }
}