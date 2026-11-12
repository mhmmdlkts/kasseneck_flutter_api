import '../enums/vat_rate.dart';
import '../src/kasse/rueckgabe.dart';

/// Die Kennzeichnungen, die eine Position tragen kann ([KasseneckItem.kind]).
const _bekannteArten = {'tip', 'discount', 'voucher', 'voucher_float', 'deposit', 'deposit_return', 'invoice_payment'};

class KasseneckItem {
  /// Name des Artikels / der Dienstleistung
  final String name;

  /// Menge (z. B. 1 Stück, 2 Stück)
  final int quantity;

  /// Steuersatz (z. B. 0, 4.9, 10, 13, 19, 20)
  final VatRate vat;

  /// Einzelpreis in **Cent** (z. B. 1999 = 19,99 EUR).
  ///
  /// Geld wird intern exakt in Integer-Cent gerechnet — keine
  /// Gleitkomma-Rundungsfehler. Das JSON-Format Richtung Backend bleibt
  /// unverändert in Euro (siehe [toJson]).
  final int priceCents;

  /// Positions-Kennzeichnung: `'tip'` (Trinkgeld, vom Backend aus dem
  /// Parameter `tip` erzeugt), `'discount'` (Rabatt, [distributeDiscount])
  /// oder eine Gutscheinzeile der neuen Form, die nur der Server setzt:
  /// `'voucher'` (Einzweck/Leistung) bzw. `'voucher_float'` (0-%-Topf,
  /// Mehrzweck-Verkauf ab dem Stichtag und Auszahlung), oder eine Pfandzeile,
  /// die ebenfalls nur der Server setzt: `'deposit'` (Pfand zur Ware) bzw.
  /// `'deposit_return'` (Leergut, negativer Betrag). Steuert nur die
  /// Beleg-Darstellung und die Berichts-Zuordnung, nie die Beträge. Zwilling
  /// von `ReceiptItem.kind` im JS-Paket.
  final String? kind;

  /// Empfänger einer Trinkgeld-Position: `{registerUserId, name, owner?}`.
  final Map<String, dynamic>? recipient;

  /// Zahlart der Trinkgeld-Position (kann von der des Belegs abweichen).
  final String? paymentMethod;

  /// Nur an Trinkgeld-Positionen: hatte der Empfaenger das Geld beim
  /// Ausstellen schon (`true`) oder behaelt es der Betrieb und schuldet es
  /// (`false`)? Drahtfeld `receivedImmediately` (frueher `sofortErhalten`);
  /// `null`, wenn der Beleg es nicht nennt.
  final bool? receivedImmediately;

  /// Nur an Trinkgeld-Positionen: Bar-Trinkgeld „gleich behalten“ -- die
  /// Mitarbeiterin hat es beim Verkauf gleich eingesteckt. Drahtfeld
  /// `keptByEmployee`, nur `true`; sonst `false`. Ein Merkmal fuer den
  /// Kassenstand, kein Betrag.
  final bool keptByEmployee;

  /// Was [KasseneckItem.fromJson] beim Lesen nicht exakt uebernehmen konnte
  /// (Bruchmenge abgeschnitten, unbekannter Steuersatz als 0 %); `null`, wenn
  /// alles passt. Wer mit so einer Position rechnet (`receiptDueCents`),
  /// bekommt einen Fehler statt eines still falschen Betrags. Geht nie hinaus.
  final String? lossyRead;

  /// Artikel-Verweis (Artikelstamm) — Grundlage der Erlösgruppen-Zuordnung
  /// im Bericht. Optional; Handeingaben haben keinen.
  final String? articleId;

  /// Nur an Storno-Zeilen mit [articleId]: Index der Position im Original.
  /// Setzt der Server; `null` an allen anderen Zeilen.
  final int? originalIndex;

  /// Nur an Storno-Zeilen mit [articleId]: wohin die Ware ging (Lager), ein
  /// Wert aus `returnDispositions`. Setzt der Server; ein unbekannter Wert
  /// faellt beim Lesen weg (`null`), wie am Rand des Servers.
  final String? returnDisposition;

  /// Zusatz-Kacheln (11.18.0): Index der Hauptposition im selben Beleg; nur
  /// an Zusatzpositionen. Der Server prueft: ganze Zahl, zeigt nach vorne auf
  /// eine Warenposition, die selbst kein Zusatz ist (`invalid_add_on_reference`).
  final int? addOnOf;

  /// Pfand & Leergut: Pfandart (Kennung aus `getKasseSettings`
  /// `deposit.depositTypes[].id`); nur an `deposit`- und `deposit_return`-Zeilen.
  final String? depositTypeId;

  /// Index der Warenposition im selben Beleg, zu der die Pfandzeile gehoert
  /// (nur `deposit`).
  final int? depositFor;

