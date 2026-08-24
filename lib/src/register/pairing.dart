import 'dart:convert';

import 'package:http/http.dart' as http;

import '../kasse/einstellungen.dart';
import 'fehler.dart';
import 'transport.dart';

export 'fehler.dart';
export 'transport.dart' show RegisterTransport, kRegisterBaseUrl;

/// Kopplung und Anmeldung eines Kassengeräts — der Zwilling von
/// `register/pairing.ts` im JS-Paket `@kreiseck/kasseneck-api`.
///
/// Diese Aufrufe laufen **ohne jede Identität**: vor ihnen gibt es weder
/// ID-Token noch Sitzung noch `api_key`. Der Kopplungs-Code bzw. das
/// Gerätegeheimnis ist der Nachweis. Deshalb stehen sie bewusst neben
/// `KasseneckApi` (die braucht einen `api_key`) und nicht darin — es soll im
/// Paket keinen Weg geben, einen anmeldungsfreien Client für *alle* Aufrufe zu
/// bekommen.
///
/// Der Ablauf einer Kasse:
///
/// 1. Im Panel wird ein Gerät angelegt → achtstelliger Code (15 Minuten gültig,
///    einmal verwendbar).
/// 2. [RegisterClient.pairRegisterDevice] tauscht ihn gegen den dauerhaften
///    Ausweis des Geräts (`ownerUid`, `deviceId`, `deviceSecret`). Das
///    Geheimnis liefert das Backend genau **einmal** aus — es gehört in den
///    sicheren Speicher des Systems (Keychain/Keystore), nicht in einfache
///    Einstellungen.
/// 3. [RegisterClient.listRegisterUsersForDevice] liefert die Benutzer, die
///    PIN-Regel und den Anmeldemodus für den Anmeldebildschirm.
/// 4. [RegisterClient.registerUserLogin] bzw. [RegisterClient.registerPinLogin]
///    eröffnet die Sitzung: Custom Token (→ Firebase → ID-Token) plus
///    `sessionId`.

/// Was das Gerät über sich sagt — fürs Panel („welches Gerät ist das?").
class RegisterClientInfo {
  const RegisterClientInfo({this.userAgent, this.platform, this.language, this.tz, this.screen});

  final String? userAgent;
  final String? platform;
  final String? language;

  /// IANA-Zeitzone, z. B. `Europe/Vienna`.
  final String? tz;
  final ({int w, int h})? screen;

  Map<String, dynamic> toJson() => {
        if (userAgent != null) 'userAgent': userAgent,
        if (platform != null) 'platform': platform,
        if (language != null) 'language': language,
        if (tz != null) 'tz': tz,
        if (screen != null) 'screen': {'w': screen!.w, 'h': screen!.h},
      };
}

/// Standort (freiwillig); Grundlage der Standortsperre.
class RegisterGeo {
  const RegisterGeo({required this.lat, required this.lng, this.acc});

  final double lat;
  final double lng;

  /// Genauigkeit in Metern.
  final double? acc;

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, if (acc != null) 'acc': acc};
}

/// Ergebnis der Kopplung — der vollständige Ausweis dieses Geräts.
class PairedRegisterDevice {
  const PairedRegisterDevice({
    required this.ownerUid,
    required this.deviceId,
    required this.deviceSecret,
    required this.cashregisterId,
    required this.companyName,
    required this.cashregisterLabel,
    this.testUmgebung = false,
  });

  /// Kunde, unter dem das Gerät hängt.
  final String ownerUid;
  final String deviceId;

  /// Geheimnis dieses Geräts; das Backend liefert es genau einmal aus.
  final String deviceSecret;

  /// Kasse, an die die Kopplung dieses Gerät gebunden hat.
  final String cashregisterId;

  /// Das Gerät hängt an einer Test-Umgebung. Die Kasse muss es zeigen: ein
  /// Beleg von dort ist kein gültiger Beleg, und wer das nicht sieht, hält
  /// ihn für einen.
  final bool testUmgebung;

