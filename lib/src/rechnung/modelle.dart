/// Anfragen und Antworten der Rechnungs-API — Zwilling von
/// `src/rechnung/typen.ts` im JS-Paket.
///
/// Beträge sind überall **ganze Cent**, Datumsangaben `JJJJ-MM-TT` nach Wiener
/// Kalender. Anfragen schreiben nur gesetzte Felder (`toJson`), damit das Backend
/// „nicht gesetzt" nicht als ausdrückliche Angabe missversteht.
///
/// Antworten werden streng gelesen: fehlt ein zugesagtes Feld, wirft das Lesen
/// eine [FormatException] mit dem Feldnamen (nie dem Wert); [RechnungApi] macht
/// daraus einen Antwortfehler statt eines `TypeError` an unpassender Stelle.
library;

// ---- Lesehilfen -----------------------------------------------------------------

T _pflicht<T>(Map<String, dynamic> j, String feld) {
  final wert = j[feld];
  if (wert is T) return wert;
  throw FormatException(feld);
}

String? _text(Map<String, dynamic> j, String feld) => j[feld] is String ? j[feld] as String : null;

int? _ganz(Map<String, dynamic> j, String feld) => j[feld] is int ? j[feld] as int : null;

Map<String, dynamic> _objekt(Map<String, dynamic> j, String feld) {
  final wert = j[feld];
  if (wert is Map) return Map<String, dynamic>.from(wert);
  throw FormatException(feld);
}

List<Map<String, dynamic>> _liste(Map<String, dynamic> j, String feld) {
  final wert = j[feld];
  if (wert is! List) throw FormatException(feld);
  return [for (final e in wert) if (e is Map) Map<String, dynamic>.from(e) else throw FormatException(feld)];
}

void _setzen(Map<String, dynamic> ziel, String feld, Object? wert) {
  if (wert != null) ziel[feld] = wert;
}

// ---- Kunden ---------------------------------------------------------------------

class CustomerInput {
  const CustomerInput({
    required this.type,
    required this.name,
    required this.country,
    this.legalForm,
    this.email,
    this.phone,
    this.street,
    this.houseNumber,
    this.zip,
    this.city,
    this.vatId,
    this.shortCode,
    this.isAuthority,
    this.note,
    this.externalId,
    this.language,
  });

  factory CustomerInput.fromJson(Map<String, dynamic> j) => CustomerInput(
        type: _pflicht<String>(j, 'type'),
        name: _pflicht<String>(j, 'name'),
        country: _pflicht<String>(j, 'country'),
        legalForm: _text(j, 'legalForm'),
        email: _text(j, 'email'),
        phone: _text(j, 'phone'),
        street: _text(j, 'street'),
        houseNumber: _text(j, 'houseNumber'),
        zip: _text(j, 'zip'),
        city: _text(j, 'city'),
        vatId: _text(j, 'vatId'),
        shortCode: _text(j, 'shortCode'),
        isAuthority: j['isAuthority'] is bool ? j['isAuthority'] as bool : null,
        note: _text(j, 'note'),
        externalId: _text(j, 'externalId'),
        language: _text(j, 'language'),
      );

  /// `private` oder `company`.
  final String type;
  final String name;

  /// ISO-3166-Alpha-2, z. B. `AT`.
  final String country;
  final String? legalForm;
  final String? email;
  final String? phone;
  final String? street;
  final String? houseNumber;
  final String? zip;
  final String? city;

  /// UID-Nummer, z. B. `ATU12345678`.
  final String? vatId;

  /// Kürzel für die Rechnungsnummer; einmal gesetzt unveränderlich.
  final String? shortCode;
  final bool? isAuthority;
  final String? note;

  /// Kennung im eigenen System; je Konto eindeutig.
  final String? externalId;

  /// Sprache der Rechnungen an diesen Kunden (`de`/`en`); fehlt = `de`.
  final String? language;

