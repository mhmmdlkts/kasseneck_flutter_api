import 'dart:typed_data';

import 'package:kasseneck_api/models/beleg_layout.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/models/keck_voucher.dart';
import 'package:kasseneck_api/services/logo_service.dart';
import 'package:kasseneck_api/services/printer_service.dart';
import 'package:kasseneck_api/services/rksv_service.dart';
import 'package:kasseneck_api/services/vienna_time.dart';

import '../enums/credit_card_provider.dart';
import '../enums/keck_payment_method.dart';
import '../enums/qr_print_mode.dart';
import '../enums/receipt_type.dart';
import '../enums/voucher_action.dart';
import '../enums/voucher_type.dart';
import 'kasseneck_item.dart';
import 'package:my_pos/enums/my_pos_print_response.dart';

class KasseneckReceipt implements Comparable<KasseneckReceipt> {
  final String receiptId;
  final ReceiptType receiptType;
  final KeckPaymentMethod paymentMethod;
  final List<KasseneckItem> items;

  List<KeckVoucher>? vouchers;
  String companyName;
  String phone;
  bool isSmallBusiness;
  String? uid;
  String taxnr;
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
  List<VatRate> get vatCategories {
    Set<VatRate> categories = {};
    for (KasseneckItem item in items) {
      categories.add(item.vat);
    }
    if (vouchers?.isNotEmpty??false) {
      for (KeckVoucher voucher in vouchers!) {
        if (voucher.isValid && voucher.action == VoucherAction.sell) {
          categories.add(VatRate.vat0);
        }
      }
    }
    return categories.toSet().toList();
  }
  String fullReceiptId;
  CreditCardProvider? creditCardProvider;
  String? cardPaymentId;
  Map<String, dynamic>? cardPaymentData; // you can store the card payment data here
  String? logoUrl;
  bool? signatureSuccess;
  String? customProjectId;

  /// Kreiseck-Branding am Belegende ("powered by kreiseck.com") — gesteuert
  /// ueber das Firestore-Flag users/{uid}.branding.kreiseck_logo, das das
  /// Backend als Metadatum `kreiseck_logo` mitliefert.
  bool showKreiseckLogo;

  /// Zeilenmodell des Backends (Kopf/Fuß wie beim Ausstellen, Belegart-
  /// Aufdruck, Regelwerk des Belegs); null bei altem Backend.
  BelegLayout? layout;
  /// Beleg einer Testumgebung (Aufdruck TESTKASSE).
  bool testKasse;
  /// Produktionskonto mit Test-Signatureinheit (Aufdruck TESTSIGNATUR).
  bool testSignatur;
  /// Kennung der eingefrorenen Kopf/Fuß-Version.
  String? kopfId;

