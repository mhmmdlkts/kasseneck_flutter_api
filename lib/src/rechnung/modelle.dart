/// Anfragen und Antworten der Rechnungs-API — Zwilling von
/// `src/rechnung/typen.ts` im JS-Paket.
///
/// Beträge sind überall **ganze Cent**, Datumsangaben `JJJJ-MM-TT` nach Wiener
/// Kalender. Anfragen schreiben nur gesetzte Felder (`toJson`), damit das Backend
/// „nicht gesetzt" nicht als ausdrückliche Angabe missversteht.
///
/// Antworten werden streng gelesen: fehlt ein zugesagtes Feld, wirft das Lesen
/// eine [FormatException] mit dem Feldnamen (nie dem Wert); [InvoiceApi] macht
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

/// Eine Map als `Map<String, dynamic>`; eine schon so getypte wird nicht
/// kopiert (der Feldmengen-Test verfolgt daran, welche Felder gelesen werden).
Map<String, dynamic> _alsObjekt(Map wert) => wert is Map<String, dynamic> ? wert : Map<String, dynamic>.from(wert);

Map<String, dynamic> _objekt(Map<String, dynamic> j, String feld) {
  final wert = j[feld];
  if (wert is Map) return _alsObjekt(wert);
  throw FormatException(feld);
}

Map<String, dynamic>? _objektOderNull(Map<String, dynamic> j, String feld) {
  final wert = j[feld];
  if (wert == null) return null;
  if (wert is Map) return _alsObjekt(wert);
  throw FormatException(feld);
}

List<Map<String, dynamic>> _liste(Map<String, dynamic> j, String feld) {
  final wert = j[feld];
  if (wert is! List) throw FormatException(feld);
  return [for (final e in wert) if (e is Map) _alsObjekt(e) else throw FormatException(feld)];
}

