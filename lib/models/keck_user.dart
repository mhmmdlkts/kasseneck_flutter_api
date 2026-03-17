class KeckUser {

  String userId;
  String email;
  String companyName;
  String phone;
  DateTime createTime;

  int cashregisterCount;
  int signatureCount;

  bool isSmallBusiness;
  String taxnr;
  bool isProduction;

  String? apiKey;
  String? uid;
  String? gln;

  String? benid;
  String? pin;
  String? tid;

  String addressCity;
  String addressStreet;
  String addressZip;

  String footer1;
  String footer2;
  String? footer3;
  String? footer4;

  String? logoUrl;
  String? thanksMessage;


  KeckUser({
    required this.userId,
    required this.email,
    required this.companyName,
    required this.phone,
    required this.createTime,
    required this.cashregisterCount,
    required this.signatureCount,
    required this.isSmallBusiness,
    required this.taxnr,
    required this.isProduction,
    required this.addressCity,
    required this.addressStreet,
    required this.addressZip,
    required this.footer1,
    required this.footer2,
    this.footer3,
    this.footer4,
    this.logoUrl,
    this.thanksMessage,
    this.apiKey,
    this.uid,
    this.gln,
    this.benid,
    this.pin,
    this.tid
  });

  factory KeckUser.fromJson(Map<String, dynamic> json, String userId) {
    return KeckUser(
      userId: userId,
      email: json['email'] as String,
      companyName: json['company_name'] as String,
      phone: json['phone'] as String,
      createTime: json['create_time'].toDate(),
      cashregisterCount: json['metadata']['cashregister_count'] as int,
      signatureCount: json['metadata']['signature_count'] as int,
      isSmallBusiness: json['tax_details']['is_small_business'] as bool,
      taxnr: json['tax_details']['taxnr'] as String,
      isProduction: json['production'] == true,
      apiKey: json['api_key'] as String?,
      uid: json['tax_details']['uid'] as String?,
      gln: json['tax_details']['gln'] as String?,
      benid: json['webservice_user']['benid'] as String?,
      tid: json['webservice_user']['tid'] as String?,
      pin: json['webservice_user']['pin'] as String?,
      addressCity: json['address']['city'] as String,
      addressStreet: json['address']['street'] as String,
      addressZip: json['address']['zip'] as String,
      footer1: json['footer']['footer1'] as String,
      footer2: json['footer']['footer2'] as String,
      footer3: json['footer']['footer3'] as String?,
      footer4: json['footer']['footer4'] as String?,
      logoUrl: json['logo_url'] as String?,
      thanksMessage: json['thanks_message'] as String?,
    );
  }

  Map<String, dynamic> receiptMetadata() => {
    'uid': uid,
    'taxnr': taxnr,
    'is_small_business': isSmallBusiness,
    'company': companyName,
    'phone': phone,
    'street': addressStreet,
    'zip': addressZip,
    'city': addressCity,
    'footer1': footer1,
    'footer2': footer2,
    'footer3': footer3,
    'footer4': footer4,
    'logo_url': logoUrl,
    'thanks_message': thanksMessage,
  };
}