  /// Was von diesem Beleg schon storniert (oder gerade reserviert) ist — roh,
  /// wie das Backend es führt. Gedeutet wird es in `restmengen`; hier steht es
  /// nur, damit der Storno-Dialog Reste zeigen kann, bevor er den Server fragt.
  List<Map<String, dynamic>> cancellations;

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
    required this.isSmallBusiness,
    required this.uid,
    required this.taxnr,
    required this.street,
    required this.zip,
    required this.city,
    required this.fullReceiptId,
    required this.footer1,
    required this.footer2,
    this.vouchers,
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
    this.customProjectId,
    this.showKreiseckLogo = false,
    this.layout,
    this.testKasse = false,
    this.testSignatur = false,
    this.kopfId,
    this.cancellations = const [],
  });

  factory KasseneckReceipt.create({
    required Map<String, dynamic> receipt,
    required String? uid,
    required String taxnr,
    required bool isSmallBusiness,
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
    bool showKreiseckLogo = false,
    BelegLayout? layout,
    bool testKasse = false,
    bool testSignatur = false,
    String? kopfId,
  }) {
    // Zuerst die Kennung: geht danach etwas schief, ist sie das Einzige,
    // womit sich der bereits signierte Beleg nachholen laesst.
    final String? kennung = _kennung(receipt);

    return KasseneckReceipt(
      qr: _pflichttext(receipt, 'qr', kennung),
      sig: _pflichttext(receipt, 'sig', kennung),
      certificateSerialNumber: _pflichttext(receipt, 'certificateSerialNumber', kennung),
      signaturePreviousReceipt: _pflichttext(receipt, 'signaturePreviousReceipt', kennung),
      turnoverCounterAES256ICM: _pflichttext(receipt, 'turnoverCounterAES256ICM', kennung),
      paymentMethod: KeckPaymentMethod.values.firstWhere((element) => element.name == receipt['paymentMethod'], orElse: () => KeckPaymentMethod.cash),
      // Nullbelege haben keine Positionen → items kann fehlen/null sein.
      items: [
        for (final e in (receipt['items'] is List ? receipt['items'] as List : const []))
          KasseneckItem.fromJson(e),
      ],
      vouchers: receipt['vouchers'] is List
          ? [for (final e in receipt['vouchers'] as List) KeckVoucher.fromJson(e)]
          : null,
      // Server liefert Wiener Wanduhrzeit ohne Offset → in echten Zeitpunkt
      // umrechnen, sonst verrutscht der Beleg bei fremder Geräte-Zeitzone.
      timeStamp: _zeitpunkt(receipt, kennung),
      cashregisterId: _pflichttext(receipt, 'cashregisterId', kennung),
      receiptType: ReceiptType.values.firstWhere((element) => element.name == receipt['receiptType'], orElse: () => ReceiptType.standard),
      receiptId: kennung ?? (throw KasseneckReceiptFormatError('receiptId')),
      fullReceiptId: _text(receipt['fullReceiptId']),
      creditCardProvider: receipt['creditCardProvider'] != null ? CreditCardProvider.values.firstWhere((element) => element.name == receipt['creditCardProvider'], orElse: () => CreditCardProvider.custom) : null,
      cardPaymentId: receipt['cardPaymentId'] is String ? receipt['cardPaymentId'] as String : null,
      cardPaymentData: receipt['cardPaymentData'] is Map
          ? Map<String, dynamic>.from(receipt['cardPaymentData'] as Map)
          : null,
      customerDetails: List<String>.from(receipt['customerDetails']?.toString().split('\n')??[]),
      legalMessage: List<String>.from(receipt['legalMessage']?.toString().split('\n')??[]),
      signatureSuccess: receipt['signatureSuccess'] is bool ? receipt['signatureSuccess'] as bool : null,
      thanksMessage: thanksMessage,
      companyName: companyName,
      phone: phone,
      isSmallBusiness: isSmallBusiness,
      uid: uid,
      taxnr: taxnr,
      street: street,
      zip: zip,
      city: city,
      logoUrl: logoUrl,
      footer1: footer1,
      footer2: footer2,
      footer3: footer3,
      footer4: footer4,
      customProjectId: receipt['customProjectId'] is String ? receipt['customProjectId'] as String : null,
      cancellations: [
        for (final e in (receipt['cancellations'] as List?) ?? const [])
          if (e is Map) Map<String, dynamic>.from(e),
      ],
      showKreiseckLogo: showKreiseckLogo,
      layout: layout,
      testKasse: testKasse,
      testSignatur: testSignatur,
      kopfId: kopfId,
    );
  }


  factory KasseneckReceipt.fromJson(Map<String, dynamic> json) {
    final roh = json['receipt'];
    if (roh is! Map) {
      // Ohne Belegteil gibt es auch keine Kennung — der Beleg ist von hier aus
      // nicht mehr auffindbar. Das gehoert benannt, nicht als TypeError.
      throw const KasseneckReceiptFormatError('receipt');
    }
    return KasseneckReceipt.create(
      receipt: Map<String, dynamic>.from(roh),
      isSmallBusiness: json['is_small_business'] == true,
      uid: json['uid'] is String ? json['uid'] as String : null,
      taxnr: _text(json['taxnr']),
      phone: _text(json['phone']),
      companyName: _text(json['company']),
      street: _text(json['street']),
      zip: _text(json['zip']),
      city: _text(json['city']),
      footer1: _text(json['footer1']),
      footer2: _text(json['footer2']),
      footer3: json['footer3'] is String ? json['footer3'] as String : null,
      footer4: json['footer4'] is String ? json['footer4'] as String : null,
      logoUrl: json['logo_url'] is String ? json['logo_url'] as String : null,
      thanksMessage: List<String>.from(json['thanks_message']?.toString().split(r'\n')??[]),
      showKreiseckLogo: json['kreiseck_logo'] == true,
      layout: BelegLayout.fromJson(json['layout']),
      testKasse: json['testKasse'] == true,
      testSignatur: json['testSignatur'] == true,
      kopfId: json['kopfId'] is String ? json['kopfId'] as String : null,
    );
  }

  // Nur die Beleg-Daten (ohne Firma/Metadaten)
  Map<String, dynamic> toReceiptJson() {
    return {
      'qr': qr,
      'sig': sig,
      'certificateSerialNumber': certificateSerialNumber,
      'signaturePreviousReceipt': signaturePreviousReceipt,
      'turnoverCounterAES256ICM': turnoverCounterAES256ICM,
      'paymentMethod': paymentMethod.name,
      'items': items.map((e) => e.toJson()).toList(),
      'vouchers': vouchers?.map((e) => e.toJson()).toList(),
      'timeStamp': timeStamp.toUtc().toIso8601String(),
      'cashregisterId': cashregisterId,
      'receiptType': receiptType.name,
      'receiptId': receiptId,
      'fullReceiptId': fullReceiptId,
      'creditCardProvider': creditCardProvider?.name,
      'cardPaymentId': cardPaymentId,
      'cardPaymentData': cardPaymentData,
      'customerDetails': customerDetails.join('\n'),
      'legalMessage': legalMessage.join('\n'),
      'signatureSuccess': signatureSuccess,
      'customProjectId': customProjectId,
    };
  }

