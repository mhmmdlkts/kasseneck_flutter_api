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
import 'models/keck_payment.dart';
import 'src/aufrufe.dart';
import 'src/kasse/belege.dart' show Stornoergebnis, Stornoposition;
import 'src/kasse/belegmail.dart' show Belegmailergebnis, belegMailFehlercodes;
import 'src/kasse/storno.dart' show pruefeKartenRueckbuchung, stornogruende;
import 'src/register/fehler.dart';
import 'src/v3.dart';

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
    show
        ErrorOutcome,
        KasseneckApiError,
        KasseneckHttpError,
        KasseneckReceiptFormatError,
        KasseneckValidationError,
        clientErrorCodes,
        isOutcomeUnknown;
// Die beiden Basen der 10.x-Linie (nur /v3).
export 'src/v3.dart' show kPublicBaseUrl, kPosBaseUrl;
// Der Storno mit Bezug (KasseneckApi.stornieren) liefert und nimmt diese Typen
// -- ohne sie waere er aus diesem Barrel nicht benutzbar.
export 'src/kasse/belege.dart' show Stornoergebnis, Stornoposition;
// Der Belegversand per Mail (KasseneckApi.belegSenden) liefert sein Ergebnis
// und nennt seine Fehlercodes aus diesem Teil -- ohne die Exporte koennte ein
// Aufrufer, der nur dieses Barrel importiert, weder das Ergebnis benennen noch
// pruefen, ob ein Code zum Katalog gehoert.
export 'src/kasse/belegmail.dart'
    show Belegmailergebnis, belegMailFehlercodes, istBelegMailFehlercode;
export 'src/kasse/storno.dart' show stornogruende, stornoFehlercodes, istStornoFehlercode, cardRefundReference;
// Mehrere Zahlungen je Beleg: `sellReceipt(payments:)` und
// `stornieren(zahlungen:)` nehmen KeckPaymentInput, der Beleg traegt
// KeckPayment, Ablehnungen kommen mit einem Code aus zahlungFehlercodes.
export 'models/keck_payment.dart' show KeckPayment, KeckPaymentInput, zahlungenFehler, zahlungenHoechstzahl;
export 'src/kasse/zahlungen.dart' show zahlungFehlercodes, istZahlungFehlercode, paymentsExpectedCents;
// Fehlercodes und Kataloge der Belegwelt unter /v3.
export 'src/receipt/codes.dart'
    show cancellationStatuses, isReceiptErrorCode, receiptEmailSendErrorCodes, receiptEmailVias, receiptErrorCodes;
// Die Typen, die der Beleg unter /v3 traegt, und der Leser fuer gespeicherte 9.x-Belege.
export 'models/registration_info.dart' show CancellationOf, RegistrationInfo;
export 'models/kasseneck_receipt.dart' show migrateStoredReceiptJson;
export 'models/beleg_layout.dart' show LayoutBannerTone;
export 'services/druck_logo.dart' show ladeDruckLogo;
// Zahlbetrag als Zwilling des Servers: was die Zahlungen eines Verkaufs
// zusammen ergeben muessen (unter /v3 ist payments Pflicht).
export 'src/receipt/due.dart'
    show
        ReceiptDueBreakdown,
        ReceiptDueLine,
        ReceiptDueTip,
        ReceiptDueTipRecipient,
        ReceiptDueTipShare,
        receiptDueBreakdown,
        receiptDueBreakdownForLines,
        receiptDueCents;
// HpsObserver ist zahlwegneutral und wird auch von HobexCloudPayments
// entgegengenommen -- ohne diesen Export waere sein Typ aus diesem Barrel
// nicht benennbar.
export 'src/hobex_hps/observer.dart' show HpsEvent, HpsEventKind, HpsObserver;

// Beleg-Blatt (npm 0.14.0): ein Beleg, der auf Bildschirm, Bon und PDF gleich aussieht.
// Mit `show`: Rechenhelfer wie `qrModulAnzahlWieNpm`, `punkteJeZeichen` oder
// `druckLogoSpeicherLeeren` bleiben ausserhalb der Paket-Schnittstelle.
export 'models/beleg_blatt.dart'
    show
        BelegBlatt,
        BlattBlock,
        BlattZeile,
        BlattLogoBlock,
        BlattQr,
        BlattMarke,
        BlattLogo,
        LogoMass,
        LogoStufe,
        belegBlatt,
        logoMass,
        logoRasterMass,
        qrBlattAnteil;