/// Hinweise einer Antwort: fehlt das Feld, keine; ein einzelnes Objekt zählt
/// als Liste mit einem Eintrag. Ein Eintrag ohne `code` oder `message` wird
/// übergangen (die Rechnung ist da schon ausgestellt).
List<InvoiceNotice> _hinweise(Map<String, dynamic> j) {
  final roh = j['notice'];
  if (roh == null) return const [];
  final liste = roh is List ? roh : [roh];
  return [
    for (final h in liste)
      if (h is Map && h['code'] is String && h['message'] is String) InvoiceNotice.fromJson(_alsObjekt(h)),
  ];
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

/// Was für die Summe einer Rechnung zählt (`computeInvoiceTotals`) –
/// [InvoiceItemInput] erfüllt es unverändert.
abstract interface class TotalsItem {
  const factory TotalsItem({
    required num quantity,
    num? unitPriceCents,
    num? unitPriceMicros,
    required num vatRate,
    num? discountPct,
  }) = _SummenPosition;

  num get quantity;

  /// Einzelpreis in ganzen Cent — `null`, wenn die Position ihren Preis in
  /// Mikro-Euro trägt (genau eines von beiden, § 9.1 der Ganzzahl-Spec).
  num? get unitPriceCents;

  /// Einzelpreis in Mikro-Euro (10⁻⁶ €), für Preise unterhalb eines Cents.
  num? get unitPriceMicros;

  /// Der Preis in Cent, gleich welches Feld ihn trägt — `unitPriceMicros`
  /// zählt dabei als Zehntausendstel Cent. Wer rechnet, nimmt das hier und
  /// nicht eines der beiden Felder: sonst stünde die Fallunterscheidung an
  /// jeder Rechenstelle, und eine davon vergäße man.
  num get priceInCents => unitPriceCents ?? (unitPriceMicros ?? 0) / 10000;

  /// Der USt-Satz in Prozent. Als `num`, weil es Saetze mit Nachkommastelle
  /// gibt (4,9 % Grundnahrungsmittel ab 01.07.2026).
  num get vatRate;
  num? get discountPct;
}

class _SummenPosition implements TotalsItem {
  const _SummenPosition({
    required this.quantity,
    this.unitPriceCents,
    this.unitPriceMicros,
    required this.vatRate,
    this.discountPct,
  }) : assert(
          (unitPriceCents == null) != (unitPriceMicros == null),
          'Genau eines von unitPriceCents und unitPriceMicros angeben (§ 9.1).',
        );

  @override
  final num quantity;
  @override
  final num? unitPriceCents;
  @override
  final num? unitPriceMicros;
  @override
  final num vatRate;
  @override
  final num? discountPct;

  @override
  num get priceInCents => unitPriceCents ?? (unitPriceMicros ?? 0) / 10000;
}

class InvoiceItemInput implements TotalsItem {
  /// Genau eines von [unitPriceCents] und [unitPriceMicros] (§ 9.1). Der
  /// `assert` fängt den Irrtum schon im Debug-Lauf; der Server weist ihn sonst
  /// als `validation` mit Feldpfad ab.
  const InvoiceItemInput({
    required this.description,
    required this.quantity,
    this.unitPriceCents,
    this.unitPriceMicros,
    required this.vatRate,
    this.subtitle,
    this.unit,
    this.kind,
    this.discountPct,
    this.articleId,
  }) : assert(
          (unitPriceCents == null) != (unitPriceMicros == null),
          'Genau eines von unitPriceCents und unitPriceMicros angeben (§ 9.1).',
        );

  factory InvoiceItemInput.fromJson(Map<String, dynamic> j) => InvoiceItemInput(
        description: _pflicht<String>(j, 'description'),
        quantity: _pflicht<num>(j, 'quantity'),
        unitPriceCents: j['unitPriceCents'] is num ? j['unitPriceCents'] as num : null,
        unitPriceMicros: j['unitPriceMicros'] is num ? j['unitPriceMicros'] as num : null,
        vatRate: _pflicht<num>(j, 'vatRate'),
        subtitle: _text(j, 'subtitle'),
        unit: _text(j, 'unit'),
        kind: _text(j, 'kind'),
        discountPct: j['discountPct'] is num ? j['discountPct'] as num : null,
        articleId: _text(j, 'articleId'),
      );

  final String description;

  /// Höchstens drei Nachkommastellen.
  @override
  final num quantity;

  /// Einzelpreis in ganzen Cent im `priceMode` der Rechnung. Als `num`, damit
  /// ein fehlerhafter Wert unverändert beim Server ankommt und dort als
  /// `validation` mit Feldpfad zurückkommt — nicht still gerundet.
  /// `null`, wenn die Position ihren Preis in [unitPriceMicros] trägt.
  @override
  final num? unitPriceCents;

  /// Einzelpreis in Mikro-Euro (10⁻⁶ €) — für Preise unterhalb eines Cents,
  /// etwa in der Verbrauchsabrechnung. Gilt erst ab dem Schalter des Kontos;
  /// ohne ihn weist der Server ihn mit `validation` ab und sagt es.
  @override
  final num? unitPriceMicros;

  /// Der USt-Satz in Prozent. Gesendet wird ein Satz aus [vatRates] (`0`,
  /// `10`, `13`, `20`); gelesen wird jeder Satz, den der Server schickt —
  /// darum `num` und nicht `int`. Eine Rechnung aus dem Panel kann eine Zeile
  /// zu 4,9 % (Grundnahrungsmittel) tragen, und ein `int` liesse das Lesen der
  /// eigenen Gutschrift daran scheitern.
  @override
  final num vatRate;
  final String? subtitle;

  /// Schlüssel aus [invoiceUnits] (`piece`, `hour`, …); ohne Angabe `piece`.
  /// Als `String`, damit ein unbekannter Wert als `validation` mit Feldpfad
  /// vom Server zurückkommt statt hier still zu verschwinden.
  final String? unit;

  /// Ware oder Leistung ([itemKinds]); ohne Angabe `goods`. Entscheidet
  /// grenzüberschreitend über ig. Lieferung oder Reverse Charge.
  final String? kind;

  /// Zeilenrabatt in Prozent, höchstens zwei Nachkommastellen.
  @override
  final num? discountPct;

  /// Artikel aus dem Artikelstamm (Lager). Ist er bestandsgeführt und das
  /// Modul Lager aktiv, bucht das Ausstellen ihn ab — danach; die Rechnung
  /// scheitert nie am Lager. Die Form (kein `/`, nicht `.`/`..`) prüft der
  /// Server (`validation` mit Feldpfad).
  final String? articleId;

  @override
  num get priceInCents => unitPriceCents ?? (unitPriceMicros ?? 0) / 10000;

  Map<String, dynamic> toJson() {
    final j = <String, dynamic>{};
    j['description'] = description;
    _setzen(j, 'subtitle', subtitle);
    j['quantity'] = quantity;
    _setzen(j, 'unit', unit);
    _setzen(j, 'kind', kind);
    // Gesendet wird genau das Feld, das gesetzt ist -- beide zu senden waere
    // ebenso ungueltig wie keines.
    _setzen(j, 'unitPriceCents', unitPriceCents);
    _setzen(j, 'unitPriceMicros', unitPriceMicros);
    j['vatRate'] = vatRate;
    _setzen(j, 'discountPct', discountPct);
    _setzen(j, 'articleId', articleId);
    return j;
  }
}

/// Eine Gutschriftsposition: wie [InvoiceItemInput], dazu die Rückgabe-Wahl.
///
/// Geht in [CreditNoteRequest.items]. An einer Rechnung ([IssueInvoiceRequest])
/// kennt der Server das Feld nicht und weist eine gesetzte [returnDisposition]
/// als `validation` (`items[i].returnDisposition`) ab.
class CreditNoteItemInput extends InvoiceItemInput {
  const CreditNoteItemInput({
    required super.description,
    required super.quantity,
    super.unitPriceCents,
    super.unitPriceMicros,
    required super.vatRate,
    super.subtitle,
    super.unit,
    super.kind,
    super.discountPct,
    super.articleId,
    this.returnDisposition,
  });

  factory CreditNoteItemInput.fromJson(Map<String, dynamic> j) {
    final p = InvoiceItemInput.fromJson(j);
    return CreditNoteItemInput(
      description: p.description,
      quantity: p.quantity,
      unitPriceCents: p.unitPriceCents,
      unitPriceMicros: p.unitPriceMicros,
      vatRate: p.vatRate,
      subtitle: p.subtitle,
      unit: p.unit,
      kind: p.kind,
      discountPct: p.discountPct,
      articleId: p.articleId,
      returnDisposition: _text(j, 'returnDisposition'),
    );
  }

  /// Wohin die Ware dieser Position geht, aus `returnDispositions`; fehlt =
  /// die Vorgabe der Gutschrift ([CreditNoteRequest.returnDisposition]) bzw.
  /// `restock`. Wirkt nur an Positionen mit [articleId]. Als `String`, damit
  /// ein unbekannter Wert unverändert beim Server ankommt und als
  /// `validation` mit Feldpfad zurückkommt.
  final String? returnDisposition;

  @override
  Map<String, dynamic> toJson() {
    final j = super.toJson();
    _setzen(j, 'returnDisposition', returnDisposition);
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
    this.stockLocationId,
    this.payment,
    this.dryRun,
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
        stockLocationId: _text(j, 'stockLocationId'),
        payment: j['payment'] is Map ? PaymentInput.fromJson(Map<String, dynamic>.from(j['payment'] as Map)) : null,
        dryRun: j['dryRun'] is bool ? j['dryRun'] as bool : null,
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

  /// Lager-Standort, von dem bestandsgeführte Positionen ([InvoiceItemInput.articleId])
  /// abgebucht werden; sonst der Standard-Standort. Ein unbekannter oder
  /// aufgelöster Standort bucht am Standard-Standort und meldet ein Ereignis
  /// im Lager — die Rechnung scheitert nie daran.
  final String? stockLocationId;

  /// Schon bezahlt: die Zahlung entsteht in derselben Transaktion wie das
  /// Festschreiben, das PDF trägt dann keine Zahlungsinformationen.
  final PaymentInput? payment;

  /// Wie im Vertrag von `issueInvoice`; bleibt beim Lesen aus JSON erhalten
  /// und geht so hinaus. `true` gehört zu `previewInvoice`: `issueInvoice`
  /// weist eine Anfrage mit `dryRun: true` vor dem Senden ab, statt die
  /// Probe-Absicht still zu verlieren.
  final bool? dryRun;

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
    _setzen(j, 'stockLocationId', stockLocationId);
    _setzen(j, 'payment', payment?.toJson());
    _setzen(j, 'dryRun', dryRun);
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

  /// Die Felder dieser Sicht, wie `/v3` sie sendet (Feldmengen-Test).
  static const fields = {'id', 'amountCents', 'paidAt', 'method', 'reference'};

  final String id;
  final int amountCents;
  final String? paidAt;
  final String? method;
  final String? reference;
}

/// Ein Hinweis an einer erfolgreichen Antwort — kein Fehler, nur etwas, das der
/// Aufrufer wissen sollte. Die Codes stehen in `invoiceNoticeCodes`.
///
/// `code` und `message` sind beide Pflicht — fehlt eines, ist es kein Hinweis:
/// [InvoiceNotice.fromJson] wirft dann, und die Aufrufe von `InvoiceApi`
/// übergehen den Eintrag (die Rechnung ist da schon ausgestellt).
class InvoiceNotice {
  const InvoiceNotice({required this.code, required this.message});

  factory InvoiceNotice.fromJson(Map<String, dynamic> j) => InvoiceNotice(
        code: _pflicht<String>(j, 'code'),
        message: _pflicht<String>(j, 'message'),
      );

  static const fields = {'code', 'message'};

  final String code;
  final String message;
}

/// Ergebnis von `recordInvoicePayment`.
class RecordPaymentResult {
  const RecordPaymentResult({required this.invoice, required this.payment, required this.replayed, this.notice = const []});

  factory RecordPaymentResult.fromJson(Map<String, dynamic> j) => RecordPaymentResult(
        invoice: Invoice.fromJson(_objekt(j, 'invoice')),
        payment: InvoicePayment.fromJson(_objekt(j, 'payment')),
        replayed: j['replayed'] == true,
        notice: _hinweise(j),
      );

  /// `notice` fehlt ohne Hinweis.
  static const fields = {'invoice', 'payment', 'replayed', 'notice'};

  final Invoice invoice;
  final InvoicePayment payment;
  final bool replayed;

  /// Hinweise zu dieser Zahlung — eine **Liste** wie bei `issueInvoice`, leer
  /// ohne Hinweis. Bis 6.20.0 ein einzelner, nullbarer [InvoiceNotice].
  final List<InvoiceNotice> notice;
}

class CreditNoteRequest {
  const CreditNoteRequest({
    required this.idempotencyKey,
    required this.invoiceId,
    required this.reason,
    required this.items,
    this.note,
    this.returnDisposition,
  });

  factory CreditNoteRequest.fromJson(Map<String, dynamic> j) => CreditNoteRequest(
        idempotencyKey: _pflicht<String>(j, 'idempotencyKey'),
        invoiceId: _pflicht<String>(j, 'invoiceId'),
        reason: _pflicht<String>(j, 'reason'),
        items: [for (final p in _liste(j, 'items')) CreditNoteItemInput.fromJson(p)],
        note: _text(j, 'note'),
        returnDisposition: _text(j, 'returnDisposition'),
      );

  final String idempotencyKey;
  final String invoiceId;

  /// Einer von [creditNoteReasons].
  final String reason;
  final String? note;

  /// Positionen; eine [CreditNoteItemInput] trägt zusätzlich ihre eigene
  /// Rückgabe-Wahl. Eine schlichte [InvoiceItemInput] bleibt gültig.
  final List<InvoiceItemInput> items;

  /// Vorgabe der Rückgabe-Wahl für alle bestandsgeführten Positionen, aus
  /// `returnDispositions`; fehlt = `restock`. Je Position abweichend über
  /// [CreditNoteItemInput.returnDisposition].
  final String? returnDisposition;

  Map<String, dynamic> toJson() {
    final j = <String, dynamic>{'idempotencyKey': idempotencyKey, 'invoiceId': invoiceId, 'reason': reason};
    _setzen(j, 'note', note);
    j['items'] = [for (final p in items) p.toJson()];
    _setzen(j, 'returnDisposition', returnDisposition);
    return j;
  }
}

/// Summen eines USt-Satzes.
class VatRateTotal {
  const VatRateTotal({required this.rate, required this.netCents, required this.vatCents, int? grossCents})
      : grossCents = grossCents ?? netCents + vatCents;

  /// Ein Server vor npm 0.22.0 schickt `grossCents` nicht mit; es ist per
  /// Definition Netto + USt und wird dann daraus gebildet.
  factory VatRateTotal.fromJson(Map<String, dynamic> j) => VatRateTotal(
        rate: _pflicht<num>(j, 'rate'),
        netCents: _pflicht<int>(j, 'netCents'),
        vatCents: _pflicht<int>(j, 'vatCents'),
        grossCents: _ganz(j, 'grossCents'),
      );

  /// Der USt-Satz in Prozent — `num`, weil es Saetze mit Nachkommastelle gibt
  /// (4,9 % Grundnahrungsmittel ab 01.07.2026). Ein `int` liess `getInvoice`
  /// bei so einer Rechnung mit `FormatException` scheitern.
  static const fields = {'rate', 'netCents', 'vatCents', 'grossCents'};

  final num rate;
  final int netCents;
  final int vatCents;

  /// `netCents + vatCents` — im Brutto-Modus der vereinbarte Preis dieses Satzes.
  final int grossCents;

  Map<String, dynamic> toJson() =>
      {'rate': rate, 'netCents': netCents, 'vatCents': vatCents, 'grossCents': grossCents};
}

/// Summen einer Rechnung in Cent, **immer positiv** — auch bei einer
/// Gutschrift (`docType: 'credit_note'`); das Vorzeichen steht im Belegtyp, nicht im
/// Betrag. Gerechnet wird je Satz wie in `computeInvoiceTotals`.
class InvoiceTotals {
  const InvoiceTotals({required this.netCents, required this.vatCents, required this.grossCents, this.byRate = const []});

  factory InvoiceTotals.fromJson(Map<String, dynamic> j) => InvoiceTotals(
        netCents: _pflicht<int>(j, 'netCents'),
        vatCents: _pflicht<int>(j, 'vatCents'),
        grossCents: _pflicht<int>(j, 'grossCents'),
        byRate: j['byRate'] is List ? [for (final r in _liste(j, 'byRate')) VatRateTotal.fromJson(r)] : const [],
      );

  static const fields = {'netCents', 'vatCents', 'grossCents', 'byRate'};

  final int netCents;
  final int vatCents;
  final int grossCents;

  /// Je USt-Satz, absteigend.
  final List<VatRateTotal> byRate;

  /// Dieselbe Form wie `totals` in den Antworten.
  Map<String, dynamic> toJson() => {
        'netCents': netCents,
        'vatCents': vatCents,
        'grossCents': grossCents,
        'byRate': [for (final r in byRate) r.toJson()],
      };
}

/// Eine gespeicherte Position: wie gesendet, fehlende Angaben mit ihrem Standardwert.
class InvoiceItem {
  const InvoiceItem({
    required this.description,
    required this.quantity,
    required this.unit,
    required this.unitPriceCents,
    required this.vatRate,
    this.kind = 'goods',
    this.unitPriceMicros,
    this.subtitle = '',
    this.discountPct = 0,
  });

  factory InvoiceItem.fromJson(Map<String, dynamic> j) => InvoiceItem(
        description: _pflicht<String>(j, 'description'),
        subtitle: _text(j, 'subtitle') ?? '',
        quantity: _pflicht<num>(j, 'quantity'),
        unit: _text(j, 'unit') ?? 'piece',
        kind: _text(j, 'kind') ?? 'goods',
        unitPriceCents: _pflicht<int>(j, 'unitPriceCents'),
        unitPriceMicros: j['unitPriceMicros'] is num ? j['unitPriceMicros'] as num : null,
        vatRate: _pflicht<num>(j, 'vatRate'),
        discountPct: j['discountPct'] is num ? j['discountPct'] as num : 0,
      );

  /// `unitPriceMicros` fehlt beim Altbestand, den der Server nicht darstellen kann.
  static const fields = {
    'description', 'subtitle', 'quantity', 'unit', 'kind', 'unitPriceCents', 'unitPriceMicros', 'vatRate', 'discountPct',
  };

  final String description;
  final String subtitle;
  final num quantity;

  /// Einer von [invoiceUnits].
  final String unit;

  /// Ware oder Leistung ([itemKinds]); ohne Angabe `goods`. Wer Positionen
  /// für eine Gutschrift übernimmt, gibt es mit: es entscheidet den Steuerfall.
  final String kind;

  /// Einzelpreis in ganzen Cent: eine ANZEIGEHILFE, kaufmännisch aus
  /// [unitPriceMicros] gerundet und damit 0, sobald der Preis unter einem
  /// halben Cent liegt. Verbindlich sind [unitPriceMicros] und die Beträge je
  /// Position (§ 9.3).
  final int unitPriceCents;

  /// Einzelpreis in Mikro-Euro (10⁻⁶ €), der verbindliche Preis. `null` nur,
  /// wenn der Server ihn nicht darstellen konnte (Altbestand mit mehr als
  /// sechs Nachkommastellen); ein geratener Wert wäre schlimmer als keiner.
  final num? unitPriceMicros;
  final num vatRate;
  final num discountPct;

  /// Der Preis in Cent, gleich welches Feld ihn trägt.
  num get priceInCents => unitPriceMicros != null ? unitPriceMicros! / 10000 : unitPriceCents;
}

class CreditNoteSummary {
  const CreditNoteSummary({required this.id, required this.grossCents, this.number});

  factory CreditNoteSummary.fromJson(Map<String, dynamic> j) => CreditNoteSummary(
        id: _pflicht<String>(j, 'id'),
        number: _text(j, 'number'),
        grossCents: _pflicht<int>(j, 'grossCents'),
      );

  static const fields = {'id', 'number', 'grossCents'};

  final String id;
  final String? number;
  final int grossCents;
}

/// Der Empfänger, wie er auf der Rechnung steht (beim Ausstellen eingefroren,
/// nicht der heutige Kundenstamm).
class InvoiceRecipient {
  const InvoiceRecipient({
    required this.name,
    required this.type,
    required this.country,
    required this.isAuthority,
    this.street,
    this.houseNumber,
    this.zip,
    this.city,
    this.vatId,
    this.shortCode,
    this.email,
  });

  factory InvoiceRecipient.fromJson(Map<String, dynamic> j) => InvoiceRecipient(
        name: _pflicht<String>(j, 'name'),
        type: _pflicht<String>(j, 'type'),
        street: _text(j, 'street'),
        houseNumber: _text(j, 'houseNumber'),
        zip: _text(j, 'zip'),
        city: _text(j, 'city'),
        country: _pflicht<String>(j, 'country'),
        vatId: _text(j, 'vatId'),
        shortCode: _text(j, 'shortCode'),
        email: _text(j, 'email'),
        isAuthority: j['isAuthority'] == true,
      );

  static const fields = {
    'name', 'type', 'street', 'houseNumber', 'zip', 'city', 'country', 'vatId', 'shortCode', 'email', 'isAuthority',
  };

  final String name;

  /// `private` oder `company` ([customerTypes]).
  final String type;
  final String? street;
  final String? houseNumber;
  final String? zip;
  final String? city;

  /// ISO-3166-Alpha-2.
  final String country;
  final String? vatId;
  final String? shortCode;
  final String? email;

  /// Behörde: die Rechnung geht als E-Rechnung hinaus.
  final bool isAuthority;
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
    this.relatedNumber,
    this.language = 'de',
    this.brandId,
    this.brandName,
    this.einvoice,
    this.taxScheme,
    this.payments,
    this.writeOffReasonCode,
    this.customer,
    this.reverseChargeReason,
    this.taxCountry,
    this.priceMode,
    this.serviceStart,
    this.serviceEnd,
    this.paymentTermDays,
    this.orderReference,
    this.source,
    this.createdAt,
    this.finalizedAt,
  });

  factory Invoice.fromJson(Map<String, dynamic> j) {
    final einvoice = _objektOderNull(j, 'einvoice');
    final metadaten = j['metadata'];
    final related = _objektOderNull(j, 'related');
    final brand = _objektOderNull(j, 'brand');
    final customer = _objektOderNull(j, 'customer');
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
      einvoiceLevel: einvoice != null && einvoice['level'] is String ? einvoice['level'] as String : null,
      metadata: metadaten is Map
          ? {for (final e in metadaten.entries) if (e.value is String) '${e.key}': e.value as String}
          : const {},
      items: j['items'] is List ? [for (final p in _liste(j, 'items')) InvoiceItem.fromJson(p)] : null,
      paidCents: _ganz(j, 'paidCents'),
      openCents: _ganz(j, 'openCents'),
      overdue: j['overdue'] is bool ? j['overdue'] as bool : null,
      writtenOff: j['writtenOff'] is bool ? j['writtenOff'] as bool : null,
      creditNotes: j['creditNotes'] is List ? [for (final c in _liste(j, 'creditNotes')) CreditNoteSummary.fromJson(c)] : null,
      relatedInvoiceId: related != null && related['invoiceId'] is String ? related['invoiceId'] as String : null,
      relatedNumber: related != null && related['number'] is String ? related['number'] as String : null,
      language: _text(j, 'language') == 'en' ? 'en' : 'de',
      brandId: brand != null && brand['id'] is String ? brand['id'] as String : null,
      brandName: brand != null && brand['name'] is String ? brand['name'] as String : null,
      einvoice: einvoice != null ? EInvoiceStatus.fromJson(einvoice) : null,
      taxScheme: _text(j, 'taxScheme'),
      payments: j['payments'] is List ? [for (final z in _liste(j, 'payments')) InvoiceDetailPayment.fromJson(z)] : null,
      writeOffReasonCode: _text(j, 'writeOffReasonCode'),
      customer: customer != null ? InvoiceRecipient.fromJson(customer) : null,
      reverseChargeReason: _text(j, 'reverseChargeReason'),
      taxCountry: _text(j, 'taxCountry'),
      priceMode: _text(j, 'priceMode'),
      serviceStart: _text(j, 'serviceStart'),
      serviceEnd: _text(j, 'serviceEnd'),
      paymentTermDays: _ganz(j, 'paymentTermDays'),
      orderReference: _text(j, 'orderReference'),
      source: _text(j, 'source'),
      createdAt: _text(j, 'createdAt'),
      finalizedAt: _text(j, 'finalizedAt'),
    );
  }

  /// Die Felder in Listen und Ausstell-Antworten.
  static const fields = {
    'id', 'number', 'docType', 'status', 'invoiceDate', 'dueDate', 'customerId', 'totals', 'einvoice', 'statusUrl',
    'statusPassword', 'metadata', 'language', 'brand', 'paidCents', 'openCents',
  };

  /// Die Felder der Detailsicht (`getInvoice`).
  static const detailFields = {
    ...fields,
    'items', 'customer', 'taxScheme', 'reverseChargeReason', 'taxCountry', 'priceMode', 'serviceStart', 'serviceEnd',
    'paymentTermDays', 'orderReference', 'payments', 'overdue', 'writtenOff', 'writeOffReasonCode', 'related',
    'creditNotes', 'source', 'createdAt', 'finalizedAt',
  };

  /// Die Felder von `brand` und `related`.
  static const brandFields = {'id', 'name'};
  static const relatedFields = {'invoiceId', 'number'};

  final String id;
  final String number;

  /// `invoice` oder `credit_note` ([docTypes]).
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

  /// Beim Ausstellen eingefroren; ältere Rechnungen `de`.
  final String language;

  /// Die eingefrorene Marke; `null` bei der Ersatzmarke ohne eigene Einrichtung.
  final String? brandId;
  final String? brandName;

  /// Wie weit die Rechnung als E-Rechnung taugt, samt der fehlenden Angaben
  /// ([einvoiceMissingCodes]); [einvoiceLevel] ist davon die Stufe.
  final EInvoiceStatus? einvoice;

  final int? paidCents;
  final int? openCents;

  // Detail (nur `getInvoice`)

  final List<InvoiceItem>? items;

  /// Der Empfänger auf der Rechnung.
  final InvoiceRecipient? customer;

  /// Der Steuerfall ([taxSchemes]).
  final String? taxScheme;

  /// Nur bei `domesticReverseCharge` ([reverseChargeReasons]).
  final String? reverseChargeReason;

  /// Land, dessen Steuer die Rechnung trägt; Altbestand `AT`.
  final String? taxCountry;

  /// `net` oder `gross` ([priceModes]).
  final String? priceMode;
  final String? serviceStart;
  final String? serviceEnd;
  final int? paymentTermDays;
  final String? orderReference;

  /// Die gebuchten Zahlungen.
  final List<InvoiceDetailPayment>? payments;
  final bool? overdue;
  final bool? writtenOff;

  /// Warum abgeschrieben wurde ([writeOffReasonCodes]); `null`, solange
  /// [writtenOff] nicht `true` ist.
  final String? writeOffReasonCode;

  /// Bei einer Gutschrift: die Rechnung, auf die sie sich bezieht.
  final String? relatedInvoiceId;
  final String? relatedNumber;
  final List<CreditNoteSummary>? creditNotes;

  /// Woher die Rechnung kam (z. B. `api`).
  final String? source;
  final String? createdAt;
  final String? finalizedAt;
}