  /// Art der Pfandart zum Belegzeitpunkt: `single_use` oder `reusable`.
  final String? depositKind;

  /// Pfand je Stueck in Cent bei einer Pfandzeile; der Zeilenpreis ist Menge
  /// mal dieser Betrag.
  final num? perUnit;

  /// Strichcode des Gebindes (GTIN), falls bekannt.
  final String? gtin;

  /// Strichcode des Artikels (EAN), falls bekannt.
  final String? ean;

  /// Das Gebinde wurde im Betrieb selbst befuellt (eigene Abfuellung).
  final bool? ownFilling;

  /// Gelernte Leergut-Codes der Zeile (Code -> Menge); nur an `deposit_return`.
  final Map<String, int>? codes;

  KasseneckItem({
    required this.name,
    required this.quantity,
    required this.vat,
    required this.priceCents,
    this.kind,
    this.recipient,
    this.paymentMethod,
    this.articleId,
    this.receivedImmediately,
    this.keptByEmployee = false,
    this.lossyRead,
    this.originalIndex,
    this.returnDisposition,
    this.addOnOf,
    this.depositTypeId,
    this.depositFor,
    this.depositKind,
    this.perUnit,
    this.gtin,
    this.ean,
    this.ownFilling,
    this.codes,
  });

  /// Trinkgeld-Position? Die eine Erkennungsstelle — niemand prüft [kind] selbst.
  bool get isTip => kind == 'tip';

  /// Rabatt-Position? Die eine Erkennungsstelle — niemand prüft [kind] selbst.
  bool get isDiscount => kind == 'discount';

  /// Gutscheinzeile mit Umsatzsteuer-Wirkung (Einzweck, Leistung), vom Server
  /// gesetzt. Zwilling von `isVoucherItem` im JS-Paket.
  bool get isVoucher => kind == 'voucher';

  /// Gutscheinzeile als durchlaufender Posten im 0-%-Topf (Mehrzweck:
  /// Verkauf ab dem Stichtag, Auszahlung). Zwilling von `isVoucherFloatItem`.
  bool get isVoucherFloat => kind == 'voucher_float';

  /// Pfandzeile (Pfand zum Verkauf)? Die eine Erkennungsstelle. Zwilling von
  /// `isDepositItem` im JS-Paket.
  bool get isDeposit => kind == 'deposit';

  /// Leergutzeile (Ruecknahme, negativer Betrag)? Zwilling von
  /// `isDepositReturnItem` im JS-Paket.
  bool get isDepositReturn => kind == 'deposit_return';

  /// Zahlung auf Rechnung (Zahlungsbeleg, nur vom Server; Bezug in
  /// `KasseneckReceipt.invoicePayments`)? Die Position zaehlt im RKSV-Feld „Null“, ist aber kein
  /// steuerfreier Umsatz: die Umsatzsteuer steht auf der Rechnung. Am Bon steht sie ohne
  /// Satzkennzeichen und nicht in der Steuertabelle. Zwilling von `isInvoicePaymentItem` im npm-Paket.
  bool get isInvoicePayment => kind == 'invoice_payment';

  /// Trinkgeld an den Inhaber? Dann ist es Entgelt (§ 4 UStG) und traegt den
  /// Steuersatz der Leistung; Trinkgeld an Mitarbeiter ist durchlaufender
  /// Posten mit 0 % (Erlass 2.4.6 / 2.4.2.1). Der Vermerk ist eine
  /// Momentaufnahme vom Belegzeitpunkt — aendert sich das `inhaber`-Flag der
  /// Person spaeter, wirkt das nicht zurueck.
  bool get isOwnerTip => isTip && recipient?['owner'] == true;

  /// Kassen-Benutzer, dem diese Trinkgeld-Position zusteht — `null`, wenn
  /// keiner angegeben war („nicht zugeordnet").
  String? get tipRecipientId {
    final id = recipient?['registerUserId'];
    return id is String && id.isNotEmpty ? id : null;
  }

  /// Name des Empfaengers, wie er beim Ausstellen galt (Momentaufnahme).
  String? get tipRecipientName {
    final name = recipient?['name'];
    return name is String && name.isNotEmpty ? name : null;
  }

  /// Komfort-Konstruktor mit Einzelpreis in **Euro**.
  ///
  /// Der Betrag wird genau einmal — hier, an der API-Grenze — auf Cent
  /// gerundet; danach wird ausschliesslich exakt in Cent gerechnet.
  factory KasseneckItem.euro({
    required String name,
    required int quantity,
    required VatRate vat,
    required double singlePrice,
    String? articleId,
  }) {
    return KasseneckItem(
      name: name,
      quantity: quantity,
      vat: vat,
      priceCents: (singlePrice * 100).round(),
      articleId: articleId,
    );
  }

