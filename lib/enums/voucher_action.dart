/// Gutschein-Aktion. Zwilling von `VoucherAction` im npm-Paket; der Name ist
/// zugleich der Drahtwert.
enum VoucherAction {
  sell,
  redeem,

  /// Neue Form: Restwert bar auszahlen (Mehrzweck/Einzweck, mit Grund).
  payout,
}