/// Die E-Rechnung aus `getInvoiceXml`, wie der Server sie sendet.
class InvoiceXml {
  const InvoiceXml({required this.xml, required this.format, required this.filename});

  final String xml;

  /// `ubl` oder `cii`.
  final String format;

  /// `invoice-<Nummer>.xml`.
  final String filename;
}

/// Eine gebuchte Zahlung in der Detailsicht (`getInvoice`). Das Datum heißt
/// hier `date`, in `recordInvoicePayment` `paidAt`. Altbestand kann ohne
/// Kennung, Datum und Zahlart sein; der Betrag ist immer da.
class InvoiceDetailPayment {
  const InvoiceDetailPayment({required this.amountCents, this.id, this.date, this.method, this.reference});

  factory InvoiceDetailPayment.fromJson(Map<String, dynamic> j) => InvoiceDetailPayment(
        id: _text(j, 'id'),
        amountCents: _pflicht<int>(j, 'amountCents'),
        date: _text(j, 'date'),
        method: _text(j, 'method'),
        reference: _text(j, 'reference'),
      );

  static const fields = {'id', 'amountCents', 'date', 'method', 'reference'};

  final String? id;
  final int amountCents;
  final String? date;

  /// Aus [invoicePaymentMethods].
  final String? method;

  /// Zahlungskennung des Fremdsystems, wie bei `recordInvoicePayment` gesetzt.
  final String? reference;
}