  /// Firmenname des Betriebs — Anzeige, kann leer sein.
  final String companyName;

  /// Bezeichnung der Kasse — Anzeige, kann leer sein.
  final String cashregisterLabel;
}

/// Art eines Kassen-Benutzers. Ein künftiger, hier unbekannter Wert gilt als
/// [person] — beim Lesen ist dieses Paket tolerant.
enum RegisterUserKind { person, device }

/// Ein Kassen-Benutzer, wie ihn der Anmeldebildschirm zeigt.
class RegisterUserSummary {
  const RegisterUserSummary({
    required this.id,
    required this.name,
    required this.kind,
    required this.altbestand,
  });

  final String id;

  /// Anzeigename; kann leer sein.
  final String name;
  final RegisterUserKind kind;

  /// Die PIN wurde noch nicht unter der aktuellen Regel gesetzt: die Kasse
  /// zeigt das Freifeld statt der Kästchen.
  final bool altbestand;
}

/// PIN-Regel des Betriebs — daraus baut die Kasse Kästchen und Tastatur.
class RegisterPinPolicy {
  const RegisterPinPolicy({required this.stellen, required this.zeichen});

  /// Feste Stellenzahl (Backend: 3 bis 6).
  final int stellen;

  /// `ziffern` (nur 0–9) oder `zeichen` (0–9 plus Kopplungs-Alphabet).
  final String zeichen;
}

/// Anmeldemodus des Geräts; ein unbekannter künftiger Wert gilt als [auswahl].
enum RegisterLoginMode { auswahl, pin }

/// Antwort von [RegisterClient.listRegisterUsersForDevice].
class RegisterDeviceUsers {
  const RegisterDeviceUsers({
    required this.users,
    required this.policy,
    required this.loginMode,
    required this.standortsperre,
    this.testUmgebung = false,
    required this.settings,
    required this.betriebsdaten,
  });

  /// Im Modus [RegisterLoginMode.pin] bewusst leer — Namen haben am nur-PIN-Gerät nichts verloren.
  final List<RegisterUserSummary> users;

  /// `null`, wenn das Backend (noch) keine brauchbare Regel nennt — dann zeigt
  /// die Kasse das Freifeld statt Kästchen mit erratener Stellenzahl.
  final RegisterPinPolicy? policy;
  final RegisterLoginMode loginMode;

  /// Der Betrieb verlangt die Ortung beim Login.
  final bool standortsperre;

  /// Das Gerät hängt an einer Test-Umgebung — siehe [PairedRegisterDevice].
  final bool testUmgebung;

  /// Kassen-Einstellungen (betriebsweit + Gerät), mit den Standardwerten
  /// gemischt — die Kasse bekommt nie ein halbes Bild.
  final KasseSettings settings;

  /// Belegkopf des Betriebs als Rohdaten (Name, Anschrift, UID, Fußzeilen).
  final Map<String, dynamic>? betriebsdaten;
}

/// Reichweite eines Rechts.
enum RegisterScope { none, own, all }

/// Rechte eines Kassen-Benutzers.
///
/// **Ein fehlendes Recht gilt als nicht erteilt** — die Oberfläche soll im
/// Zweifel weniger anbieten; die tatsächliche Grenze zieht ohnehin das Backend.
/// [cancelScope] und [receiptsScope] sind **keine** Schalter: wer sie als
/// Ja/Nein liest, nimmt jedem Kassier die eigenen Belege und dem Chef das
/// Stornieren.
class RegisterUserPerms {
  const RegisterUserPerms({
    this.sell = false,
    this.cancel = false,
    this.articles = false,
    this.layout = false,
    this.reports = false,
    this.takeover = false,
    this.drawer = false,
    this.discount = false,
    this.tipAssign = false,
    this.cancelScope = RegisterScope.none,
    this.receiptsScope = RegisterScope.all,
    this.weitere = const {},
  });