  factory KasseneckItem.cancel({
    required String name,
    required int amount,
    required VatRate vat,
    required int priceCents,
  }) {
    return KasseneckItem(
      name: name,
      quantity: amount,
      vat: vat,
      priceCents: -priceCents,
    );
  }

  /// Einzelpreis in Euro (Anzeige/Format — fuer Arithmetik [priceCents] nutzen).
  double get singlePrice => priceCents / 100;

  /// Zeilensumme in Cent (exakt, ohne Gleitkomma).
  int get totalCents => priceCents * quantity;

  /// Umwandlung ins JSON-Format (v2, empfohlen): `{ name, quantity,
  /// unitPriceCents, vatRate }`. Der Preis wird als ganze Cent (Integer)
  /// gesendet — keine Gleitkomma-Betraege. Das Backend akzeptiert weiterhin
  /// die alte v1-Form; gelesen werden beide (siehe [fromJson]).
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'quantity': quantity,
      'unitPriceCents': priceCents,
      'vatRate': vat.rate,
      // Kennzeichnungen reisen mit (Zwilling von toReceiptItemPayload im
      // JS-Paket): sonst käme ein Storno dieser Positionen am Bon wieder
      // als gewöhnliche Warenzeile an. Zeilen ohne bleiben schlank.
      if (kind == 'tip') ...{
        'kind': 'tip',
        'recipient': recipient,
        if (paymentMethod != null) 'paymentMethod': paymentMethod,
        'receivedImmediately': ?receivedImmediately,
        if (keptByEmployee) 'keptByEmployee': true,
      },
      if (kind == 'discount') 'kind': 'discount',
      // Gutscheinzeilen (vom Server) reisen mit: der Zwischenspeicher schreibt
      // gelesene Belege wieder. Ein Verkauf traegt sie nie (createReceipt
      // weist sie vor dem Senden als voucher_invalid ab).
      if (kind == 'voucher' || kind == 'voucher_float') 'kind': kind,
      // Zahlung auf Rechnung (vom Server): reist mit wie die Gutscheinzeilen; ein Wunsch an den Server
      // traegt sie nie (createReceipt weist sie ausser beim Selbstaufruf ab).
      if (kind == 'invoice_payment') 'kind': kind,
      // Pfand & Leergut: Kennzeichen und Felder reisen mit (der Zwischenspeicher
      // schreibt gelesene Belege wieder; ein Wunsch an den Server traegt `deposit`
      // nie mit `articleId`). Zwilling von toReceiptItemPayload im JS-Paket.
      if (kind == 'deposit' || kind == 'deposit_return') ...{
        'kind': kind,
        if (depositTypeId != null && depositTypeId!.isNotEmpty) 'depositTypeId': depositTypeId,
        if (depositFor != null && depositFor! >= 0) 'depositFor': depositFor,
        if (depositKind == 'single_use' || depositKind == 'reusable') 'depositKind': depositKind,
        if (perUnit != null && perUnit!.isFinite) 'perUnit': perUnit,
        if (gtin != null && gtin!.isNotEmpty) 'gtin': gtin,
        if (ean != null && ean!.isNotEmpty) 'ean': ean,
        'ownFilling': ?ownFilling,
        if (codes != null && codes!.isNotEmpty) 'codes': codes,
      },
      if (articleId != null && articleId!.isNotEmpty) 'articleId': articleId,
      // Nur an gelesenen Storno-Zeilen gesetzt (der Zwischenspeicher behaelt
      // sie); eine Verkaufszeile traegt beides nie.
      'originalIndex': ?originalIndex,
      'returnDisposition': ?returnDisposition,
      // Zusatz-Kacheln: Verweis auf die Hauptposition nur, wenn gesetzt.
      if (addOnOf != null && addOnOf! >= 0) 'addOnOf': addOnOf,
    };
  }

  /// Erzeugt ein KasseneckItem aus einem JSON-Objekt.
  ///
  /// Liest sowohl die neue v2-Form (`unitPriceCents` / `quantity` / `vatRate`)
  /// als auch die alte v1-Form (`priceOneCents` bzw. `priceOne` / `amount` /
  /// `vat`) — so parsen alte gespeicherte Belege weiterhin. Cent-Felder werden
  /// bevorzugt (exakt), Euro nur als Fallback mit einmaliger Rundung.
  factory KasseneckItem.fromJson(Map<String, dynamic> json) {
    final cents = json['unitPriceCents'] ?? json['priceOneCents'];
    final euro = json['priceOne'];
    final quantity = json['quantity'] ?? json['amount'];
    final rate = json['vatRate'] ?? json['vat'];
    final kind = json['kind'];
    final pfand = kind == 'deposit' || kind == 'deposit_return';
    final satzBekannt = VatRate.values.any((e) => e.rate == rate);
    final String? ungenau = quantity is num && quantity != quantity.toInt()
        ? 'Menge $quantity ist keine ganze Zahl'
        : (rate != null && !satzBekannt ? 'Steuersatz $rate ist unbekannt' : null);
    return KasseneckItem(
      name: (json['name'] as String?) ?? '',
      // num statt int: manche Quellen liefern 1.0 statt 1.
      quantity: quantity is num ? quantity.toInt() : 0,
      vat: VatRate.values.firstWhere((e) => e.rate == rate, orElse: () => VatRate.vat0),
      priceCents: cents is num ? cents.round() : (euro is num ? (euro * 100).round() : 0),
      kind: _bekannteArten.contains(kind) ? kind as String : null,
      recipient: json['recipient'] is Map ? Map<String, dynamic>.from(json['recipient'] as Map) : null,
      paymentMethod: json['paymentMethod'] as String?,
      articleId: json['articleId'] is String && (json['articleId'] as String).isNotEmpty ? json['articleId'] as String : null,
      receivedImmediately: kind == 'tip' && json['receivedImmediately'] is bool ? json['receivedImmediately'] as bool : null,
      keptByEmployee: kind == 'tip' && json['keptByEmployee'] == true,
      lossyRead: ungenau,
      // Lager: Bezug und Rueckgabe-Wahl einer Storno-Zeile (nur gelesen; ein
      // unbekannter Wert faellt weg wie im JS-Zwilling).
      originalIndex: json['originalIndex'] is int && (json['originalIndex'] as int) >= 0 ? json['originalIndex'] as int : null,
      returnDisposition: isReturnDisposition(json['returnDisposition']) ? json['returnDisposition'] as String : null,
      // Zusatz-Kacheln: nur eine ganze Zahl >= 0 (wie im JS-Zwilling).
      addOnOf: json['addOnOf'] is int && (json['addOnOf'] as int) >= 0 ? json['addOnOf'] as int : null,
      // Pfand & Leergut (wie im JS-Zwilling nur an Pfandzeilen gelesen).
      depositTypeId: pfand && json['depositTypeId'] is String && (json['depositTypeId'] as String).isNotEmpty ? json['depositTypeId'] as String : null,
      depositFor: pfand && json['depositFor'] is int && (json['depositFor'] as int) >= 0 ? json['depositFor'] as int : null,
      depositKind: pfand && (json['depositKind'] == 'single_use' || json['depositKind'] == 'reusable') ? json['depositKind'] as String : null,
      perUnit: pfand && json['perUnit'] is num && (json['perUnit'] as num).isFinite ? json['perUnit'] as num : null,
      gtin: pfand && json['gtin'] is String && (json['gtin'] as String).isNotEmpty ? json['gtin'] as String : null,
      ean: pfand && json['ean'] is String && (json['ean'] as String).isNotEmpty ? json['ean'] as String : null,
      ownFilling: pfand && json['ownFilling'] is bool ? json['ownFilling'] as bool : null,
      codes: pfand ? _leergutCodes(json['codes']) : null,
    );
  }

  bool get isValid => name.isNotEmpty && quantity > 0;

  KasseneckItem get negative {
    return KasseneckItem(
      name: name,
      quantity: quantity,
      vat: vat,
      priceCents: -priceCents,
      // Kennzeichnungen bleiben erhalten — die Storno-Spiegelung trägt sie
      // weiter (wie storno-core im Backend).
      kind: kind,
      recipient: recipient,
      paymentMethod: paymentMethod,
      articleId: articleId,
      receivedImmediately: receivedImmediately,
      keptByEmployee: keptByEmployee,
      lossyRead: lossyRead,
      // Die Spiegelung behaelt die Reihenfolge, der Verweis bleibt gueltig.
      addOnOf: addOnOf,
      depositTypeId: depositTypeId,
      depositFor: depositFor,
      depositKind: depositKind,
      perUnit: perUnit,
      gtin: gtin,
      ean: ean,
      ownFilling: ownFilling,
      codes: codes,
    );
  }
}

/// Gelernte Codes (Code -> ganze Menge ab 1); ohne brauchbaren Eintrag `null`.
/// Zwilling von `leergutCodes` im JS-Paket.
Map<String, int>? _leergutCodes(Object? wert) {
  if (wert is! Map) return null;
  final raus = <String, int>{};
  for (final e in wert.entries) {
    final menge = e.value;
    if (e.key is String && (e.key as String).isNotEmpty && menge is num && menge == menge.truncate() && menge >= 1) {
      raus[e.key as String] = menge.toInt();
    }
  }
  return raus.isEmpty ? null : raus;
}