  Map<String, dynamic> toJson() {
    final j = <String, dynamic>{'type': type, 'name': name, 'country': country};
    _setzen(j, 'legalForm', legalForm);
    _setzen(j, 'email', email);
    _setzen(j, 'phone', phone);
    _setzen(j, 'street', street);
    _setzen(j, 'houseNumber', houseNumber);
    _setzen(j, 'zip', zip);
    _setzen(j, 'city', city);
    _setzen(j, 'vatId', vatId);
    _setzen(j, 'shortCode', shortCode);
    _setzen(j, 'isAuthority', isAuthority);
    _setzen(j, 'note', note);
    _setzen(j, 'externalId', externalId);
    _setzen(j, 'language', language);
    return j;
  }
}

class Customer {
  const Customer({
    required this.id,
    required this.type,
    required this.name,
    required this.country,
    this.legalForm,
    this.email,
    this.phone,
    this.street,
    this.houseNumber,
    this.zip,
    this.city,
    this.vatId,
    this.shortCode,
    this.isAuthority = false,
    this.note,
    this.externalId,
    this.language = 'de',
    this.createdAt,
    this.updatedAt,
  });

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: _pflicht<String>(j, 'id'),
        type: _pflicht<String>(j, 'type'),
        name: _pflicht<String>(j, 'name'),
        country: _pflicht<String>(j, 'country'),
        legalForm: _text(j, 'legalForm'),
        email: _text(j, 'email'),
        phone: _text(j, 'phone'),
        street: _text(j, 'street'),
        houseNumber: _text(j, 'houseNumber'),
        zip: _text(j, 'zip'),
        city: _text(j, 'city'),
        vatId: _text(j, 'vatId'),
        shortCode: _text(j, 'shortCode'),
        isAuthority: j['isAuthority'] == true,
        note: _text(j, 'note'),
        externalId: _text(j, 'externalId'),
        language: _text(j, 'language') == 'en' ? 'en' : 'de',
        createdAt: _text(j, 'createdAt'),
        updatedAt: _text(j, 'updatedAt'),
      );

  final String id;
  final String type;
  final String name;
  final String country;
  final String? legalForm;
  final String? email;
  final String? phone;
  final String? street;
  final String? houseNumber;
  final String? zip;
  final String? city;
  final String? vatId;
  final String? shortCode;
  final bool isAuthority;
  final String? note;
  final String? externalId;

  /// Sprache der Rechnungen an diesen Kunden; fehlt = `de`.
  final String language;
  final String? createdAt;
  final String? updatedAt;
}

class CustomerPage {
  const CustomerPage({required this.customers, this.nextCursor});

  final List<Customer> customers;

  /// `null` auf der letzten Seite.
  final String? nextCursor;
}

// ---- Rechnungen -----------------------------------------------------------------

class InvoiceItemInput {
  const InvoiceItemInput({
    required this.description,
    required this.quantity,
    required this.unitPriceCents,
    required this.vatRate,
    this.subtitle,
    this.unit,
    this.kind,
    this.discountPct,
  });

  factory InvoiceItemInput.fromJson(Map<String, dynamic> j) => InvoiceItemInput(
        description: _pflicht<String>(j, 'description'),
        quantity: _pflicht<num>(j, 'quantity'),
        unitPriceCents: _pflicht<num>(j, 'unitPriceCents'),
        vatRate: _pflicht<int>(j, 'vatRate'),
        subtitle: _text(j, 'subtitle'),
        unit: _text(j, 'unit'),
        kind: _text(j, 'kind'),
        discountPct: j['discountPct'] is num ? j['discountPct'] as num : null,
      );

  final String description;

  /// Höchstens drei Nachkommastellen.
  final num quantity;

  /// Einzelpreis in ganzen Cent im `priceMode` der Rechnung. Als `num`, damit
  /// ein fehlerhafter Wert unverändert beim Server ankommt und dort als
  /// `validation` mit Feldpfad zurückkommt — nicht still gerundet.
  final num unitPriceCents;

  /// `0`, `10`, `13` oder `20`.
  final int vatRate;
  final String? subtitle;