/// Eine Marke des Kontos (Logo, Farbe, Absender); `id` geht als `brandId` in `issueInvoice`.
class Brand {
  const Brand({required this.id, required this.name, required this.isDefault});

  factory Brand.fromJson(Map<String, dynamic> j) => Brand(
        id: _pflicht<String>(j, 'id'),
        name: _text(j, 'name') ?? '',
        isDefault: j['isDefault'] == true,
      );

  static const fields = {'id', 'name', 'isDefault'};

  final String id;
  final String name;
  final bool isDefault;
}

class InvoicePage {
  const InvoicePage({required this.invoices, this.nextCursor});

  factory InvoicePage.fromJson(Map<String, dynamic> j) => InvoicePage(
        invoices: [for (final i in _liste(j, 'invoices')) Invoice.fromJson(i)],
        nextCursor: _text(j, 'nextCursor'),
      );

  static const fields = {'invoices', 'nextCursor'};

  final List<Invoice> invoices;

  /// `null` auf der letzten Seite. Eine Seite kann kürzer als `limit` sein und
  /// trotzdem einen Cursor tragen (Status wird nachgefiltert).
  final String? nextCursor;
}

class IssueResult {
  const IssueResult({required this.invoice, required this.replayed, this.notice = const []});

  factory IssueResult.fromJson(Map<String, dynamic> j) => IssueResult(
        invoice: Invoice.fromJson(_objekt(j, 'invoice')),
        replayed: j['replayed'] == true,
        notice: _hinweise(j),
      );

