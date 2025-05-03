import 'package:kasseneck_api/enums/cashbox_status.dart';

class Cashregister {
  String userId;

  String id;

  DateTime createTime;
  String token;
  String aesKey;
  String? signatureId;

  CashboxStatus? status;

  Cashregister({
    required this.userId,
    required this.id,
    required this.createTime,
    required this.token,
    required this.aesKey,
    this.signatureId,
    this.status
  });

  factory Cashregister.fromJson(Map<String, dynamic> json, String id, String userId) {
    return Cashregister(
      userId: userId,
      id: id,
      createTime: json['create_time']?.toDate(),
      token: json['token'] as String,
      aesKey: json['aes_key'] as String,
      signatureId: json['signature_id'] as String?,
    );
  }
}