  /// Schlüssel aus [invoiceUnits] (`piece`, `hour`, …); ohne Angabe `piece`.
  /// Als `String`, damit ein unbekannter Wert als `validation` mit Feldpfad
  /// vom Server zurückkommt statt hier still zu verschwinden.
  final String? unit;

  /// Ware oder Leistung ([itemKinds]); ohne Angabe `goods`. Entscheidet
  /// grenzüberschreitend über ig. Lieferung oder Reverse Charge.
  final String? kind;

  /// Zeilenrabatt in Prozent, höchstens zwei Nachkommastellen.
  final num? discountPct;

  Map<String, dynamic> toJson() {
    final j = <String, dynamic>{};
    j['description'] = description;
    _setzen(j, 'subtitle', subtitle);
    j['quantity'] = quantity;
    _setzen(j, 'unit', unit);
    _setzen(j, 'kind', kind);
    j['unitPriceCents'] = unitPriceCents;
    j['vatRate'] = vatRate;
    _setzen(j, 'discountPct', discountPct);
    return j;
  }
}

class IssueInvoiceRequest {
  const IssueInvoiceRequest({
    required this.idempotencyKey,
    this.taxScheme,
    this.reverseChargeReason,
    required this.priceMode,
    required this.serviceStart,
    required this.items,
    this.customerId,
    this.serviceEnd,
    this.paymentTermDays,
    this.orderReference,
    this.intro,
    this.note,
    this.paymentReference,
    this.girocode,
    this.tracking,
    this.metadata,
    this.language,
    this.brandId,
    this.payment,
  });

  factory IssueInvoiceRequest.fromJson(Map<String, dynamic> j) => IssueInvoiceRequest(
        idempotencyKey: _pflicht<String>(j, 'idempotencyKey'),
        taxScheme: _text(j, 'taxScheme'),
        reverseChargeReason: _text(j, 'reverseChargeReason'),
        priceMode: _pflicht<String>(j, 'priceMode'),
        serviceStart: _pflicht<String>(j, 'serviceStart'),
        items: [for (final p in _liste(j, 'items')) InvoiceItemInput.fromJson(p)],
        customerId: _text(j, 'customerId'),
        serviceEnd: _text(j, 'serviceEnd'),
        paymentTermDays: _ganz(j, 'paymentTermDays'),
        orderReference: _text(j, 'orderReference'),
        intro: _text(j, 'intro'),
        note: _text(j, 'note'),
        paymentReference: _text(j, 'paymentReference'),
        girocode: j['girocode'] is bool ? j['girocode'] as bool : null,
        tracking: j['tracking'] is bool ? j['tracking'] as bool : null,
        metadata: j['metadata'] is Map ? Map<String, String>.from(j['metadata'] as Map) : null,
        language: _text(j, 'language'),
        brandId: _text(j, 'brandId'),
        payment: j['payment'] is Map ? PaymentInput.fromJson(Map<String, dynamic>.from(j['payment'] as Map)) : null,
      );

  /// Pflicht: dieselbe Anfrage mit demselben Schlüssel erzeugt nie eine zweite Rechnung.
  final String idempotencyKey;

  /// Pflicht über 400 € brutto sowie bei Reverse Charge und ig. Lieferung.
  final String? customerId;
  /// Optional: der Server leitet den Fall aus Kundenland, Kundenart, UID und
  /// Ware/Leistung ab. Eine Angabe wird geprüft — passt sie nicht, kommt
  /// `tax_scheme_mismatch` mit dem erwarteten Fall zurück.
  final String? taxScheme;

  /// Pflicht bei `domesticReverseCharge`, ein Schlüssel aus
  /// [reverseChargeReasons]. Zu einem anderen Fall ist er ein Feldfehler.
  final String? reverseChargeReason;
  final String priceMode;
  final String serviceStart;
  final String? serviceEnd;
  final int? paymentTermDays;
  final String? orderReference;
  final String? intro;
  final String? note;
  final String? paymentReference;
  final bool? girocode;
  final bool? tracking;
  final List<InvoiceItemInput> items;

  /// Eigene Merkmale (höchstens 20), nie gedruckt.
  final Map<String, String>? metadata;

