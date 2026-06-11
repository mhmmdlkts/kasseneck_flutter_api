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

  KasseneckItem({
    required this.name,
    required this.quantity,
    required this.vat,
    required this.priceCents,
  });

  /// Komfort-Konstruktor mit Einzelpreis in **Euro**.
  ///
  /// Der Betrag wird genau einmal — hier, an der API-Grenze — auf Cent
  /// gerundet; danach wird ausschliesslich exakt in Cent gerechnet.
  factory KasseneckItem.euro({
    required String name,
    required int quantity,
    required VatRate vat,
    required double singlePrice,
  }) {
    return KasseneckItem(
      name: name,
      quantity: quantity,
      vat: vat,
      priceCents: (singlePrice * 100).round(),
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

  /// Umwandlung ins JSON-Format (Wire-Format unveraendert: Euro).
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'amount': quantity,
      'vat': vat.rate,
      'priceOne': priceCents / 100,
    };
  }

  /// Erzeugt ein KasseneckItem aus einem JSON-Objekt (Euro -> Cent, einmalige Rundung)
  factory KasseneckItem.fromJson(Map<String, dynamic> json) {
    return KasseneckItem(
      name: json['name'] as String,
      quantity: json['amount'] as int,
      vat: VatRate.values.firstWhere((e) => e.rate == json['vat'], orElse: () => VatRate.vat0),
      priceCents: ((json['priceOne'] as num) * 100).round(),
    );
  }

  bool get isValid => name.isNotEmpty && quantity > 0;

  KasseneckItem get negative {
    return KasseneckItem.cancel(
      name: name,
      amount: quantity,
      vat: vat,
      priceCents: priceCents,
    );
  }
}
