import '../enums/vat_rate.dart';

class KasseneckItem {
  /// Name des Artikels / der Dienstleistung
  final String name;

  /// Menge (z. B. 1 Stück, 2 Stück)
  final int quantity;

  /// Steuersatz (z. B. 0, 10, 13, 19, 20)
  final VatRate vat;

  /// Einzelpreis
  final double singlePrice;

  KasseneckItem({
    required this.name,
    required this.quantity,
    required this.vat,
    required this.singlePrice,
  });

  factory KasseneckItem.cancel({
    required String name,
    required int amount,
    required VatRate vat,
    required double priceOne,
  }) {
    return KasseneckItem(
      name: name,
      quantity: amount,
      vat: vat,
      singlePrice: -priceOne,
    );
  }

  /// Umwandlung ins JSON-Format
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'amount': quantity,
      'vat': vat.rate,
      'priceOne': singlePrice,
    };
  }

  /// Erzeugt ein KasseneckItem aus einem JSON-Objekt
  factory KasseneckItem.fromJson(Map<String, dynamic> json) {
    return KasseneckItem(
      name: json['name'] as String,
      quantity: json['amount'] as int,
      vat: VatRate.values.firstWhere((e) => e.rate == json['vat'], orElse: () => VatRate.vat0),
      singlePrice: (json['priceOne'] as num).toDouble(),
    );
  }

  bool get isValid => name.isNotEmpty && quantity > 0;

  KasseneckItem get negative {
    return KasseneckItem.cancel(
      name: name,
      amount: quantity,
      vat: vat,
      priceOne: singlePrice,
    );
  }
}