  /// Sprache dieser Rechnung; sonst die des Kunden, sonst `de`.
  final String? language;

  /// Marke (Kennung aus `listBrands`); sonst die Standardmarke.
  final String? brandId;

  /// Schon bezahlt: die Zahlung entsteht in derselben Transaktion wie das
  /// Festschreiben, das PDF trägt dann keine Zahlungsinformationen.
  final PaymentInput? payment;

  Map<String, dynamic> toJson() {
    final j = <String, dynamic>{'idempotencyKey': idempotencyKey};
    _setzen(j, 'customerId', customerId);
    _setzen(j, 'taxScheme', taxScheme);
    _setzen(j, 'reverseChargeReason', reverseChargeReason);
    j['priceMode'] = priceMode;
    j['serviceStart'] = serviceStart;
    _setzen(j, 'serviceEnd', serviceEnd);
    _setzen(j, 'paymentTermDays', paymentTermDays);
    _setzen(j, 'orderReference', orderReference);
    _setzen(j, 'intro', intro);
    _setzen(j, 'note', note);
    _setzen(j, 'paymentReference', paymentReference);
    _setzen(j, 'girocode', girocode);
    _setzen(j, 'tracking', tracking);
    j['items'] = [for (final p in items) p.toJson()];
    _setzen(j, 'metadata', metadata);
    _setzen(j, 'language', language);
    _setzen(j, 'brandId', brandId);
    _setzen(j, 'payment', payment?.toJson());
    return j;
  }
}

/// Eine Zahlung, wie das Fremdsystem sie meldet.
class PaymentInput {
  const PaymentInput({required this.method, this.amountCents, this.paidAt, this.reference, this.onSite});

  factory PaymentInput.fromJson(Map<String, dynamic> j) => PaymentInput(
        method: _pflicht<String>(j, 'method'),
        amountCents: _ganz(j, 'amountCents'),
        paidAt: _text(j, 'paidAt'),
        reference: _text(j, 'reference'),
        onSite: j['onSite'] is bool ? j['onSite'] as bool : null,
      );

  /// Ein Schlüssel aus [invoicePaymentMethods].
  final String method;

  /// Ohne Angabe der volle Bruttobetrag.
  final int? amountCents;

  /// Ohne Angabe der heutige Wiener Tag; nie in der Zukunft.
  final String? paidAt;

  /// Zahlungskennung des Fremdsystems — gespeichert, aber nie gedruckt.
  final String? reference;

  /// Die Zahlung erfolgte **vor Ort** (Terminal an der Kasse). Dann ist sie ein
  /// Barumsatz — auch mit Karte (§ 131b Abs. 1 Z 3 UStG) — und die Antwort
  /// trägt den Hinweis `cash_receipt_required`. Zu `transfer` passt das nicht.
  final bool? onSite;

  Map<String, dynamic> toJson() {
    final j = <String, dynamic>{'method': method};
    _setzen(j, 'amountCents', amountCents);
    _setzen(j, 'paidAt', paidAt);
    _setzen(j, 'reference', reference);
    _setzen(j, 'onSite', onSite);
    return j;
  }
}

/// Eine Zahlung nachtragen. Der Schlüssel ist Pflicht: ohne ihn bucht eine
/// Wiederholung nach einem Zeitlimit ein zweites Mal.
class RecordPaymentRequest {
  const RecordPaymentRequest({
    required this.idempotencyKey,
    required this.invoiceId,
    required this.method,
    this.amountCents,
    this.paidAt,
    this.reference,
    this.onSite,
  });

  final String idempotencyKey;
  final String invoiceId;
  final String method;
  final int? amountCents;
  final String? paidAt;
  final String? reference;

  /// Zahlung vor Ort — siehe [PaymentInput.onSite].
  final bool? onSite;

  Map<String, dynamic> toJson() {
    final j = <String, dynamic>{'idempotencyKey': idempotencyKey, 'invoiceId': invoiceId, 'method': method};
    _setzen(j, 'amountCents', amountCents);
    _setzen(j, 'paidAt', paidAt);
    _setzen(j, 'reference', reference);
    _setzen(j, 'onSite', onSite);
    return j;
  }
}

