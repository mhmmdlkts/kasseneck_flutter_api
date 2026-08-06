/// A terminal entry returned by `GET /api/terminals`.
///
/// The REST specification's field table and its example response disagree on
/// the exact set of fields, so every field here is optional. Anything not
/// modelled explicitly stays available via [raw].
class TerminalInfo {
  const TerminalInfo({
    required this.raw,
    this.tid,
    this.password,
    this.company,
    this.merchantName,
    this.header,
    this.elv,
    this.creditCard,
    this.refNumberRequired,
    this.active,
    this.vu,
    this.terminalType,
    this.street,
    this.zip,
    this.city,
    this.phone,
    this.fax,
    this.email,
  });

  /// Terminal identifier.
  final String? tid;

  /// Terminal password.
  final String? password;

  /// Company name.
  final String? company;

  /// Merchant name.
  final String? merchantName;

  /// Receipt header lines — one string per printed line.
  final List<String>? header;

  /// Whether the terminal supports ELV.
  final bool? elv;

  /// Whether the terminal accepts credit cards.
  final bool? creditCard;

  /// Whether a reference is required for a transaction.
  final bool? refNumberRequired;

  /// Whether the terminal is active.
  final bool? active;

  /// Merchant id (Vertragsunternehmen).
  final String? vu;

  /// Terminal type: `PINPAD`, `POS`, `MPOS`, `VIRTUALTERMINAL` or `PAYMENTLINK`.
  final String? terminalType;

  final String? street;
  final String? zip;
  final String? city;
  final String? phone;
  final String? fax;
  final String? email;

  /// The raw decoded JSON, for fields not modelled explicitly.
  final Map<String, dynamic> raw;

  factory TerminalInfo.fromJson(Map<String, dynamic> json) {
    List<String>? header;
    final rawHeader = json['header'];
    if (rawHeader is List) {
      header = rawHeader.map((Object? e) => e.toString()).toList();
    }
    return TerminalInfo(
      raw: json,
      tid: json['tid'] as String?,
      password: json['password'] as String?,
      company: json['company'] as String?,
      merchantName: json['merchantName'] as String?,
      header: header,
      elv: json['elv'] as bool?,
      creditCard: json['creditCard'] as bool?,
      refNumberRequired: json['refNumberRequired'] as bool?,
      active: json['active'] as bool?,
      vu: json['vu'] as String?,
      terminalType: json['terminalType'] as String?,
      street: json['street'] as String?,
      zip: json['zip'] as String?,
      city: json['city'] as String?,
      phone: json['phone'] as String?,
      fax: json['fax'] as String?,
      email: json['email'] as String?,
    );
  }

  @override
  String toString() =>
      'TerminalInfo(tid: $tid, merchant: $merchantName, '
      'type: $terminalType, active: $active)';
}