export 'models/logo_raster.dart' show LogoRaster, logoRaster;
export 'models/marke.dart' show markeBild;
export 'models/print_paper.dart' show DruckLogo;
export 'widgets/keck_beleg_blatt_widget.dart' show KeckBelegBlattWidget;

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
///   items: [KasseneckItem(name: 'Coffee', quantity: 1, vat: VatRate.vat20, priceCents: 320)],
/// );
/// ```
class KasseneckApi {
  /// Die oeffentliche Basis: alle Aufrufe dieses Clients sind oeffentlich.
  static const String _baseUrl = kPublicBaseUrl;
  static final String downloadBaseUrl = 'https://beleg.kasseneck.at';
  final String apiKey;
  final String cashregisterToken;
  final ReceiptPrintType? printType;
  String? printerAddress;

  /// HTTP-Client; im Konstruktor austauschbar (Tests/Mocking).
  ///
  /// **Kein `RetryClient` und kein anderer wiederholender Client.** Ein Beleg,
  /// ein Storno, eine Kartenbelastung (`hobexPay`), eine Erstattung und ein
  /// Stripe-Einzug sind nicht folgenlos wiederholbar; ein Client, der nach
  /// einem Netzfehler still ein zweites Mal sendet, erzeugt einen zweiten
  /// Beleg bzw. eine zweite Belastung, ohne dass dieses Paket es merkt. Bei
  /// `isOutcomeUnknown(e)` nachlesen, nie wiederholen.
  final http.Client _http;

  KasseneckApi({
    required this.apiKey,
    required this.cashregisterToken,
    this.printType,
    http.Client? httpClient,
    this.readTimeout = const Duration(seconds: 30),
    this.cardTimeout = const Duration(minutes: 3),
    this.signatureTimeout = const Duration(seconds: 90),
    String? clientHeader,
    bool omitKasseneckHeaders = false,
  })  : _http = httpClient ?? http.Client(),
        _kopf = V3Headers('KasseneckApi', clientHeader: clientHeader, omit: omitKasseneckHeaders);

  /// Kasseneck-Kopfzeilen der Anfragen ([clientHeader] nennt die App in der
  /// Zaehlung des Backends, Vorgabe `kasseneck_api/<version>`).
  final V3Headers _kopf;

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