/// Eine gebuchte Zahlung, wie die API sie zurückgibt.
class InvoicePayment {
  const InvoicePayment({required this.id, required this.amountCents, this.paidAt, this.method, this.reference});

  factory InvoicePayment.fromJson(Map<String, dynamic> j) => InvoicePayment(
        id: _pflicht<String>(j, 'id'),
        amountCents: _pflicht<num>(j, 'amountCents').toInt(),
        paidAt: _text(j, 'paidAt'),
        method: _text(j, 'method'),
        reference: _text(j, 'reference'),
      );

  final String id;
  final int amountCents;
  final String? paidAt;
  final String? method;
  final String? reference;
}

/// Ein Hinweis an einer erfolgreichen Antwort — kein Fehler, nur etwas, das der
/// Aufrufer wissen sollte (heute nur `cash_receipt_required`).
class InvoiceNotice {
  const InvoiceNotice({required this.code, required this.message});

  factory InvoiceNotice.fromJson(Map<String, dynamic> j) => InvoiceNotice(
        code: _pflicht<String>(j, 'code'),
        message: _text(j, 'message') ?? '',
      );

  final String code;
  final String message;
}

/// Ergebnis von `recordInvoicePayment`.
class RecordPaymentResult {
  const RecordPaymentResult({required this.invoice, required this.payment, required this.replayed, this.notice});

  final Invoice invoice;
  final InvoicePayment payment;
  final bool replayed;
  final InvoiceNotice? notice;
}

class CreditNoteRequest {
  const CreditNoteRequest({
    required this.idempotencyKey,
    required this.invoiceId,
    required this.reason,
    required this.items,
    this.note,
  });

  factory CreditNoteRequest.fromJson(Map<String, dynamic> j) => CreditNoteRequest(
        idempotencyKey: _pflicht<String>(j, 'idempotencyKey'),
        invoiceId: _pflicht<String>(j, 'invoiceId'),
        reason: _pflicht<String>(j, 'reason'),
        items: [for (final p in _liste(j, 'items')) InvoiceItemInput.fromJson(p)],
        note: _text(j, 'note'),
      );

  final String idempotencyKey;
  final String invoiceId;

  /// Einer von [creditNoteReasons].
  final String reason;
  final String? note;
  final List<InvoiceItemInput> items;

  Map<String, dynamic> toJson() {
    final j = <String, dynamic>{'idempotencyKey': idempotencyKey, 'invoiceId': invoiceId, 'reason': reason};
    _setzen(j, 'note', note);
    j['items'] = [for (final p in items) p.toJson()];
    return j;
  }
}

class VatRateTotal {
  const VatRateTotal({required this.rate, required this.netCents, required this.vatCents});

  factory VatRateTotal.fromJson(Map<String, dynamic> j) => VatRateTotal(
        rate: _pflicht<int>(j, 'rate'),
        netCents: _pflicht<int>(j, 'netCents'),
        vatCents: _pflicht<int>(j, 'vatCents'),
      );

  final int rate;
  final int netCents;
  final int vatCents;
}

class InvoiceTotals {
  const InvoiceTotals({required this.netCents, required this.vatCents, required this.grossCents, this.byRate = const []});

  factory InvoiceTotals.fromJson(Map<String, dynamic> j) => InvoiceTotals(
        netCents: _pflicht<int>(j, 'netCents'),
        vatCents: _pflicht<int>(j, 'vatCents'),
        grossCents: _pflicht<int>(j, 'grossCents'),
        byRate: j['byRate'] is List ? [for (final r in _liste(j, 'byRate')) VatRateTotal.fromJson(r)] : const [],
      );

  final int netCents;
  final int vatCents;
  final int grossCents;
  final List<VatRateTotal> byRate;
}

/// Eine gespeicherte Position — wie gesendet, fehlende Angaben mit ihrem Standardwert.
class InvoiceItem {
  const InvoiceItem({
    required this.description,
    required this.quantity,
    required this.unit,
    required this.unitPriceCents,
    required this.vatRate,
    this.subtitle = '',
    this.discountPct = 0,
  });

