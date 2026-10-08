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
/// `inventoryRetryAfterSec` warten. Jeder Aufruf mit Wirkung meldet nach
/// Zeitlimit, Netzfehler, HTTP 5xx oder unlesbarer Antwort Ausgang unklar.
/// Lager schreiben und Reservierungen tragen einen `idempotencyKey`: dann mit
/// **demselben** Schluessel erneut senden, nie mit einem neuen. Die
/// Webhook-Aufrufe haben keinen Schluessel: erst nachlesen (`listWebhooks`,
/// bei der Probesendung `listWebhookDeliveries`), nicht erneut senden.
library;

import 'dart:convert';
import 'dart:typed_data';

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
    // Ein Probelauf (`previewGoodsReceipt`) bleibt nach einem Zeitlimit
    // `rejected`, jeder Aufruf mit Wirkung `unknown`; entschieden an genau
    // den Parametern, die hinausgehen.
    final probelauf = isDryRun(name, params);
    final antwort = await _senden(name, params, probelauf);
    final huelle = readEnvelope(name, antwort, dryRun: probelauf);
    if (huelle['status'] == 'success') return envelopeData(name, huelle, antwort.statusCode, dryRun: probelauf);
    throw envelopeError(name, huelle);
  }

  /// Einen Aufruf absetzen, der eine Datei **oder** eine Nutzlast liefert
  /// (Inventurprotokoll `getStocktakePdf`: die Datei bis 9 MiB, darueber ein
  /// Lese-Link). Zwilling von `createPdfOrDataTransport` im JS-Paket, wie
  /// `InvoiceTransport.callBinary` als Methode des Transports.
  ///
  /// Die ersten Bytes entscheiden: `%PDF` ergibt [PdfOrDataFile], eine
  /// Erfolgshuelle [PdfOrDataPayload] mit ihrer `data`, eine Fehlerhuelle
  /// denselben fachlichen Fehler wie [call]. Leer, kein JSON oder ohne
  /// Statusfeld ist unlesbar mit denselben Gruenden wie dort.
  Future<PdfOrData> callPdfOrData(String name, Map<String, dynamic> params) async {
    final probelauf = isDryRun(name, params);
    final antwort = await _senden(name, params, probelauf);
    final bytes = antwort.bodyBytes;
    if (bytes.length >= 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46) {
      return PdfOrDataFile(bytes); // %PDF
    }
    final huelle = readEnvelope(name, antwort, dryRun: probelauf);
    if (huelle['status'] == 'success') {
      return PdfOrDataPayload(envelopeData(name, huelle, antwort.statusCode, dryRun: probelauf));
    }
    throw envelopeError(name, huelle);
  }

  Future<http.Response> _senden(String name, Map<String, dynamic> params, bool probelauf) {
    // Vor dem Senden: ein nicht serialisierbarer Parameter ist ein
    // Programmierfehler und keine Netzstoerung.
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
      dryRun: probelauf,
    );
  }
}

/// Ergebnis von [InventoryTransport.callPdfOrData]: die Datei als Bytes oder
/// die `data` einer Erfolgshuelle (etwa ein Lese-Link, wenn die Datei zu gross
/// fuer die Antwort ist). Zwilling von `PdfOrData` im JS-Paket.
sealed class PdfOrData {
  const PdfOrData();
}

/// Die Antwort war eine Datei (`%PDF`).
final class PdfOrDataFile extends PdfOrData {
  const PdfOrDataFile(this.pdf);

  final Uint8List pdf;
}

/// Die Antwort war eine Erfolgshuelle; [data] ohne Huelle.
final class PdfOrDataPayload extends PdfOrData {
  const PdfOrDataPayload(this.data);

  final Map<String, dynamic> data;
}