  /// Belege ausstellen.
  final bool sell;

  /// Stornieren (Schalter; die Reichweite steht in [cancelScope]).
  final bool cancel;

  /// Artikelstamm bearbeiten.
  final bool articles;

  /// Beleglayout/Kassen-Einstellungen bearbeiten (Chef).
  final bool layout;

  /// Berichte ansehen.
  final bool reports;

  /// Eine belegte Kasse übernehmen (nur Kassen-Chef).
  final bool takeover;

  /// Kassenlade ohne Verkauf öffnen.
  final bool drawer;

  /// Rabatt geben.
  final bool discount;

  /// Trinkgeld anderen zuweisen.
  final bool tipAssign;

  /// Storno-Reichweite; fehlt sie (Altbestand), entscheidet [cancel].
  final RegisterScope cancelScope;

  /// Beleg-Reichweite; fehlt sie (Altbestand), gilt `all`.
  final RegisterScope receiptsScope;

  /// Weitere Schalter, die der Inhaber gesetzt hat und die dieses Paket noch
  /// nicht kennt.
  final Map<String, bool> weitere;

  /// Ein Recht nachschlagen, auch ein hier noch unbekanntes.
  bool operator [](String name) {
    switch (name) {
      case 'sell':
        return sell;
      case 'cancel':
        return cancel;
      case 'articles':
        return articles;
      case 'layout':
        return layout;
      case 'reports':
        return reports;
      case 'takeover':
        return takeover;
      case 'drawer':
        return drawer;
      case 'discount':
        return discount;
      case 'tipAssign':
        return tipAssign;
      default:
        return weitere[name] ?? false;
    }
  }
}

/// Der angemeldete Kassen-Benutzer.
class RegisterUser {
  const RegisterUser({required this.id, required this.name, required this.perms});

  final String id;
  final String name;
  final RegisterUserPerms perms;
}

/// Ergebnis der Anmeldung.
class RegisterUserSession {
  const RegisterUserSession({
    required this.customToken,
    required this.sessionId,
    required this.expiresAt,
    required this.user,
  });

  /// Firebase-Custom-Token: damit meldet sich die App bei Firebase an und
  /// bekommt das ID-Token für alle weiteren Aufrufe. Dieses Paket kennt
  /// Firebase nicht.
  final String customToken;

  /// Laufende Sitzung — Kopfzeile `register-session` jedes weiteren Aufrufs.
  final String sessionId;

  /// Ablauf in Millisekunden seit 1970. Die Sitzung lebt 90 Sekunden und will
  /// alle 30 Sekunden erneuert werden.
  final int expiresAt;

  final RegisterUser user;
}

