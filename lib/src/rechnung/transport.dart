/// Transport der Rechnungs-API: der `api_key` des Kontos als Bearer an
/// `api.kasseneck.at/v3`, Zwilling von `rechnungKeyAuth` + `createTransport`
/// im JS-Paket.
///
/// Anders als [RegisterTransport] **ohne** Kassen-Sitzung: eine Rechnung
/// entsteht am Konto, nicht an einer Kasse. Der Schlüssel gehört deshalb auf
/// einen Server bzw. in ein Gerät, das ihn ohnehin hält.
///
/// **Nichts wird wiederholt.** Wer nach einem Zeitlimit erneut ausstellt, tut
/// das mit **demselben** `idempotencyKey` — dann kommt die schon ausgestellte
/// Rechnung zurück statt einer zweiten.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../register/fehler.dart';
import '../v3.dart';

/// Standardadresse der Rechnungs-API (die oeffentliche Basis).
const String kRechnungBaseUrl = kPublicBaseUrl;

class RechnungTransport {
  RechnungTransport({
    required String apiKey,
    String? baseUrl,
    http.Client? httpClient,
    Duration? timeout,
    String? clientHeader,
    bool omitKasseneckHeaders = false,
  })  : _apiKey = apiKey.trim(),
        baseUrl = v3BaseUrl('RechnungTransport', baseUrl, kRechnungBaseUrl),
        _kopf = V3Headers('RechnungTransport', clientHeader: clientHeader, omit: omitKasseneckHeaders),
        _http = httpClient ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 30) {
    // Geprüft wird nur, was ohne Netz sicher falsch ist. Die Meldung nennt die
    // Art des Schlüssels, nie seinen Wert.
    if (_apiKey.isEmpty) {
      throw const KasseneckValidationError('RechnungTransport', 'apiKey fehlt', 'request');
    }
    if (RegExp(r'^pk_(live|test)_', caseSensitive: false).hasMatch(_apiKey)) {
      throw const KasseneckValidationError('RechnungTransport',
          'das ist ein Partner-Schlüssel (pk_…) — die Rechnungs-API nimmt den api_key des Kontos (kr_…)', 'request');
    }
    if (RegExp(r'^cb_(live|test)_', caseSensitive: false).hasMatch(_apiKey)) {
      throw const KasseneckValidationError('RechnungTransport',
          'das ist ein Kassen-Token (cb_…) — die Rechnungs-API nimmt den api_key des Kontos (kr_…)', 'request');
    }
  }

  final String _apiKey;
  final String baseUrl;
  final V3Headers _kopf;
  final http.Client _http;
  final Duration _timeout;

  /// Einen Aufruf mit JSON-Antwort absetzen; liefert `data` ohne Hülle.
  Future<Map<String, dynamic>> rufen(String name, Map<String, dynamic> params) async {
    final antwort = await _senden(name, params);
    final huelle = readEnvelope(name, antwort);
    if (huelle['status'] == 'success') return envelopeData(name, huelle, antwort.statusCode);
    throw envelopeError(name, huelle);
  }

  /// Einen Aufruf mit Binärantwort (PDF) absetzen. Im Fehlerfall antwortet der
  /// Server mit der gewohnten JSON-Hülle.
  Future<Uint8List> rufenBinaer(String name, Map<String, dynamic> params) async {
    final antwort = await _senden(name, params);
    final bytes = antwort.bodyBytes;
    if (bytes.length >= 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46) {
      return bytes; // %PDF
    }
    final huelle = readEnvelope(name, antwort);
    if (huelle['status'] == 'success') {
      throw KasseneckValidationError(name, 'Antwort ist ein Erfolgsrumpf statt eines PDF', 'response');
    }
    throw envelopeError(name, huelle);
  }

  /// Ueber issueInvoice kann die Rechnung nach einem Zeitlimit laengst
  /// bestehen: mit demselben idempotencyKey wiederholen, nie mit einem neuen.
  Future<http.Response> _senden(String name, Map<String, dynamic> params) {
    // Vor dem Senden: ein nicht serialisierbarer Parameter ist ein
    // Programmierfehler und keine Netzstörung.
    final rumpf = jsonEncode({'params': params});
    return v3Post(
      _http,
      functionName: name,
      basis: baseUrl,
      name: name,
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_apiKey'},
      kasseneck: _kopf,
      body: rumpf,
      timeout: _timeout,
    );
  }
}
