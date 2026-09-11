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
import 'package:kasseneck_api/services/vienna_time.dart';

import 'enums/keck_payment_method.dart';
import 'enums/receipt_type.dart';
import 'enums/signature_status.dart';
import 'enums/voucher_action.dart';
import 'enums/voucher_type.dart';
import 'models/kasseneck_item.dart';
import 'models/keck_tip.dart';
import 'models/keck_tip_person.dart';
import 'models/kasseneck_receipt.dart';
import 'src/aufrufe.dart';
import 'src/kasse/belege.dart' show Stornoergebnis, Stornoposition;
import 'src/kasse/storno.dart' show stornogruende;
import 'src/register/fehler.dart';

export 'src/hobex_cloud/hobex_cloud_payments.dart'
    show HobexCloudPayments, HobexCloudResult;
// Der Ausgangs-Enum und der Beleg sind Teil der oeffentlichen Signatur von
// HobexCloudResult -- ohne diese Exporte koennte ein Aufrufer, der nur dieses
// Barrel importiert, den Typ von HobexCloudResult.outcome nicht benennen.
export 'src/payments/card_payment_outcome.dart' show CardPaymentOutcome;
export 'models/hobex_receipt.dart' show HobexReceipt;
// Der Beleg-Lesefehler traegt die receiptId eines bereits signierten Belegs --
// ohne diesen Export koennte ein Aufrufer, der nur dieses Barrel importiert,
// ihn nicht fangen und den Faden zum Beleg nicht aufnehmen. Dieselbe
// Ueberlegung fuer die beiden Antwortfehler: eine kaputte Antwort nach der
// Signatur ist etwas anderes als ein fehlgeschlagener Verkauf, und
// unterscheiden kann das nur, wer den Typ benennen darf.
export 'src/register/fehler.dart'
    show KasseneckApiError, KasseneckHttpError, KasseneckReceiptFormatError, KasseneckValidationError;
