/// Die Aufrufe der Rechnungs-API — Zwilling von `createRechnungApi` im
/// JS-Paket `@kreiseck/kasseneck-api/rechnung`.
///
/// **Geprüft wird hier nichts Fachliches.** Die Anfrage geht unverändert an das
/// Backend, das sie gegen denselben Vertrag prüft und einen Formfehler als
/// `validation` mit `details['errors']` zurückgibt — zwei Prüfungen hießen zwei
/// Wahrheiten. Ausnahme sind Aufrufe mit „genau einer" Kennung: welche gemeint
/// ist, lässt sich ohne Server entscheiden. Auch die Lagerfelder (Rückgabe-Wahl,
/// `articleId`, `stockLocationId`) prüft wie im JS-Zwilling nur der Server.
///
/// **Vor dem ersten Ausstellen [getInvoiceSetupStatus] aufrufen.** Ohne Freigabe
/// durch Kasseneck (live) oder mit unvollständiger Einrichtung antworten die
/// Aufrufe mit `invoice_api_not_enabled` bzw. `invoice_setup_incomplete`.
library;

import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../aufrufe.dart';
import '../register/fehler.dart';
import 'modelle.dart';
import 'transport.dart';
import 'vertrag.dart';

class InvoiceApi {
  InvoiceApi({
    required String apiKey,
    String? baseUrl,
    http.Client? httpClient,
    Duration? timeout,
    String? clientHeader,
    bool omitKasseneckHeaders = false,
  }) : _transport = InvoiceTransport(
          apiKey: apiKey,
          baseUrl: baseUrl,
          httpClient: httpClient,
          timeout: timeout,
          clientHeader: clientHeader,
          omitKasseneckHeaders: omitKasseneckHeaders,
        );

  /// Mit einem bereits gebauten Transport (Tests, eigene Adresse).
  InvoiceApi.withTransport(InvoiceTransport transport) : _transport = transport;

  final InvoiceTransport _transport;

  // ---- Kunden -------------------------------------------------------------------

  Future<Customer> createCustomer(CustomerInput customer, {String? idempotencyKey}) async {
    const name = Aufrufe.createCustomer;
    final daten = await _transport.call(name, {
      'customer': customer.toJson(),
      'idempotencyKey': ?idempotencyKey,
    });
    return _lesen(name, () => Customer.fromJson(_objekt(daten, 'customer')));
  }

  Future<Customer> getCustomer({String? customerId, String? externalId}) async {
    const name = Aufrufe.getCustomer;
    _genauEine(name, {'customerId': customerId, 'externalId': externalId});
    final daten = await _transport.call(name, {'customerId': ?customerId, 'externalId': ?externalId});
    return _lesen(name, () => Customer.fromJson(_objekt(daten, 'customer')));
  }

  /// Nur die übergebenen Felder ändern sich (Feldnamen wie in [CustomerInput.toJson]).
  Future<Customer> updateCustomer(String customerId, Map<String, dynamic> patch) async {
    const name = Aufrufe.updateCustomer;
    final daten = await _transport.call(name, {'customerId': customerId, 'customer': patch});
    return _lesen(name, () => Customer.fromJson(_objekt(daten, 'customer')));
  }

  /// Mindestens einer von [externalId], [vatId], [email] oder [name] (Namensanfang).
  Future<CustomerPage> searchCustomers({
    String? externalId,
    String? vatId,
    String? email,
    String? name,
    int? limit,
    String? cursor,
  }) async {
    const aufruf = Aufrufe.searchCustomers;
    final daten = await _transport.call(aufruf, {
      'externalId': ?externalId,
      'vatId': ?vatId,
      'email': ?email,
      'name': ?name,
      'limit': ?limit,
      'cursor': ?cursor,
    });
    return _lesen(aufruf, () => CustomerPage(
          customers: [for (final c in _liste(daten, 'customers')) Customer.fromJson(c)],
          nextCursor: daten['nextCursor'] is String ? daten['nextCursor'] as String : null,
        ));
  }

