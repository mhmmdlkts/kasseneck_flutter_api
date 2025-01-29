import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/kasseneck_api.dart';

import 'kasseneck_item.dart';

class KasseneckReceipt {
  final String receiptId;
  final String receiptType;
  final String? paymentMethod;
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
    this.footer3,
    this.footer4,
    this.customerDetails = const [],
  });

  factory KasseneckReceipt.create({
    required Map<String, dynamic> receipt,
    required uid,
    required phone,
    required companyName,
    required street,
    required zip,
    required city,
    required footer1,
    required footer2,
    footer3,
    footer4,
    customerDetails = const [],
  }) {
    return KasseneckReceipt(
      qr: receipt['qr'],
      sig: receipt['sig'],
      certificateSerialNumber: receipt['certificateSerialNumber'],
      signaturePreviousReceipt: receipt['signaturePreviousReceipt'],
      turnoverCounterAES256ICM: receipt['turnoverCounterAES256ICM'],
      paymentMethod: receipt['paymentMethod'],
      items: receipt['items'].map<KasseneckItem>((e) => KasseneckItem.fromJson(e)).toList(),
      timeStamp: DateTime.parse(receipt['timeStamp']),
      cashregisterId: receipt['cashregisterId'],
      receiptType: receipt['receiptType'],
      receiptId: receipt['receiptId'],
      fullReceiptId: receipt['fullReceiptId'],
      companyName: companyName,
      phone: phone,
      uid: uid,
      street: street,
      zip: zip,
      city: city,
      footer1: footer1,
      footer2: footer2,
      footer3: footer3,
      footer4: footer4,
      customerDetails: customerDetails,
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
        customerDetails: List<String>.from(json['receipt']?['customerDetails']?.toString().split('\n')??[])
    );
  }

  String get downloadUrl => '${KasseneckApi.downloadBaseUrl}?fullReceiptId=$fullReceiptId';

  String get readableTime => '${timeStamp.day.toString().padLeft(2, '0')}.${timeStamp.month.toString().padLeft(2, '0')}.${timeStamp.year} ${timeStamp.hour.toString().padLeft(2, '0')}:${timeStamp.minute.toString().padLeft(2, '0')}';

  double get sum {
    double sum = 0;
    for (KasseneckItem item in items) {
      sum += item.amount * item.priceOne;
    }
    return sum;
  }
}