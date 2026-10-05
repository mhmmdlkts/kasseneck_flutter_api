import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/register.dart';

/// Lager an der Kasse: die Fehlerlagen neben den Vertragsfaellen
/// (kasse_v3_test). Zwilling von `pos/lager.ts` im JS-Paket.
///
/// Die Leitregel: eine Antwort, die keine ganze Menge traegt, wird nie zu 0.
/// „Kein Bestand" und „Antwort kaputt" sind verschiedene Aussagen.

/// Ein Kassen-Client, dessen Antwort `data` ist; [gesendet] haelt die Nutzlast.
({RegisterReceiptClient client, List<Map<String, dynamic>> gesendet}) _client(Object? data) {
  final gesendet = <Map<String, dynamic>>[];
  final mock = MockClient((request) async {
    gesendet.add(((jsonDecode(request.body) as Map)['params'] as Map).cast<String, dynamic>());
    return http.Response.bytes(
      utf8.encode(jsonEncode({'status': 'success', 'message': '', 'data': data})),
      200,
      headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'},
    );
  });
  final transport = RegisterTransport(
    idToken: () async => 'id-token',
    sessionId: () async => 'sess-1',
    cashregisterId: 'KASSE1',
    httpClient: mock,
  );
  return (client: RegisterReceiptClient(transport), gesendet: gesendet);
}

final _antwortfehler = throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'response'));
final _anfragefehler = throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'request'));

Map<String, dynamic> _zeile([Map<String, dynamic> anders = const {}]) => {
      'articleId': 'art_kaffee',
      'locationId': 'haupt',
      'sellable': 12000,
      'defective': 0,
      'reserved': 2000,
      'available': 10000,
      ...anders,
    };

