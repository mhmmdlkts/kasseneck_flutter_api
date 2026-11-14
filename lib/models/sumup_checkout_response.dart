/// Ergebnis einer SumUp-Kartenzahlung, wie es an der Zahlung des Belegs
/// (`providerData`) gespeichert und auf Bon und Vorschau gezeigt wird.
///
/// Reines Datenmodell: Das SumUp-Plugin bindet die App selbst ein und
/// übersetzt dessen Antwort mit dem Konstruktor hierher.
class SumupCheckoutResponse {
  final bool success;
  final String? transactionCode;
  final double? amount;
  final String? currency;
  final double? vatAmount;
  final double? tipAmount;
  final String? paymentType;
  final String? entryMode;
  final int? installments;
  final String? cardType;
  final String? cardLastDigits;

  /// Eigene Kennung der Zahlung (SumUp `foreignTransactionId`), mit der sie
  /// sich bei SumUp wiederfinden lässt; nur gesetzt, wenn die Kasse eine
  /// mitgab.
  final String? foreignTransactionId;

  /// Händlernummer des SumUp-Kontos, auf das gebucht wurde.
  final String? merchantCode;

  SumupCheckoutResponse({
    required this.success,
    this.transactionCode,
    this.amount,
    this.currency,
    this.vatAmount,
    this.tipAmount,
    this.paymentType,
    this.entryMode,
    this.installments,
    this.cardType,
    this.cardLastDigits,
    this.foreignTransactionId,
    this.merchantCode,
  });

  /// Liest jede Form, die das Plugin oder ein gespeicherter Beleg liefert:
  /// Zahlen als Zahl oder Zeichenkette, leere Zeichenketten als `null`
  /// (iOS meldet fehlende Felder als `""`). Wirft nie; fehlt `success`, gilt
  /// kein Erfolg.
  factory SumupCheckoutResponse.fromMap(Map<String, dynamic> response) {
    String? text(String k) {
      final v = response[k];
      if (v == null) return null;
      final s = v.toString();
      return s.isEmpty ? null : s;
    }

    double? zahl(String k) {
      final v = response[k];
      if (v is num) return v.toDouble();
      if (v is String && v.trim().isNotEmpty) return double.tryParse(v.trim());
      return null;
    }

    return SumupCheckoutResponse(
      success: response['success'] == true,
      transactionCode: text('transactionCode'),
      amount: zahl('amount'),
      currency: text('currency'),
      vatAmount: zahl('vatAmount'),
      tipAmount: zahl('tipAmount'),
      paymentType: text('paymentType'),
      entryMode: text('entryMode'),
      installments: int.tryParse(response['installments']?.toString() ?? ''),
      cardType: text('cardType'),
      cardLastDigits: text('cardLastDigits'),
      foreignTransactionId: text('foreignTransactionId'),
      merchantCode: text('merchantCode'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'transactionCode': transactionCode,
      'amount': amount,
      'currency': currency,
      'vatAmount': vatAmount,
      'tipAmount': tipAmount,
      'paymentType': paymentType,
      'entryMode': entryMode,
      'installments': installments?.toString(),
      'cardType': cardType,
      'cardLastDigits': cardLastDigits,
      'foreignTransactionId': ?foreignTransactionId,
      'merchantCode': ?merchantCode,
    };
  }
}