  // ---- Rechnungen ---------------------------------------------------------------

  /// Stellt eine Rechnung aus. Positionen mit
  /// [IssueInvoiceItemInput.reservationId] loesen eine Reservierung der
  /// Lager-API ein.
  ///
  /// Eine Rechnung ohne Steuer, die auf der UID des Kunden beruht (ig.
  /// Lieferung, Reverse Charge), entsteht nur mit einem Ergebnis der
  /// UID-Pruefung (FinanzOnline, sonst VIES) am Tag des Ausstellens. Am Code
  /// entscheiden: `vat_id_check_pending` heisst spaeter mit demselben
  /// `idempotencyKey` wiederholen (`details['retryAfter']` Sekunden) oder mit
  /// [IssueInvoiceRequest.acceptVatIdRisk] trotzdem ausstellen;
  /// `vat_id_invalid` heisst so nicht ausstellen.
  Future<IssueResult> issueInvoice(IssueInvoiceRequest request) async {
    const name = Aufrufe.issueInvoice;
    if (request.dryRun == true) {
      throw const KasseneckValidationError(name, 'dryRun: true gehört zu previewInvoice', 'request');
    }
    final daten = await _transport.call(name, request.toJson());
    return _lesen(name, () => IssueResult.fromJson(daten));
  }

  /// Probelauf von [issueInvoice]: dieselbe Anfrage wird geprüft und gerechnet
  /// wie beim Ausstellen, aber nichts festgeschrieben — keine Nummer, kein
  /// Dokument, keine Zahlung. Die Antwort nennt Summen, Steuerfall samt Grund,
  /// Sprache, Marke, E-Rechnung und die Hinweise — oder scheitert mit demselben
  /// Fehlercode, mit dem das Ausstellen scheitern würde.
  ///
  /// Der `idempotencyKey` wird nicht verbraucht: dieselbe Anfrage lässt sich
  /// danach unverändert ausstellen. Verbindlich ist das Ausstellen — zwischen
  /// Probelauf und Ausstellen können sich Kunde oder Konto ändern.
  ///
  /// Geht als `issueInvoice` mit `dryRun: true` hinaus; Fehler tragen deshalb
  /// den Aufrufnamen `issueInvoice`. Ein Server ohne Probelauf lehnt das
  /// unbekannte Feld als `validation` ab.
  Future<PreviewResult> previewInvoice(IssueInvoiceRequest request) async {
    const name = Aufrufe.issueInvoice;
    final daten = await _transport.call(name, {...request.toJson(), 'dryRun': true});
    return _lesen(name, () => PreviewResult.fromJson(daten));
  }

  /// Vollstorno: Gutschrift über alle Positionen, das Original wird storniert.
  ///
  /// [returnDisposition] (aus `returnDispositions`) sagt, wohin die Ware der
  /// bestandsgeführten Positionen geht; fehlt = `restock`. Geht nur mit, wenn
  /// gesetzt; einen unbekannten Wert weist der Server als `validation` ab.
  Future<CancelResult> cancelInvoice({
    required String idempotencyKey,
    required String invoiceId,
    required String reason,
    String? note,
    String? returnDisposition,
  }) async {
    const name = Aufrufe.cancelInvoice;
    final daten = await _transport.call(name, {
      'idempotencyKey': idempotencyKey,
      'invoiceId': invoiceId,
      'reason': reason,
      'note': ?note,
      'returnDisposition': ?returnDisposition,
    });
    return _lesen(name, () => CancelResult.fromJson(daten));
  }