  factory InvoiceItem.fromJson(Map<String, dynamic> j) => InvoiceItem(
        description: _pflicht<String>(j, 'description'),
        subtitle: _text(j, 'subtitle') ?? '',
        quantity: _pflicht<num>(j, 'quantity'),
        unit: _text(j, 'unit') ?? 'Stk',
        unitPriceCents: _pflicht<int>(j, 'unitPriceCents'),
        vatRate: _pflicht<num>(j, 'vatRate'),
        discountPct: j['discountPct'] is num ? j['discountPct'] as num : 0,
      );

  final String description;
  final String subtitle;
  final num quantity;
  final String unit;
  final int unitPriceCents;
  final num vatRate;
  final num discountPct;
}

class CreditNoteSummary {
  const CreditNoteSummary({required this.id, required this.grossCents, this.number});

  factory CreditNoteSummary.fromJson(Map<String, dynamic> j) => CreditNoteSummary(
        id: _pflicht<String>(j, 'id'),
        number: _text(j, 'number'),
        grossCents: _pflicht<int>(j, 'grossCents'),
      );

  final String id;
  final String? number;
  final int grossCents;
}

/// Eine Rechnung oder Gutschrift. Die Felder unter „Detail" liefert nur
/// `getInvoice`; in Listen und Ausstell-Antworten sind sie `null`.
class Invoice {
  const Invoice({
    required this.id,
    required this.number,
    required this.docType,
    required this.status,
    required this.totals,
    this.invoiceDate,
    this.dueDate,
    this.customerId,
    this.statusUrl,
    this.statusPassword,
    this.einvoiceLevel,
    this.metadata = const {},
    this.items,
    this.paidCents,
    this.openCents,
    this.overdue,
    this.writtenOff,
    this.creditNotes,
    this.relatedInvoiceId,
    this.language = 'de',
    this.brandId,
    this.brandName,
  });

  factory Invoice.fromJson(Map<String, dynamic> j) {
    final einvoice = j['einvoice'];
    final metadaten = j['metadata'];
    final related = j['related'];
    final brand = j['brand'];
    return Invoice(
      id: _pflicht<String>(j, 'id'),
      number: _pflicht<String>(j, 'number'),
      docType: _pflicht<String>(j, 'docType'),
      status: _pflicht<String>(j, 'status'),
      totals: InvoiceTotals.fromJson(_objekt(j, 'totals')),
      invoiceDate: _text(j, 'invoiceDate'),
      dueDate: _text(j, 'dueDate'),
      customerId: _text(j, 'customerId'),
      statusUrl: _text(j, 'statusUrl'),
      statusPassword: _text(j, 'statusPassword'),
      einvoiceLevel: einvoice is Map && einvoice['level'] is String ? einvoice['level'] as String : null,
      metadata: metadaten is Map
          ? {for (final e in metadaten.entries) if (e.value is String) '${e.key}': e.value as String}
          : const {},
      items: j['items'] is List ? [for (final p in _liste(j, 'items')) InvoiceItem.fromJson(p)] : null,
      paidCents: _ganz(j, 'paidCents'),
      openCents: _ganz(j, 'openCents'),
      overdue: j['overdue'] is bool ? j['overdue'] as bool : null,
      writtenOff: j['writtenOff'] is bool ? j['writtenOff'] as bool : null,
      creditNotes: j['creditNotes'] is List ? [for (final c in _liste(j, 'creditNotes')) CreditNoteSummary.fromJson(c)] : null,
      relatedInvoiceId: related is Map && related['invoiceId'] is String ? related['invoiceId'] as String : null,
      language: _text(j, 'language') == 'en' ? 'en' : 'de',
      brandId: brand is Map && brand['id'] is String ? brand['id'] as String : null,
      brandName: brand is Map && brand['name'] is String ? brand['name'] as String : null,
    );
  }

  final String id;
  final String number;

