class StripeUrlSession {
  final String id;
  final String url;
  final String shortenUrl;
  final DateTime? expiresAt;

  StripeUrlSession({
    required this.id,
    required this.url,
    required this.shortenUrl,
    this.expiresAt,
  });

  factory StripeUrlSession.fromJson(Map<String, dynamic> json) {
    return StripeUrlSession(
      id: json['id'] as String,
      url: json['url'] as String,
      shortenUrl: json['shorten_payment_url'] as String,
      expiresAt: DateTime.parse(json['expires_at'])
    );
  }
}