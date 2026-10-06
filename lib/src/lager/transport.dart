/// Transport der Lager-API: der `api_key` des Kontos als Bearer an
/// `api.kasseneck.at/v3`, Zwilling von `inventoryKeyAuth` + `createTransport`
/// im JS-Paket.
///
/// Wie `InvoiceTransport` **ohne** Kassen-Token: gelesen wird am Konto, nicht
/// an einer Kasse. **Der Schluessel gehoert auf einen Server**, etwa in das
/// Backend eines Online-Shops, nie in eine App, die Kunden installieren.
///
/// **Nichts wird wiederholt.** Lesen hat keine Wirkung und darf nach einem
/// Zeitlimit erneut gerufen werden; bei `rate_limited` vorher
/// `inventoryRetryAfterSec` warten. Ein schreibender Aufruf meldet nach
/// Zeitlimit, Netzfehler, HTTP 5xx oder unlesbarer Antwort Ausgang unklar:
/// dann mit **demselben** `idempotencyKey` erneut senden, nie mit einem
/// neuen.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../register/fehler.dart';
import '../v3.dart';

/// Standardadresse der Lager-API (die oeffentliche Basis).
const String kInventoryBaseUrl = kPublicBaseUrl;

class InventoryTransport {
  /// [baseUrl] muss auf `/v3` enden, sonst wirft schon das Anlegen.
  InventoryTransport({
    required String apiKey,
    String? baseUrl,
    http.Client? httpClient,
    Duration? timeout,
    String? clientHeader,
    bool omitKasseneckHeaders = false,
  })  : _apiKey = apiKey.trim(),
        baseUrl = v3BaseUrl('InventoryTransport', baseUrl, kInventoryBaseUrl),
        _kopf = V3Headers('InventoryTransport', clientHeader: clientHeader, omit: omitKasseneckHeaders),
        _http = httpClient ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 30) {
    // Geprueft wird nur, was ohne Netz sicher falsch ist. Die Meldung nennt die
    // Art des Schluessels, nie seinen Wert.
    if (_apiKey.isEmpty) {
      throw const KasseneckValidationError('InventoryTransport', 'apiKey fehlt', 'request');
    }
    if (RegExp(r'^pk_(live|test)_', caseSensitive: false).hasMatch(_apiKey)) {
      throw const KasseneckValidationError('InventoryTransport',
          'das ist ein Partner-Schluessel (pk_…); die Lager-API nimmt den api_key des Kontos (kr_…)', 'request');
    }
    if (RegExp(r'^cb_(live|test)_', caseSensitive: false).hasMatch(_apiKey)) {
      throw const KasseneckValidationError('InventoryTransport',
          'das ist ein Kassen-Token (cb_…); die Lager-API nimmt den api_key des Kontos (kr_…)', 'request');
    }
  }

  final String _apiKey;
  final String baseUrl;
  final V3Headers _kopf;
  final http.Client _http;
  final Duration _timeout;

  /// Einen Aufruf absetzen; liefert `data` ohne Huelle.
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> params) async {
    // Vor dem Senden: ein nicht serialisierbarer Parameter ist ein
    // Programmierfehler und keine Netzstoerung.
    final rumpf = jsonEncode({'params': params});
    // Ein Probelauf (`previewGoodsReceipt`) bleibt nach einem Zeitlimit
    // `rejected`, jeder Aufruf mit Wirkung `unknown`; entschieden an genau
    // den Parametern, die hinausgehen.
    final probelauf = isDryRun(name, params);
    final antwort = await v3Post(
      _http,
      functionName: name,
      basis: baseUrl,
      name: name,
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_apiKey'},
      kasseneck: _kopf,
      body: rumpf,
      timeout: _timeout,
      dryRun: probelauf,
    );
    final huelle = readEnvelope(name, antwort, dryRun: probelauf);
    if (huelle['status'] == 'success') return envelopeData(name, huelle, antwort.statusCode, dryRun: probelauf);
    throw envelopeError(name, huelle);
  }
}
