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

import '../v3.dart';
import 'fehler.dart';

/// Basis-Adresse der Kassen-Aufrufe (Kassenweg, Kanal `app`).
///
/// **Nicht** die oeffentliche Basis: die Kassen-Aufrufe liegen hinter den
/// Hosting-Umschreibungen der Browser-Kasse; die App spricht dieselbe Adresse
/// an wie sie. Alle 25 Aufrufe des Kassenwegs laufen mit der Kassen-Anmeldung
/// hierhin.
const String kRegisterBaseUrl = kPosBaseUrl;

String ohneSchraegstrich(String url) => url.replaceAll(RegExp(r'/+$'), '');

class RegisterTransport {
  /// [baseUrl] muss auf `/v3` enden (die Web-Kasse: `/api/v3`), sonst wirft
  /// schon das Anlegen. [clientHeader] nennt die App in der Zaehlung des
  /// Backends (`kasse-app/<version+build>`), Vorgabe `kasseneck_api/<version>`.
  /// [omitKasseneckHeaders] laesst die beiden Kasseneck-Kopfzeilen weg; die
  /// Pruefung der Antwort bleibt.
  ///
  /// [httpClient] darf kein `RetryClient` (oder anderer wiederholender
  /// Client) sein: ein zweites stilles Senden waere ein zweiter Beleg.
  RegisterTransport({
    required this.idToken,
    required this.sessionId,
    required this.cashregisterId,
    String? baseUrl,
    http.Client? httpClient,
    Duration? timeout,
    String? clientHeader,
    bool omitKasseneckHeaders = false,
  })  : baseUrl = v3BaseUrl('RegisterTransport', baseUrl, kRegisterBaseUrl),
        _kopf = V3Headers('RegisterTransport', clientHeader: clientHeader, omit: omitKasseneckHeaders),
        _http = httpClient ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 30);

  /// Liefert ein gültiges Firebase-ID-Token (darf erneuern).
  final Future<String?> Function() idToken;

  /// Liefert die laufende Sitzung.
  final Future<String?> Function() sessionId;

  /// Kasse, an der die Sitzung läuft.
  final String cashregisterId;

  final String baseUrl;
  final V3Headers _kopf;
  final http.Client _http;
  final Duration _timeout;

  /// Einen Endpunkt rufen. [params] kommt zur Kasse dazu; `null`-Werte fallen
  /// weg, damit das Backend „nicht gesetzt" nicht als ausdrückliche Angabe
  /// missversteht.
  ///
  /// [frist] überschreibt die Vorgabe für diesen einen Aufruf — der Abschluss
  /// eines Belegs darf länger warten als eine Belegliste.
  ///
  /// Fehler tragen `outcome`: bei [ErrorOutcome.unknown] nie wiederholen,
  /// sondern nachlesen (siehe `v3Post`).
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

    // Ausserhalb des Sendens: ein nicht serialisierbarer Parameter ist ein
    // Programmierfehler und keine Netzstoerung. Sonst haette ihn der
    // Sammelfang als `network` gemeldet — ein Fehler, der nie am Netz lag,
    // saehe aus wie einer, nach dem ein Beleg entstanden sein koennte.
    final String rumpf = jsonEncode({'params': nutzlast});

    // Zeitlimit getrennt vom Netzfehler: die Anfrage war draussen, ueber
    // `createReceipt` kann der Beleg laengst signiert sein. Nur der Typ der
    // Ursache, nie die Meldung: die kann eine Adresse tragen.
    final antwort = await v3Post(
      _http,
      functionName: name,
      basis: baseUrl,
      name: name,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        'register-session': sitzung,
      },
      kasseneck: _kopf,
      body: rumpf,
      timeout: frist ?? _timeout,
    );

    final huelle = readEnvelope(name, antwort);
    if (huelle['status'] == 'success') {
      // Fehlendes `data` ist erlaubt — nicht jeder Aufruf hat eine Nutzlast.
      // Ein `data`, das da ist und **kein Objekt** ist (Array, Zahl, Text), ist
      // dagegen kaputt und darf nicht als leeres Objekt durchgehen: aus dem
      // wurde weiter oben ein voller Standardsatz Einstellungen, und der
      // Bildschirm meldete „der Betrieb hat nichts eingestellt". Dieselbe
      // Grenze wie bei den Listen: leer ist etwas anderes als kaputt.
      return envelopeData(name, huelle, antwort.statusCode);
    }
    throw envelopeError(name, huelle);
  }
}
