import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;
import 'package:kasseneck_api/enums/cashbox_status.dart';
import 'package:kasseneck_api/enums/credit_card_provider.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/receipt_print_type.dart';
import 'package:kasseneck_api/enums/stripe_link_mode.dart';
import 'package:kasseneck_api/models/hobex_receipt.dart';
import 'package:kasseneck_api/models/keck_voucher.dart';
import 'package:kasseneck_api/models/report_month.dart';
import 'package:kasseneck_api/models/stripe_url_seesion.dart';
import 'package:kasseneck_api/services/printer_service.dart';

import 'enums/keck_payment_method.dart';
import 'enums/receipt_type.dart';
import 'enums/signature_status.dart';
import 'enums/voucher_action.dart';
import 'enums/voucher_type.dart';
import 'models/kasseneck_item.dart';
import 'models/kasseneck_receipt.dart';

/// Client for the **Kasseneck** RKSV cash-register backend.
///
/// Create one instance with your [apiKey] and [cashregisterToken] (request both
/// from Kreiseck — office@kreiseck.com), then issue receipts, take card
/// payments, print and pull reports through it.
///
/// ```dart
/// final kasseneck = KasseneckApi(apiKey: '…', cashregisterToken: '…');
/// final receipt = await kasseneck.sellReceipt(
///   paymentMethod: KeckPaymentMethod.cash,
///   items: [KasseneckItem(name: 'Coffee', quantity: 1, vat: VatRate.vat20, singlePrice: 3.20)],
/// );
/// ```
class KasseneckApi {
  static final String _baseUrl = 'https://europe-west1-kasseneck.cloudfunctions.net';
  static final String downloadBaseUrl = 'https://beleg.kasseneck.at';
  final String apiKey;
  final String cashregisterToken;
  final ReceiptPrintType? printType;
  String? printerAddress;

  /// HTTP-Client; im Konstruktor austauschbar (Tests/Mocking).
  final http.Client _http;

