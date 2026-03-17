import 'package:kasseneck_api/enums/voucher_action.dart';
import 'package:kasseneck_api/enums/voucher_type.dart';

class KeckVoucher {

  final String? name;
  final String? code;
  final VoucherAction action;
  final VoucherType type;
  final double? value;

  KeckVoucher({
    this.name,
    this.code,
    required this.action,
    required this.type,
    this.value
  });

  factory KeckVoucher.fromJson(Map<String, dynamic> json) {
    return KeckVoucher(
      name: json['name'] as String?,
      code: json['code'] as String?,
      action: VoucherAction.values.firstWhere((e) => e.name == json['action'], orElse: () => VoucherAction.sell),
      type: VoucherType.values.firstWhere((e) => e.name == json['type'], orElse: () => VoucherType.promo),
      value: (json['value'] as num?)?.toDouble(),
    );
  }

  Map <String, dynamic> toJson() {
    return {
      'name': name,
      'code': code,
      'action': action.name,
      'type': type.name,
      'value': value,
    };
  }

  bool get isValid {
    if (type == VoucherType.value && value == null) {
      return false;
    }
    if (type == VoucherType.promo && action != VoucherAction.redeem) {
      return false;
    }
    if (type == VoucherType.promo && value == null) {
      return false;
    }
    if (value != null && value! <= 0) {
      return false;
    }
    return true;
  }

  String get receipText {
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



  String formatVoucherAmount(num value) {
    if (value.ceil() != value) {
      return '~${value.toStringAsFixed(0).replaceAll('.', ',')}';
    }
    return value.toStringAsFixed(0).replaceAll('.', ',');
  }
}