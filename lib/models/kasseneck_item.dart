import '../enums/vat_rate.dart';

class KasseneckItem {
  /// Name des Artikels / der Dienstleistung
  final String name;

  /// Menge (z. B. 1 Stück, 2 Stück)
  final int amount;

  /// Steuersatz (z. B. 0, 10, 13, 19, 20)
  final VatRate vat;

  /// Einzelpreis
  final double priceOne;

  KasseneckItem({
    required this.name,
    required this.amount,
    required this.vat,
    required this.priceOne,
  });

  factory KasseneckItem.cancel({
    required String name,
    required int amount,
    required VatRate vat,
    required double priceOne,
  }) {
    return KasseneckItem(
      name: name,
      amount: -amount,
      vat: vat,
      priceOne: priceOne,
    );
  }

  /// Umwandlung ins JSON-Format
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'amount': amount,
      'vat': vat.rate,
      'priceOne': priceOne,
    };
  }

  /// Erzeugt ein KasseneckItem aus einem JSON-Objekt
  factory KasseneckItem.fromJson(Map<String, dynamic> json) {
    return KasseneckItem(
      name: json['name'] as String,
      amount: json['amount'] as int,
      vat: VatRate.values.firstWhere((e) => e.rate == json['vat'], orElse: () => VatRate.vat0),
      priceOne: (json['priceOne'] as num).toDouble(),
    );
  }

  bool get isValid => name.isNotEmpty && amount > 0;

  KasseneckItem get negative {
    return KasseneckItem.cancel(
      name: name,
      amount: amount,
      vat: vat,
      priceOne: priceOne,
    );
  }
}