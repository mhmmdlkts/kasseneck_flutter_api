import '../enums/vat_rate.dart';

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
  /// Parameter `tip` erzeugt) oder `'discount'` (Rabatt, [verteileRabatt]).
  /// Steuert nur die Beleg-Darstellung und die Berichts-Zuordnung, nie die
  /// Beträge. Zwilling von `ReceiptItem.kind` im JS-Paket.
  final String? kind;

  /// Empfänger einer Trinkgeld-Position: `{registerUserId, name, owner?}`.
  final Map<String, dynamic>? recipient;

  /// Zahlart der Trinkgeld-Position (kann von der des Belegs abweichen).
  final String? paymentMethod;

  /// Artikel-Verweis (Artikelstamm) — Grundlage der Erlösgruppen-Zuordnung
  /// im Bericht. Optional; Handeingaben haben keinen.
  final String? articleId;

  KasseneckItem({
    required this.name,
    required this.quantity,
    required this.vat,
    required this.priceCents,
    this.kind,
    this.recipient,
    this.paymentMethod,
    this.articleId,
  });

  /// Trinkgeld-Position? Die eine Erkennungsstelle — niemand prüft [kind] selbst.
  bool get isTip => kind == 'tip';

  /// Rabatt-Position? Die eine Erkennungsstelle — niemand prüft [kind] selbst.
  bool get isDiscount => kind == 'discount';

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
      },
      if (kind == 'discount') 'kind': 'discount',
      if (articleId != null && articleId!.isNotEmpty) 'articleId': articleId,
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
    return KasseneckItem(
      name: (json['name'] as String?) ?? '',
      // num statt int: manche Quellen liefern 1.0 statt 1.
      quantity: quantity is num ? quantity.toInt() : 0,
      vat: VatRate.values.firstWhere((e) => e.rate == rate, orElse: () => VatRate.vat0),
      priceCents: cents is num ? cents.round() : (euro is num ? (euro * 100).round() : 0),
      kind: kind == 'tip' || kind == 'discount' ? kind as String : null,
      recipient: json['recipient'] is Map ? Map<String, dynamic>.from(json['recipient'] as Map) : null,
      paymentMethod: json['paymentMethod'] as String?,
      articleId: json['articleId'] is String && (json['articleId'] as String).isNotEmpty ? json['articleId'] as String : null,
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
    );
  }
}
