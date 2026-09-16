/// Die Aufrufe der Rechnungs-API — Zwilling von `createRechnungApi` im
/// JS-Paket `@kreiseck/kasseneck-api/rechnung`.
///
/// **Geprüft wird hier nichts Fachliches.** Die Anfrage geht unverändert an das
/// Backend, das sie gegen denselben Vertrag prüft und einen Formfehler als
/// `validation` mit `details['errors']` zurückgibt — zwei Prüfungen hießen zwei
/// Wahrheiten. Ausnahme sind Aufrufe mit „genau einer" Kennung: welche gemeint
/// ist, lässt sich ohne Server entscheiden.
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

class RechnungApi {
  RechnungApi({required String apiKey, String? baseUrl, http.Client? httpClient, Duration? timeout})
      : _transport = RechnungTransport(apiKey: apiKey, baseUrl: baseUrl, httpClient: httpClient, timeout: timeout);

  /// Mit einem bereits gebauten Transport (Tests, eigene Adresse).
  RechnungApi.mitTransport(RechnungTransport transport) : _transport = transport;

  final RechnungTransport _transport;

  // ---- Kunden -------------------------------------------------------------------

  Future<Customer> createCustomer(CustomerInput customer, {String? idempotencyKey}) async {
    const name = Aufrufe.createCustomer;
    final daten = await _transport.rufen(name, {
      'customer': customer.toJson(),
      'idempotencyKey': ?idempotencyKey,
    });
    return _lesen(name, () => Customer.fromJson(_objekt(daten, 'customer')));
  }

  Future<Customer> getCustomer({String? customerId, String? externalId}) async {
    const name = Aufrufe.getCustomer;
    _genauEine(name, {'customerId': customerId, 'externalId': externalId});
    final daten = await _transport.rufen(name, {'customerId': ?customerId, 'externalId': ?externalId});
    return _lesen(name, () => Customer.fromJson(_objekt(daten, 'customer')));
  }

