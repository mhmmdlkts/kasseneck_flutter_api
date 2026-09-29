import 'dart:typed_data';

import 'package:kasseneck_api/models/receipt_sheet.dart' show SheetLogoSize;
import 'package:kasseneck_api/models/receipt_layout.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/kasseneck_api.dart' show KasseneckApi, KasseneckReceiptFormatError;
import 'package:kasseneck_api/models/keck_voucher.dart';
import 'package:kasseneck_api/services/logo_service.dart';
import 'package:kasseneck_api/services/printer_service.dart';
import 'package:kasseneck_api/services/rksv_service.dart';
import 'package:kasseneck_api/services/vienna_time.dart';

import '../enums/credit_card_provider.dart';
import '../enums/keck_payment_method.dart';
import '../enums/qr_print_mode.dart';
import '../src/printing/qr_groesse.dart';
import '../enums/receipt_type.dart';
import '../enums/voucher_action.dart';
import '../enums/voucher_type.dart';
import 'kasseneck_item.dart';
import 'registration_info.dart';
import 'keck_payment.dart';
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

  /// UID-Nummer (`vatId`, frueher `uid`).
  String? vatId;

  /// Steuernummer (`taxNumber`, frueher `taxnr`).
  String taxNumber;
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

  /// Zahlungsliste (mehrere Zahlungen je Beleg), nur vorhanden, wenn der
  /// Beleg sie traegt. Altbelege haben keine; dort gelten [paymentMethod] und
  /// die Kartenfelder. Siehe [KeckPayment].
  List<KeckPayment>? payments;
  String? logoUrl;
  bool? signatureSuccess;
  String? customProjectId;

  /// Kreiseck-Branding am Belegende ("powered by kreiseck.com") — gesteuert
  /// ueber das Firestore-Flag users/{uid}.branding.kreiseck_logo, das das
  /// Backend als Metadatum `kreiseck_logo` mitliefert.
  bool showKreiseckLogo;

  /// Groesse des Firmenlogos am Beleg (Kasse-Einstellung `logoScale` des
  /// Betriebs, vom Backend als Metadatum `logo_scale` mitgeliefert). Bon und
  /// Bildschirm setzen das Logo in dieser Stufe; fehlt sie, gilt M.
  SheetLogoSize logoScale;

  /// Zeilenmodell des Backends (Kopf/Fuß wie beim Ausstellen, Belegart-
  /// Aufdruck, Regelwerk des Belegs); null bei altem Backend.
  ReceiptLayout? layout;

  /// Zeigt das gelieferte Zeilenmodell alles, was dieser Beleg hergibt?
  ///
  /// Der Beleg wird an EINER Stelle gebaut -- im Backend, über
  /// `@kreiseck/kasseneck-api`; Druck, Bildschirm und PDF rendern nur noch.
  /// Solange aber Geräte gegen ein älteres Backend sprechen können, kann ein
  /// Layout ankommen, das weniger zeigt, als der Beleg weiß.
  ///
  /// Bekannter Fall: Kartenzahlungsblöcke. Bis Paket 0.8.0 trug das
  /// Zeilenmodell nur den Hobex-Block; GP Tom, SumUp, myPOS und Stripe
  /// fehlten. Ein Bon aus so einem Layout sähe die Zahlung nicht mehr, obwohl
  /// der Beleg die Daten mitbringt. Wer `false` bekommt, nimmt den alten
  /// Bauer.
  ///
  /// Bewusst KEIN Versionsvergleich: eine Zahl im Layout wäre eine zweite
  /// Zusage, die selbst wieder driften kann. Gefragt wird die Sache selbst.
  ///
  /// **Weg damit**, sobald kein Backend unter Paket 0.9.0 mehr im Feld ist:
  /// dann können dieser Getter, `PrintPaper.setKeckReceipt` und
  /// `KeckReceiptWidget` verschwinden, und es gibt wirklich nur einen Bauer.
  ///
  /// Mit Zahlungsliste zaehlt jeder Kartenblock aus [cardPayments]: steht
  /// derselbe Anbieter zweimal auf dem Beleg, muss sein Kopf auch zweimal im
  /// Layout stehen -- ein Paket vor der Aufschluesselung zeigte nur den Block
  /// der alten Einzelfelder, und der zweite Kartenbeleg fiele stumm weg.
  bool get isLayoutComplete {
    final ReceiptLayout? l = layout;
    if (l == null) return false;
    final Map<String, int> noetig = {};
    for (final k in cardPayments) {
      final String? ueberschrift = cardBlockHeadings[k.provider];
      if (ueberschrift != null) noetig[ueberschrift] = (noetig[ueberschrift] ?? 0) + 1;
    }
    for (final MapEntry(key: ueberschrift, value: anzahl) in noetig.entries) {
      final int vorhanden = l.lines.where((z) => z is LayoutTextLine && z.text.contains(ueberschrift)).length;
      if (vorhanden < anzahl) return false;
    }
    return true;
  }

  /// Die Kartenzahlungsbloecke dieses Belegs, in Druckreihenfolge -- Zwilling
  /// von `kartenblock` in `receipt/layout.ts` des npm-Pakets.
  ///
  /// Mit Zahlungsliste je Zahlung mit bekanntem Anbieter und Terminaldaten
  /// ein Block; zwei Karten desselben Anbieters ergeben zwei. Die alten
  /// Einzelfelder zaehlen dann nicht -- ausser bei hoechstens einer Zahlung
  /// ohne Terminaldaten neben gesetzten Altfeldern: dort traegt der alte
  /// Block, wie ohne Liste. `custom` bleibt drin (der Bauer entscheidet, dass
  /// er nichts zeigt), ein unbekannter Anbieter nicht.
  List<({CreditCardProvider provider, Map<String, dynamic> data, String? paymentId})> get cardPayments {
    final List<KeckPayment>? zahlungen = payments;
    final bool altfelderTragen = zahlungen != null &&
        zahlungen.length <= 1 &&
        zahlungen.every((z) => z.providerData == null) &&
        creditCardProvider != null &&
        cardPaymentData != null;
    if (zahlungen != null && zahlungen.isNotEmpty && !altfelderTragen) {
      return [
        for (final z in zahlungen)
          if (z.provider != null && z.providerData != null)
            (provider: z.provider!, data: z.providerData!, paymentId: z.providerPaymentId),
      ];
    }
    final CreditCardProvider? anbieter = creditCardProvider;
    final Map<String, dynamic>? daten = cardPaymentData;
    if (anbieter == null || daten == null) return const [];
    return [(provider: anbieter, data: daten, paymentId: cardPaymentId)];
  }
  /// Beleg einer Testumgebung (Aufdruck TESTKASSE), Drahtfeld `testCashregister`.
  bool testCashregister;
  /// Produktionskonto mit Test-Signatureinheit (Aufdruck TESTSIGNATUR),
  /// Drahtfeld `testSignature`.
  bool testSignature;
  /// Kennung der eingefrorenen Kopf/Fuß-Version (`headerVersionId`).
  String? headerVersionId;

  /// Regelwerk, nach dem der Beleg ausgestellt wurde (`receipt.layoutRuleset`);
  /// fehlt bei Altbelegen.
  int? layoutRuleset;

  /// Registrierdaten fuer den Block „Prüfangaben“ (nur Nullbelege).
  RegistrationInfo? registrationInfo;

  /// Nur am Storno-Beleg: das Original (Kennung, Volltext-Kennung, Zeitpunkt).
  CancellationOf? cancellationOf;

  /// Nur am Nullbeleg: die Art (`monthly`, `annual`, `annual_replacement`,
  /// `final`, `outage_end`); bestimmt den Aufdruck (MONATSBELEG …).
  String? zeroKind;

  /// Nur am Storno-Beleg: der Grund, Code aus `cancellationReasons` (englisch, wie
  /// unter `/v3`; ein unbekannter kuenftiger Code bleibt roh stehen).
  String? cancellationReason;

  /// Was von diesem Beleg schon storniert (oder gerade reserviert) ist — roh,
  /// wie das Backend es führt. Gedeutet wird es in `remainingQuantities`; hier steht es
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
    required this.vatId,
    required this.taxNumber,
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
    this.payments,
    this.signatureSuccess,
    this.customProjectId,
    this.showKreiseckLogo = false,
    this.logoScale = SheetLogoSize.m,
    this.layout,
    this.testCashregister = false,
    this.testSignature = false,
    this.headerVersionId,
    this.layoutRuleset,
    this.registrationInfo,
    this.cancellationOf,
    this.zeroKind,
    this.cancellationReason,
    this.cancellations = const [],
  });

  factory KasseneckReceipt.create({
    required Map<String, dynamic> receipt,
    required String? vatId,
    required String taxNumber,
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
    SheetLogoSize logoScale = SheetLogoSize.m,
    ReceiptLayout? layout,
    bool testCashregister = false,
    bool testSignature = false,
    String? headerVersionId,
    RegistrationInfo? registrationInfo,
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
      payments: KeckPayment.listFromJson(receipt['payments']),
      customerDetails: List<String>.from(receipt['customerDetails']?.toString().split('\n')??[]),
      legalMessage: List<String>.from(receipt['legalMessage']?.toString().split('\n')??[]),
      signatureSuccess: receipt['signatureSuccess'] is bool ? receipt['signatureSuccess'] as bool : null,
      thanksMessage: thanksMessage,
      companyName: companyName,
      phone: phone,
      isSmallBusiness: isSmallBusiness,
      vatId: vatId,
      taxNumber: taxNumber,
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
      logoScale: logoScale,
      layout: layout,
      testCashregister: testCashregister,
      testSignature: testSignature,
      headerVersionId: headerVersionId ?? _nichtLeer(receipt['headerVersionId']),
      layoutRuleset: receipt['layoutRuleset'] is num ? (receipt['layoutRuleset'] as num).toInt() : null,
      registrationInfo: registrationInfo ?? RegistrationInfo.fromJson(receipt['registrationInfo']),
      cancellationOf: CancellationOf.fromJson(receipt['cancellationOf']),
      zeroKind: _nichtLeer(receipt['zeroKind']),
      cancellationReason: _nichtLeer(receipt['cancellationReason']),
    );
  }


  /// Liest `data` von `createReceipt`/`getReceipt` unter `/v3` (bzw. die
  /// Form aus [toJson]): Beleg unter `receipt`, daneben Kopf und Fuss
  /// (`company`, `vatId`, `taxNumber`, …), `testCashregister`,
  /// `testSignature`, `headerVersionId`, `registrationInfo`, `logo_scale` und
  /// das Server-Layout. Die deutschen Namen aus 0.x (`uid`, `taxnr`,
  /// `testCashregister`, `logo_skala` …) liest diese Stelle nicht mehr; eine in 9.x
  /// gespeicherte Form geht vorher durch [migrateStoredReceiptJson].
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
      vatId: json['vatId'] is String ? json['vatId'] as String : null,
      taxNumber: _text(json['taxNumber']),
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
      logoScale: SheetLogoSize.fromCode(json['logo_scale'] is String ? json['logo_scale'] as String : null),
      layout: ReceiptLayout.fromJson(json['layout']),
      testCashregister: json['testCashregister'] == true,
      testSignature: json['testSignature'] == true,
      headerVersionId: _nichtLeer(json['headerVersionId']),
      registrationInfo: RegistrationInfo.fromJson(json['registrationInfo']),
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
      if (payments != null) 'payments': [for (final p in payments!) p.toJson()],
      'customerDetails': customerDetails.join('\n'),
      'legalMessage': legalMessage.join('\n'),
      'signatureSuccess': signatureSuccess,
      'customProjectId': customProjectId,
      'headerVersionId': ?headerVersionId,
      'layoutRuleset': ?layoutRuleset,
      'registrationInfo': ?registrationInfo?.toJson(),
      'cancellationOf': ?cancellationOf?.toJson(),
      'zeroKind': ?zeroKind,
      'cancellationReason': ?cancellationReason,
      if (cancellations.isNotEmpty) 'cancellations': cancellations,
    };
  }

