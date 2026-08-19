/// Der gemeinsame Weg aller Aufrufe der **laufenden** Sitzung — der Zwilling
/// von `registerUserAuth` + `createTransport` im JS-Paket.
///
/// Anders als Kopplung und Anmeldung haben diese Aufrufe eine Identität: das
/// Firebase-ID-Token als Bearer, die laufende Sitzung als Kopfzeile
/// `register-session`, die Kasse als Parameter. Welche Sitzung gemeint ist,
/// steht also im Ausweis und nicht in der Nutzlast.
///
/// **Token und Sitzung werden bei jedem Aufruf frisch erfragt.** ID-Tokens
/// laufen nach einer Stunde ab, die Kassen-Sitzung lebt sogar nur 90 Sekunden;
/// ein einmal gemerkter Wert wäre bald tot.
///
/// **Nichts wird wiederholt.** Es gibt hier bewusst keine Wiederholung nach
/// Netzfehlern: ein Beleg ist nicht folgenlos wiederholbar, und ein zweiter
/// Versuch wäre ein zweiter Umsatz, den nur noch ein Storno aufhebt. Wer für
/// einen unschädlichen Aufruf eine Wiederholung will, baut sie über sich, nicht
/// hier drin.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'fehler.dart';

/// Basis-Adresse der Kassen-Aufrufe.
///
/// **Nicht** `api.kasseneck.at/v1` — das ist die api_key-Schnittstelle für
/// Kassengeräte. Die Kassen-Aufrufe liegen hinter den Hosting-Umschreibungen
/// der Browser-Kasse; die App spricht dieselbe Adresse an wie sie.
const String kRegisterBaseUrl = 'https://kasse.kasseneck.at/api';

String ohneSchraegstrich(String url) => url.replaceAll(RegExp(r'/+$'), '');

class RegisterTransport {
  RegisterTransport({
    required this.idToken,
    required this.sessionId,
    required this.cashregisterId,
    String? baseUrl,
    http.Client? httpClient,
    Duration? timeout,
  })  : baseUrl = ohneSchraegstrich(baseUrl ?? kRegisterBaseUrl),
        _http = httpClient ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 30);

  /// Liefert ein gültiges Firebase-ID-Token (darf erneuern).
  final Future<String?> Function() idToken;

  /// Liefert die laufende Sitzung.
  final Future<String?> Function() sessionId;

  /// Kasse, an der die Sitzung läuft.
  final String cashregisterId;

  final String baseUrl;
  final http.Client _http;
  final Duration _timeout;

  /// Einen Endpunkt rufen. [params] kommt zur Kasse dazu; `null`-Werte fallen
  /// weg, damit das Backend „nicht gesetzt" nicht als ausdrückliche Angabe
  /// missversteht.
  ///
  /// [frist] überschreibt die Vorgabe für diesen einen Aufruf — der Abschluss
  /// eines Belegs darf länger warten als eine Belegliste.
  Future<Map<String, dynamic>> rufen(
    String name, {
    Map<String, dynamic> params = const {},
    Duration? frist,
  }) async {
    // Beides frisch — siehe Klassenkommentar.
    final token = await idToken();
    final sitzung = await sessionId();
    if (token == null || token.isEmpty) {
      throw KasseneckValidationError(name, 'idToken lieferte kein Token', 'request');
    }
    if (sitzung == null || sitzung.isEmpty) {
      throw KasseneckValidationError(name, 'sessionId lieferte keine Sitzung', 'request');
    }

    final nutzlast = <String, dynamic>{'cashregisterId': cashregisterId};
    params.forEach((schluessel, wert) {
      if (wert != null) nutzlast[schluessel] = wert;
    });

    final http.Response antwort;
    try {
      antwort = await _http
          .post(
            Uri.parse('$baseUrl/$name'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
              'register-session': sitzung,
            },
            body: jsonEncode({'params': nutzlast}),
          )
          .timeout(frist ?? _timeout);
    } on Object {
      throw KasseneckHttpError(name, 0, 'network');
    }

    Object? roh;
    try {
      roh = jsonDecode(antwort.body);
    } on FormatException {
      throw KasseneckHttpError(name, antwort.statusCode, 'not-json');
    }
    if (roh is! Map) throw KasseneckHttpError(name, antwort.statusCode, 'missing-status');
    final huelle = Map<String, dynamic>.from(roh);
    if (huelle['status'] == 'success') {
      final daten = huelle['data'];
      return daten is Map ? Map<String, dynamic>.from(daten) : <String, dynamic>{};
    }
    final meldung = huelle['message'];
    throw KasseneckApiError(name, meldung is String && meldung.isNotEmpty ? meldung : 'Der Aufruf ist fehlgeschlagen.');
  }
}
