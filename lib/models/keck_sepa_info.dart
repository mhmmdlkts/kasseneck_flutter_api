class KeckSepaInfo {
  final String debtorAddress;
  final String debtorBic;
  final String debtorIban;
  final String debtorCountry;
  final String debtorName;
  final String mandateId;
  final String mandateDate;

  KeckSepaInfo({
    required this.debtorAddress,
    required this.debtorBic,
    required this.debtorIban,
    required this.debtorCountry,
    required this.debtorName,
    required this.mandateId,
    required this.mandateDate,
  });

  factory KeckSepaInfo.fromJson(Map<String, dynamic> json) {
    return KeckSepaInfo(
      debtorAddress: json['debtor_address'] as String,
      debtorBic: json['debtor_bic'] as String,
      debtorIban: json['debtor_iban'] as String,
      debtorCountry: json['debtor_country'] as String,
      debtorName: json['debtor_name'] as String,
      mandateId: json['mandate_id'] as String,
      mandateDate: json['mandate_date'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'debtor_address': debtorAddress,
      'debtor_bic': debtorBic,
      'debtor_iban': debtorIban,
      'debtor_country': debtorCountry,
      'debtor_name': debtorName,
      'mandate_id': mandateId,
      'mandate_date': mandateDate,
    };
  }
}