/// Die anmeldungsfreien Aufrufe rund um Kopplung und Anmeldung.
class RegisterClient {
  RegisterClient({String? baseUrl, http.Client? httpClient, Duration? timeout})
      : _baseUrl = ohneSchraegstrich(baseUrl ?? kRegisterBaseUrl),
        _http = httpClient ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 30);

  final String _baseUrl;
  final http.Client _http;
  final Duration _timeout;

  /// Gerät koppeln: der Code wird gegen den dauerhaften Ausweis getauscht.
  ///
  /// Der Code wird dabei verbraucht, auch wenn der Aufrufer das Ergebnis
  /// verliert — eine unvollständige Antwort ist deshalb ein Fehler und kein
  /// halbes Gerät. Groß-/Kleinschreibung und Leerzeichen sind gleichgültig:
  /// das Backend beschneidet selbst; dieses Paket prüft das Format **nicht**
  /// (es kennt das Alphabet nicht und würde eine Erweiterung ausschließen).
  /// [takeover] gilt nur für dauerhafte Kopplungs-Codes: die tragen immer nur
  /// **ein** Gerät. Ist schon eines gekoppelt, antwortet das Backend
  /// abweisend; erst mit `takeover: true` wird das andere Gerät entkoppelt.
  Future<PairedRegisterDevice> pairRegisterDevice({
    required String code,
    String? label,
    RegisterClientInfo? client,
    RegisterGeo? geo,
    bool takeover = false,
  }) async {
    const name = 'pairRegisterDevice';
    _pflicht(name, 'code', code);
    final daten = await _rufen(name, {
      'code': code,
      if (takeover) 'takeover': true,
      if (label != null) 'label': label,
      if (client != null) 'client': client.toJson(),
      if (geo != null) 'geo': geo.toJson(),
    });
    return PairedRegisterDevice(
      deviceId: _pflichtfeld(name, daten, 'deviceId'),
      deviceSecret: _pflichtfeld(name, daten, 'deviceSecret'),
      ownerUid: _pflichtfeld(name, daten, 'ownerUid'),
      cashregisterId: _pflichtfeld(name, daten, 'cashregisterId'),
      companyName: _text(daten['betrieb']),
      cashregisterLabel: _text(daten['kasse']),
      testUmgebung: daten['testUmgebung'] == true,
    );
  }

  /// Kassen-Benutzer dieses Betriebs auflisten — die Auswahl des
  /// Anmeldebildschirms. Die Antwort trägt nur Kennung, Name und Art: keine
  /// Rechte, keine Hashes; gesperrte Benutzer fehlen bereits.
  Future<RegisterDeviceUsers> listRegisterUsersForDevice({
    required String ownerUid,
    required String deviceId,
    required String deviceSecret,
  }) async {
    const name = 'listRegisterUsersForDevice';
    _ausweisPflicht(name, ownerUid, deviceId, deviceSecret);
    final daten = await _rufen(name, {
      'ownerUid': ownerUid,
      'deviceId': deviceId,
      'deviceSecret': deviceSecret,
    });

    final liste = daten['users'];
    if (liste is! List) {
      throw const KasseneckValidationError(
          'listRegisterUsersForDevice', 'Antwort enthaelt keine Benutzerliste (data.users fehlt)', 'response');
    }
    final users = liste.map((eintrag) {
      final roh = eintrag is Map ? Map<String, dynamic>.from(eintrag) : <String, dynamic>{};
      return RegisterUserSummary(
        // Ein Eintrag ohne Kennung ist nicht anmeldbar — ihn anzuzeigen hieße,
        // dem Kassier eine Schaltfläche zu geben, die nichts tun kann.
        id: _pflichtfeld(name, roh, 'id'),
        name: _text(roh['name']),
        kind: roh['kind'] == 'device' ? RegisterUserKind.device : RegisterUserKind.person,
        altbestand: roh['altbestand'] == true,
      );
    }).toList();

    final settings = daten['settings'];
    final betriebsdaten = daten['betriebsdaten'];
    return RegisterDeviceUsers(
      users: users,
      policy: _regel(daten['policy']),
      loginMode: daten['loginMode'] == 'pin' ? RegisterLoginMode.pin : RegisterLoginMode.auswahl,
      standortsperre: daten['standortsperre'] == true,
      testUmgebung: daten['testUmgebung'] == true,
      settings: KasseSettings.aus(settings is Map ? Map<String, dynamic>.from(settings) : null),
      betriebsdaten: betriebsdaten is Map ? Map<String, dynamic>.from(betriebsdaten) : null,
    );
  }

  /// „Gerät entkoppeln" an der Kasse selbst: das Gerät sperrt sich im Backend,
  /// damit das Panel den Widerruf sieht und keine Sitzung nachläuft.
  /// Idempotent — danach das Gerät lokal vergessen.
  Future<void> unpairRegisterDevice({
    required String ownerUid,
    required String deviceId,
    required String deviceSecret,
  }) async {
    const name = 'unpairRegisterDevice';
    _ausweisPflicht(name, ownerUid, deviceId, deviceSecret);
    await _rufen(name, {'ownerUid': ownerUid, 'deviceId': deviceId, 'deviceSecret': deviceSecret});
  }

  /// Kassen-Benutzer per PIN anmelden.
  ///
  /// Das Backend prüft in dieser Reihenfolge: Gerät, Benutzer, Sperre, PIN,
  /// Kassenzuweisung, Kopplungsbindung, Lizenzplatz. Fehlversuche zählen und
  /// sperren gestaffelt. Das PIN-Format prüft dieses Paket **nicht** — eine zu
  /// strenge Prüfung im Client sperrte Benutzer aus, deren PIN das Panel anders
  /// gesetzt hat.
  Future<RegisterUserSession> registerUserLogin({
    required String ownerUid,
    required String deviceId,
    required String deviceSecret,
    required String userId,
    required String pin,
    required String cashregisterId,
    bool takeover = false,
    RegisterClientInfo? client,
    RegisterGeo? geo,
  }) async {
    const name = 'registerUserLogin';
    _ausweisPflicht(name, ownerUid, deviceId, deviceSecret);
    _pflicht(name, 'userId', userId);
    _pflicht(name, 'pin', pin);
    _pflicht(name, 'cashregisterId', cashregisterId);
    final daten = await _rufen(name, {
      'ownerUid': ownerUid,
      'deviceId': deviceId,
      'deviceSecret': deviceSecret,
      'userId': userId,
      'pin': pin,
      'cashregisterId': cashregisterId,
      // Nur die ausdrückliche Übernahme geht mit: das Backend prüft auf `true`,
      // ein mitgesendetes `false` wäre nur Rauschen.
      if (takeover) 'takeover': true,
      if (client != null) 'client': client.toJson(),
      if (geo != null) 'geo': geo.toJson(),
    });
    return _sitzung(name, daten);
  }

  /// Anmeldung allein mit der PIN (Geräte-Modus `pin`): das Backend ermittelt
  /// den Benutzer über die betriebsweit eindeutige PIN. Fehlversuche sperren
  /// dort am **Gerät**, nicht an einem Benutzer.
  Future<RegisterUserSession> registerPinLogin({
    required String ownerUid,
    required String deviceId,
    required String deviceSecret,
    required String pin,
    required String cashregisterId,
    bool takeover = false,
    RegisterClientInfo? client,
    RegisterGeo? geo,
  }) async {
    const name = 'registerPinLogin';
    _ausweisPflicht(name, ownerUid, deviceId, deviceSecret);
    _pflicht(name, 'pin', pin);
    _pflicht(name, 'cashregisterId', cashregisterId);
    final daten = await _rufen(name, {
      'ownerUid': ownerUid,
      'deviceId': deviceId,
      'deviceSecret': deviceSecret,
      'pin': pin,
      'cashregisterId': cashregisterId,
      if (takeover) 'takeover': true,
      if (client != null) 'client': client.toJson(),
      if (geo != null) 'geo': geo.toJson(),
    });
    return _sitzung(name, daten);
  }

  /// Der Client für die **laufende** Sitzung — mit derselben Adresse, demselben
  /// HTTP-Client und demselben Zeitlimit wie dieser. So hängt die Kasse an
  /// einer Verbindung statt an zweien, und wer für Tests einen anderen
  /// HTTP-Client einsetzt, erwischt beide Wege.
  RegisterSessionClient sitzung({
    required Future<String?> Function() idToken,
    required Future<String?> Function() sessionId,
    required String cashregisterId,
  }) {
    return RegisterSessionClient(
      idToken: idToken,
      sessionId: sessionId,
      cashregisterId: cashregisterId,
      baseUrl: _baseUrl,
      httpClient: _http,
      timeout: _timeout,
    );
  }

  /// Ein Aufruf ohne jede Anmeldung: nur `{params: …}` im Rumpf.
  Future<Map<String, dynamic>> _rufen(String name, Map<String, dynamic> params) async {
    final http.Response antwort;
    try {
      antwort = await _http
          .post(
            Uri.parse('$_baseUrl/$name'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'params': params}),
          )
          .timeout(_timeout);
    } on Object {
      // Die Ursache kann Werte des Rumpfs tragen (manche Clients hängen ihn an)
      // — hier fährt weder PIN noch Gerätegeheimnis mit.
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
    // Alles, was nicht ausdrücklich Erfolg ist, gilt als fachlicher Fehler —
    // ein unbekannter Statuswert darf nie stillschweigend durchgehen.
    final meldung = huelle['message'];
    throw KasseneckApiError(name, meldung is String && meldung.isNotEmpty ? meldung : 'Der Aufruf ist fehlgeschlagen.');
  }

  /// Die Sitzungsantwort beider Anmeldewege — ein Vertrag, eine Lesart.
  RegisterUserSession _sitzung(String name, Map<String, dynamic> daten) {
    final roherBenutzer = daten['user'];
    if (roherBenutzer is! Map) {
      throw KasseneckValidationError(name, 'Antwort enthaelt keinen Benutzer (data.user fehlt)', 'response');
    }
    final benutzer = Map<String, dynamic>.from(roherBenutzer);
    final expiresAt = daten['expiresAt'];
    if (expiresAt is! int) {
      throw KasseneckValidationError(name, 'Antwort enthaelt keinen Ablaufzeitpunkt (data.expiresAt fehlt)', 'response');
    }
    return RegisterUserSession(
      customToken: _pflichtfeld(name, daten, 'customToken'),
      sessionId: _pflichtfeld(name, daten, 'sessionId'),
      expiresAt: expiresAt,
      user: RegisterUser(
        id: _pflichtfeld(name, benutzer, 'id'),
        name: _text(benutzer['name']),
        perms: _rechte(benutzer['perms']),
      ),
    );
  }
}

