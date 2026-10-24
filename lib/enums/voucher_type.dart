/// Gutscheinart. Zwilling von `VoucherType` im npm-Paket; am Draht steht
/// [wire] (`multi_purpose` …), in Dart heisst der Wert in Dart-Schreibweise.
///
/// [value] und [promo] sind die Altform (Wert in Cent, Code frei). Die vier
/// Arten der neuen Form fuehrt der Server mit Saldo, Gueltigkeit und Satz;
/// eine Kasse prueft sie vorher mit `checkVoucher`.
enum VoucherType {
  /// Altform: Wertgutschein.
  value('value'),

  /// Altform: Rabatt-/Aktionsgutschein.
  promo('promo'),

  /// Neue Form: Mehrzweckgutschein (Zahlungsmittel, Steuer erst bei der Einloesung).
  multiPurpose('multi_purpose'),

  /// Neue Form: Einzweckgutschein (Steuer schon beim Verkauf, ein Satz).
  singlePurpose('single_purpose'),

  /// Neue Form: Leistungsgutschein (Artikel mal Menge).
  service('service'),

  /// Neue Form: Aktionsgutschein (Rabatt laut Aktion, nur einloesbar).
  promotion('promotion');

  const VoucherType(this.wire);

  /// Der Wert am Draht (`/v3`).
  final String wire;

  /// Eine der vier Arten der neuen Form?
  bool get isNewForm => this != value && this != promo;

  /// Die Art zum Drahtwert; `null` fuer einen unbekannten Wert.
  static VoucherType? fromWire(Object? wire) {
    for (final t in values) {
      if (t.wire == wire) return t;
    }
    return null;
  }
}