  /// `notice` fehlt ohne Hinweis.
  static const fields = {'invoice', 'replayed', 'notice'};

  final Invoice invoice;

  /// `true`, wenn die Anfrage schon einmal ausgeführt wurde.
  final bool replayed;

  /// Hinweise zu dieser Rechnung — kein Fehler, sondern etwas, das der Aufrufer
  /// wissen sollte ([invoiceNoticeCodes]). Eine **Liste**, weil mehrere zugleich
  /// anfallen können: eine bar bezahlte ig. Lieferung trägt zwei.
  final List<InvoiceNotice> notice;
}

/// Wie weit eine Rechnung als E-Rechnung (EN 16931) taugt.
class EInvoiceStatus {
  const EInvoiceStatus({required this.level, this.formats = const [], this.missing = const []});

  factory EInvoiceStatus.fromJson(Map<String, dynamic> j) => EInvoiceStatus(
        level: _pflicht<String>(j, 'level'),
        formats: _texte(j, 'formats'),
        missing: _texte(j, 'missing'),
      );

  static const fields = {'level', 'formats', 'missing'};

  /// `full`, `partial` oder `insufficient`.
  final String level;

  /// Die Formate, die entstehen (`UBL`, `Factur-X`); leer bei `insufficient`.
  final List<String> formats;