/// Rechte lesen: Schalter werden zu Wahrheitswerten, Reichweiten bleiben
/// Reichweiten, alles Fehlende gilt als nicht erteilt.
RegisterUserPerms _rechte(Object? wert) {
  final roh = wert is Map ? Map<String, dynamic>.from(wert) : <String, dynamic>{};
  final bekannt = {
    'sell', 'cancel', 'articles', 'layout', 'reports', 'takeover',
    'drawer', 'discount', 'tipAssign', 'cancelScope', 'receiptsScope',
  };
  final weitere = <String, bool>{};
  for (final eintrag in roh.entries) {
    if (!bekannt.contains(eintrag.key)) weitere[eintrag.key] = eintrag.value == true;
  }
  final cancel = roh['cancel'] == true;
  return RegisterUserPerms(
    sell: roh['sell'] == true,
    cancel: cancel,
    articles: roh['articles'] == true,
    layout: roh['layout'] == true,
    reports: roh['reports'] == true,
    takeover: roh['takeover'] == true,
    drawer: roh['drawer'] == true,
    discount: roh['discount'] == true,
    tipAssign: roh['tipAssign'] == true,
    // Altbestand ohne Reichweite: der Schalter entscheidet (so migriert es auch
    // das Backend, register-auth.js).
    cancelScope: roh.containsKey('cancelScope') ? _scope(roh['cancelScope']) : (cancel ? RegisterScope.all : RegisterScope.none),
    receiptsScope: roh.containsKey('receiptsScope') ? _scope(roh['receiptsScope']) : RegisterScope.all,
    weitere: weitere,
  );
}

