import '../enums/vat_rate.dart';

class KeckInvoiceItem {
  /// Name des Artikels / der Dienstleistung
  String name;

  /// Menge (z. B. 1 Stück, 2 Stück)
  int quantity;

  /// Einheit der Menge (z. B. "Stück", "Liter", "kg")
  String quantityUnit;

  /// Steuersatz (z. B. 0, 4.9, 10, 13, 19, 20)
  VatRate vat;

  /// Einzelpreis in **Cent** (z. B. 1999 = 19,99 EUR).
  ///
  /// Geld wird intern exakt in Integer-Cent gerechnet. Das JSON-Format
  /// Richtung Backend bleibt unveraendert in Euro (siehe [toJson]).
  int priceCents;

  KeckInvoiceItem({
    required this.name,
    required this.quantity,
    required this.quantityUnit,
    required this.vat,
    required this.priceCents,
  });

  /// Komfort-Konstruktor mit Einzelpreis in **Euro** (einmalige Rundung auf Cent).
  factory KeckInvoiceItem.euro({
    required String name,
    required int quantity,
    required String quantityUnit,
    required VatRate vat,
    required double singlePrice,
  }) {
    return KeckInvoiceItem(
      name: name,
      quantity: quantity,
      quantityUnit: quantityUnit,
      vat: vat,
      priceCents: (singlePrice * 100).round(),
    );
  }

  /// Einzelpreis in Euro (Anzeige/Format — fuer Arithmetik [priceCents] nutzen).
  double get singlePrice => priceCents / 100;

  /// Zeilensumme in Cent (exakt, ohne Gleitkomma).
  int get totalCents => priceCents * quantity;

  /// Umwandlung ins JSON-Format. Sendet BEIDE Felder: `singlePrice` (Euro,
  /// altes Backend) + `singlePriceCents` (neu, exakt).
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'quantity': quantity,
      'vatRate': vat.rate,
      'singlePrice': priceCents / 100,
      'singlePriceCents': priceCents,
      'quantityUnit': quantityUnit,
    };
  }

  /// `singlePriceCents` wird bevorzugt (exakt); Fallback: Euro mit einmaliger Rundung.
  factory KeckInvoiceItem.fromJson(Map<String, dynamic> json) {
    final cents = json['singlePriceCents'];
    return KeckInvoiceItem(
      name: json['name'] as String,
      quantityUnit: json['quantityUnit'] as String,
      quantity: json['quantity'] as int,
      vat: VatRate.values.firstWhere((e) => e.rate == json['vatRate'], orElse: () => VatRate.vat0),
      priceCents: cents is num ? cents.round() : ((json['singlePrice'] as num) * 100).round(),
    );
  }

  bool get isValid => name.isNotEmpty && quantity > 0;
}