  /// Was für eine vollständige E-Rechnung fehlt.
  final List<String> missing;
}

List<String> _texte(Map<String, dynamic> j, String feld) {
  final wert = j[feld];
  if (wert == null) return const [];
  if (wert is! List) throw FormatException(feld);
  return [for (final e in wert) if (e is String) e else throw FormatException(feld)];
}

/// Was `issueInvoice` mit dieser Anfrage ausstellen würde — ohne Nummer, ohne
/// Dokument, ohne Zahlung (`previewInvoice`).
class InvoicePreview {
  const InvoicePreview({
    required this.docType,
    required this.invoiceDate,
    required this.taxScheme,
    required this.taxCountry,
    required this.priceMode,
    required this.totals,
    this.dueDate,
    this.customerId,
    this.taxSchemeReason,
    this.reverseChargeReason,
    this.language = 'de',
    this.brandId,
    this.brandName,
    this.einvoice,
  });

  factory InvoicePreview.fromJson(Map<String, dynamic> j) {
    final brand = _objektOderNull(j, 'brand');
    final einvoice = _objektOderNull(j, 'einvoice');
    return InvoicePreview(
      docType: _pflicht<String>(j, 'docType'),
      invoiceDate: _pflicht<String>(j, 'invoiceDate'),
      taxScheme: _pflicht<String>(j, 'taxScheme'),
      taxCountry: _pflicht<String>(j, 'taxCountry'),
      priceMode: _pflicht<String>(j, 'priceMode'),
      totals: InvoiceTotals.fromJson(_objekt(j, 'totals')),
      dueDate: _text(j, 'dueDate'),
      customerId: _text(j, 'customerId'),
      taxSchemeReason: _text(j, 'taxSchemeReason'),
      reverseChargeReason: _text(j, 'reverseChargeReason'),
      language: _text(j, 'language') == 'en' ? 'en' : 'de',
      brandId: brand != null && brand['id'] is String ? brand['id'] as String : null,
      brandName: brand != null && brand['name'] is String ? brand['name'] as String : null,
      einvoice: einvoice != null ? EInvoiceStatus.fromJson(einvoice) : null,
    );
  }