/// Bekannte Reichweite oder `none` — ein unbekannter Wert wird nicht erhoben.
RegisterScope _scope(Object? wert) {
  switch (wert) {
    case 'own':
      return RegisterScope.own;
    case 'all':
      return RegisterScope.all;
    default:
      return RegisterScope.none;
  }
}

/// Die PIN-Regel aus der Antwort — oder `null`, wenn keine brauchbare kommt.
RegisterPinPolicy? _regel(Object? wert) {
  if (wert is! Map) return null;
  final stellen = wert['stellen'];
  final zeichen = wert['zeichen'];
  if (stellen is! int || stellen < 1) return null;
  if (zeichen is! String || zeichen.isEmpty) return null;
  return RegisterPinPolicy(stellen: stellen, zeichen: zeichen);
}

/// Pflichtangabe des Aufrufers. Die Meldung nennt das **Feld**, nie den Wert.
void _pflicht(String functionName, String feld, String? wert) {
  if (wert == null || wert.trim().isEmpty) {
    throw KasseneckValidationError(functionName, '$feld fehlt', 'request');
  }
}

void _ausweisPflicht(String functionName, String ownerUid, String deviceId, String deviceSecret) {
  _pflicht(functionName, 'ownerUid', ownerUid);
  _pflicht(functionName, 'deviceId', deviceId);
  _pflicht(functionName, 'deviceSecret', deviceSecret);
}