  /// Teilgutschrift; höchstens bis zum Brutto des Originals je USt-Satz.
  ///
  /// Die Rückgabe-Wahl ([CreditNoteRequest.returnDisposition] als Vorgabe,
  /// [CreditNoteItemInput.returnDisposition] je Position) geht unverändert
  /// hinaus; geprüft wird sie vom Server.
  Future<CreditNoteResult> createCreditNote(CreditNoteRequest request) async {
    const name = Aufrufe.createCreditNote;
    final daten = await _transport.call(name, request.toJson());
    return _lesen(name, () => CreditNoteResult.fromJson(daten));
  }

  Future<Invoice> getInvoice({String? invoiceId, String? number}) async {
    const name = Aufrufe.getInvoice;
    _genauEine(name, {'invoiceId': invoiceId, 'number': number});
    final daten = await _transport.call(name, {'invoiceId': ?invoiceId, 'number': ?number});
    return _lesen(name, () => Invoice.fromJson(_objekt(daten, 'invoice')));
  }

  Future<InvoicePage> listInvoices({
    String? from,
    String? to,
    String? status,
    String? docType,
    String? customerId,
    int? limit,
    String? cursor,
  }) async {
    const name = Aufrufe.listInvoices;
    final daten = await _transport.call(name, {
      'from': ?from,
      'to': ?to,
      'status': ?status,
      'docType': ?docType,
      'customerId': ?customerId,
      'limit': ?limit,
      'cursor': ?cursor,
    });
    return _lesen(name, () => InvoicePage.fromJson(daten));
  }

  // ---- Dateien ------------------------------------------------------------------

  /// Das PDF, bei ausreichenden Angaben mit eingebetteter Factur-X-Datei.
  ///
  /// Mit [language] in der anderen Sprache als der Rechnung kommt eine
  /// **Übersetzungskopie**: dieselbe Nummer, auf jeder Seite gekennzeichnet,
  /// ohne eingebettete E-Rechnung — keine eigene Rechnung.
  Future<Uint8List> getInvoicePdf(String invoiceId, {String? language}) =>
      _transport.callBinary(Aufrufe.getInvoicePdf, {'invoiceId': invoiceId, 'language': ?language});

  /// Die E-Rechnung als XML; [format] `ubl` (Peppol) oder `cii`. Zurück kommt
  /// die Antwort, wie der Server sie sendet: der Text, das Format und der
  /// Dateiname (`invoice-<Nummer>.xml`). Fehlt eines davon oder ist das Format
  /// keines aus [einvoiceFormats], ist die Antwort kaputt.
  Future<InvoiceXml> getInvoiceXml(String invoiceId, {String format = 'ubl'}) async {
    const name = Aufrufe.getInvoiceXml;
    final daten = await _transport.call(name, {'invoiceId': invoiceId, 'format': format});
    final xml = daten['xml'];
    final gesendet = daten['format'];
    final filename = daten['filename'];
    if (xml is! String || xml.isEmpty) {
      throw const KasseneckValidationError(name, 'Antwort ohne xml', 'response');
    }
    if (gesendet is! String || !einvoiceFormats.contains(gesendet)) {
      throw const KasseneckValidationError(name, 'Antwort ohne gültiges format', 'response');
    }
    if (filename is! String || filename.isEmpty) {
      throw const KasseneckValidationError(name, 'Antwort ohne filename', 'response');
    }
    return InvoiceXml(xml: xml, format: gesendet, filename: filename);
  }

  // ---- Freigabe und Einrichtung -------------------------------------------------

  /// Darf dieses Konto ausstellen, und was fehlt noch? Antwortet auch ohne
  /// Freigabe und vor der Live-Freischaltung.
  Future<InvoiceSetupStatus> getInvoiceSetupStatus() async {
    const name = Aufrufe.getInvoiceSetupStatus;
    final daten = await _transport.call(name, const {});
    return _lesen(name, () => InvoiceSetupStatus.fromJson(daten));
  }

  // ---- Zahlungen -----------------------------------------------------------------