// Der Storno mit Bezug (KasseneckApi.stornieren) liefert und nimmt diese Typen
// -- ohne sie waere er aus diesem Barrel nicht benutzbar.
export 'src/kasse/belege.dart' show Stornoergebnis, Stornoposition;
export 'src/kasse/storno.dart' show stornogruende, stornoFehlercodes, istStornoFehlercode;
// HpsObserver ist zahlwegneutral und wird auch von HobexCloudPayments
// entgegengenommen -- ohne diesen Export waere sein Typ aus diesem Barrel
// nicht benennbar.
export 'src/hobex_hps/observer.dart' show HpsEvent, HpsEventKind, HpsObserver;

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
  static final String _baseUrl = 'https://api.kasseneck.at/v1';
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
    this.readTimeout = const Duration(seconds: 30),
    this.cardTimeout = const Duration(minutes: 3),
    this.signatureTimeout = const Duration(seconds: 90),
  }) : _http = httpClient ?? http.Client();

  /// Frist fuer lesende Aufrufe und fuer schreibende ohne Signatur.
  final Duration readTimeout;

  /// Frist fuer Aufrufe, an denen die **Signatureinheit** haengt — also
  /// `createReceipt` in allen drei Gestalten (Verkauf, Storno, Nullbeleg).
  ///
  /// Getrennt von [readTimeout], weil hier etwas anderes auf dem Spiel steht:
  /// ein Abbruch beendet nur das Warten der Kasse, nicht die Arbeit des
  /// Servers. Laeuft die Frist ab, ist der Beleg womoeglich laengst signiert
  /// und in der Kette — der Aufrufer bekommt aber eine `TimeoutException` und
  /// liest sie als Fehlschlag. Je knapper die Frist, desto oefter passiert
  /// genau das. Der Kassen-Weg (`RegisterReceiptClient.abschlussFrist`) gibt
  /// aus demselben Grund seit jeher 90 Sekunden; die pauschalen 30 Sekunden
  /// hier waren ein uebersehener Rest.
  final Duration signatureTimeout;

  /// Frist fuer Aufrufe, an denen ein Kartenterminal haengt. Deutlich laenger,
  /// weil der Karteninhaber am Geraet steht: Karte einstecken, PIN, Autorisierung.
  /// Die frueher pauschalen 30 s galten einem haengenden Belege-Cache und haben
  /// im Zahlweg eine durchgelaufene Zahlung als Fehlschlag gemeldet.
  final Duration cardTimeout;

  Future<dynamic> _kasseneckPostRequest(
      {required String endpoint, Map<String, dynamic> params = const {}, Duration? deadline}) async {
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
      // Ohne Frist bleibt ein haengender Request fuer immer offen — der Aufrufer
      // bekommt weder Ergebnis noch Fehler. Die Frist ist je Aufruf waehlbar:
      // ein Kartenaufruf braucht deutlich mehr Zeit als eine Belegabfrage.
    ).timeout(deadline ?? readTimeout);

    if (response.statusCode == 200 && response.body.isNotEmpty) {
      return response.body;
    } else {
      throw Exception(
        'Server-Fehler beim Aufruf von $endpoint: ${response.statusCode} - ${response.body}',
      );
    }
  }

  Future<dynamic> _financeWebServicePostRequest(
      {required String method, Map<String, dynamic> params = const {}, Duration? deadline}) async {
    Uri uri = Uri.parse('$_baseUrl/${Aufrufe.financeWebService}');

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
      // Dieselbe Frist wie nebenan: eine fest verdrahtete Spanne liess den
      // Konstruktorparameter `readTimeout` hier wirkungslos.
    ).timeout(deadline ?? readTimeout);

    if (response.statusCode == 200 && response.body.isNotEmpty) {
      return response.body;
    } else {
      throw Exception(
        'Server-Fehler beim Aufruf von financeWebService $method: ${response.statusCode} - ${response.body}',
      );
    }
  }

  /// Ruft [endpoint] und gibt die Huelle `{status, data}` **geprueft** zurueck.
  ///
  /// Der Umweg ueber diese Stelle ersetzt die implizite Zuweisung
  /// `final Map<String, dynamic> resJson = … json.decode(value)`, die an jeder
  /// Aufrufstelle stand. Sie erzeugte bei einem `200` mit Array, Skalar oder
  /// `null` einen rohen `TypeError` — im Verkauf **nach** der Signatur, mit
  /// einer Meldung, die kein Aufrufer anzeigen kann. Und ein `200` mit
  /// Nicht-JSON im Rumpf (HTML einer Captive-Portal- oder CDN-Fehlerseite)
  /// gab eine rohe `FormatException`.
  ///
  /// Wirft [KasseneckHttpError] — fangbar und ohne jeden Rumpfinhalt.
  Future<Map<String, dynamic>> _kasseneckJson({
    required String endpoint,
    Map<String, dynamic> params = const {},
    Duration? deadline,
  }) async =>
      _huelle(endpoint, await _kasseneckPostRequest(endpoint: endpoint, params: params, deadline: deadline));

  Future<Map<String, dynamic>> _financeJson({
    required String method,
    Map<String, dynamic> params = const {},
    Duration? deadline,
  }) async =>
      _huelle('financeWebService/$method',
          await _financeWebServicePostRequest(method: method, params: params, deadline: deadline));

  /// Geworfen wird [KasseneckHttpError] mit denselben `reason`-Werten, die der
  /// Kassen-Weg (`RegisterTransport.rufen`) fuer dieselben drei Lagen setzt.
  /// Ein blankes `Exception` waere hier zu wenig: im Verkauf, **nach** der
  /// Signatur, ist der Unterschied zwischen „die Antwort ist kaputt, der Beleg
  /// existiert" und „der Verkauf ist fehlgeschlagen" das, was der Aufrufer
  /// entscheiden muss — und gezielt fangen kann er nur einen eigenen Typ.
  ///
  /// Der Statuscode steht fest auf 200: was hier ankommt, hat
  /// [_kasseneckPostRequest] bereits als 200 mit nicht leerem Rumpf
  /// durchgelassen, alles andere wirft dort.
  static Map<String, dynamic> _huelle(String endpoint, dynamic rumpf) {
    final Object? roh;
    try {
      roh = json.decode(rumpf as String);
    } on FormatException {
      // Der Rumpf selbst bleibt draussen: er kann eine fremde Fehlerseite
      // sein und gehoert nicht ins Protokoll.
      throw KasseneckHttpError(endpoint, 200, 'not-json');
    }
    if (roh is! Map<String, dynamic>) {
      throw KasseneckHttpError(endpoint, 200, 'missing-status');
    }
    return roh;
  }

  /// Das `data`-Objekt einer erfolgreichen Antwort — geprueft statt gecastet.
  static Map<String, dynamic> _daten(String endpoint, Map<String, dynamic> huelle) {
    final daten = huelle['data'];
    if (daten is! Map) {
      throw KasseneckHttpError(endpoint, 200, 'data-not-object');
    }
    return Map<String, dynamic>.from(daten);
  }

  /// Die Belegkennung aus einer rohen Antwort — defensiv, wirft nie.
  ///
  /// Der Faden zum Beleg: geht das Einlesen schief, ist der Beleg trotzdem
  /// signiert und in der Kette, und `getReceipt(receiptId)` holt ihn nach.
  static String? _receiptIdAus(Object? daten) {
    if (daten is! Map) return null;
    final beleg = daten['receipt'];
    final wert = beleg is Map ? beleg['receiptId'] : daten['receiptId'];
    return wert is String && wert.isNotEmpty ? wert : null;
  }

  /// Downloads the daily report PDF for [dateTime] as raw bytes.
  Future<Uint8List?> downloadDailyReport(DateTime dateTime) async => _kasseneckPostRequest(
      endpoint: Aufrufe.downloadDailyReport,
      params: {
        'year': dateTime.year,
        'month': dateTime.month,
        'day': dateTime.day
      }).then((value) => Uint8List.fromList(value.codeUnits));

  /// Downloads the monthly report PDF for [reportMonth] as raw bytes.
  Future<Uint8List?> downloadMonthlyReport(ReportMonth reportMonth) async => _kasseneckPostRequest(
    endpoint: Aufrufe.downloadReport,
    params: {
      'month': reportMonth.month.id,
      'year': reportMonth.year
    }).then((value) => Uint8List.fromList(value.codeUnits));

  Future<ReportMonth?> getFirstReceiptDate() async {
    final resJson = await _kasseneckJson(endpoint: Aufrufe.getFirstReceiptDate);

    if (resJson['status'] == 'success') {
      final roh = resJson['data'];
      if (roh is! String) {
        throw Exception('getFirstReceiptDate: data ist kein Datum');
      }
      DateTime dateTime = DateTime.parse(roh);
      return ReportMonth.fromDateTime(dateTime);
    } else {
      final msg = resJson['message'] ?? 'Unbekannter Fehler';
      throw Exception('getFirstReceiptDate fehlgeschlagen: $msg');
    }
  }

  /// Issues a **cancellation** receipt that reverses [receipt] (its items, negated).
  ///
  /// **Deprecated — old cancellation path.** Runs through `createReceipt` without
  /// a reference to the original: no remaining quantities, no protection against
  /// cancelling twice, vouchers are not taken back. The backend still accepts it
  /// and answers with `deprecation`. Use [stornieren] instead (or
  /// `RegisterReceiptClient.stornieren` with a register login): reference,
  /// reason, partial cancellation, stable error codes.
  @Deprecated('Alter Storno-Weg ohne Bezug — KasseneckApi.stornieren (bzw. RegisterReceiptClient.stornieren) verwenden')
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

  /// **Deprecated — old cancellation path**, see [cancelReceipt].
  @Deprecated('Alter Storno-Weg ohne Bezug — KasseneckApi.stornieren (bzw. RegisterReceiptClient.stornieren) verwenden')
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

  /// Storno-Beleg zu einem bestehenden Beleg ueber den Endpunkt
  /// `cancelReceipt` — **der Storno-Weg mit Bezug** fuer den API-Schluessel-
  /// Zugang (Zwilling von `cancelReceipt` im Client des npm-Pakets, Gegenstueck
  /// zu `RegisterReceiptClient.stornieren` der Kassen-Anmeldung).
  ///
  /// Anders als [cancelReceipt] negiert hier der **Server**: er prueft Restmengen
  /// und Rechte, verkettet Original und Storno (`cancellationOf` am Storno,
  /// `cancellations[]` am Original), nimmt Gutscheine und Rabatte zurueck und
  /// weist einen zweiten Storno desselben Restes mit `bereits_storniert` ab.
  ///
  /// Ohne [positionen] ist es ein Vollstorno der Restmengen; eine **leere**
  /// Liste ist ein Fehler, sonst wuerde aus einem missglueckten Teilstorno still
  /// ein Vollstorno. [grund] ist ein Schluessel aus [stornogruende] — sein
  /// Anzeigetext steht am Bon.
  ///
  /// [kartenanbieter], [kartenzahlungId] und [kartenzahlungsdaten] beschreiben
  /// die **Erstattung** am Terminal (Gutschrift oder Aufhebung) fuer den
  /// Kartenblock am Storno-Bon — nie die Originalzahlung, und nur bei
  /// Rueckzahlweg Karte. Ohne [zahlungsart] entscheidet das Backend an der
  /// Zahlungsart des Originals.
  ///
  /// Fachliche Ablehnungen kommen als [KasseneckApiError] mit `code` aus
  /// `stornoFehlercodes` — daran entscheiden, nie am Text.
  Future<Stornoergebnis> stornieren({
    required String cashregisterId,
    required String originalReceiptId,
    required String grund,
    List<Stornoposition>? positionen,
    String? anmerkung,
    KeckPaymentMethod? zahlungsart,
    CreditCardProvider? kartenanbieter,
    String? kartenzahlungId,
    Map<String, dynamic>? kartenzahlungsdaten,
  }) async {
    const name = Aufrufe.cancelReceipt;
    if (cashregisterId.trim().isEmpty) {
      throw const KasseneckValidationError(name, 'cashregisterId fehlt', 'request');
    }
    if (originalReceiptId.trim().isEmpty) {
      throw const KasseneckValidationError(name, 'originalReceiptId fehlt', 'request');
    }
    if (!stornogruende.containsKey(grund)) {
      throw const KasseneckValidationError(name, 'Storno-Grund fehlt oder ist unbekannt', 'request');
    }
    if (positionen != null) {
      if (positionen.isEmpty) {
        throw const KasseneckValidationError(name, 'positionen muss eine nicht leere Liste sein', 'request');
      }
      if (positionen.any((p) => p.index < 0 || p.menge < 1)) {
        throw const KasseneckValidationError(name, 'Storno-Menge muss eine ganze Zahl >= 1 sein', 'request');
      }
    }
    if (anmerkung != null && anmerkung.length > 200) {
      throw const KasseneckValidationError(name, 'Anmerkung ist zu lang', 'request');
    }
    final karte = kartenanbieter != null || kartenzahlungId != null || kartenzahlungsdaten != null;
    if (karte && zahlungsart != null && zahlungsart != KeckPaymentMethod.creditCard) {
      // Ohne zahlungsart entscheidet das Backend an der Zahlungsart des
      // Originals; ein ausdruecklich anderer Rueckzahlweg ist hier schon falsch.
      throw const KasseneckValidationError(name, 'Kartendaten gibt es nur bei zahlungsart creditCard', 'request');
    }

    final resJson = await _kasseneckJson(
      endpoint: name,
      params: {
        'cashregisterId': cashregisterId,
        'originalReceiptId': originalReceiptId,
        'reason': grund,
        if (positionen != null) 'items': [for (final p in positionen) {'index': p.index, 'quantity': p.menge}],
        if (anmerkung != null && anmerkung.isNotEmpty) 'note': anmerkung,
        'paymentMethod': ?zahlungsart?.name,
        'creditCardProvider': ?kartenanbieter?.name,
        if (kartenzahlungId != null && kartenzahlungId.isNotEmpty) 'cardPaymentId': kartenzahlungId,
        'cardPaymentData': ?kartenzahlungsdaten,
      },
      deadline: signatureTimeout,
    );

    if (resJson['status'] != 'success') {
      final msg = resJson['message'];
      throw KasseneckApiError(name, msg is String && msg.isNotEmpty ? msg : 'Storno fehlgeschlagen',
          code: fehlercodeAus(resJson));
    }

    // Ab hier ist der Storno-Beleg ausgestellt und signiert — jeder Fehler
    // traegt deshalb die Kennung mit, sofern die Antwort sie mitbrachte (siehe
    // [_belegAus]); ein zweiter Storno waere eine zweite Ruecknahme.
    final daten = _daten(name, resJson);
    final receipt = _belegAus(name, daten);
    final bezug = daten['cancellationOf'];
    if (bezug is! Map || bezug['receiptId'] is! String) {
      throw KasseneckValidationError(name, 'Antwort enthaelt keinen Bezug (data.cancellationOf fehlt)', 'response',
          receiptId: receipt.receiptId);
    }
    final rest = daten['remaining'];
    if (rest is! List || rest.any((n) => n is! int)) {
      throw KasseneckValidationError(name, 'Antwort enthaelt keine Restmengen (data.remaining fehlt)', 'response',
          receiptId: receipt.receiptId);
    }
    await receipt.init();
    return Stornoergebnis(
      beleg: receipt,
      originalReceiptId: bezug['receiptId'] as String,
      originalFullReceiptId: bezug['fullReceiptId'] is String ? bezug['fullReceiptId'] as String : null,
      restmengen: rest.cast<int>(),
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
    KeckTip? tip,
  }) async {
    return _createReceipt(
      receiptType: ReceiptType.standard,
      tip: tip,
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
    Map<String, dynamic>? cardPaymentData,
    KeckTip? tip,
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

    if (tip != null) {
      // Trinkgeld wird NICHT als Position geschickt: Das Backend baut sie aus
      // diesem Parameter, weil erst dort feststeht, ob der Empfaenger Inhaber
      // ist (Entgelt, anteilig auf die Steuersaetze) oder Mitarbeiter
      // (durchlaufender Posten, 0 %). Eine Position vom Client wird abgelehnt.
      if (!receiptType.allowsTip) {
        throw ArgumentError(
            'Trinkgeld ist nur auf Standard- und Trainingsbelegen moeglich.');
      }
      // Ein Beleg nur mit Trinkgeld ist keiner — es haengt an einer Leistung.
      if (items == null || items.isEmpty) {
        throw ArgumentError('Trinkgeld: Beleg braucht mindestens eine Position');
      }
      final tipFehler = tip.fehler;
      if (tipFehler != null) {
        throw ArgumentError(tipFehler);
      }
      params['tip'] = tip.toJson();
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

    final resJson = await _kasseneckJson(
      endpoint: Aufrufe.createReceipt,
      params: params,
      deadline: signatureTimeout,
    );

    if (resJson['status'] == 'success') {
      // Ab hier ist der Beleg signiert und steht in der Kette. Alles, was
      // beim Einlesen noch schiefgeht, darf ihn nicht mehr verschwinden
      // lassen — siehe [_belegAus].
      KasseneckReceipt receipt = _belegAus(Aufrufe.createReceipt, _daten(Aufrufe.createReceipt, resJson));
      await receipt.init();
      return receipt;
    } else {
      final msg = resJson['message'] ?? 'Unbekannter Fehler';
      throw Exception('createReceipt fehlgeschlagen: $msg');
    }
  }

  /// Einen Beleg aus dem `data`-Objekt lesen, **ohne die Kennung zu verlieren**.
  ///
  /// Der Beleg ist an dieser Stelle bereits ausgestellt. Fliegt beim Einlesen
  /// noch ein Fehler, ist die `receiptId` das Einzige, womit er sich nachholen
  /// laesst (`getReceipt`): ohne sie ist ein Beleg, der in der Signaturkette
  /// steht, fuer die Kasse verloren — und der naheliegende zweite Versuch
  /// waere ein zweiter Umsatz. Deshalb wird hier **jede** Ausnahme in einen
  /// [KasseneckReceiptFormatError] mit Kennung uebersetzt, nicht nur die, die
  /// das Modell selbst wirft.
  static KasseneckReceipt _belegAus(String endpoint, Map<String, dynamic> daten) {
    try {
      return KasseneckReceipt.fromJson(daten);
    } on KasseneckReceiptFormatError catch (e) {
      if (e.receiptId != null) rethrow;
      throw KasseneckReceiptFormatError(e.field, receiptId: _receiptIdAus(daten));
    } catch (e) {
      throw KasseneckReceiptFormatError(
        'receipt',
        receiptId: _receiptIdAus(daten),
        causeType: e.runtimeType.toString(),
      );
    }
  }

  /// Personen, denen sich Trinkgeld zuweisen laesst.
  ///
  /// Es ist **dieselbe Menge, die [sellReceipt] akzeptiert**: Wer hier steht,
  /// wird beim Verkauf nicht zurueckgewiesen. Aus einer Person macht
  /// [KeckTipPerson.mit] den Anteil fuer [KeckTip.recipients] — so kann keine
  /// Kennung danebengreifen, die der Server ablehnt.
  Future<List<KeckTipPerson>> listTipRecipients() async {
    final resJson = await _kasseneckJson(endpoint: Aufrufe.listMyTipRecipients);

    if (resJson['status'] != 'success') {
      final msg = resJson['message'] ?? 'Unbekannter Fehler';
      throw Exception('listMyTipRecipients fehlgeschlagen: $msg');
    }
    final roh = resJson['data'] is Map ? resJson['data']['recipients'] : null;
    if (roh is! List) {
      // Keine Liste ist etwas anderes als eine leere Liste: „niemand
      // zuweisbar" darf nicht aussehen wie „Antwort kaputt".
      throw const KasseneckValidationError(
          Aufrufe.listMyTipRecipients, 'Antwort enthaelt keine Liste (data.recipients fehlt)', 'response');
    }
    return [
      for (final e in roh)
        if (e is Map) KeckTipPerson.aus(Map<String, dynamic>.from(e)),
    ];
  }

  /// Fetches a single receipt by its [receiptId].
  Future<KasseneckReceipt?> getReceipt(String receiptId) async {
    final resJson = await _kasseneckJson(endpoint: Aufrufe.getReceipt, params: {
      'receiptId': receiptId
    });

    if (resJson['status'] == 'success') {
      KasseneckReceipt receipt = _belegAus(Aufrufe.getReceipt, _daten(Aufrufe.getReceipt, resJson));
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

    final resJson = await _kasseneckJson(endpoint: Aufrufe.getReportV2, params: {
      'start': start.toIso8601String().split('.').first,
      'end': end.toIso8601String().split('.').first
    });
    if (resJson['status'] == 'success') {
      final daten = _daten(Aufrufe.getReportV2, resJson);
      final rohMetadata = daten['metadata'];
      if (rohMetadata is! Map) {
        throw const KasseneckValidationError(
            Aufrufe.getReportV2, 'Antwort enthaelt keine Metadaten (data.metadata fehlt)', 'response');
      }
      final Map<String, dynamic> metadata = Map<String, dynamic>.from(rohMetadata);
      final rohBelege = daten['receipts'];
      if (rohBelege is! List) {
        // Keine Liste ist etwas anderes als eine leere Liste: „im Zeitraum
        // nichts verkauft" darf nicht aussehen wie „Antwort kaputt". Wortgleich
        // mit `belege.dart` auf dem Kassen-Weg -- dieselbe Lage, derselbe Typ.
        throw const KasseneckValidationError(
            Aufrufe.getReportV2, 'Antwort enthaelt keine Belegliste (data.receipts fehlt)', 'response');
      }
      // Gezaehlt wird erst HIER. Die Zeile stand vorher ueber den Pruefungen
      // und las `data['receipts']` mit einem String-Index: bei `data: [...]`
      // oder `data: "text"` griff das in eine Liste bzw. einen Text, bei
      // `receipts: {...}` scheiterte der Cast — in allen drei Faellen ein
      // roher TypeError, genau vor der Stelle, die ihn verhindern soll.
      debugPrint('getReportV2 $start–$end: ${rohBelege.length} Belege');
      // Pro Beleg parsen: EIN defekter/unerwarteter Beleg (z. B. Nullbeleg ohne
      // items) darf nicht den gesamten Abruf kippen — sonst bleibt der ganze
      // Tages-/Zeitraums-Cache leer und keine Buchung findet ihren Beleg.
      final List<KasseneckReceipt> receipts = [];
      for (final r in rohBelege) {
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
    final resJson = await _financeJson(method: 'status_cashbox');
    try {
      String res = resJson['data']['rkdbMessage']['status'];
      return CashboxStatus.values.where((element) => element.name == res).firstOrNull;
    } catch (e) {
      throw Exception('Fehler beim Parsen des Cashbox-Status: $e');
    }
  }

  Future<SignatureStatus?> getSignatureStatus(String zertifikatNrHex) async {
    final resJson = await _financeJson(
      method: 'status_signature',
      params: {
        'zertifikatnr_hex': zertifikatNrHex
      },
    );
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
    final resJson = await _kasseneckJson(
        endpoint: Aufrufe.createPaymentLinkStripe,
        params: {
          'items': items.map((e) => e.toJson()).toList(),
          'createReceiptAfterPayment': createReceiptAfterPayment,
          'mode': mode.name,
          'webhookId': ?webhookId,
          // Die Namen des Backends (createPaymentLinkStripe: customer_email,
          // customer_phone) -- camelCase fiel dort still unter den Tisch, der
          // Gast bekam nie eine Bestaetigung.
          'customer_phone': ?customerPhone,
          'customer_email': ?customerEmail
        },
    );
    try {
      return StripeUrlSession.fromJson(resJson['data']);
    } catch (e) {
      throw Exception('Fehler beim Erstellen des Stripe-Links: $e');
    }
  }

  Future<StripeUrlSession?> stripeCaptureIntent({
    required String stripeSessionId,
  }) async {
    final resJson = await _kasseneckJson(
        endpoint: Aufrufe.stripeCaptureIntent,
        params: {
          'stripe_sessions_id': stripeSessionId
        },
    );
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
    final resJson = await _kasseneckJson(
        endpoint: Aufrufe.hobexPayApi,
        params: {
          'transactionId': transactionId,
          'amount': amount,
          'tip': tip,
          'reference': reference
        },
        deadline: cardTimeout,
    );
    try {
      return HobexReceipt.fromJson(resJson['data']);
    } catch (e) {
      throw Exception('Fehler beim Parsen des Hobex-Belegs: $e');
    }
  }

  /// Refunds a previous **Hobex Cloud** transaction.
  Future<bool> hobexRefund({required String transactionId, required double amount, double tip = 0}) async {
    final resJson = await _kasseneckJson(
        endpoint: Aufrufe.hobexRefundApi,
        params: {
          'transactionId': transactionId,
          'amount': amount,
          'tip': tip,
        },
        deadline: cardTimeout,
    );
    return resJson['status'] == 'success';
  }

  /// Fragt den Stand einer Hobex-Cloud-Transaktion ab.
  ///
  /// Das ist die Klaerstufe des Cloud-Wegs: nach einem Abbruch beantwortet sie
  /// die Frage, ob die Zahlung trotzdem durchgelaufen ist. Der Vertrag
  /// unterscheidet bewusst zwei Ausgaenge, die NICHT gleich behandelt werden
  /// duerfen:
  ///
  /// * Rueckgabe `null`: der Dienst hat geantwortet und kennt zu
  ///   [transactionId] nichts, oder der gelieferte Beleg war nicht lesbar.
  ///   Das ist eine Aussage -- weiter klaeren/pollen ist sinnvoll.
  /// * Eine geworfene Ausnahme: wir konnten den Dienst gar nicht erst fragen
  ///   (Server-Fehler, Netzwerk, unerwartetes Antwortformat). Das ist ein
  ///   Transportfehler und KEINE Aussage ueber den Vorgang -- er darf niemals
  ///   als "nicht belastet" gelesen werden. Genau diese Vermischung von
  ///   Nichtwissen und Aussage fuehrte zu einer durchgelaufenen Zahlung, die
  ///   als Fehlschlag gemeldet wurde.
  ///
  /// Eine Abfrage, kein Kartenfluss -- daher die kurze Lesefrist statt der
  /// Kartenfrist.
  Future<HobexReceipt?> hobexGetStatus({required String transactionId}) async {
    // Ueber dieselbe Huelle wie jeder andere Aufruf: ein unerwarteter Rumpf
    // (Array, Skalar, HTML einer Fehlerseite) ist ein Transportfehler -- wir
    // konnten den Dienst nicht sinnvoll befragen -- und wirft benannt. Die
    // frueher hier gebaute Meldung hing den ganzen Rumpf an; die Ausnahmen der
    // Klaerschleife landen im Nachweistext, und der wird im Belastungsstreit
    // gelesen. Auch das ungesicherte json.decode faellt damit weg.
    final Map<String, dynamic> resJson = await _kasseneckJson(
      endpoint: Aufrufe.hobexGetStatus,
      params: {'transactionId': transactionId},
      deadline: readTimeout,
    );

    if (resJson['status'] != 'success' || resJson['data'] == null) return null;
    try {
      return HobexReceipt.fromJson(resJson['data']);
    } catch (_) {
      return null;
    }
  }

  /// Zufallsquelle der Hobex-Transaktionskennung. Eine Quelle fuer alle
  /// Aufrufe: `Random()` je Aufruf neu zu bauen kostet, ohne die Folge besser
  /// zu machen.
  static final Random _hobexZufall = Random();

  /// Erzeugt eine Transaktionskennung fuer Hobex: 19 Stellen, rein numerisch.
  ///
  /// Aufbau mit fester Stellenzahl je Bestandteil, gerechnet nach **Wiener
  /// Wanduhrzeit**: Jahr (2, ohne Jahrhundert), Monat, Tag, Stunde, Minute,
  /// Sekunde (je 2), Millisekunde (3) und vier Zufallsziffern.
  ///
  /// **Dasselbe Verfahren wie `newHobexTransactionId` im JS-Zwilling**
  /// (@kreiseck/kasseneck-api, src/payments/hobex.ts). Beide Seiten pinnen
  /// dieselben Golden-Werte in ihrer Testsuite; weicht eine ab, faellt ihr
  /// Test.
  ///
  /// Wiener Zeit statt Geraetezeit: sonst haetten zwei Kassen desselben
  /// Betriebs in verschiedenen Zeitzonen Kennungen, die sich um Stunden
  /// unterscheiden, und der Tageswechsel in der Kennung faende nicht zum
  /// Geschaeftstag statt.
  ///
  /// [zeitpunkt] und [zufall] dienen dem Test; ohne Angabe gelten
  /// `DateTime.now()` und `Random.nextDouble`.
  static String newHobexTransactionId({DateTime? zeitpunkt, double Function()? zufall}) {
    final DateTime wand = ViennaTime.toWallClock(zeitpunkt ?? DateTime.now());
    final double Function() quelle = zufall ?? _hobexZufall.nextDouble;
    String zwei(int wert) => wert.toString().padLeft(2, '0');
    final StringBuffer kennung = StringBuffer()
      ..write(zwei(wand.year % 100))
      ..write(zwei(wand.month))
      ..write(zwei(wand.day))
      ..write(zwei(wand.hour))
      ..write(zwei(wand.minute))
      ..write(zwei(wand.second))
      ..write(wand.millisecond.toString().padLeft(3, '0'))
      // Vier Ziffern, immer vierstellig: eine kuerzere Zahl wuerde die Kennung
      // verkuerzen und damit ihre Form verlassen. Der Wert wird auf [0, 1)
      // begrenzt -- eine fremde Zufallsquelle koennte 1 liefern.
      ..write((_hobexBegrenzt(quelle()) * 10000).floor().toString().padLeft(4, '0'));
    return kennung.toString();
  }

  /// Auf `[0, 1)` begrenzen -- eine fremde Zufallsquelle haelt sich nicht daran.
  static double _hobexBegrenzt(double wert) =>
      wert.isFinite ? wert.clamp(0.0, 0.9999999) : 0.0;
}