  static const fields = {
    'docType', 'invoiceDate', 'dueDate', 'customerId', 'taxScheme', 'taxSchemeReason', 'reverseChargeReason',
    'taxCountry', 'priceMode', 'totals', 'language', 'brand', 'einvoice',
  };

  /// Immer `invoice`: einen Probelauf gibt es nur für das Ausstellen.
  final String docType;

  /// Heutiger Wiener Tag — der Tag, den eine sofort ausgestellte Rechnung trüge.
  final String invoiceDate;
  final String? dueDate;
  final String? customerId;

  /// Der abgeleitete Steuerfall ([taxSchemes]).
  final String taxScheme;

  /// Warum dieser Fall gilt (z. B. `customer_country_eu_with_vat_id`).
  final String? taxSchemeReason;

  /// Bei `domesticReverseCharge` einer aus `reverseChargeReasons`.
  final String? reverseChargeReason;

  /// ISO-3166-Alpha-2 des Landes, dessen Steuer gilt.
  final String taxCountry;
  final String priceMode;

  /// Die Summen, die die Rechnung ausweisen würde – wie `computeInvoiceTotals` sie
  /// vorab rechnet, hier aber vom Server.
  final InvoiceTotals totals;
  final String language;

  /// Die Marke, die die Rechnung trüge; `null` bei der Ersatzmarke.
  final String? brandId;
  final String? brandName;
  final EInvoiceStatus? einvoice;
}