  KasseneckApi({
    required this.apiKey,
    required this.cashregisterToken,
    this.printType,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  Future<dynamic> _kasseneckPostRequest(
      {required String endpoint, Map<String, dynamic> params = const {}}) async {
    Uri uri = Uri.parse('$_baseUrl/$endpoint');

    final headers = {
      'Authorization': 'Bearer $apiKey',
      'cashregister-token': cashregisterToken,
      'Content-Type': 'application/json',
    };

    final response = await _http.post(
      uri,
      headers: headers,
      body: jsonEncode({
        'params': params,
      }),
      // Ohne Timeout bleibt ein hängender Request für immer offen — der Aufrufer
      // bekommt weder Ergebnis noch Fehler (z. B. blieb so der Belege-Cache still leer).
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200 && response.body.isNotEmpty) {
      return response.body;
    } else {
      throw Exception(
        'Server-Fehler beim Aufruf von $endpoint: ${response.statusCode} - ${response.body}',
      );
    }
  }

  Future<dynamic> _financeWebServicePostRequest(
      {required String method, Map<String, dynamic> params = const {}}) async {
    Uri uri = Uri.parse('$_baseUrl/financeWebService');

    final headers = {
      'Authorization': 'Bearer $apiKey',
      'cashregister-token': cashregisterToken,
      'Content-Type': 'application/json',
    };

    final response = await _http.post(
      uri,
      headers: headers,
      body: jsonEncode({
        'params': params,
        'method': method,
      }),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200 && response.body.isNotEmpty) {
      return response.body;
    } else {
      throw Exception(
        'Server-Fehler beim Aufruf von financeWebService $method: ${response.statusCode} - ${response.body}',
      );
    }
  }

  /// Downloads the daily report PDF for [dateTime] as raw bytes.
  Future<Uint8List?> downloadDailyReport(DateTime dateTime) async => _kasseneckPostRequest(
      endpoint: 'downloadDailyReport',
      params: {
        'year': dateTime.year,
        'month': dateTime.month,
        'day': dateTime.day
      }).then((value) => Uint8List.fromList(value.codeUnits));

  /// Downloads the monthly report PDF for [reportMonth] as raw bytes.
  Future<Uint8List?> downloadMonthlyReport(ReportMonth reportMonth) async => _kasseneckPostRequest(
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

  /// Issues a **cancellation** receipt that reverses [receipt] (its items, negated).
  Future<KasseneckReceipt?> cancelReceipt({
    required KasseneckReceipt receipt,
    KeckPaymentMethod? paymentMethod,
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

  Future<KasseneckReceipt?> createCancelReceipt({
    required KeckPaymentMethod paymentMethod,
    required List<KasseneckItem> items,
    List<String>? customerDetails,
    CreditCardProvider? creditCardProvider,
    String? customProjectId,
    String? cardPaymentId,
    Map<String, dynamic>? cardPaymentData,
    List<String>? legalMessage,
  }) async {
    return _createReceipt(
        receiptType: ReceiptType.cancellation,
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

  /// Issues a **zero** receipt (_Nullbeleg_), e.g. for the periodic RKSV check.
  Future<KasseneckReceipt?> zeroReceipt() async {
    return _createReceipt(receiptType: ReceiptType.zero);
  }

  /// Issues a **standard** RKSV receipt (a sale) for the given [items] and [paymentMethod].
  Future<KasseneckReceipt?> sellReceipt({
    required KeckPaymentMethod paymentMethod,
    List<KasseneckItem>? items,
    List<KeckVoucher>? vouchers,
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
      vouchers: vouchers,
      paymentMethod: paymentMethod,
      cardPaymentData: cardPaymentData,
      cardPaymentId: cardPaymentId,
      creditCardProvider: creditCardProvider,
      customProjectId: customProjectId,
      legalMessage: legalMessage
    );
  }

  Future<bool> checkSumup({required String affiliateKey}) async {
    return false;
    // return await SumupService.init(affiliateKey); TODO
  }

  String? checkVoucherCombinationError(List<KeckVoucher> vouchers, List<KasseneckItem> items) {
    int countRedeemValueVoucher = 0;
    int countSellValueVoucher = 0;
    int countRedeemPromoVoucher = 0;
    int countSellPromoVoucher = 0;
    int countRedeemTotalVoucher = 0;
    int countSellTotalVoucher = 0;

    for (var voucher in vouchers) {
      if (voucher.type == VoucherType.value && voucher.action == VoucherAction.redeem) {
        countRedeemValueVoucher++;
      } else if (voucher.type == VoucherType.value && voucher.action == VoucherAction.sell) {
        countSellValueVoucher++;
      } else if (voucher.type == VoucherType.promo && voucher.action == VoucherAction.redeem) {
        countRedeemPromoVoucher++;
      } else if (voucher.type == VoucherType.promo && voucher.action == VoucherAction.sell) {
        countSellPromoVoucher++;
      }
    }

    countRedeemTotalVoucher = countRedeemValueVoucher + countRedeemPromoVoucher;
    countSellTotalVoucher = countSellValueVoucher + countSellPromoVoucher;

    if (countSellPromoVoucher > 0) {
      return 'Ungültige Daten: Gutscheine mit type promo dürfen nicht verkauft werden';
    }
    if (countRedeemPromoVoucher > 1) {
      return 'Ungültige Daten: Es darf nur ein Gutschein mit type promo eingelöst werden';
    }
    if (countRedeemPromoVoucher > 0 && countRedeemTotalVoucher > 1) {
      return 'Ungültige Daten: Ein Gutschein mit type promo darf nicht mit anderen Gutscheinen kombiniert werden';
    }
    if (countRedeemPromoVoucher > 0 && countSellTotalVoucher > 0) {
      return 'Ungültige Daten: Mit einem Gutschein mit type promo dürfen nicht andere Gutscheine verkauft werden';
    }
    if (countRedeemTotalVoucher > 0 && items.isEmpty) {
      return 'Ungültige Daten: Gutscheine mit action redeem benötigen mindestens ein item';
    }
    return null;
  }

  Future<KasseneckReceipt?> _createReceipt({
    required ReceiptType receiptType,
    KeckPaymentMethod? paymentMethod,
    CreditCardProvider? creditCardProvider,
    String? customProjectId,
    String? cardPaymentId,
    List<KasseneckItem>? items,
    List<KeckVoucher>? vouchers,
    List<String>? customerDetails,
    List<String>? legalMessage,
    Map<String, dynamic>? cardPaymentData
  }) async {

    if (receiptType.needsItems) {
      bool hasSellVoucher = vouchers?.any((v) => v.action == VoucherAction.sell)??false;
      if ((items == null || items.isEmpty) && !hasSellVoucher) {
        throw ArgumentError(
          'Items sind Pflicht bei receiptType "$receiptType" und dürfen nicht leer sein.',
        );
      }

      if (items?.any((item) => !item.isValid)??false) {
        throw ArgumentError('Ungültige Items übergeben.');
      }
    }

    final Map<String, dynamic> params = {
      'receiptType': receiptType.name,
    };

    if (vouchers != null && vouchers.isNotEmpty) {
      if (!receiptType.allowsVouchers) {
        throw ArgumentError('Vouchers sind nicht erlaubt bei receiptType "$receiptType".');
      }
      if (vouchers.any((voucher) => !voucher.isValid)) {
        throw ArgumentError('Ungültige Vouchers übergeben.');
      }
      String? voucherError = checkVoucherCombinationError(vouchers, items ?? []);
      if (voucherError != null) {
        throw ArgumentError(voucherError);
      }
      params['vouchers'] = vouchers.map((e) => e.toJson()).toList();
    }


    if (items != null && items.isNotEmpty) {
      params['items'] = items.map((e) => e.toJson()).toList();
    }
    if (paymentMethod != null) {
      params['paymentMethod'] = paymentMethod.name;
      creditCardProvider ??= CreditCardProvider.custom;
      if (paymentMethod == KeckPaymentMethod.creditCard) {
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

  /// Fetches a single receipt by its [receiptId].
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

  /// Returns all receipts created between [start] and [end].
  Future<List<KasseneckReceipt>> getReceipts(DateTime start, DateTime end) async {
    if (start.isAfter(end)) {
      throw ArgumentError('start darf nicht nach end sein.');
    }

    final Map<String, dynamic> resJson = await _kasseneckPostRequest(endpoint: 'getReportV2', params: {
      'start': start.toIso8601String().split('.').first,
      'end': end.toIso8601String().split('.').first
    }).then((value) => json.decode(value));
    debugPrint('getReportV2 $start–$end: status=${resJson['status']} '
        'receipts=${(resJson['data']?['receipts'] as List?)?.length ?? 'null'}');
    if (resJson['status'] == 'success') {
      Map<String, dynamic> metadata = resJson['data']['metadata'];
      // Pro Beleg parsen: EIN defekter/unerwarteter Beleg (z. B. Nullbeleg ohne
      // items) darf nicht den gesamten Abruf kippen — sonst bleibt der ganze
      // Tages-/Zeitraums-Cache leer und keine Buchung findet ihren Beleg.
      final List<KasseneckReceipt> receipts = [];
      for (final r in (resJson['data']['receipts'] as List)) {
        try {
          receipts.add(KasseneckReceipt.fromMetadata(r, metadata));
        } catch (e) {
          debugPrint('getReceipts: Beleg übersprungen (${r is Map ? r['receiptId'] : r}): $e');
        }
      }
      await Future.wait(receipts.map((r) => r.init()));
      return receipts;
    } else {
      final msg = resJson['message'] ?? 'Unbekannter Fehler';
      throw Exception('getReceipts fehlgeschlagen: $msg');
    }
  }

  Future initWifiPrinter(String ipAddress, KeckPaperSize size) async {
    printerAddress = ipAddress;
    return KeckPrinterService.initWifiPrinter(ipAddress, size);
  }

  BluetoothDevice get devicePrinter => KeckPrinterService.devicePrinter;

  Future initBluetoothPrinter({KeckPaperSize size = KeckPaperSize.mm58, required String printerAddress}) async {
    return await KeckPrinterService.initBluetoothPrinter(size: size, printerAddress: printerAddress);
  }

  Future<CashboxStatus?> getCashboxStatus() async {
    final Map<String, dynamic> resJson = await _financeWebServicePostRequest(
      method: 'status_cashbox',
    ).then((value) => json.decode(value));
    try {
      String res = resJson['data']['rkdbMessage']['status'];
      return CashboxStatus.values.where((element) => element.name == res).firstOrNull;
    } catch (e) {
      throw Exception('Fehler beim Parsen des Cashbox-Status: $e');
    }
  }

  Future<SignatureStatus?> getSignatureStatus(String zertifikatNrHex) async {
    final Map<String, dynamic> resJson = await _financeWebServicePostRequest(
      method: 'status_signature',
      params: {
        'zertifikatnr_hex': zertifikatNrHex
      },
    ).then((value) => json.decode(value));
    try {
      String rc = resJson['data']['rkdbMessage']['rc'];
      if (rc == 'B33') {
        return SignatureStatus.NOT_REGISTERED;
      }
      String res = resJson['data']['rkdbMessage']['status'];
      return SignatureStatus.values.where((element) => element.name == res).firstOrNull;
    } catch (e) {
      throw Exception('Fehler beim Parsen des Signature-Status: $e');
    }
  }

  static Future openCashDrawer() => KeckPrinterService.openCashDrawer();

  /// Creates a Stripe payment link for the given [items] (remote/online payment).
  Future<StripeUrlSession?> createStripeLink({
    required List<KasseneckItem> items,
    required bool createReceiptAfterPayment,
    required StripeLinkMode mode,
    String? webhookId,
    String? customerPhone,
    String? customerEmail,
  }) async {
    final Map<String, dynamic> resJson = await _kasseneckPostRequest(
        endpoint: 'createPaymentLinkStripe',
        params: {
          'items': items.map((e) => e.toJson()).toList(),
          'createReceiptAfterPayment': createReceiptAfterPayment,
          'mode': mode.name,
          if (webhookId != null) 'webhookId': webhookId,
          if (customerPhone != null) 'customerPhone': customerPhone,
          if (customerEmail != null) 'customerEmail': customerEmail
        },
    ).then((value) => json.decode(value));
    try {
      return StripeUrlSession.fromJson(resJson['data']);
    } catch (e) {
      throw Exception('Fehler beim Erstellen des Stripe-Links: $e');
    }
  }

  Future<StripeUrlSession?> stripeCaptureIntent({
    required String stripeSessionId,
  }) async {
    final Map<String, dynamic> resJson = await _kasseneckPostRequest(
        endpoint: 'stripeCaptureIntent',
        params: {
          'stripe_sessions_id': stripeSessionId
        },
    ).then((value) => json.decode(value));
    try {
      return StripeUrlSession.fromJson(resJson['data']);
    } catch (e) {
      throw Exception('Fehler beim Erstellen des Stripe-Links: $e');
    }
  }

  String get cashregisterId {
    final decoded = utf8.decode(base64.decode(cashregisterToken));
    return decoded.split(':').first;
  }

  /// Charges a card via the **Hobex Cloud** API and returns the resulting [HobexReceipt].
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

  /// Refunds a previous **Hobex Cloud** transaction.
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