/// Pflichtfeld der Antwort. Auch hier wandert nichts aus der Antwort in die
/// Meldung; genannt wird nur, welches Feld fehlt.
String _pflichtfeld(String functionName, Map<String, dynamic> daten, String feld) {
  final wert = daten[feld];
  if (wert is! String || wert.isEmpty) {
    throw KasseneckValidationError(functionName, 'Antwort enthaelt kein Feld "$feld"', 'response');
  }
  return wert;
}

/// Leere Zeichenkette statt `null` — Anzeigefelder dürfen leer sein.
String _text(Object? wert) => wert is String ? wert : '';

/// Die beiden Aufrufe der **laufenden** Sitzung.
///
/// Sie führen keine eigenen Parameter — welche Sitzung gemeint ist, steht im
/// Ausweis, den der [RegisterTransport] anlegt.
class RegisterSessionClient {
  RegisterSessionClient({
    required Future<String?> Function() idToken,
    required Future<String?> Function() sessionId,
    required String cashregisterId,
    String? baseUrl,
    http.Client? httpClient,
    Duration? timeout,
  }) : transport = RegisterTransport(
          idToken: idToken,
          sessionId: sessionId,
          cashregisterId: cashregisterId,
          baseUrl: baseUrl,
          httpClient: httpClient,
          timeout: timeout,
        );

  /// Aus einem bestehenden Transport — so teilen Sitzung, Belege und
  /// Einstellungen einen Ausweis statt drei.
  RegisterSessionClient.aus(this.transport);

  final RegisterTransport transport;

  String get cashregisterId => transport.cashregisterId;

  /// Sitzung verlängern; liefert den neuen Ablauf (Millisekunden seit 1970).
  ///
  /// Die Sitzung lebt 90 Sekunden; erneuert wird alle 30. Ist sie beendet oder
  /// übernommen, antwortet das Backend fachlich („Sitzung beendet — bitte neu
  /// anmelden.") — dann hilft nur eine neue Anmeldung.
  Future<int> renewRegisterSession() async {
    const name = 'renewRegisterSession';
    final daten = await transport.rufen(name);
    final bis = daten['expiresAt'];
    if (bis is! int) {
      // Ohne brauchbaren Ablaufzeitpunkt weiß die Kasse nicht, wann sie das
      // nächste Mal erneuern muss — das ist ein Antwortfehler, kein Erfolg.
      throw const KasseneckValidationError(name, 'Antwort enthaelt keinen Ablaufzeitpunkt (data.expiresAt fehlt)', 'response');
    }
    return bis;
  }

  /// Sitzung beenden (Abmelden am Tresen).
  Future<void> endRegisterSession() => transport.rufen('endRegisterSession');
}
