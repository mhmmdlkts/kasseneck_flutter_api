import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/kasse.dart';
import 'package:kasseneck_api/register.dart';

/// Kopplung und Anmeldung eines Kassengeräts — der Zwilling von
/// `register/pairing.ts` im JS-Paket. Diese drei Aufrufe laufen **ohne jede
/// Identität**: der Kopplungs-Code bzw. das Gerätegeheimnis ist der Nachweis.
///
/// Geprüft wird gegen einen MockClient: Adresse, Rumpf, Auswertung der Antwort
/// und die Zusagen, die den Kassier betreffen (Reichweiten der Rechte,
/// Geheimnisse tauchen in keiner Fehlermeldung auf).

const ownerUid = 'kunde-1';
const deviceId = 'geraet-1';
const deviceSecret = 'ds_geheim_abcdef';
const cashregisterId = 'KASSE1';
const userId = 'benutzer-1';
const pin = '1234';

({RegisterClient client, List<http.Request> log, List<String> bodies}) clientWith(
  Object antwort, {
  int status = 200,
}) {
  final log = <http.Request>[];
  final bodies = <String>[];
  final mock = MockClient((request) async {
    log.add(request);
    bodies.add(request.body);
    return http.Response(
      antwort is String ? antwort : jsonEncode(antwort),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
  return (client: RegisterClient(httpClient: mock), log: log, bodies: bodies);
}

Map<String, dynamic> erfolg(Map<String, dynamic> daten) => {'status': 'success', 'data': daten};

const kopplungsAntwort = {
  'deviceId': deviceId,
  'deviceSecret': deviceSecret,
  'ownerUid': ownerUid,
  'cashregisterId': cashregisterId,
  'betrieb': 'Bäckerei Muster',
  'kasse': 'Theke',
};

const anmeldeAntwort = {
  'customToken': 'eyJ-CUSTOM-TOKEN',
  'sessionId': 'sess-neu',
  'expiresAt': 1776000090000,
  'user': {
    'id': userId,
    'name': 'Anna',
    'perms': {
      'sell': true,
      'cancel': true,
      'cancelScope': 'own',
      'receiptsScope': 'own',
      'discount': true,
      'drawer': false,
    },
  },
};

void main() {
  basisadresse();
  einstellungen();

  group('Kopplung', () {
    test('tauscht den Code gegen den Ausweis des Geräts', () async {
      final f = clientWith(erfolg(kopplungsAntwort));
      final geraet = await f.client.pairRegisterDevice(code: ' abcd1234 ', label: 'Theke');

      expect(f.log.single.method, 'POST');
      expect(f.log.single.url.toString(), 'https://kasse.kasseneck.at/api/pairRegisterDevice');
      final rumpf = jsonDecode(f.bodies.single)['params'] as Map<String, dynamic>;
      expect(rumpf['code'], ' abcd1234 ', reason: 'das Backend beschneidet selbst — der Client rät nicht am Format herum');
      expect(rumpf['label'], 'Theke');
      expect(rumpf.containsKey('geo'), isFalse, reason: 'ohne Ortung nichts mitsenden');

      expect(geraet.deviceId, deviceId);
      expect(geraet.deviceSecret, deviceSecret);
      expect(geraet.ownerUid, ownerUid);
      expect(geraet.cashregisterId, cashregisterId);
      expect(geraet.companyName, 'Bäckerei Muster');
      expect(geraet.cashregisterLabel, 'Theke');
    });

    test('ein leerer Code geht gar nicht erst hinaus', () async {
      final f = clientWith(erfolg(kopplungsAntwort));
      expect(
        () => f.client.pairRegisterDevice(code: '   '),
        throwsA(isA<KasseneckValidationError>().having((e) => e.toString(), 'Meldung', contains('code'))),
      );
      expect(f.log, isEmpty);
    });

    test('eine unvollständige Antwort ist ein Fehler — kein halbes Gerät', () async {
      for (final fehlt in ['deviceId', 'deviceSecret', 'ownerUid', 'cashregisterId']) {
        final unvollstaendig = Map<String, dynamic>.from(kopplungsAntwort)..remove(fehlt);
        final f = clientWith(erfolg(unvollstaendig));
        await expectLater(
          f.client.pairRegisterDevice(code: 'abcd1234'),
          throwsA(isA<KasseneckValidationError>().having((e) => e.toString(), 'nennt das Feld', contains(fehlt))),
        );
      }
    });

    test('Angaben zum Gerät und Standort gehen mit, wenn sie da sind', () async {
      final f = clientWith(erfolg(kopplungsAntwort));
      await f.client.pairRegisterDevice(
        code: 'abcd1234',
        client: const RegisterClientInfo(platform: 'ios', language: 'de-AT', tz: 'Europe/Vienna'),
        geo: const RegisterGeo(lat: 47.8, lng: 13.0, acc: 12.5),
      );
      final rumpf = jsonDecode(f.bodies.single)['params'] as Map<String, dynamic>;
      expect(rumpf['client'], {'platform': 'ios', 'language': 'de-AT', 'tz': 'Europe/Vienna'});
      expect(rumpf['geo'], {'lat': 47.8, 'lng': 13.0, 'acc': 12.5});
    });
  });

  group('Benutzerliste des Geräts', () {
    test('liest Benutzer, PIN-Regel, Modus und Standortsperre', () async {
      final f = clientWith(erfolg({
        'users': [
          {'id': 'u1', 'name': 'Anna', 'kind': 'person'},
          {'id': 'u2', 'name': '', 'kind': 'device', 'altbestand': true},
          {'id': 'u3', 'name': 'Neu', 'kind': 'kuenftig'},
        ],
        'policy': {'stellen': 4, 'zeichen': 'ziffern'},
        'loginMode': 'auswahl',
        'standortsperre': true,
        'settings': {'betrieb': {}, 'geraet': {}},
      }));

      final antwort = await f.client.listRegisterUsersForDevice(
        ownerUid: ownerUid,
        deviceId: deviceId,
        deviceSecret: deviceSecret,
      );

      expect(antwort.users.map((u) => u.id), ['u1', 'u2', 'u3']);
      expect(antwort.users[0].kind, RegisterUserKind.person);
      expect(antwort.users[1].kind, RegisterUserKind.device);
      expect(antwort.users[1].altbestand, isTrue);
      expect(antwort.users[2].kind, RegisterUserKind.person, reason: 'unbekannte Art gilt als Person');
      expect(antwort.users[0].altbestand, isFalse);
      expect(antwort.policy?.stellen, 4);
      expect(antwort.policy?.zeichen, 'ziffern');
      expect(antwort.loginMode, RegisterLoginMode.auswahl);
      expect(antwort.standortsperre, isTrue);
    });

    test('ohne brauchbare Regel bleibt policy null; unbekannter Modus gilt als Auswahl', () async {
      for (final regel in [null, {}, {'stellen': 'vier'}, {'stellen': 4}, {'zeichen': 'ziffern'}]) {
        final f = clientWith(erfolg({'users': [], 'policy': regel, 'loginMode': 'was-neues'}));
        final antwort = await f.client.listRegisterUsersForDevice(
          ownerUid: ownerUid,
          deviceId: deviceId,
          deviceSecret: deviceSecret,
        );
        expect(antwort.policy, isNull, reason: 'Regel $regel');
        expect(antwort.loginMode, RegisterLoginMode.auswahl);
      }
    });

    test('fehlende Benutzerliste ist ein Antwortfehler', () async {
      final f = clientWith(erfolg({'policy': null}));
      await expectLater(
        f.client.listRegisterUsersForDevice(ownerUid: ownerUid, deviceId: deviceId, deviceSecret: deviceSecret),
        throwsA(isA<KasseneckValidationError>()),
      );
    });
  });

  group('Anmeldung', () {
    test('PIN-Anmeldung liefert Sitzung und Rechte', () async {
      final f = clientWith(erfolg(Map<String, dynamic>.from(anmeldeAntwort)));
      final sitzung = await f.client.registerUserLogin(
        ownerUid: ownerUid,
        deviceId: deviceId,
        deviceSecret: deviceSecret,
        userId: userId,
        pin: pin,
        cashregisterId: cashregisterId,
      );

      expect(f.log.single.url.toString(), endsWith('/registerUserLogin'));
      final rumpf = jsonDecode(f.bodies.single)['params'] as Map<String, dynamic>;
      expect(rumpf['userId'], userId);
      expect(rumpf['pin'], pin);
      expect(rumpf['cashregisterId'], cashregisterId);
      expect(rumpf.containsKey('takeover'), isFalse, reason: 'nur die ausdrückliche Übernahme geht mit');

      expect(sitzung.customToken, 'eyJ-CUSTOM-TOKEN');
      expect(sitzung.sessionId, 'sess-neu');
      expect(sitzung.expiresAt, 1776000090000);
      expect(sitzung.user.id, userId);
      expect(sitzung.user.name, 'Anna');
    });

    test('Storno- und Beleg-Reichweite kommen als Text durch, nicht als Ja/Nein', () async {
      // Ein Kassier hat cancelScope/receiptsScope = 'own'. Wer daraus einen
      // Wahrheitswert macht, nimmt ihm die eigenen Belege und dem Chef das
      // Stornieren (derselbe Fehler steckte bis 0.6.8 im JS-Paket).
      final f = clientWith(erfolg(Map<String, dynamic>.from(anmeldeAntwort)));
      final sitzung = await f.client.registerPinLogin(
        ownerUid: ownerUid,
        deviceId: deviceId,
        deviceSecret: deviceSecret,
        pin: pin,
        cashregisterId: cashregisterId,
      );

      expect(sitzung.user.perms.cancelScope, RegisterScope.own);
      expect(sitzung.user.perms.receiptsScope, RegisterScope.own);
      expect(sitzung.user.perms.sell, isTrue);
      expect(sitzung.user.perms.discount, isTrue);
      expect(sitzung.user.perms.drawer, isFalse);
      expect(sitzung.user.perms.layout, isFalse, reason: 'ein fehlendes Recht gilt als nicht erteilt');
    });

    test('Altbestand ohne Reichweiten: cancel entscheidet, Belege gelten als alle', () async {
      final f = clientWith(erfolg({
        ...anmeldeAntwort,
        'user': {'id': userId, 'name': 'Alt', 'perms': {'sell': true, 'cancel': true}},
      }));
      final sitzung = await f.client.registerPinLogin(
        ownerUid: ownerUid, deviceId: deviceId, deviceSecret: deviceSecret,
        pin: pin, cashregisterId: cashregisterId,
      );
      expect(sitzung.user.perms.cancelScope, RegisterScope.all);
      expect(sitzung.user.perms.receiptsScope, RegisterScope.all);
    });

    test('unbekannte Reichweite wird nicht erhoben', () async {
      final f = clientWith(erfolg({
        ...anmeldeAntwort,
        'user': {'id': userId, 'name': 'X', 'perms': {'cancelScope': 'alles', 'receiptsScope': 'all'}},
      }));
      final sitzung = await f.client.registerPinLogin(
        ownerUid: ownerUid, deviceId: deviceId, deviceSecret: deviceSecret,
        pin: pin, cashregisterId: cashregisterId,
      );
      expect(sitzung.user.perms.cancelScope, RegisterScope.none);
      expect(sitzung.user.perms.receiptsScope, RegisterScope.all);
    });

    test('Übernahme geht nur ausdrücklich mit', () async {
      final f = clientWith(erfolg(Map<String, dynamic>.from(anmeldeAntwort)));
      await f.client.registerPinLogin(
        ownerUid: ownerUid, deviceId: deviceId, deviceSecret: deviceSecret,
        pin: pin, cashregisterId: cashregisterId, takeover: true,
      );
      expect((jsonDecode(f.bodies.single)['params'] as Map)['takeover'], isTrue);
    });

    test('unvollständige Sitzungsantwort ist ein Fehler', () async {
      final faelle = <String, Map<String, dynamic>>{
        'ohne customToken': Map<String, dynamic>.from(anmeldeAntwort)..remove('customToken'),
        'ohne sessionId': Map<String, dynamic>.from(anmeldeAntwort)..remove('sessionId'),
        'ohne expiresAt': Map<String, dynamic>.from(anmeldeAntwort)..remove('expiresAt'),
        'ohne user': Map<String, dynamic>.from(anmeldeAntwort)..remove('user'),
        'user ohne id': {...anmeldeAntwort, 'user': {'name': 'A', 'perms': {}}},
      };
      for (final fall in faelle.entries) {
        final f = clientWith(erfolg(fall.value));
        await expectLater(
          f.client.registerPinLogin(
            ownerUid: ownerUid, deviceId: deviceId, deviceSecret: deviceSecret,
            pin: pin, cashregisterId: cashregisterId,
          ),
          throwsA(isA<KasseneckValidationError>()),
          reason: fall.key,
        );
      }
    });

    test('eine falsche PIN kommt als fachlicher Fehler des Backends an', () async {
      final f = clientWith({'status': 'error', 'message': 'PIN falsch (noch 2 Versuche)'});
      await expectLater(
        f.client.registerPinLogin(
          ownerUid: ownerUid, deviceId: deviceId, deviceSecret: deviceSecret,
          pin: '9999', cashregisterId: cashregisterId,
        ),
        throwsA(isA<KasseneckApiError>().having((e) => e.message, 'Meldung', contains('PIN falsch'))),
      );
    });

    test('weder PIN noch Gerätegeheimnis stehen je in einer Fehlermeldung', () async {
      final f = clientWith('kein json', status: 500);
      try {
        await f.client.registerPinLogin(
          ownerUid: ownerUid, deviceId: deviceId, deviceSecret: deviceSecret,
          pin: pin, cashregisterId: cashregisterId,
        );
        fail('hätte werfen müssen');
      } catch (e) {
        expect(e.toString(), isNot(contains(deviceSecret)));
        expect(e.toString(), isNot(contains(pin)));
      }
    });
  });

  group('Entkoppeln', () {
    test('sperrt das Gerät im Backend', () async {
      final f = clientWith(erfolg({'ok': true}));
      await f.client.unpairRegisterDevice(ownerUid: ownerUid, deviceId: deviceId, deviceSecret: deviceSecret);
      expect(f.log.single.url.toString(), endsWith('/unpairRegisterDevice'));
      final rumpf = jsonDecode(f.bodies.single)['params'] as Map<String, dynamic>;
      expect(rumpf['deviceId'], deviceId);
      expect(rumpf['deviceSecret'], deviceSecret);
    });

    test('ohne Ausweis geht nichts hinaus', () async {
      final f = clientWith(erfolg({'ok': true}));
      for (final fall in [
        () => f.client.unpairRegisterDevice(ownerUid: '', deviceId: deviceId, deviceSecret: deviceSecret),
        () => f.client.unpairRegisterDevice(ownerUid: ownerUid, deviceId: '', deviceSecret: deviceSecret),
        () => f.client.unpairRegisterDevice(ownerUid: ownerUid, deviceId: deviceId, deviceSecret: ' '),
      ]) {
        expect(fall, throwsA(isA<KasseneckValidationError>()));
      }
      expect(f.log, isEmpty);
    });
  });
}

void einstellungen() {
  test('die Kassen-Einstellungen kommen gemischt mit den Standardwerten', () async {
    final f = clientWith(erfolg({
      'users': [],
      'settings': {
        'betrieb': {'zahlKarte': true, 'kartenanbieter': 'hobex'},
        'geraet': {'layout': 'vollbild'},
      },
    }));
    final antwort = await f.client.listRegisterUsersForDevice(
      ownerUid: ownerUid, deviceId: deviceId, deviceSecret: deviceSecret,
    );
    expect(antwort.settings.betrieb.kartenAktiv, isTrue);
    expect(antwort.settings.geraet.layout, KasseLayout.vollbild);
    expect(antwort.settings.betrieb.zahlBar, isTrue, reason: 'ungenanntes bleibt beim Standard');
  });

  test('ohne Einstellungen in der Antwort gelten die Standardwerte', () async {
    final f = clientWith(erfolg({'users': []}));
    final antwort = await f.client.listRegisterUsersForDevice(
      ownerUid: ownerUid, deviceId: deviceId, deviceSecret: deviceSecret,
    );
    expect(antwort.settings.toJson(), const KasseSettings.standard().toJson());
  });
}

void basisadresse() {
  test('die Vorgabe zeigt auf die Kassen-Adresse, nicht auf die api_key-Schnittstelle', () async {
    // Unter api.kasseneck.at/v1 antwortet auf diese Aufrufe eine HTML-404 —
    // die Kopplung schlug damit mit einer nichtssagenden Meldung fehl.
    expect(kRegisterBaseUrl, 'https://kasse.kasseneck.at/api');
    final log = <http.Request>[];
    final client = RegisterClient(
      httpClient: MockClient((r) async {
        log.add(r);
        return http.Response(jsonEncode(erfolg(kopplungsAntwort)), 200);
      }),
    );
    await client.pairRegisterDevice(code: 'ABCD1234');
    expect(log.single.url.toString(), 'https://kasse.kasseneck.at/api/pairRegisterDevice');
  });

  group('Zeitablauf ist etwas anderes als ein Netzfehler', () {
    // Der Kopplungs-Code wird beim Aufruf verbraucht und das Geraetegeheimnis
    // genau einmal ausgeliefert. Laeuft die Frist auf dem Rueckweg ab, kann die
    // Kopplung serverseitig vollzogen sein — ein neuer Versuch mit demselben
    // Code laeuft dann ins Leere. Als blosses 'network' war das von „nie
    // angekommen" nicht zu unterscheiden.
    test('abgelaufene Frist: reason "timeout" mit Ursachentyp', () async {
      final client = RegisterClient(
        httpClient: MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 20),
      );

      await expectLater(
        client.pairRegisterDevice(code: 'ABCD1234'),
        throwsA(isA<KasseneckHttpError>()
            .having((e) => e.reason, 'reason', KasseneckHttpError.zeitablauf)
            .having((e) => e.causeType, 'causeType', 'TimeoutException')),
      );
    });

    test('Verbindungsfehler bleibt "network" — und traegt keinen Rumpfwert', () async {
      final client = RegisterClient(
        httpClient: MockClient((_) async => throw http.ClientException('pin=$pin')),
      );

      await expectLater(
        client.pairRegisterDevice(code: 'ABCD1234'),
        throwsA(isA<KasseneckHttpError>()
            .having((e) => e.reason, 'reason', KasseneckHttpError.netz)
            .having((e) => e.toString(), 'toString', isNot(contains(pin)))),
      );
    });
  });

  // Zwilling von listRegisterSessionsForDevice (npm 0.6.48): Welche Sitzungen
  // haelt diese Kasse? Fuer den Anmeldebildschirm, wenn alle Lizenzplaetze
  // belegt sind -- der Kassier sieht, WELCHE weichen soll, statt dass das
  // Backend still die aelteste nimmt. Die Wahl geht als takeoverSessionId mit.
  group('listRegisterSessionsForDevice', () {
    test('liest Lizenzen und Sitzungen; fehlende Felder fallen auf null, userName nur wenn wirklich da', () async {
      final f = clientWith(erfolg({
        'licenses': 2,
        'sessions': [
          {'id': 's1', 'deviceId': 'd1', 'deviceLabel': 'Theke', 'startedAt': 1000, 'expiresAt': 2000, 'selbst': true, 'userName': 'Anna'},
          {'id': 's2', 'deviceLabel': '', 'userName': ''},
        ],
      }));
      final stand = await f.client.listRegisterSessionsForDevice(ownerUid: ownerUid, deviceId: deviceId, deviceSecret: deviceSecret);
      expect(stand.licenses, 2);
      expect(stand.sessions.map((s) => s.id), ['s1', 's2']);
      expect(stand.sessions[0].deviceLabel, 'Theke');
      expect(stand.sessions[0].selbst, isTrue);
      expect(stand.sessions[0].userName, 'Anna');
      expect(stand.sessions[1].deviceId, isNull);
      expect(stand.sessions[1].deviceLabel, 'Kasse', reason: 'leeres Etikett faellt auf den Standard');
      expect(stand.sessions[1].startedAt, isNull);
      expect(stand.sessions[1].selbst, isFalse);
      expect(stand.sessions[1].userName, isNull, reason: 'leerer Name ist kein Name');
      final Map<String, dynamic> body = jsonDecode(f.log.single.body);
      expect(body['params'], {'ownerUid': ownerUid, 'deviceId': deviceId, 'deviceSecret': deviceSecret});
    });

    test('Lizenzen ohne oder mit unbrauchbarem Wert gelten als 1', () async {
      final f = clientWith(erfolg({'sessions': []}));
      final stand = await f.client.listRegisterSessionsForDevice(ownerUid: ownerUid, deviceId: deviceId, deviceSecret: deviceSecret);
      expect(stand.licenses, 1);
      expect(stand.sessions, isEmpty);
    });

    test('ohne Sitzungsliste: Antwortfehler, kein leeres Ergebnis', () async {
      final f = clientWith(erfolg({'licenses': 1}));
      await expectLater(
        f.client.listRegisterSessionsForDevice(ownerUid: ownerUid, deviceId: deviceId, deviceSecret: deviceSecret),
        throwsA(isA<KasseneckValidationError>()),
      );
    });

    test('Sitzung ohne Kennung ist nicht waehlbar: Antwortfehler', () async {
      final f = clientWith(erfolg({'sessions': [{'deviceLabel': 'x'}]}));
      await expectLater(
        f.client.listRegisterSessionsForDevice(ownerUid: ownerUid, deviceId: deviceId, deviceSecret: deviceSecret),
        throwsA(isA<KasseneckValidationError>()),
      );
    });
  });

  group('registerUserLogin: takeoverSessionId', () {
    test('die gewaehlte Sitzung geht mit; ohne Wahl fehlt das Feld', () async {
      final f = clientWith(erfolg({
        'customToken': 'ct', 'sessionId': 's9', 'expiresAt': 5000,
        'user': {'id': 'u1', 'name': 'Anna', 'perms': {}},
      }));
      await f.client.registerUserLogin(
        ownerUid: ownerUid, deviceId: deviceId, deviceSecret: deviceSecret,
        userId: 'u1', pin: '1234', cashregisterId: 'K1', takeover: true, takeoverSessionId: 's1',
      );
      final Map<String, dynamic> body = jsonDecode(f.log.single.body);
      expect(body["params"]['takeoverSessionId'], 's1');
      expect(body["params"]['takeover'], isTrue);

      final g = clientWith(erfolg({
        'customToken': 'ct', 'sessionId': 's9', 'expiresAt': 5000,
        'user': {'id': 'u1', 'name': 'Anna', 'perms': {}},
      }));
      await g.client.registerUserLogin(
        ownerUid: ownerUid, deviceId: deviceId, deviceSecret: deviceSecret,
        userId: 'u1', pin: '1234', cashregisterId: 'K1',
      );
      final Map<String, dynamic> body2 = jsonDecode(g.log.single.body);
      expect(body2["params"].containsKey('takeoverSessionId'), isFalse);
    });
  });
}

