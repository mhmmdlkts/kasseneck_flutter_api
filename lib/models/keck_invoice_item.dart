import '../enums/vat_rate.dart';

class KeckInvoiceItem {
  /// Name des Artikels / der Dienstleistung
  String name;

  /// Menge (z. B. 1 Stück, 2 Stück)
  int quantity;

  /// Einheit der Menge (z. B. "Stück", "Liter", "kg")
  String quantityUnit;

  /// Steuersatz (z. B. 0, 10, 13, 19, 20)
  VatRate vat;

  /// Einzelpreis
  double singlePrice;

  KeckInvoiceItem({
    required this.name,
    required this.quantity,
    required this.quantityUnit,
    required this.vat,
    required this.singlePrice,
  });

  /// Umwandlung ins JSON-Format
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'quantity': quantity,
      'vatRate': vat.rate,
      'singlePrice': singlePrice,
      'quantityUnit': quantityUnit,
    };
  }

  /// Erzeugt ein KasseneckItem aus einem JSON-Objekt
  factory KeckInvoiceItem.fromJson(Map<String, dynamic> json) {
    return KeckInvoiceItem(
      name: json['name'] as String,
      quantityUnit: json['quantityUnit'] as String,
      quantity: json['quantity'] as int,
      vat: VatRate.values.firstWhere((e) => e.rate == json['vatRate'], orElse: () => VatRate.vat0),
      singlePrice: (json['singlePrice'] as num).toDouble(),
    );
  }

  bool get isValid => name.isNotEmpty && quantity > 0;
}