  /// Eine Zahlung nachtragen, die nach dem Ausstellen eingetroffen ist.
  ///
  /// Der `idempotencyKey` ist Pflicht: ohne ihn bucht ein Wiederholungslauf
  /// nach einem Zeitlimit ein zweites Mal. Bei `method: 'cash'` (und bei
  /// `onSite: true`) wird die Zahlung gebucht und die Liste `notice` trägt
  /// `cash_receipt_required` — ein Barumsatz braucht einen Beleg (§ 132a BAO).
  Future<RecordPaymentResult> recordInvoicePayment(RecordPaymentRequest request) async {
    const name = Aufrufe.recordInvoicePayment;
    final daten = await _transport.call(name, request.toJson());
    return _lesen(name, () => RecordPaymentResult.fromJson(daten));
  }

  // ---- Marken --------------------------------------------------------------------

  /// Die Marken des Kontos; `id` geht als `brandId` in [issueInvoice].
  Future<List<Brand>> listBrands() async {
    const name = Aufrufe.listBrands;
    final daten = await _transport.call(name, const {});
    return _lesen(name, () => [for (final b in _liste(daten, 'brands')) Brand.fromJson(b)]);
  }

  // ---- Hilfen -------------------------------------------------------------------

  static void _genauEine(String name, Map<String, String?> kennungen) {
    final gesetzt = kennungen.values.where((w) => w != null && w.isNotEmpty).length;
    if (gesetzt != 1) {
      throw KasseneckValidationError(name, 'genau eines von ${kennungen.keys.join(', ')} angeben', 'request');
    }
  }

  static T _lesen<T>(String name, T Function() lies) {
    try {
      return lies();
    } on FormatException catch (e) {
      // e.message ist der Feldname, nie ein Wert.
      throw KasseneckValidationError(name, 'Antwort ohne gültiges Feld ${e.message}', 'response');
    } on TypeError {
      throw KasseneckValidationError(name, 'Antwort hat einen unerwarteten Typ', 'response');
    }
  }

  /// Hinweise aus der Antwort — immer eine Liste, leer ohne Hinweis.
  ///
  /// Ein einzelnes Objekt (Server vor npm 0.22.0 bei `recordInvoicePayment`)
  /// wird zur Liste, damit ein Versionssprung nichts bricht.
  ///
  /// Ein unbrauchbarer Eintrag (kein Objekt, `code` oder `message` kein Text)
  /// wird uebergangen, nicht geworfen — wie im JS-Zwilling. Der Aufruf hat an
  /// dieser Stelle schon gewirkt: die Rechnung ist ausgestellt, die Zahlung
  /// gebucht. Ein Fehler liesse den Aufrufer glauben, es sei nichts entstanden,
  /// und eine Wiederholung mit demselben Schluessel liefert die Hinweise nicht
  /// noch einmal.
  static Map<String, dynamic> _objekt(Map<String, dynamic> daten, String feld) {
    final wert = daten[feld];
    if (wert is Map) return Map<String, dynamic>.from(wert);
    throw FormatException(feld);
  }

  static List<Map<String, dynamic>> _liste(Map<String, dynamic> daten, String feld) {
    final wert = daten[feld];
    if (wert is! List) throw FormatException(feld);
    return [for (final e in wert) if (e is Map) Map<String, dynamic>.from(e) else throw FormatException(feld)];
  }
}

/// Der Fehlercode eines geworfenen Fehlers — `null`, wenn es keiner der Rechnungs-API ist.
String? invoiceErrorCode(Object? error) =>
    error is KasseneckApiError && isInvoiceErrorCode(error.code) ? error.code : null;

/// Die Feldfehler einer `validation`-Antwort; leer, wenn es keine sind.
List<({String field, String message})> invoiceFieldErrors(Object? error) {
  if (error is! KasseneckApiError) return const [];
  final roh = error.details['errors'];
  if (roh is! List) return const [];
  return [
    for (final e in roh)
      if (e is Map && e['field'] is String && e['message'] is String)
        (field: e['field'] as String, message: e['message'] as String),
  ];
}