  /// `RE` (Rechnung) oder `GU` (Gutschrift).
  final String docType;
  final String status;
  final InvoiceTotals totals;
  final String? invoiceDate;
  final String? dueDate;
  final String? customerId;
  final String? statusUrl;
  final String? statusPassword;
  final String? einvoiceLevel;
  final Map<String, String> metadata;

  // Detail
  final List<InvoiceItem>? items;
  final int? paidCents;
  final int? openCents;
  final bool? overdue;
  final bool? writtenOff;
  final List<CreditNoteSummary>? creditNotes;
  final String? relatedInvoiceId;

  /// Beim Ausstellen eingefroren; ältere Rechnungen `de`.
  final String language;

  /// Die eingefrorene Marke; `null` bei der Ersatzmarke ohne eigene Einrichtung.
  final String? brandId;
  final String? brandName;
}

/// Eine Marke des Kontos (Logo, Farbe, Absender); `id` geht als `brandId` in `issueInvoice`.
class Brand {
  const Brand({required this.id, required this.name, required this.isDefault});

  factory Brand.fromJson(Map<String, dynamic> j) => Brand(
        id: _pflicht<String>(j, 'id'),
        name: _text(j, 'name') ?? '',
        isDefault: j['isDefault'] == true,
      );

  final String id;
  final String name;
  final bool isDefault;
}

class InvoicePage {
  const InvoicePage({required this.invoices, this.nextCursor});

  final List<Invoice> invoices;

  /// `null` auf der letzten Seite. Eine Seite kann kürzer als `limit` sein und
  /// trotzdem einen Cursor tragen (Status wird nachgefiltert).
  final String? nextCursor;
}

class IssueResult {
  const IssueResult({required this.invoice, required this.replayed, this.notice = const []});

  final Invoice invoice;

  /// `true`, wenn die Anfrage schon einmal ausgeführt wurde.
  final bool replayed;

  /// Hinweise zu dieser Rechnung — kein Fehler, sondern etwas, das der Aufrufer
  /// wissen sollte ([invoiceNoticeCodes]). Eine **Liste**, weil mehrere zugleich
  /// anfallen können: eine bar bezahlte ig. Lieferung trägt zwei.
  final List<InvoiceNotice> notice;
}

class CancelResult {
  const CancelResult({
    required this.creditNote,
    required this.originalId,
    required this.originalStatus,
    required this.originalPaidCents,
    required this.replayed,
  });

  final Invoice creditNote;
  final String originalId;
  final String? originalStatus;

  /// Bereits auf das Original bezahlt — die Rückerstattung ist Sache des Betriebs.
  final int originalPaidCents;
  final bool replayed;
}

class CreditNoteResult {
  const CreditNoteResult({required this.creditNote, required this.remainingCents, required this.replayed});

  final Invoice creditNote;

  /// Brutto, das nach dieser Gutschrift noch gutgeschrieben werden kann.
  final int remainingCents;
  final bool replayed;
}

// ---- Freigabe und Einrichtung ---------------------------------------------------

class InvoiceSetupGap {
  const InvoiceSetupGap({required this.requirement, required this.message});

  factory InvoiceSetupGap.fromJson(Map<String, dynamic> j) => InvoiceSetupGap(
        requirement: _pflicht<String>(j, 'requirement'),
        message: _pflicht<String>(j, 'message'),
      );

  /// Einer von [invoiceSetupRequirements].
  final String requirement;
  final String message;
}

class InvoiceSetupStatus {
  const InvoiceSetupStatus({required this.ready, required this.environment, required this.missing});

  factory InvoiceSetupStatus.fromJson(Map<String, dynamic> j) => InvoiceSetupStatus(
        ready: _pflicht<bool>(j, 'ready'),
        environment: _text(j, 'environment') == 'test' ? 'test' : 'live',
        missing: [for (final m in _liste(j, 'missing')) InvoiceSetupGap.fromJson(m)],
      );

  final bool ready;

  /// `live` oder `test` — die Umgebung des Schlüssels.
  final String environment;
  final List<InvoiceSetupGap> missing;
}