/// Ergebnis von `previewInvoice`.
class PreviewResult {
  const PreviewResult({required this.preview, this.notice = const []});

  factory PreviewResult.fromJson(Map<String, dynamic> j) => PreviewResult(
        preview: InvoicePreview.fromJson(_objekt(j, 'preview')),
        notice: _hinweise(j),
      );

  static const fields = {'preview', 'notice'};

  final InvoicePreview preview;

  /// Dieselben Hinweise, die das Ausstellen liefern würde; leer ohne Hinweis.
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

  factory CancelResult.fromJson(Map<String, dynamic> j) {
    final original = _objekt(j, 'original');
    return CancelResult(
      creditNote: Invoice.fromJson(_objekt(j, 'creditNote')),
      originalId: _pflicht<String>(original, 'id'),
      originalStatus: _text(original, 'status'),
      originalPaidCents: _ganz(j, 'originalPaidCents') ?? 0,
      replayed: j['replayed'] == true,
    );
  }

  static const fields = {'creditNote', 'original', 'originalPaidCents', 'replayed'};
  static const originalFields = {'id', 'status'};

  final Invoice creditNote;
  final String originalId;
  final String? originalStatus;

  /// Bereits auf das Original bezahlt — die Rückerstattung ist Sache des Betriebs.
  final int originalPaidCents;
  final bool replayed;
}

class CreditNoteResult {
  const CreditNoteResult({required this.creditNote, required this.remainingCents, required this.replayed});

  factory CreditNoteResult.fromJson(Map<String, dynamic> j) => CreditNoteResult(
        creditNote: Invoice.fromJson(_objekt(j, 'creditNote')),
        remainingCents: _ganz(j, 'remainingCents') ?? 0,
        replayed: j['replayed'] == true,
      );

  static const fields = {'creditNote', 'remainingCents', 'replayed'};

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

  static const fields = {'requirement', 'message'};

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

  static const fields = {'ready', 'environment', 'missing'};

  final bool ready;

  /// `live` oder `test` — die Umgebung des Schlüssels.
  final String environment;
  final List<InvoiceSetupGap> missing;
}
