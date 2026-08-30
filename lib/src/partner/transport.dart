/// Der gemeinsame Weg aller Partner-Aufrufe: POST auf
/// `<basis>/<funktionsname>` mit dem Rumpf `{"params": {...}}`, Bearer ist der
/// Partner-Schluessel.
///
/// **Der Schluessel gehoert auf einen Server.** Er kann Betriebe anlegen und --
/// mit `credentials:read` -- deren Geheimnisse holen. In einer ausgelieferten
/// App ist er verteilt, nicht hinterlegt.
///
/// **Keine Kopfzeile `cashregister-token`:** ein Partner arbeitet nie an einer
/// Kasse, sondern ueber Betriebe.
///
/// **Nichts wird wiederholt.** `createPartnerCustomer` legt ohne
/// `idempotencyKey` beim zweiten Versuch einen zweiten Betrieb an; eine
/// eingebaute Wiederholung waere genau der Fehler, den der Schluessel
/// verhindern soll. Die einzige Ausnahme entscheidet der Server, nicht dieses
/// Paket: `activateCashregister` ist Schritt fuer Schritt idempotent und darf
/// von Hand wiederholt werden.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../register/fehler.dart';

/// Basis-Adresse der Partner-API.
const String kPartnerBaseUrl = 'https://api.kasseneck.at/v1';

/// Form eines Partner-Schluessels. Der Rest ist opak -- die Laenge kann sich
/// aendern, das Praefix nicht (an ihm haengt die Umgebung).
final RegExp _schluesselForm = RegExp(r'^pk_(test|live)_[A-Za-z0-9_-]{16,}$');

/// Die Umgebung eines Partner-Schluessels, ohne Netzaufruf -- `null`, wenn es
/// keiner ist. Nuetzlich fuer die Zusicherung "auf diesem Server laeuft nur
/// pk_live_" beim Hochfahren.
String? partnerSchluesselEnv(String schluessel) {
  final treffer = _schluesselForm.firstMatch(schluessel.trim());
  return treffer?.group(1);
}

class PartnerTransport {
  /// Wirft, wenn der Schluessel nicht die Form eines Partner-Schluessels hat.
  ///
  /// Die Pruefung steht hier und nicht erst beim Server: ein vertauschter
  /// `kr_live_`-Schluessel (der eines Betriebs) faellt sonst als
  /// nichtssagendes "ungueltiger Schluessel" auf, obwohl er tadellos ist -- nur
  /// eben fuer einen anderen Weg. Die Meldung nennt nie den Wert.
  PartnerTransport({
    required String partnerKey,
    String? baseUrl,
    http.Client? httpClient,
    Duration? frist,
  })  : _schluessel = partnerKey.trim(),
        baseUrl = (baseUrl ?? kPartnerBaseUrl).replaceAll(RegExp(r'/+$'), ''),
        _http = httpClient ?? http.Client(),
        _frist = frist ?? const Duration(seconds: 30) {
    if (_schluessel.isEmpty) {
      throw const KasseneckValidationError('PartnerTransport', 'partnerKey fehlt', 'request');
    }
    if (partnerSchluesselEnv(_schluessel) == null) {
      throw const KasseneckValidationError(
        'PartnerTransport',
        'partnerKey hat nicht die Form pk_test_... / pk_live_... -- ein Betriebsschluessel (kr_...) passt hier nicht',
        'request',
      );
    }
  }

  final String _schluessel;
  final String baseUrl;
  final http.Client _http;
  final Duration _frist;

  /// `test` oder `live`, aus dem Schluessel abgelesen.
  String get env => partnerSchluesselEnv(_schluessel)!;

  /// Einen Endpunkt rufen. `null`-Werte in [params] fallen weg, damit das
  /// Backend "nicht gesetzt" nicht als ausdrueckliche Angabe missversteht.
  Future<Map<String, dynamic>> rufen(
    String name, {
    Map<String, dynamic> params = const <String, dynamic>{},
  }) async {
    final nutzlast = <String, dynamic>{};
    params.forEach((schluessel, wert) {
      if (wert != null) nutzlast[schluessel] = wert;
    });

    // Ausserhalb des try: ein nicht serialisierbarer Parameter ist ein
    // Programmierfehler und keine Netzstoerung.
    final String rumpf = jsonEncode(<String, dynamic>{'params': nutzlast});

    final http.Response antwort;
    try {
      antwort = await _http
          .post(
            Uri.parse('$baseUrl/$name'),
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_schluessel',
            },
            body: rumpf,
          )
          .timeout(_frist);
    } on TimeoutException catch (e) {
      // Getrennt vom Netzfehler: die Anfrage war draussen, der Ausgang ist
      // unbekannt. Ueber `createPartnerCustomer` kann der Betrieb laengst
      // angelegt sein -- mit `idempotencyKey` ist die Wiederholung dann
      // folgenlos, ohne ihn nicht.
      throw KasseneckHttpError(name, 0, KasseneckHttpError.zeitablauf, causeType: '${e.runtimeType}');
    } on Object catch (e) {
      // Nur der Typ, nie die Meldung: die kann eine Adresse tragen. Der
      // Schluessel faehrt in der Kopfzeile und ist davon nicht betroffen.
      throw KasseneckHttpError(name, 0, KasseneckHttpError.netz, causeType: '${e.runtimeType}');
    }

    Object? roh;
    try {
      roh = jsonDecode(antwort.body);
    } on FormatException {
      // Typischer Fall: der Aufruf landete mangels Weiterleitung auf der
      // HTML-Seite -- HTTP 200, aber kein JSON.
      throw KasseneckHttpError(name, antwort.statusCode, 'not-json');
    }
    if (roh is! Map) throw KasseneckHttpError(name, antwort.statusCode, 'missing-status');
    final huelle = Map<String, dynamic>.from(roh);
    if (huelle['status'] == 'success') {
      final daten = huelle['data'];
      if (daten == null) return <String, dynamic>{};
      if (daten is! Map) throw KasseneckHttpError(name, antwort.statusCode, 'data-not-object');
      return Map<String, dynamic>.from(daten);
    }
    final meldung = huelle['message'];
    // Die Beilage wird gesiebt und nicht durchgereicht -- flach, klein,
    // bezeichner-foermig benannt, und kein Wert, der mit dem gesendeten
    // Schluessel ueberlappt (siehe fehlerDetails).
    final details = fehlerDetails(huelle['data'], <String>[_schluessel]);
    final code = details['code'];
    throw KasseneckApiError(
      name,
      meldung is String && meldung.isNotEmpty ? meldung : 'Der Aufruf ist fehlgeschlagen.',
      code: code is String && RegExp(r'^[A-Za-z][A-Za-z0-9_./-]{0,63}$').hasMatch(code) ? code : null,
      details: details,
    );
  }
}
