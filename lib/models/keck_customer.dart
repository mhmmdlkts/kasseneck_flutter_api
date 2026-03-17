import 'package:kasseneck_api/models/keck_customer_address.dart';
import 'package:kasseneck_api/models/keck_sepa_info.dart';

class KeckCustomer {
  final String id;
  final String name;
  final String? email;
  final String? phoneNumber;
  final KeckCustomerAddress address;
  final KeckSepaInfo? sepaInfo;
  final String? vatNumber;

  KeckCustomer({
    required this.id,
    required this.name,
    required this.email,
    required this.phoneNumber,
    required this.address,
    this.sepaInfo,
    this.vatNumber,
  });

  factory KeckCustomer.fromJson(Map<String, dynamic> json) {
    return KeckCustomer(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      phoneNumber: json['phone_number'] as String,
      vatNumber: json['vat_number'] as String?,
      sepaInfo: json['sepa_info'] != null
          ? KeckSepaInfo.fromJson(json['sepa_info'] as Map<String, dynamic>)
          : null,
      address: KeckCustomerAddress.fromJson(json['address'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone_number': phoneNumber,
      'address': address.toJson(),
      'sepa_info': sepaInfo?.toJson(),
    };
  }
}