void main() {
  group('listMyStock: Mengen', () {
    test('negativer Bestand bleibt negativ, nichts wird geklemmt oder geteilt', () async {
      final c = _client({
        'stock': [_zeile({'sellable': -250, 'available': -250, 'reserved': 0})],
      });
      final b = (await c.client.stock()).stock.single;
      expect([b.sellable, b.reserved, b.available], [-250, 0, -250]);
    });

    test('fehlende Menge ist ein Antwortfehler, nie 0', () async {
      for (final feld in ['sellable', 'defective', 'reserved', 'available']) {
        final ohne = _zeile()..remove(feld);
        await expectLater(_client({'stock': [ohne]}).client.stock(), _antwortfehler, reason: feld);
      }
    });

    test('Bruchzahl, Text, null und Wahrheitswert als Menge sind Antwortfehler', () async {
      for (final falsch in <Object?>[12.5, '12000', null, true]) {
        await expectLater(_client({'stock': [_zeile({'sellable': falsch})]}).client.stock(), _antwortfehler,
            reason: '$falsch');
      }
    });

    test('eine ganze Zahl in Gleitkommaform (12000.0) gilt wie im JS-Zwilling als ganz', () async {
      final b = (await _client({'stock': [_zeile({'sellable': 12000.0})]}).client.stock()).stock.single;
      expect(b.sellable, 12000);
    });

    test('Zeile ohne Kennung oder ohne Objektform ist ein Antwortfehler', () async {
      await expectLater(_client({'stock': [_zeile({'articleId': ''})]}).client.stock(), _antwortfehler);
      await expectLater(_client({'stock': [_zeile()..remove('locationId')]}).client.stock(), _antwortfehler);
      await expectLater(_client({'stock': ['kaputt']}).client.stock(), _antwortfehler);
    });

    test('fehlende oder falsche Liste ist ein Antwortfehler, eine leere Liste ist leer', () async {
      await expectLater(_client(<String, dynamic>{}).client.stock(), _antwortfehler);
      await expectLater(_client({'stock': {'a': 1}}).client.stock(), _antwortfehler);
      final leer = await _client({'stock': []}).client.stock();
      expect(leer.stock, isEmpty);
    });
  });

  group('listMyStock: Werte', () {
    test('ohne values (kein Recht stockCosts) ist es null, nie eine leere Liste', () async {
      expect((await _client({'stock': []}).client.stock()).values, isNull);
      expect((await _client({'stock': [], 'values': null}).client.stock()).values, isNull);
    });

    test('mit Recht und nichts bewertet: leere Liste', () async {
      expect((await _client({'stock': [], 'values': []}).client.stock()).values, isEmpty);
    });

    test('values in falscher Form ist kaputt, nicht „kein Recht"', () async {
      await expectLater(_client({'stock': [], 'values': 'nein'}).client.stock(), _antwortfehler);
    });

    test('Durchschnitt fehlt oder null: null; eine unbrauchbare Zahl ist ein Antwortfehler', () async {
      final ohne = await _client({
        'stock': [],
        'values': [
          {'articleId': 'a', 'stockValueCents': 0},
          {'articleId': 'b', 'stockValueCents': 0, 'averageCostMicros': null},
        ],
      }).client.stock();
      expect(ohne.values!.map((w) => w.averageCostMicros), [null, null]);
      await expectLater(
          _client({
            'stock': [],
            'values': [
              {'articleId': 'a', 'stockValueCents': 100, 'averageCostMicros': 1.5},
            ],
          }).client.stock(),
          _antwortfehler);
      await expectLater(
          _client({
            'stock': [],
            'values': [
              {'articleId': 'a'},
            ],
          }).client.stock(),
          _antwortfehler);
    });
  });

  group('listMyStock: Anfrage', () {
    test('leere Filter gehen nicht hinaus, belowMinimum nur als true', () async {
      final c = _client({'stock': []});
      await c.client.stock(locationId: '', articleId: '', belowMinimum: false);
      await c.client.stock(locationId: 'auto1', articleId: 'art_kaffee', belowMinimum: true);
      expect(c.gesendet[0].keys.toSet(), {'cashregisterId'});
      expect(c.gesendet[1], {
        'cashregisterId': 'KASSE1',
        'locationId': 'auto1',
        'articleId': 'art_kaffee',
        'belowMinimum': true,
      });
    });
  });

  group('listMyStockLocations', () {
    test('Adresse ohne einen Teil ist null; leere Teile sind null; unbekannter Typ ist null', () async {
      final orte = await _client({
        'locations': [
          {
            'id': 'x',
            'name': 'X',
            'type': 'spaceship',
            'address': {'street': '', 'zip': null, 'city': '', 'country': null},
          },
          {
            'id': 'y',
            'type': 'store',
            'address': {'street': '', 'city': 'Wien'},
            'licensePlate': '',
          },
        ],
      }).client.stockLocations();
      expect([orte[0].type, orte[0].address, orte[0].active, orte[0].virtual], [null, null, true, false]);
      expect(orte[1].name, '');
      expect([orte[1].address?.street, orte[1].address?.city, orte[1].address?.zip], [null, 'Wien', null]);
      expect(orte[1].licensePlate, isNull);
    });

    test('Standort ohne Kennung ist ein Antwortfehler; fehlende Liste ebenso', () async {
      await expectLater(
          _client({
            'locations': [
              {'name': 'ohne'},
            ],
          }).client.stockLocations(),
          _antwortfehler);
      await expectLater(_client(<String, dynamic>{}).client.stockLocations(), _antwortfehler);
    });
  });

  group('setMyCashregisterStockLocation', () {
    test('null setzt zurück: am Draht der leere Text; ohne cashregisterId gilt die Kasse der Anmeldung', () async {
      final c = _client({'cashregisterId': 'KASSE1', 'stockLocationId': null});
      final r = await c.client.setStockLocation(stockLocationId: null);
      expect(c.gesendet.single, {'cashregisterId': 'KASSE1', 'stockLocationId': ''});
      expect(r.stockLocationId, isNull);
    });

    test('eine andere Kasse geht ausdrücklich hinaus', () async {
      final c = _client({'cashregisterId': 'KASSE2', 'stockLocationId': 'auto1'});
      final r = await c.client.setStockLocation(stockLocationId: 'auto1', cashregisterId: 'KASSE2');
      expect(c.gesendet.single, {'cashregisterId': 'KASSE2', 'stockLocationId': 'auto1'});
      expect([r.cashregisterId, r.stockLocationId], ['KASSE2', 'auto1']);
    });

    test('nur Leerraum ist kein Zurücksetzen, sondern ein Fehler vor dem Senden; leere Kasse ebenso', () async {
      final c = _client({'cashregisterId': 'KASSE1'});
      await expectLater(c.client.setStockLocation(stockLocationId: '  '), _anfragefehler);
      await expectLater(c.client.setStockLocation(stockLocationId: 'auto1', cashregisterId: ' '), _anfragefehler);
      expect(c.gesendet, isEmpty);
    });

    test('Antwort ohne Kasse oder mit unbrauchbarem Standort ist ein Antwortfehler; leerer Standort ist null', () async {
      await expectLater(_client({'stockLocationId': 'auto1'}).client.setStockLocation(stockLocationId: 'auto1'),
          _antwortfehler);
      await expectLater(
          _client({'cashregisterId': 'KASSE1', 'stockLocationId': 7}).client.setStockLocation(stockLocationId: 'auto1'),
          _antwortfehler);
      final leer = await _client({'cashregisterId': 'KASSE1', 'stockLocationId': ''})
          .client
          .setStockLocation(stockLocationId: null);
      expect(leer.stockLocationId, isNull);
    });
  });

  group('Rechte', () {
    test('stockViewOf: fehlt = erteilt, nur ein ausdrückliches false sperrt, ohne Rechte gesperrt', () {
      expect(stockViewOf(RegisterUserPerms.fromJson(const {})), isTrue);
      expect(stockViewOf(RegisterUserPerms.fromJson(const {'stockView': true})), isTrue);
      expect(stockViewOf(RegisterUserPerms.fromJson(const {'stockView': false})), isFalse);
      // Wie im JS-Zwilling: ein vorhandener Schluessel zaehlt nur als true.
      expect(stockViewOf(RegisterUserPerms.fromJson(const {'stockView': null})), isFalse);
      expect(stockViewOf(RegisterUserPerms.fromJson(const {'stockView': 'ja'})), isFalse);
      expect(stockViewOf(null), isFalse);
      expect(stockViewOf(const RegisterUserPerms()), isTrue);
    });

    test('die sieben Lager-Rechte sind typisiert, nicht mehr im Auffangbecken', () {
      const alle = {
        'stockView', 'stockCosts', 'stockMove', 'stockLoss', 'stocktakeCount', 'stocktakeClose', 'stockLocation',
      };
      final p = RegisterUserPerms.fromJson({for (final r in alle) r: true, 'kuenftig': true});
      expect([p.stockView, p.stockCosts, p.stockMove, p.stockLoss, p.stocktakeCount, p.stocktakeClose, p.stockLocation],
          everyElement(isTrue));
      expect(p.other.keys, ['kuenftig']);
      for (final r in alle) {
        expect(p[r], isTrue, reason: r);
      }
    });

    test('fehlende Lager-Rechte ausser stockView gelten als verweigert; [] liefert den Rohwert', () {
      final p = RegisterUserPerms.fromJson(const {'stockCosts': false});
      expect([p.stockCosts, p.stockMove, p.stockLoss, p.stocktakeCount, p.stocktakeClose, p.stockLocation],
          everyElement(isFalse));
      expect(p.stockView, isNull);
      // Der Operator bleibt beim Rohwert (fehlt = false) wie vor 10.2; die
      // Regel „fehlt = erteilt" steht allein in stockViewOf.
      expect(p['stockView'], isFalse);
      expect(p['stockCosts'], isFalse);
    });
  });

  group('Standorte an Artikel, Kasse und Gerät', () {
    test('PosArticle.stockLocationIds: Liste ohne leere Einträge, null ohne Angabe, übersteht den Zwischenspeicher', () {
      final mit = PosArticle.fromJson({
        'id': 'a',
        'name': 'Kaffee',
        'stockLocationIds': ['haupt', '', 7, 'auto1'],
      });
      expect(mit.stockLocationIds, ['haupt', 'auto1']);
      expect(PosArticle.fromJson(mit.toJson()).stockLocationIds, ['haupt', 'auto1']);
      expect(PosArticle.fromJson({'id': 'a', 'stockLocationIds': []}).stockLocationIds, isEmpty);
      final ohne = PosArticle.fromJson({'id': 'a', 'name': 'Kaffee'});
      expect(ohne.stockLocationIds, isNull);
      expect(PosArticle.fromJson({'id': 'a', 'stockLocationIds': 'haupt'}).stockLocationIds, isNull);
      expect(PosArticle.fromJson(ohne.toJson()).stockLocationIds, isNull);
    });

    test('PosArticle-Codes (npm 1.3.0): Text unveraendert, leer/Leerraum/falscher Typ = null; stockTracked nur bool',
        () {
      final mit = PosArticle.fromJson({
        'id': 'a',
        'name': 'Semmel',
        'number': '00123',
        'ean': '9001234567897',
        'internalCode': ' K-7 ',
        'stockTracked': true,
      });
      expect([mit.number, mit.ean, mit.internalCode, mit.stockTracked], ['00123', '9001234567897', ' K-7 ', true]);
      // Der Zwischenspeicher behaelt alles.
      final zurueck = PosArticle.fromJson(mit.toJson());
      expect([zurueck.number, zurueck.ean, zurueck.internalCode, zurueck.stockTracked],
          ['00123', '9001234567897', ' K-7 ', true]);
      expect(PosArticle.fromJson({'id': 'a', 'stockTracked': false}).stockTracked, isFalse);

      for (final falsch in <Object?>['', '   ', '\t', 123, true, null]) {
        final a = PosArticle.fromJson({'id': 'a', 'number': falsch, 'ean': falsch, 'internalCode': falsch});
        expect([a.number, a.ean, a.internalCode], [null, null, null], reason: '$falsch');
      }
      for (final falsch in <Object?>['true', 1, null]) {
        expect(PosArticle.fromJson({'id': 'a', 'stockTracked': falsch}).stockTracked, isNull, reason: '$falsch');
      }
      final ohne = PosArticle.fromJson({'id': 'a', 'name': 'Kaffee'});
      expect([ohne.number, ohne.ean, ohne.internalCode, ohne.stockTracked], [null, null, null, null]);
      final leer = PosArticle.fromJson(ohne.toJson());
      expect([leer.number, leer.ean, leer.internalCode, leer.stockTracked], [null, null, null, null]);
    });

    test('CashregisterEntry.stockLocationId: fehlt oder leer = null (Standard-Standort)', () {
      Map<String, dynamic> kasse(Object? standort) => {'id': 'KASSE1', 'onboarding': {}, 'stockLocationId': standort};
      expect(CashregisterEntry.fromJson(kasse('auto1')).stockLocationId, 'auto1');
      expect(CashregisterEntry.fromJson(kasse('')).stockLocationId, isNull);
      expect(CashregisterEntry.fromJson(kasse(null)).stockLocationId, isNull);
      expect(CashregisterEntry.fromJson({'id': 'KASSE1'}).stockLocationId, isNull);
    });

    test('listRegisterUsersForDevice: cashregister.stockLocationId', () async {
      Future<RegisterCashregisterState?> lies(Map<String, dynamic> kasse) async {
        final mock = MockClient((request) async => http.Response.bytes(
              utf8.encode(jsonEncode({
                'status': 'success',
                'message': '',
                'data': {'loginMode': 'pin', 'users': [], 'cashregister': kasse},
              })),
              200,
              headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'},
            ));
        final users = await RegisterClient(httpClient: mock)
            .listRegisterUsersForDevice(ownerUid: 'o', deviceId: 'd', deviceSecret: 's');
        return users.cashregister;
      }

      expect((await lies({'ready': true, 'stockLocationId': 'auto1'}))?.stockLocationId, 'auto1');
      expect((await lies({'ready': true, 'stockLocationId': ''}))?.stockLocationId, isNull);
      expect((await lies({'ready': true}))?.stockLocationId, isNull);
      expect((await lies({'ready': true, 'stockLocationId': 5}))?.stockLocationId, isNull);
    });
  });
}
