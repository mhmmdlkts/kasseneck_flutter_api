/// Numeric transaction type as sent in the request body of the
/// `/api/transaction/payment` route.
enum HpsTransactionType {
  /// Normal sale / authorization (purchase).
  sale(1),

  /// Pre-authorization (blocks an amount on the card).
  preAuth(2),

  /// Cancel a former pre-authorization (releases the blocked amount).
  preAuthCancel(7),

  /// Capture a former pre-authorization.
  preAuthCapture(8);

  const HpsTransactionType(this.code);

  /// The integer value expected by the HPS.
  final int code;
}

/// Cardholder Verification Method.
///
/// Payment responses encode this as a number (0–3); the transaction-status (v2)
/// endpoint encodes it as a string (`PIN`, `SIGNATURE`, `NOCVM`, `UNKNOWN`).
/// [fromValue] accepts both.
enum Cvm {
  unknown(0),
  signature(1),
  pin(2),
  noCvm(3);

  const Cvm(this.code);

  final int code;

  /// Parses a CVM from either the numeric or the string form. Returns `null`
  /// when the value is missing or not recognised.
  static Cvm? fromValue(Object? value) {
    if (value == null) return null;
    if (value is num) {
      switch (value.toInt()) {
        case 0:
          return Cvm.unknown;
        case 1:
          return Cvm.signature;
        case 2:
          return Cvm.pin;
        case 3:
          return Cvm.noCvm;
      }
      return null;
    }
    switch (value.toString().toUpperCase().replaceAll(' ', '')) {
      case 'SIGNATURE':
        return Cvm.signature;
      case 'PIN':
        return Cvm.pin;
      case 'NOCVM':
        return Cvm.noCvm;
      case 'UNKNOWN':
        return Cvm.unknown;
    }
    return null;
  }
}
