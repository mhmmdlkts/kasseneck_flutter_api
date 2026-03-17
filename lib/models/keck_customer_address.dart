class KeckCustomerAddress {
  String country;
  String city;
  String street;
  String streetNumber;
  String zip;

  KeckCustomerAddress({
    required this.country,
    required this.city,
    required this.street,
    required this.streetNumber,
    required this.zip,
  });

  factory KeckCustomerAddress.fromJson(Map<String, dynamic> json) {
    return KeckCustomerAddress(
      country: json['country'] as String,
      city: json['city'] as String,
      street: json['street'] as String,
      streetNumber: json['street_number'] as String,
      zip: json['zip'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'country': country,
      'city': city,
      'street': street,
      'street_number': streetNumber,
      'zip': zip,
    };
  }

  @override
  String toString() => '$street $streetNumber\n$zip $city-$country';
}