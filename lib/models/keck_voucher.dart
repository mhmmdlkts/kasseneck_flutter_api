import 'package:kasseneck_api/enums/voucher_action.dart';
import 'package:kasseneck_api/enums/voucher_type.dart';

class KeckVoucher {

  final String? name;
  final String? code;
  final VoucherAction action;
  final VoucherType type;

  /// Gutscheinwert in **Cent** (z. B. 500 = 5,00 EUR).
  ///
  /// Geld wird intern exakt in Integer-Cent gerechnet. Das JSON-Format
  /// Richtung Backend bleibt unveraendert in Euro (siehe [toJson]).
  int? valueCents;

  KeckVoucher({
    this.name,
    this.code,
    required this.action,
    required this.type,
    required this.valueCents,
  });

  /// Komfort-Konstruktor mit Wert in **Euro** (einmalige Rundung auf Cent).
  factory KeckVoucher.euro({
    String? name,
    String? code,
    required VoucherAction action,
    required VoucherType type,
    required double value,
  }) {
    return KeckVoucher(
      name: name,
      code: code,
      action: action,
      type: type,
      valueCents: (value * 100).round(),
    );
  }

  /// Wert in Euro (Anzeige/Format — fuer Arithmetik [valueCents] nutzen).
  double? get value => valueCents == null ? null : valueCents! / 100;

  /// `valueCents` wird bevorzugt (exakt); Fallback: Euro mit einmaliger Rundung.
  factory KeckVoucher.fromJson(Map<String, dynamic> json) {
    final cents = json['valueCents'];
    return KeckVoucher(
      name: json['name'] as String?,
      code: json['code'] as String?,
      action: VoucherAction.values.firstWhere((e) => e.name == json['action'], orElse: () => VoucherAction.sell),
      type: VoucherType.values.firstWhere((e) => e.name == json['type'], orElse: () => VoucherType.promo),
      valueCents: cents is num
          ? cents.round()
          : (json['value'] == null ? null : ((json['value'] as num) * 100).round()),
    );
  }

  /// Sendet BEIDE Felder: `value` (Euro, altes Backend) + `valueCents` (neu, exakt).
  Map <String, dynamic> toJson() {
    return {
      'name': name,
      'code': code,
      'action': action.name,
      'type': type.name,
      'value': valueCents == null ? null : valueCents! / 100,
      'valueCents': valueCents,
    };
  }

  bool get isValid {
    if (type == VoucherType.value && valueCents == null) {
      return false;
    }
    if (type == VoucherType.promo && action != VoucherAction.redeem) {
      return false;
    }
    if (type == VoucherType.promo && valueCents == null) {
      return false;
    }
    if (valueCents != null && valueCents! <= 0) {
      return false;
    }
    return true;
  }

  String get receiptText {
    String text = '';
    if (type == VoucherType.value) {
      text += 'Wertgutschein';
    } else if (type == VoucherType.promo) {
      text += 'Promotionsgutschein';
    }

    if (name?.toLowerCase().contains(text.toLowerCase())??false) {
      return name!;
    }
    if (value != null) {
      text += ' ${formatVoucherAmount(value!)} EUR';
    }
    if (name != null && name!.isNotEmpty) {
      text += ' - $name';
    }
    return text;
  }



  /// Ganze Betraege kurz ("10"), krumme exakt mit 2 Nachkommastellen ("1,50") —
  /// frueher wurde gerundet ("~2"), was auf dem Beleg wie ein falscher Betrag wirkte.
  String formatVoucherAmount(num value) {
    if (value % 1 != 0) {
      return value.toStringAsFixed(2).replaceAll('.', ',');
    }
    return value.toStringAsFixed(0);
  }
}