// Nur die Metadaten (Firma, Adresse, etc.)
  Map<String, dynamic> toMetadataJson() {
    return {
      'is_small_business': isSmallBusiness,
      'vatId': vatId,
      'taxNumber': taxNumber,
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
      'logo_scale': logoScale.code,
      'testCashregister': testCashregister,
      'testSignature': testSignature,
      'headerVersionId': ?headerVersionId,
      'registrationInfo': ?registrationInfo?.toJson(),
    };
  }

// Kombiniert – für lokale Speicherung (Isar), in der Form von `/v3`;
// [KasseneckReceipt.fromJson] liest sie zurueck.
  Map<String, dynamic> toJson() {
    return {
      'receipt': toReceiptJson(),
      ...toMetadataJson(),
      'layout': ?layout?.toJson(),
    };
  }

  factory KasseneckReceipt.fromMetadata(Object? receipt, Map<String, dynamic> metadata) {
    if (receipt is! Map) {
      throw const KasseneckReceiptFormatError('receipt');
    }
    return KasseneckReceipt.create(
      receipt: Map<String, dynamic>.from(receipt),
      vatId: metadata['vatId'] is String ? metadata['vatId'] as String : null,
      taxNumber: _text(metadata['taxNumber']),
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
      logoScale: SheetLogoSize.fromCode(metadata['logo_scale'] is String ? metadata['logo_scale'] as String : null),
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
  /// **Nur die Bezeichnung des leistenden Unternehmers** steht hier: `taxNumber`,
  /// Anschrift und Fusszeilen sind auf einem Beleg keine Pflichtangaben (erst
  /// auf einer Rechnung nach § 11 UStG). Die Signatur- und Identitaetsfelder
  /// laufen weiter ueber `_pflichttext` und werfen.
  List<String> get missingMandatoryFields => [
        // § 132a Abs. 3 Z 1 BAO: eindeutige Bezeichnung des liefernden oder
        // leistenden Unternehmers.
        if (companyName.trim().isEmpty) 'company',
      ];

  /// `false`, wenn dem Beleg eine Pflichtangabe fehlt — siehe
  /// [missingMandatoryFields].
  bool get hasMandatoryFields => missingMandatoryFields.isEmpty;

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
  Future printReceiptBluetooth(
          {QrPrintMode qrMode = QrPrintMode.imageRaster,
          QrModuleSize qrModuleSize = QrModuleSize.auto}) =>
      KeckPrinterService.printReceiptBluetooth(this, qrMode: qrMode, qrModuleSize: qrModuleSize);

  Future<List<Uint8List>> getPrintBytes(
          {required KeckPaperSize paperSize,
          QrPrintMode qrMode = QrPrintMode.imageRaster,
          QrModuleSize qrModuleSize = QrModuleSize.auto}) =>
      KeckPrinterService.getBytesFromReceipt(this, paperSize,
          qrMode: qrMode, qrModuleSize: qrModuleSize);

  bool get isSigFailed => !RKSVService.isSigSuccess(sig);

  String get taxInfo => (vatId?.isNotEmpty ?? false) ? vatId! : taxNumber;

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

/// Ein Text, der nur zaehlt, wenn er nicht leer ist.
String? _nichtLeer(Object? wert) => wert is String && wert.isNotEmpty ? wert : null;

/// Bringt einen Beleg in der gespeicherten Form von 9.x (`toJson` mit 0.x-
/// Namen: `uid`, `taxnr`, `logo_skala`, `testCashregister`, `testSignatur`, `kopfId`,
/// Layout mit `regelwerk`/`ton`) in die Form von `/v3`, die
/// [KasseneckReceipt.fromJson] liest. Fuer lokale Ablagen, die das Update
/// ueberleben muessen: gelesen wird migriert, verworfen wird nichts. Schon
/// englische Schluessel bleiben, wie sie sind; ein englischer Schluessel
/// gewinnt immer gegen seinen deutschen Vorgaenger. [stored] bleibt unberuehrt.
///
/// Das Layout geht durch [storedLayoutJson]: ist es nicht ganz lesbar, fehlt
/// es im Ergebnis, und die Kasse baut den Beleg selbst.
Map<String, dynamic> migrateStoredReceiptJson(Map<String, dynamic> stored) {
  final neu = Map<String, dynamic>.from(stored);
  const namen = {
    'uid': 'vatId',
    'taxnr': 'taxNumber',
    'logo_skala': 'logo_scale',
    'testKasse': 'testCashregister',
    'testSignatur': 'testSignature',
    'kopfId': 'headerVersionId',
  };
  for (final MapEntry(key: vorher, value: nachher) in namen.entries) {
    if (!neu.containsKey(vorher)) continue;
    final wert = neu.remove(vorher);
    neu.putIfAbsent(nachher, () => wert);
  }
  final pruef = neu.remove('pruefangaben');
  if (pruef is Map && !neu.containsKey('registrationInfo')) {
    neu['registrationInfo'] = {
      'cardRegisteredAt': pruef['karteRegistriertAm'],
      'cashregisterRegisteredAt': pruef['kasseRegistriertAm'],
    };
  }
  if (neu.containsKey('layout')) {
    final layout = storedLayoutJson(neu['layout']);
    // Ein halb lesbares Zeilenmodell faellt weg: ohne Layout baut die Kasse
    // den Beleg aus seinen Angaben neu (receiptLayoutFromResult), samt
    // TESTKASSE und Warnzeilen. Ein halbes gewaenne sonst immer.
    if (layout == null) {
      neu.remove('layout');
    } else {
      neu['layout'] = layout;
    }
  }
  return neu;
}

/// Ein gespeichertes Zeilenmodell (`layout`) in der Form von `/v3`, wie
/// [ReceiptLayout.fromJson] es liest. Zwilling von `fromStoredLayout` im
/// npm-Paket: nimmt die Form von 0.x bzw. 9.x (`regelwerk`, Bannerzeilen mit
/// `ton` `belegart`/`warnung`) und die Form 1.0 (`ruleset`, `tone`
/// `receipt_type`/`warning`); ein unbekannter Ton geht woertlich durch. Die
/// Schluessel werden an ihrer Stelle umbenannt, die Reihenfolge bleibt; traegt
/// ein Objekt beide Namen, gewinnt der englische.
///
/// `null`, wenn es kein ganzes Zeilenmodell ist: kein Objekt, keine oder leere
/// `lines`, eine Zeile, die kein Objekt ist, oder kein `paperSize`. Dann baut
/// der Aufrufer neu (aus Beleg und `testCashregister`/`testSignature`), und
/// TESTKASSE und die Warnzeilen stehen wieder da. [stored] bleibt unberuehrt.
///
/// Die Gegenrichtung (`toStoredLayout` im npm-Paket) gibt es hier nicht: dieses
/// Paket schreibt das Zeilenmodell nur noch in der Form 1.0
/// ([ReceiptLayout.toJson], auch an `createPrintJob` unter `/v3`), nie in der
/// inneren Form von 0.x.
Map<String, dynamic>? storedLayoutJson(Object? stored) {
  if (stored is! Map) return null;
  final zeilen = stored['lines'];
  if (zeilen is! List || zeilen.isEmpty || zeilen.any((z) => z is! Map)) return null;
  final papier = stored['paperSize'];
  if (papier is! String || papier.isEmpty) return null;
  final raus = _umbenannt(stored, const {'regelwerk': 'ruleset'});
  raus['lines'] = [
    for (final z in zeilen.cast<Map>())
      _umbenannt(z, const {'ton': 'tone'}, werte: {'ton': (w) => _tonNach10[w] ?? w}),
  ];
  return raus;
}

const Map<Object?, String> _tonNach10 = {'belegart': 'receipt_type', 'warnung': 'warning'};

/// [objekt] mit umbenannten Schluesseln an derselben Stelle; [werte] ersetzt
/// den Wert eines (alten) Schluessels.
Map<String, dynamic> _umbenannt(Map objekt, Map<String, String> namen, {Map<String, Object? Function(Object?)> werte = const {}}) {
  final raus = <String, dynamic>{};
  for (final MapEntry(:key, :value) in objekt.entries) {
    final alt = '$key';
    final neu = namen[alt] ?? alt;
    if (neu != alt && objekt.containsKey(neu)) continue;
    raus[neu] = werte[alt]?.call(value) ?? value;
  }
  return raus;
}
