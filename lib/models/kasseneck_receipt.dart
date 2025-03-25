import 'dart:typed_data';

import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/services/logo_service.dart';
import 'package:kasseneck_api/services/printer_service.dart';
import 'package:kasseneck_api/services/rksv_service.dart';

import '../enums/credit_card_provider.dart';
import '../enums/keck_payment_method.dart';
import 'kasseneck_item.dart';

class KasseneckReceipt implements Comparable<KasseneckReceipt> {
  final String receiptId;
  final String receiptType;
  final KeckPaymentMethod paymentMethod;
  final List<KasseneckItem> items;

  String companyName;
  String phone;
  String uid;
  String street;
  String zip;
  String city;
  String footer1;
  String footer2;
  String? footer3;
  String? footer4;
  List<String> legalMessage;
  List<String> thanksMessage;

  String cashregisterId;
  DateTime timeStamp;
  List<String> customerDetails;
  String turnoverCounterAES256ICM;
  String signaturePreviousReceipt;
  String certificateSerialNumber;
  String sig;
  String qr;
  List<VatRate> get vatCategories => items.map((e) => e.vat).toSet().toList();
  String fullReceiptId;
  CreditCardProvider? creditCardProvider;
  String? cardPaymentId;
  Map<String, dynamic>? cardPaymentData; // you can store the card payment data here
  String? logoUrl;
  bool? signatureSuccess;
  String? customProjectId;

  KasseneckReceipt({
    required this.receiptId,
    required this.cashregisterId,
    required this.timeStamp,
    required this.items,
    required this.paymentMethod,
    required this.turnoverCounterAES256ICM,
    required this.signaturePreviousReceipt,
    required this.certificateSerialNumber,
    required this.receiptType,
    required this.sig,
    required this.qr,
    required this.companyName,
    required this.phone,
    required this.uid,
    required this.street,
    required this.zip,
    required this.city,
    required this.fullReceiptId,
    required this.footer1,
    required this.footer2,
    this.logoUrl,
    this.footer3,
    this.footer4,
    this.customerDetails = const [],
    this.legalMessage = const [],
    this.thanksMessage = const [],
    this.creditCardProvider,
    this.cardPaymentId,
    this.cardPaymentData,
    this.signatureSuccess,
    this.customProjectId
  });

  factory KasseneckReceipt.create({
    required Map<String, dynamic> receipt,
    required String uid,
    required String phone,
    required String companyName,
    required String street,
    required String zip,
    required String city,
    required String footer1,
    required String footer2,
    String? logoUrl,
    String? footer3,
    String? footer4,
    required List<String> thanksMessage,
  }) {
    return KasseneckReceipt(
      qr: receipt['qr'],
      sig: receipt['sig'],
      certificateSerialNumber: receipt['certificateSerialNumber'],
      signaturePreviousReceipt: receipt['signaturePreviousReceipt'],
      turnoverCounterAES256ICM: receipt['turnoverCounterAES256ICM'],
      paymentMethod: KeckPaymentMethod.values.firstWhere((element) => element.name == receipt['paymentMethod'], orElse: () => KeckPaymentMethod.cash),
      items: receipt['items'].map<KasseneckItem>((e) => KasseneckItem.fromJson(e)).toList(),
      timeStamp: DateTime.parse(receipt['timeStamp']),
      cashregisterId: receipt['cashregisterId'],
      receiptType: receipt['receiptType'],
      receiptId: receipt['receiptId'],
      fullReceiptId: receipt['fullReceiptId'] ?? '',
      creditCardProvider: receipt['creditCardProvider'] != null ? CreditCardProvider.values.firstWhere((element) => element.name == receipt['creditCardProvider']) : null,
      cardPaymentId: receipt['cardPaymentId'],
      cardPaymentData: receipt['cardPaymentData'],
      customerDetails: List<String>.from(receipt['customerDetails']?.toString().split('\n')??[]),
      legalMessage: List<String>.from(receipt['legalMessage']?.toString().split('\n')??[]),
      signatureSuccess: receipt['signatureSuccess'],
      thanksMessage: thanksMessage,
      companyName: companyName,
      phone: phone,
      uid: uid,
      street: street,
      zip: zip,
      city: city,
      logoUrl: logoUrl,
      footer1: footer1,
      footer2: footer2,
      footer3: footer3,
      footer4: footer4,
      customProjectId: receipt['customProjectId']
    );
  }


  factory KasseneckReceipt.fromJson(Map<String, dynamic> json) {
    return KasseneckReceipt.create(
      receipt: json['receipt'],
      uid: json['uid'],
      phone: json['phone'],
      companyName: json['company'],
      street: json['street'],
      zip: json['zip'],
      city: json['city'],
      footer1: json['footer1'],
      footer2: json['footer2'],
      footer3: json['footer3'],
      footer4: json['footer4'],
      logoUrl: json['logo_url'],
      thanksMessage: List<String>.from(json['thanks_message']?.toString().split(r'\n')??[]),
    );
  }

  factory KasseneckReceipt.fromMetadata(Map<String, dynamic> receipt, Map<String, dynamic> metadata) {
    return KasseneckReceipt.create(
      receipt: receipt,
      uid: metadata['uid'],
      phone: metadata['phone'],
      companyName: metadata['company'],
      street: metadata['street'],
      zip: metadata['zip'],
      city: metadata['city'],
      footer1: metadata['footer1'],
      footer2: metadata['footer2'],
      footer3: metadata['footer3'],
      footer4: metadata['footer4'],
      logoUrl: metadata['logo_url'],
      thanksMessage: List<String>.from(metadata['thanks_message']?.toString().split(r'\n')??[]),
    );
  }

  String get downloadUrl => '${KasseneckApi.downloadBaseUrl}?fullReceiptId=$fullReceiptId';

  String get readableTime => '${timeStamp.day.toString().padLeft(2, '0')}.${timeStamp.month.toString().padLeft(2, '0')}.${timeStamp.year} ${timeStamp.hour.toString().padLeft(2, '0')}:${timeStamp.minute.toString().padLeft(2, '0')}:${timeStamp.second.toString().padLeft(2, '0')}';

  double get sum {
    double sum = 0;
    for (KasseneckItem item in items) {
      sum += item.quantity * item.singlePrice;
    }
    return sum;
  }

  @override
  int compareTo(KasseneckReceipt other) {
    return other.timeStamp.compareTo(timeStamp);
  }

  @override
  int get hashCode => receiptId.hashCode;

  Uint8List? get logo => LogoService.getLogoBytes(logoUrl);

  @override
  bool operator ==(Object other) {
    if (other is KasseneckReceipt) {
      return receiptId == other.receiptId;
    }
    return false;
  }

  Future init() => LogoService.loadLogo(logoUrl);

  Future printReceipt() => KeckPrinterService.printReceipt(this);

  Future<List<Uint8List>> getPrintBytes({required KeckPaperSize paperSize, bool qrAsImage = false}) => KeckPrinterService.getBytesFromReceipt(this, paperSize, qrAsImage: qrAsImage);

  bool get isSigFailed => !RKSVService.isSigSuccess(sig);
}