  /// Nur die übergebenen Felder ändern sich (Feldnamen wie in [CustomerInput.toJson]).
  Future<Customer> updateCustomer(String customerId, Map<String, dynamic> patch) async {
    const name = Aufrufe.updateCustomer;
    final daten = await _transport.rufen(name, {'customerId': customerId, 'customer': patch});
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
    final daten = await _transport.rufen(aufruf, {
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

  Future<IssueResult> issueInvoice(IssueInvoiceRequest anfrage) async {
    const name = Aufrufe.issueInvoice;
    final daten = await _transport.rufen(name, anfrage.toJson());
    return _lesen(name, () => IssueResult(
          invoice: Invoice.fromJson(_objekt(daten, 'invoice')),
          replayed: daten['replayed'] == true,
        ));
  }

  /// Vollstorno: Gutschrift über alle Positionen, das Original wird storniert.
  Future<CancelResult> cancelInvoice({
    required String idempotencyKey,
    required String invoiceId,
    required String reason,
    String? note,
  }) async {
    const name = Aufrufe.cancelInvoice;
    final daten = await _transport.rufen(name, {
      'idempotencyKey': idempotencyKey,
      'invoiceId': invoiceId,
      'reason': reason,
      'note': ?note,
    });
    return _lesen(name, () {
      final original = _objekt(daten, 'original');
      return CancelResult(
        creditNote: Invoice.fromJson(_objekt(daten, 'creditNote')),
        originalId: original['id'] as String,
        originalStatus: original['status'] is String ? original['status'] as String : null,
        originalPaidCents: daten['originalPaidCents'] is int ? daten['originalPaidCents'] as int : 0,
        replayed: daten['replayed'] == true,
      );
    });
  }

  /// Teilgutschrift; höchstens bis zum Brutto des Originals je USt-Satz.
  Future<CreditNoteResult> createCreditNote(CreditNoteRequest anfrage) async {
    const name = Aufrufe.createCreditNote;
    final daten = await _transport.rufen(name, anfrage.toJson());
    return _lesen(name, () => CreditNoteResult(
          creditNote: Invoice.fromJson(_objekt(daten, 'creditNote')),
          remainingCents: daten['remainingCents'] is int ? daten['remainingCents'] as int : 0,
          replayed: daten['replayed'] == true,
        ));
  }

  Future<Invoice> getInvoice({String? invoiceId, String? number}) async {
    const name = Aufrufe.getInvoice;
    _genauEine(name, {'invoiceId': invoiceId, 'number': number});
    final daten = await _transport.rufen(name, {'invoiceId': ?invoiceId, 'number': ?number});
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
    final daten = await _transport.rufen(name, {
      'from': ?from,
      'to': ?to,
      'status': ?status,
      'docType': ?docType,
      'customerId': ?customerId,
      'limit': ?limit,
      'cursor': ?cursor,
    });
    return _lesen(name, () => InvoicePage(
          invoices: [for (final i in _liste(daten, 'invoices')) Invoice.fromJson(i)],
          nextCursor: daten['nextCursor'] is String ? daten['nextCursor'] as String : null,
        ));
  }

  // ---- Dateien ------------------------------------------------------------------

  /// Das PDF, bei ausreichenden Angaben mit eingebetteter Factur-X-Datei.
  ///
  /// Mit [language] in der anderen Sprache als der Rechnung kommt eine
  /// **Übersetzungskopie**: dieselbe Nummer, auf jeder Seite gekennzeichnet,
  /// ohne eingebettete E-Rechnung — keine eigene Rechnung.
  Future<Uint8List> getInvoicePdf(String invoiceId, {String? language}) =>
      _transport.rufenBinaer(Aufrufe.getInvoicePdf, {'invoiceId': invoiceId, 'language': ?language});

  /// Die E-Rechnung als XML-Text; [format] `ubl` (Peppol) oder `cii`.
  Future<String> getInvoiceXml(String invoiceId, {String format = 'ubl'}) async {
    const name = Aufrufe.getInvoiceXml;
    final daten = await _transport.rufen(name, {'invoiceId': invoiceId, 'format': format});
    final xml = daten['xml'];
    if (xml is! String || xml.isEmpty) {
      throw const KasseneckValidationError(name, 'Antwort ohne xml', 'response');
    }
    return xml;
  }

  // ---- Freigabe und Einrichtung -------------------------------------------------

  /// Darf dieses Konto ausstellen, und was fehlt noch? Antwortet auch ohne
  /// Freigabe und vor der Live-Freischaltung.
  Future<InvoiceSetupStatus> getInvoiceSetupStatus() async {
    const name = Aufrufe.getInvoiceSetupStatus;
    final daten = await _transport.rufen(name, const {});
    return _lesen(name, () => InvoiceSetupStatus.fromJson(daten));
  }

  // ---- Zahlungen -----------------------------------------------------------------

  /// Eine Zahlung nachtragen, die nach dem Ausstellen eingetroffen ist.
  ///
  /// Der `idempotencyKey` ist Pflicht: ohne ihn bucht ein Wiederholungslauf
  /// nach einem Zeitlimit ein zweites Mal. Bei `method: 'cash'` wird die
  /// Zahlung gebucht und die Antwort trägt zusätzlich einen [InvoiceNotice] —
  /// eine Barzahlung ist ein Barumsatz und braucht einen Beleg (§ 132a BAO).
  Future<RecordPaymentResult> recordInvoicePayment(RecordPaymentRequest anfrage) async {
    const name = Aufrufe.recordInvoicePayment;
    final daten = await _transport.rufen(name, anfrage.toJson());
    return _lesen(name, () => RecordPaymentResult(
          invoice: Invoice.fromJson(_objekt(daten, 'invoice')),
          payment: InvoicePayment.fromJson(_objekt(daten, 'payment')),
          replayed: daten['replayed'] == true,
          notice: daten['notice'] is Map
              ? InvoiceNotice.fromJson(Map<String, dynamic>.from(daten['notice'] as Map))
              : null,
        ));
  }

  // ---- Marken --------------------------------------------------------------------

  /// Die Marken des Kontos; `id` geht als `brandId` in [issueInvoice].
  Future<List<Brand>> listBrands() async {
    const name = Aufrufe.listBrands;
    final daten = await _transport.rufen(name, const {});
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
String? rechnungFehlerCode(Object? fehler) =>
    fehler is KasseneckApiError && istRechnungFehlercode(fehler.code) ? fehler.code : null;

/// Die Feldfehler einer `validation`-Antwort; leer, wenn es keine sind.
List<({String field, String message})> rechnungFeldFehler(Object? fehler) {
  if (fehler is! KasseneckApiError) return const [];
  final roh = fehler.details['errors'];
  if (roh is! List) return const [];
  return [
    for (final e in roh)
      if (e is Map && e['field'] is String && e['message'] is String)
        (field: e['field'] as String, message: e['message'] as String),
  ];
}