// Nur die Metadaten (Firma, Adresse, etc.)
  Map<String, dynamic> toMetadataJson() {
    return {
      'is_small_business': isSmallBusiness,
      'uid': uid,
      'taxnr': taxnr,
      'phone': phone,
      'company': companyName,
      'street': street,
      'zip': zip,
      'city': city,
      'footer1': footer1,
      'footer2': footer2,
      'footer3': footer3,
      'footer4': footer4,
      'logo_url': logoUrl,
      'thanks_message': thanksMessage.join(r'\n'),
      'kreiseck_logo': showKreiseckLogo,
    };
  }

// Kombiniert — für lokale Speicherung (Isar)
  Map<String, dynamic> toJson() {
    return {
      'receipt': toReceiptJson(),
      ...toMetadataJson(),
    };
  }

  factory KasseneckReceipt.fromMetadata(Object? receipt, Map<String, dynamic> metadata) {
    if (receipt is! Map) {
      throw const KasseneckReceiptFormatError('receipt');
    }
    return KasseneckReceipt.create(
      receipt: Map<String, dynamic>.from(receipt),
      uid: metadata['uid'] is String ? metadata['uid'] as String : null,
      taxnr: _text(metadata['taxnr']),
      isSmallBusiness: metadata['is_small_business'] == true,
      phone: _text(metadata['phone']),
      companyName: _text(metadata['company']),
      street: _text(metadata['street']),
      zip: _text(metadata['zip']),
      city: _text(metadata['city']),
      footer1: _text(metadata['footer1']),
      footer2: _text(metadata['footer2']),
      footer3: metadata['footer3'] is String ? metadata['footer3'] as String : null,
      footer4: metadata['footer4'] is String ? metadata['footer4'] as String : null,
      logoUrl: metadata['logo_url'] is String ? metadata['logo_url'] as String : null,
      thanksMessage: List<String>.from(metadata['thanks_message']?.toString().split(r'\n')??[]),
      showKreiseckLogo: metadata['kreiseck_logo'] == true,
    );
  }

  /// Pflichtangaben nach § 132a Abs. 3 BAO, die auf diesem Beleg **fehlen** —
  /// leer, solange er vollstaendig ist. Feldnamen wie in der Antwort
  /// (`'company'`), nie deren Werte.
  ///
  /// Warum ein abgeleitetes Merkmal und kein Wurf: der Beleg ist an dieser
  /// Stelle bereits signiert und in der Kette. Ihn wegen einer fehlenden
  /// Kopfzeile zu verwerfen kostet genau den Beleg, den die
  /// Belegerteilungspflicht verlangt — dieselbe Abwaegung, die weiter unten
  /// die Grenze zwischen Signatur und Zierde zieht. Er darf aber auch nicht
  /// stumm bleiben: bis hierher entstand aus einem fehlenden `company` ein
  /// Pflichtbeleg mit **leerer erster Zeile**, ohne jedes Signal.
  ///
  /// Als Ableitung statt als gespeichertes Feld, damit die Aussage auf jedem
  /// Bauweg gilt — [KasseneckReceipt.create], [fromJson], [fromMetadata], der
  /// Konstruktor selbst und ein aus Isar zurueckgelesener Beleg — und damit
  /// sie nicht veraltet, wenn der Kopf nachgetragen wird.
  ///
  /// **Nur die Bezeichnung des leistenden Unternehmers** steht hier: `taxnr`,
  /// Anschrift und Fusszeilen sind auf einem Beleg keine Pflichtangaben (erst
  /// auf einer Rechnung nach § 11 UStG). Die Signatur- und Identitaetsfelder
  /// laufen weiter ueber `_pflichttext` und werfen.
  List<String> get fehlendePflichtangaben => [
        // § 132a Abs. 3 Z 1 BAO: eindeutige Bezeichnung des liefernden oder
        // leistenden Unternehmers.
        if (companyName.trim().isEmpty) 'company',
      ];

  /// `false`, wenn dem Beleg eine Pflichtangabe fehlt — siehe
  /// [fehlendePflichtangaben].
  bool get pflichtangabenVollstaendig => fehlendePflichtangaben.isEmpty;

  String get downloadUrl => '${KasseneckApi.downloadBaseUrl}/$fullReceiptId';

  /// Beleg-Zeit in Wiener Zeit (RKSV-Zeitzone), unabhängig von der Geräte-Zeitzone.
  String get readableTime {
    final t = ViennaTime.toWallClock(timeStamp);
    return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
  }

  /// Zwischensumme in **Cent** (exakte Integer-Arithmetik, keine Gleitkommafehler).
  int get subSumCents {
    int cents = 0;
    for (KasseneckItem item in items) {
      cents += item.totalCents;
    }
    for (KeckVoucher voucher in vouchers??[]) {
      if (voucher.action == VoucherAction.redeem && voucher.type == VoucherType.promo) {
        cents -= voucher.valueCents ?? 0;
      }
      if (voucher.action == VoucherAction.sell && voucher.type == VoucherType.value) {
        cents += voucher.valueCents ?? 0;
      }
    }
    return cents;
  }

  /// Gesamtsumme in **Cent** (exakte Integer-Arithmetik).
  int get sumCents {
    int cents = subSumCents;
    for (KeckVoucher voucher in vouchers??[]) {
      if (voucher.action == VoucherAction.redeem && voucher.type == VoucherType.value) {
        cents -= voucher.valueCents ?? 0;
      }
    }
    return cents;
  }

  /// Zwischensumme in Euro (Anzeige — fuer Arithmetik [subSumCents] nutzen).
  double get subSum => subSumCents / 100;

  /// Gesamtsumme in Euro (Anzeige — fuer Arithmetik [sumCents] nutzen).
  double get sum => sumCents / 100;

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

  Future<PrintResponse> printReceiptMyPos() => KeckPrinterService.printReceiptMypos(this);
  Future printReceiptWifi() => KeckPrinterService.printReceiptWifi(this);
  Future printReceiptBluetooth({QrPrintMode qrMode = QrPrintMode.imageRaster}) => KeckPrinterService.printReceiptBluetooth(this, qrMode: qrMode);

  Future<List<Uint8List>> getPrintBytes({required KeckPaperSize paperSize, QrPrintMode qrMode = QrPrintMode.imageRaster}) => KeckPrinterService.getBytesFromReceipt(this, paperSize, qrMode: qrMode);

  bool get isSigFailed => !RKSVService.isSigSuccess(sig);

  String get taxInfo => (uid?.isNotEmpty??false)?uid!:taxnr;

  /// Summe der eingeloesten Promo-Gutscheine in **Cent** (exakt).
  int get totalPromoVoucherValueCents {
    int cents = 0;
    for (KeckVoucher voucher in vouchers??[]) {
      if (voucher.action == VoucherAction.redeem && voucher.type == VoucherType.promo) {
        cents += voucher.valueCents ?? 0;
      }
    }
    return cents;
  }

  /// Summe der eingeloesten Promo-Gutscheine in Euro (Anzeige).
  double get totalPromoVoucherValue => totalPromoVoucherValueCents / 100;

  /// Trinkgeld-Positionen dieses Belegs.
  ///
  /// Die Positionen sind die Wahrheit — das Backend fuehrt am Belegdokument
  /// zwar ein abgeleitetes `tipCents`, gerechnet wird hier aber aus dem, was
  /// auch signiert wurde.
  List<KasseneckItem> get tipItems => items.where((item) => item.isTip).toList(growable: false);

  /// Trinkgeld gesamt in **Cent**. Auf einem Storno negativ.
  int get tipCents {
    int cents = 0;
    for (final item in tipItems) {
      cents += item.totalCents;
    }
    return cents;
  }

  /// Trinkgeld an Mitarbeiter in **Cent** — durchlaufender Posten, kein Umsatz
  /// des Betriebs. Bei Kartenzahlung ist das der Betrag, der weitergegeben
  /// werden muss.
  int get staffTipCents {
    int cents = 0;
    for (final item in tipItems) {
      if (!item.isOwnerTip) cents += item.totalCents;
    }
    return cents;
  }

  /// Trinkgeld an den Inhaber in **Cent** — Entgelt, in [sumCents] und in der
  /// USt-Bemessung enthalten.
  int get ownerTipCents {
    int cents = 0;
    for (final item in tipItems) {
      if (item.isOwnerTip) cents += item.totalCents;
    }
    return cents;
  }

  /// Trinkgeld gesamt in Euro (Anzeige — fuer Arithmetik [tipCents] nutzen).
  double get tip => tipCents / 100;
}