  /// Ein Aufruf unter `/v3`, gepruefter Kopf (siehe `v3Post`): ohne
  /// Kennzeichen `dialect_mismatch`, HTML `route_missing`, HTTP != 200
  /// `server-error`. Netzfehler und Zeitlimit kommen als [KasseneckHttpError]
  /// mit `outcome`; die Frist ist je Aufruf waehlbar, ein Kartenaufruf braucht
  /// deutlich mehr Zeit als eine Belegabfrage.
  Future<http.Response> _senden(String name, String fehlerName, Map<String, dynamic> rumpf, Duration? deadline) {
    final body = jsonEncode(rumpf);
    return v3Post(
      _http,
      functionName: fehlerName,
      basis: _baseUrl,
      name: name,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'cashregister-token': cashregisterToken,
        'Content-Type': 'application/json',
      },
      kasseneck: _kopf,
      body: body,
      timeout: deadline ?? readTimeout,
    );
  }

  /// Der Rumpf einer Antwort mit HTTP 200 und Kennzeichen, strikt als UTF-8
  /// aus den Bytes (siehe `readBodyText`): leer `empty-body`, kein UTF-8
  /// `not-json`, bei wirkenden Aufrufen mit Ausgang unklar.
  static String _rumpf(String fehlerName, http.Response response) => readBodyText(fehlerName, response);

  /// Die Bytes einer Binaerantwort (Bericht-PDF), nie ueber eine Textdeutung.
  Future<Uint8List> _bytes(String endpoint, Map<String, dynamic> params) async {
    final antwort = await _senden(endpoint, endpoint, {'params': params}, null);
    if (antwort.bodyBytes.isEmpty) {
      throw KasseneckHttpError(endpoint, antwort.statusCode, 'empty-body', outcome: unreadableOutcome(endpoint));
    }
    return antwort.bodyBytes;
  }

  Future<dynamic> _kasseneckPostRequest(
      {required String endpoint, Map<String, dynamic> params = const {}, Duration? deadline}) async =>
      _rumpf(endpoint, await _senden(endpoint, endpoint, {'params': params}, deadline));

  Future<dynamic> _financeWebServicePostRequest(
      {required String method, Map<String, dynamic> params = const {}, Duration? deadline}) async {
    final fehlerName = '${Aufrufe.financeWebService}/$method';
    return _rumpf(
        fehlerName, await _senden(Aufrufe.financeWebService, fehlerName, {'params': params, 'method': method}, deadline));
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
  /// [_kasseneckPostRequest] bereits als 200 mit Kennzeichen und nicht
  /// leerem Rumpf durchgelassen, alles andere wirft dort. Bei einem
  /// signierenden Aufruf ist eine unlesbare Antwort Ausgang unklar.
  static Map<String, dynamic> _huelle(String endpoint, dynamic rumpf) {
    final Object? roh;
    try {
      roh = json.decode(rumpf as String);
    } on FormatException {
      // Der Rumpf selbst bleibt draussen: er kann eine fremde Fehlerseite
      // sein und gehoert nicht ins Protokoll.
      throw KasseneckHttpError(endpoint, 200, 'not-json', outcome: unreadableOutcome(endpoint));
    }
    if (roh is! Map<String, dynamic> || !roh.containsKey('status')) {
      throw KasseneckHttpError(endpoint, 200, 'missing-status', outcome: unreadableOutcome(endpoint));
    }
    return roh;
  }

  /// Das `data`-Objekt einer erfolgreichen Antwort — geprueft statt gecastet.
  static Map<String, dynamic> _daten(String endpoint, Map<String, dynamic> huelle) {
    final daten = huelle['data'];
    if (daten is! Map) {
      throw KasseneckHttpError(endpoint, 200, 'data-not-object', outcome: unreadableOutcome(endpoint));
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
  Future<Uint8List?> downloadDailyReport(DateTime dateTime) async => _bytes(Aufrufe.downloadDailyReport, {
        'year': dateTime.year,
        'month': dateTime.month,
        'day': dateTime.day
      });

  /// Downloads the monthly report PDF for [reportMonth] as raw bytes.
  Future<Uint8List?> downloadMonthlyReport(ReportMonth reportMonth) async => _bytes(Aufrufe.downloadReport, {
        'month': reportMonth.month.id,
        'year': reportMonth.year
      });

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
  /// weist einen zweiten Storno desselben Restes mit `already_cancelled` ab.
  ///
  /// Ohne [positionen] ist es ein Vollstorno der Restmengen; eine **leere**
  /// Liste ist ein Fehler, sonst wuerde aus einem missglueckten Teilstorno still
  /// ein Vollstorno. [grund] ist ein Schluessel aus [stornogruende] — sein
  /// Anzeigetext steht am Bon.
  ///
  /// [zahlungen] sind die Rueckzahlungen je Zahlung (Betraege negativ,
  /// `refundOf` = `id` der Originalzahlung); ohne Angabe spiegelt der Server
  /// die Restbetraege jeder Originalzahlung. Eine Einzel-Zahlungsart und
  /// Kartenfelder am Storno gibt es unter `/v3` nicht mehr: die Erstattung am
  /// Terminal beschreibt die Zahlung selbst (`provider`, `providerPaymentId`,
  /// `providerData`). Eine Karten-Rueckbuchung ueber einen Anbieter braucht
  /// einen Bezug: ihre eigene `providerPaymentId` oder, mit [original], die
  /// Kennung der erstatteten Kartenzahlung dort. Die liefert nur der
  /// Kassenweg; ueber diesen oeffentlichen Weg traegt das Original keine
  /// (`cardRefundReference`). Fehlt beides, wirft der Aufruf vor dem Senden.
  ///
  /// Fachliche Ablehnungen kommen als [KasseneckApiError] mit `code` aus
  /// `stornoFehlercodes` – daran entscheiden, nie am Text. Ist der Storno
  /// gebucht, die Antwort aber unlesbar, kommt `response_unreadable` mit
  /// Ausgang unklar (`isOutcomeUnknown`): nachlesen, nie wiederholen.
  Future<Stornoergebnis> stornieren({
    required String cashregisterId,
    required String originalReceiptId,
    required String grund,
    List<Stornoposition>? positionen,
    String? anmerkung,
    List<KeckPaymentInput>? zahlungen,
    KasseneckReceipt? original,
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
    if (zahlungen != null) {
      final fehler = zahlungenFehler(zahlungen, storno: true);
      if (fehler != null) throw KasseneckValidationError(name, fehler, 'request');
    }
    if (original != null && (original.receiptId != originalReceiptId || original.cashregisterId != cashregisterId)) {
      throw KasseneckValidationError(
          name,
          'original (${original.cashregisterId}/${original.receiptId}) ist nicht der Beleg '
          '$cashregisterId/$originalReceiptId',
          'request');
    }
    if (zahlungen != null) pruefeKartenRueckbuchung(zahlungen, original);

    final resJson = await _kasseneckJson(
      endpoint: name,
      params: {
        'cashregisterId': cashregisterId,
        'originalReceiptId': originalReceiptId,
        'reason': grund,
        if (positionen != null) 'items': [for (final p in positionen) {'index': p.index, 'quantity': p.menge}],
        if (anmerkung != null && anmerkung.isNotEmpty) 'note': anmerkung,
        if (zahlungen != null) 'payments': [for (final z in zahlungen) z.toJson()],
      },
      deadline: signatureTimeout,
    );

    if (resJson['status'] != 'success') {
      // Code (auch data.code) und Details bleiben erhalten: an `handled`
      // haengt, ob der Ausgang unklar ist.
      throw envelopeError(name, resJson, fallback: 'Storno fehlgeschlagen');
    }

    // Ab hier ist der Storno-Beleg ausgestellt und signiert: scheitert das
    // Lesen, kommt `response_unreadable` mit der Kennung, sofern die Antwort
    // sie mitbrachte; ein zweiter Storno waere eine zweite Ruecknahme.
    final Stornoergebnis ergebnis = readSignedResponse(
      name,
      () {
        final daten = _daten(name, resJson);
        return Stornoergebnis.ausAntwort(name, daten, () => _belegAus(name, daten));
      },
      kennung: () => _receiptIdAus(resJson['data']),
    );
    await ergebnis.beleg.init();
    return ergebnis;
  }

  /// Einen bereits ausgestellten Beleg als **Link auf die oeffentliche
  /// Belegseite** an [an] schicken — Endpunkt `sendReceiptEmail`, Zwilling von
  /// `sendReceiptEmail` im Client des npm-Pakets und Gegenstueck zu
  /// `RegisterReceiptClient.belegSenden` der Kassen-Anmeldung.
  ///
  /// Verschickt wird ein Link, kein PDF im Anhang: die Belegseite setzt dasselbe
  /// Zeilenmodell wie Bildschirm und Bondrucker und gibt dort auf Wunsch ein PDF
  /// aus. Der Beleg selbst bleibt byteidentisch (DEP, BAO §131) — das Backend
  /// protokolliert den Versand daneben, nie am Beleg.
  ///
  /// **Welche Kasse gemeint ist, sagt der `cashregister-token` dieses Clients**
  /// — es gibt hier kein `cashregisterId`. Ein Beleg einer anderen Kasse
  /// beantwortet das Backend mit `receipt_not_found`, genau wie einen, den es
  /// nicht gibt: sonst waere der Endpunkt ein Auskunftsdienst ueber fremde
  /// Belege.
  ///
  /// [language] nimmt das Backend heute entgegen, ohne es auszuwerten (es gibt
  /// eine Fassung, Deutsch); der Parameter steht im Vertrag, damit eine zweite
  /// Sprache spaeter kein neuer Aufruf wird.
  ///
  /// Die Adresse wird hier **nicht** auf Form geprueft — siehe
  /// `RegisterReceiptClient.belegSenden`: es gibt genau eine Adresspruefung,
  /// und die steht im Backend. Fachliche Ablehnungen kommen als
  /// [KasseneckApiError] mit einem Code aus [belegMailFehlercodes]; daran
  /// entscheiden, nie am Text. Die Schleuse des Backends (fuenf Mails je Beleg
  /// in 24 Stunden, 30 je Kasse und Stunde) meldet sich als `too_many_requests`.
  Future<Belegmailergebnis> belegSenden({
    required String fullReceiptId,
    required String an,
    String? language,
  }) async {
    const name = Aufrufe.sendReceiptEmail;
    final beleg = fullReceiptId.trim();
    final adresse = an.trim();
    if (beleg.isEmpty) {
      throw const KasseneckValidationError(name, 'fullReceiptId fehlt', 'request');
    }
    if (adresse.isEmpty) {
      throw const KasseneckValidationError(name, 'to fehlt', 'request');
    }
    final gewuenschteSprache = language?.trim() ?? '';

    final resJson = await _kasseneckJson(
      endpoint: name,
      params: {
        'fullReceiptId': beleg,
        'to': adresse,
        if (gewuenschteSprache.isNotEmpty) 'language': gewuenschteSprache,
      },
    );

    if (resJson['status'] != 'success') {
      throw envelopeError(name, resJson, fallback: 'Belegversand fehlgeschlagen');
    }

    // Ab hier ist die Mail draussen. Die einzelnen Felder werden deshalb
    // nachsichtig gelesen (siehe Belegmailergebnis.aus): ein Wurf ueber einem
    // fehlenden `at` saehe fuer die Kasse aus wie „nicht gesendet", und der
    // Kassier schickte sie ein zweites Mal an den Gast. Die Huelle selbst muss
    // trotzdem eine sein -- dieselbe Grenze zieht der Kassen-Weg im Transport.
    return Belegmailergebnis.aus(_daten(name, resJson), gesendetAn: adresse);
  }

  /// Issues a **zero** receipt (_Nullbeleg_), e.g. for the periodic RKSV check.
  Future<KasseneckReceipt?> zeroReceipt() async {
    return _createReceipt(receiptType: ReceiptType.zero);
  }

  /// Issues a **standard** RKSV receipt (a sale) for the given [items] and [paymentMethod].
  ///
  /// Several payments on one receipt (two cards, the rest in cash) go out as
  /// [payments] instead. They exclude [paymentMethod] and the card fields --
  /// the card details belong to each payment (backend: `PAYMENTS_CONFLICT`).
  /// One of the two is required; `mixed` is never sent, the server derives it.
  Future<KasseneckReceipt?> sellReceipt({
    KeckPaymentMethod? paymentMethod,
    List<KeckPaymentInput>? payments,
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
    if (paymentMethod == null && payments == null) {
      throw ArgumentError('paymentMethod oder payments ist Pflicht.');
    }
    return _createReceipt(
      receiptType: ReceiptType.standard,
      tip: tip,
      customerDetails: customerDetails,
      items: items,
      vouchers: vouchers,
      paymentMethod: paymentMethod,
      payments: payments,
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
    List<KeckPaymentInput>? payments,
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
    if (payments != null) {
      // Der alte Storno-Weg und der Null-/Startbeleg nehmen keine
      // Zahlungsliste (Backend: payments_not_allowed); ein Storno mit mehreren
      // Zahlungen laeuft ueber [stornieren].
      if (receiptType == ReceiptType.cancellation) {
        throw ArgumentError('payments am Storno gehen nur ueber stornieren.');
      }
      if (receiptType != ReceiptType.standard && receiptType != ReceiptType.training) {
        throw ArgumentError('payments sind bei receiptType "${receiptType.name}" nicht erlaubt.');
      }
      final fehler = zahlungsKonflikt({
            'paymentMethod': paymentMethod,
            'creditCardProvider': creditCardProvider,
            'cardPaymentId': cardPaymentId,
            'cardPaymentData': cardPaymentData,
          }) ??
          zahlungenFehler(payments, storno: false);
      if (fehler != null) throw ArgumentError(fehler);
      params['payments'] = [for (final p in payments) p.toJson()];
    }
    if (paymentMethod == KeckPaymentMethod.mixed) {
      throw ArgumentError(mixedNichtSenden);
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
      // beim Einlesen noch schiefgeht, wird `response_unreadable` (Ausgang
      // unklar) mit der Kennung, sofern die Antwort sie trug: nachlesen, nie
      // ein zweiter Verkauf.
      final KasseneckReceipt receipt = readSignedResponse(
        Aufrufe.createReceipt,
        () => _belegAus(Aufrufe.createReceipt, _daten(Aufrufe.createReceipt, resJson)),
        kennung: () => _receiptIdAus(resJson['data']),
      );
      await receipt.init();
      return receipt;
    } else {
      // Mit Code und Details: `receipt_outcome_unknown` heisst Ausgang
      // unklar, dann nachlesen statt wiederholen.
      throw envelopeError(Aufrufe.createReceipt, resJson, fallback: 'Unbekannter Fehler');
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
    // Eine Fehlerhuelle geht mit Code und Ausgang hinaus, nicht als
    // Lesefehler verpackt.
    if (resJson['status'] != 'success') {
      throw envelopeError('${Aufrufe.financeWebService}/status_cashbox', resJson);
    }
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
    if (resJson['status'] != 'success') {
      throw envelopeError('${Aufrufe.financeWebService}/status_signature', resJson);
    }
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
    if (resJson['status'] != 'success') {
      throw envelopeError(Aufrufe.stripeCaptureIntent, resJson);
    }
    // Erfolg gemeldet heisst: eingezogen. Eine unlesbare Nutzlast bleibt
    // Ausgang unklar (`response_unreadable`), nie ein gewoehnlicher Lesefehler.
    return readSignedResponse(
        Aufrufe.stripeCaptureIntent, () => StripeUrlSession.fromJson(resJson['data'] as Map<String, dynamic>));
  }

  /// Die Kassen-ID, gelesen aus [cashregisterToken].
  ///
  /// Liest dieselben Formate wie `cashboxIdFromToken` im Backend
  /// (`functions/gemeinsam/keys.js`):
  ///
  /// * aktuell `cb_<env>_<base64url(id:zufall)>` ohne `=`-Padding,
  /// * alt `cb_<env>_<base64(id:zufall)>` mit Padding,
  /// * alt reines `base64(id:zufall)` ohne Praefix.
  ///
  /// Ein Token, das in keines dieser Formate passt, wirft wie bisher eine
  /// [FormatException].
  String get cashregisterId {
    // Praefix cb_live_/cb_test_ abtrennen; base64.normalize gleicht das
    // base64url-Alphabet an und ergaenzt fehlendes Padding.
    final praefix = RegExp(r'^cb_(live|test)_', caseSensitive: false);
    final rumpf = cashregisterToken.replaceFirst(praefix, '');
    final decoded = utf8.decode(base64.decode(base64.normalize(rumpf)));
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
    // Fehlerhuelle mit Code und Ausgang weiterreichen: eine Kartenbelastung
    // mit unklarem Ausgang darf nie blind wiederholt werden.
    if (resJson['status'] != 'success') {
      throw envelopeError(Aufrufe.hobexPayApi, resJson);
    }
    // Erfolg gemeldet heisst: die Karte ist belastet. Ist der Beleg dann
    // unlesbar, bleibt der Ausgang unklar (`response_unreadable`), damit keine
    // App ein zweites Mal belastet.
    return readSignedResponse(Aufrufe.hobexPayApi, () => HobexReceipt.fromJson(resJson['data'] as Map<String, dynamic>));
  }

  /// Refunds a previous **Hobex Cloud** transaction.
  ///
  /// Returns `true` on success; a rejection throws [KasseneckApiError]. When
  /// `isOutcomeUnknown(e)` is true the refund may have gone through: look it
  /// up, never retry blindly.
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
    // Eine Fehlerhuelle wirft mit Code und Ausgang, statt still `false` zu
    // liefern: bei `isOutcomeUnknown` kann die Erstattung gelaufen sein, und
    // ein `false` luede zum zweiten Versuch ein (doppelte Erstattung).
    if (resJson['status'] != 'success') {
      throw envelopeError(Aufrufe.hobexRefundApi, resJson);
    }
    return true;
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