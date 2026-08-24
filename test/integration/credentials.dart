import 'dart:convert';
import 'dart:io';

/// Demo-Zugangsdaten für die Integrationstests. Liegen NUR lokal in
/// test/integration/credentials.local.json (gitignored) — Vorlage siehe
/// credentials.local.json.example.
class DemoCredentials {
  final String apiKey;
  final String cashregisterToken;

  /// Optional: ein Kassen-Benutzer der Demo-Kasse. Ist er gesetzt, prueft der
  /// Trinkgeld-Test auch die Zuordnung zum Empfaenger; sonst laeuft er nur
  /// gegen „nicht zugeordnet". Ohne Anmeldung als Kassen-Benutzer (der Weg
  /// ueber den API-Schluessel) gibt es sonst niemanden, dem etwas zusteht.
  final String? registerUserId;

  DemoCredentials({
    required this.apiKey,
    required this.cashregisterToken,
    this.registerUserId,
  });

  /// null, wenn die Datei fehlt → Tests werden übersprungen.
  static DemoCredentials? tryLoad() {
    final file = File('test/integration/credentials.local.json');
    if (!file.existsSync()) return null;
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return DemoCredentials(
        apiKey: json['apiKey'] as String,
        cashregisterToken: json['cashregisterToken'] as String,
        registerUserId: json['registerUserId'] as String?,
      );
    } catch (e) {
      throw FormatException(
        'test/integration/credentials.local.json ist fehlerhaft '
        '(erwartet: {"apiKey": "...", "cashregisterToken": "..."}): $e',
      );
    }
  }
}