// ── Antwort lesen ───────────────────────────────────────────────────────────
//
// Jede Antwort von aussen ist fremd. Bis 5.0.0 wurden die `dynamic`-Werte hier
// ungeprueft an nicht nullbare Felder zugewiesen: ein einziges fehlendes Feld
// erzeugte einen `TypeError` NACH der Signatur, und mit der verworfenen
// Antwort ging die Kennung verloren — es blieb nichts zum Nachholen.
//
// Die Grenze verlaeuft zwischen zwei Arten von Feldern:
//
// * **Signatur und Identitaet** (`receiptId`, `cashregisterId`, `timeStamp`,
//   `qr`, `sig`, `certificateSerialNumber`, `signaturePreviousReceipt`,
//   `turnoverCounterAES256ICM`) — hier wird nichts erfunden. Ein Ersatzwert
//   waere keine Toleranz, sondern eine Behauptung ueber RKSV-Daten. Fehlt
//   eines, wirft [KasseneckReceiptFormatError] **mit der Kennung**, sofern sie
//   in der Antwort stand.
// * **Kopf- und Fusszeilen** (Firma, Anschrift, Steuerangabe, Fusszeilen) —
//   rein darstellend. `null` und `''` drucken gleich. Hier zu werfen hiesse,
//   einen signierten Beleg wegen einer fehlenden Fusszeile zu verlieren; das
//   ist die teurere Verwechslung.

/// Die Belegkennung aus einer rohen Belegantwort. Wirft nie.
String? _kennung(Map<String, dynamic> receipt) {
  final wert = receipt['receiptId'];
  return wert is String && wert.isNotEmpty ? wert : null;
}

/// Ein Pflichtfeld des Belegs. Leer ist erlaubt, fehlend oder falsch getippt
/// nicht — genau diese beiden Faelle gaben bisher den rohen `TypeError`.
String _pflichttext(Map<String, dynamic> receipt, String feld, String? kennung) {
  final wert = receipt[feld];
  if (wert is String) return wert;
  throw KasseneckReceiptFormatError(feld, receiptId: kennung);
}

DateTime _zeitpunkt(Map<String, dynamic> receipt, String? kennung) {
  final roh = _pflichttext(receipt, 'timeStamp', kennung);
  try {
    return ViennaTime.parseServerTimeStamp(roh);
  } on FormatException {
    throw KasseneckReceiptFormatError('timeStamp', receiptId: kennung);
  }
}

/// Ein rein darstellendes Textfeld — siehe die Grenze oben.
String _text(Object? wert) => wert is String ? wert : '';