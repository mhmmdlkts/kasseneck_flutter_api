import 'package:kasseneck_api/enums/keck_invoice_payment_methode.dart';

class KeckInvoice {
  final String invoiceNumber;
  final DateTime invoiceDate;
  final DateTime serviceDateStart;
  final DateTime? serviceDateEnd; // optional
  final bool vatIncluded;
  final bool isTaxFree;
  final KeckInvoicePaymentMethode paymentMethod;
  final String company;
  final String customerName;
  final String customerPhone;
  final String customerAddressStreetName;
  final String customerAddressStreetNumber;
  final String customerAddressCountryCode;
  final String customerAddressZIP;
  final String customerAddressCity;
  final int? payUntil; // optional, used for bank transfer unpaid
  String downloadUrl;

  KeckInvoice({
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.serviceDateStart,
    this.serviceDateEnd,
    required this.vatIncluded,
    required this.isTaxFree,
    required this.paymentMethod,
    required this.company,
    required this.customerName,
    required this.customerPhone,
    required this.customerAddressStreetName,
    required this.customerAddressStreetNumber,
    required this.customerAddressCountryCode,
    required this.customerAddressZIP,
    required this.customerAddressCity,
    this.payUntil, // optional
    required this.downloadUrl
  });

  factory KeckInvoice.fromJson(Map<String, dynamic> json) {
    print(json);
    return KeckInvoice(
      invoiceNumber: json['invoiceNumber'] as String,
      invoiceDate: json['invoiceDate'].toDate(),
      serviceDateStart: json['serviceDateStart'].toDate(),
      serviceDateEnd: json['serviceDateEnd']?.toDate(),
      vatIncluded: json['vatIncluded'] as bool,
      isTaxFree: json['isTaxFree'] as bool,
      paymentMethod: KeckInvoicePaymentMethode.values.firstWhere(
        (e) => e.name == json['paymentMethod'],
        orElse: () => KeckInvoicePaymentMethode.bankTransferUnpaid // default value
      ),
      company: json['company'] as String,
      customerName: json['customerName'] as String,
      customerPhone: json['customerPhone'] as String,
      customerAddressStreetName: json['customerAddressStreetName'] as String,
      customerAddressStreetNumber: json['customerAddressStreetNumber'] as String,
      customerAddressCountryCode: json['customerAddressCountryCode'] as String,
      customerAddressZIP: json['customerAddressZIP'] as String,
      customerAddressCity: json['customerAddressCity'] as String,
      payUntil: json.containsKey('payUntil') ? (json['payUntil'] as int?) : null, // optional
      downloadUrl: json['downloadUrl'] as String
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'invoiceNumber': invoiceNumber,
      'invoiceDate': invoiceDate,
      'serviceDateStart': serviceDateStart,
      'serviceDateEnd': serviceDateEnd,
      'vatIncluded': vatIncluded,
      'isTaxFree': isTaxFree,
      'paymentMethod': paymentMethod.name,
      'company': company,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'customerAddressStreetName': customerAddressStreetName,
      'customerAddressStreetNumber': customerAddressStreetNumber,
      'customerAddressCountryCode': customerAddressCountryCode,
      'customerAddressZIP': customerAddressZIP,
      'customerAddressCity': customerAddressCity,
      if (payUntil != null) 'payUntil': payUntil, // optional
      'downloadUrl': downloadUrl
    };
  }
}

/*
                "invoiceNumber": 41,
                "invoiceDate": "16-05-2025",
                "serviceDateStart": "16-05-2025",
                "serviceDateEnd": "16-05-2025", // optional
                "vatIncluded": true,
                "isTaxFree": false,
                "paymentMethod": "bankTransferUnpaid",
                "company": "taxi",
                "customerName": "Nico Eibensteiner",
                "customerPhone": "+43660504148483",
                "customerAddressStreetName": "Derfflingerstraße",
                "customerAddressStreetNumber": "2D",
                "customerAddressCountryCode": "AT",
                "customerAddressZIP": "4020",
                "customerAddressCity": "Linz",
                "payUntil": 10
 */