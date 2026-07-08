import 'dart:convert';
import 'dart:io';

/// Demo-Zugangsdaten für die Integrationstests. Liegen NUR lokal in
/// test/integration/credentials.local.json (gitignored) — Vorlage siehe
/// credentials.local.json.example.
class DemoCredentials {
  final String apiKey;
  final String cashregisterToken;

  DemoCredentials({required this.apiKey, required this.cashregisterToken});

  /// null, wenn die Datei fehlt → Tests werden übersprungen.
  static DemoCredentials? tryLoad() {
    final file = File('test/integration/credentials.local.json');
    if (!file.existsSync()) return null;
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return DemoCredentials(
        apiKey: json['apiKey'] as String,
        cashregisterToken: json['cashregisterToken'] as String,
      );
    } catch (e) {
      throw FormatException(
        'test/integration/credentials.local.json ist fehlerhaft '
        '(erwartet: {"apiKey": "...", "cashregisterToken": "..."}): $e',
      );
    }
  }
}
