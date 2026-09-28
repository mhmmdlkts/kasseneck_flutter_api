/// Registrierdaten fuer den Block „Prüfangaben“ am Nullbeleg (Regelwerk 2):
/// wann die Signaturkarte und wann die Kasse bei FinanzOnline registriert
/// wurden. Zwilling von `RegistrationInfo` in `@kreiseck/kasseneck-api` 1.0,
/// Drahtfeld `registrationInfo` (frueher `pruefangaben`).
class RegistrationInfo {
  const RegistrationInfo({this.cardRegisteredAt, this.cashregisterRegisteredAt});

  /// Zeitpunkt wie vom Server geliefert (ISO); `null`, wenn unbekannt.
  final String? cardRegisteredAt;
  final String? cashregisterRegisteredAt;

  /// Liest den Drahtwert; alles ausser einem Objekt ergibt `null`. Leere oder
  /// fremd getippte Zeitpunkte werden `null`, wie im npm-Zwilling.
  static RegistrationInfo? fromJson(Object? raw) {
    if (raw is! Map) return null;
    String? zeit(Object? v) => v is String && v.isNotEmpty ? v : null;
    return RegistrationInfo(
      cardRegisteredAt: zeit(raw['cardRegisteredAt']),
      cashregisterRegisteredAt: zeit(raw['cashregisterRegisteredAt']),
    );
  }

  Map<String, String?> toJson() => {
        'cardRegisteredAt': cardRegisteredAt,
        'cashregisterRegisteredAt': cashregisterRegisteredAt,
      };

  @override
  bool operator ==(Object other) =>
      other is RegistrationInfo &&
      other.cardRegisteredAt == cardRegisteredAt &&
      other.cashregisterRegisteredAt == cashregisterRegisteredAt;

  @override
  int get hashCode => Object.hash(cardRegisteredAt, cashregisterRegisteredAt);
}

/// Bezug eines Storno-Belegs auf sein Original (`cancellationOf`).
class CancellationOf {
  const CancellationOf({required this.receiptId, this.fullReceiptId, this.timeStamp});

  final String receiptId;
  final String? fullReceiptId;

  /// Zeitstempel des Originals (Server-Format, Wiener Wanduhr); fehlt bei
  /// Altbelegen.
  final String? timeStamp;

  /// `null`, wenn [raw] kein Bezug mit Kennung ist.
  static CancellationOf? fromJson(Object? raw) {
    if (raw is! Map || raw['receiptId'] is! String) return null;
    final voll = raw['fullReceiptId'];
    final zeit = raw['timeStamp'];
    return CancellationOf(
      receiptId: raw['receiptId'] as String,
      fullReceiptId: voll is String ? voll : null,
      timeStamp: zeit is String && zeit.isNotEmpty ? zeit : null,
    );
  }

  Map<String, String?> toJson() => {
        'receiptId': receiptId,
        'fullReceiptId': fullReceiptId,
        'timeStamp': ?timeStamp,
      };
}
