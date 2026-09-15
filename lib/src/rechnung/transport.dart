/// Transport der Rechnungs-API: der `api_key` des Kontos als Bearer an
/// `api.kasseneck.at/v1` — Zwilling von `rechnungKeyAuth` + `createTransport`
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

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../register/fehler.dart';
import '../register/transport.dart' show ohneSchraegstrich;

/// Standardadresse der Rechnungs-API.
const String kRechnungBaseUrl = 'https://api.kasseneck.at/v1';

class RechnungTransport {
  RechnungTransport({
    required String apiKey,
    String? baseUrl,
    http.Client? httpClient,
    Duration? timeout,
  })  : _apiKey = apiKey.trim(),
        baseUrl = ohneSchraegstrich(baseUrl ?? kRechnungBaseUrl),
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
  final http.Client _http;
  final Duration _timeout;

  /// Einen Aufruf mit JSON-Antwort absetzen; liefert `data` ohne Hülle.
  Future<Map<String, dynamic>> rufen(String name, Map<String, dynamic> params) async {
    final antwort = await _senden(name, params);
    final huelle = _huelleAus(name, antwort);
    if (huelle['status'] == 'success') {
      final daten = huelle['data'];
      if (daten == null) return <String, dynamic>{};
      if (daten is! Map) throw KasseneckHttpError(name, antwort.statusCode, 'data-not-object');
      return Map<String, dynamic>.from(daten);
    }
    throw _fachfehler(name, huelle);
  }

  /// Einen Aufruf mit Binärantwort (PDF) absetzen. Im Fehlerfall antwortet der
  /// Server mit der gewohnten JSON-Hülle.
  Future<Uint8List> rufenBinaer(String name, Map<String, dynamic> params) async {
    final antwort = await _senden(name, params);
    final bytes = antwort.bodyBytes;
    if (bytes.length >= 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46) {
      return bytes; // %PDF
    }
    final huelle = _huelleAus(name, antwort);
    if (huelle['status'] == 'success') {
      throw KasseneckValidationError(name, 'Antwort ist ein Erfolgsrumpf statt eines PDF', 'response');
    }
    throw _fachfehler(name, huelle);
  }

  Future<http.Response> _senden(String name, Map<String, dynamic> params) async {
    // Ausserhalb des try: ein nicht serialisierbarer Parameter ist ein
    // Programmierfehler und keine Netzstörung.
    final rumpf = jsonEncode({'params': params});
    try {
      return await _http
          .post(
            Uri.parse('$baseUrl/$name'),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_apiKey'},
            body: rumpf,
          )
          .timeout(_timeout);
    } on TimeoutException catch (e) {
      // Die Anfrage war draussen — über issueInvoice kann die Rechnung längst
      // bestehen. Mit demselben idempotencyKey wiederholen, nie mit einem neuen.
      throw KasseneckHttpError(name, 0, KasseneckHttpError.zeitablauf, causeType: '${e.runtimeType}');
    } on Object catch (e) {
      throw KasseneckHttpError(name, 0, KasseneckHttpError.netz, causeType: '${e.runtimeType}');
    }
  }

  Map<String, dynamic> _huelleAus(String name, http.Response antwort) {
    Object? roh;
    try {
      roh = jsonDecode(utf8.decode(antwort.bodyBytes));
    } on FormatException {
      throw KasseneckHttpError(name, antwort.statusCode, 'not-json');
    }
    if (roh is! Map || !roh.containsKey('status')) {
      throw KasseneckHttpError(name, antwort.statusCode, 'missing-status');
    }
    return Map<String, dynamic>.from(roh);
  }

  KasseneckApiError _fachfehler(String name, Map<String, dynamic> huelle) {
    final meldung = huelle['message'];
    final daten = huelle['data'];
    return KasseneckApiError(
      name,
      meldung is String && meldung.isNotEmpty ? meldung : 'Der Aufruf ist fehlgeschlagen.',
      code: fehlercodeAus(huelle) ?? (daten is Map && daten['code'] is String ? daten['code'] as String : null),
      details: daten is Map ? Map<String, dynamic>.from(daten) : const {},
    );
  }
}
