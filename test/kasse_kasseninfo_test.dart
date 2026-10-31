import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/register.dart';

/// Kasseninfo fuer die Pruefung (seit 11.15, Zwilling von npm 1.23.0): die
/// Zeilen fuer Bildschirm und Bondrucker gegen die gemeinsamen Prueffaelle
/// (`inspection-info-cases.json`), das Lesen der Antwort und der Nullbeleg am
/// Kassenweg. Die Vertragsfaelle des Backends laufen in `kasse_v3_test.dart`.

final _faelle = ((jsonDecode(File('test/fixtures/vertrag/inspection-info-cases.json').readAsStringSync())
        as Map<String, dynamic>)['cases'] as List)
    .cast<Map<String, dynamic>>();

RegisterInspectionInfo _info(Object? json) => RegisterInspectionInfo.fromJson(Map<String, dynamic>.from(json as Map));

final _gedruckt = DateTime.utc(2026, 10, 29, 13, 5);

Map<String, dynamic> _fall(String anfang) => _faelle.firstWhere((f) => (f['name'] as String).startsWith(anfang));

/// Ein Kassenweg, der genau eine Antwort liefert und die Anfragen mitschreibt.
(RegisterReceiptClient, List<http.Request>) _kasse(Map<String, dynamic> huelle) {
  final log = <http.Request>[];
  final client = MockClient((anfrage) async {
    log.add(anfrage);
    return http.Response.bytes(utf8.encode(jsonEncode(huelle)), 200,
        headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'});
  });
  final transport = RegisterTransport(
      idToken: () async => 'id-token', sessionId: () async => 'sess-1', cashregisterId: 'KECK-1', httpClient: client);
  return (RegisterReceiptClient(transport), log);
}

void main() {
  group('inspectionInfoRows und inspectionInfoLines (inspection-info-cases.json)', () {
    test('jeder Fall des Vertrags: dieselben Zeilen wie das npm-Paket', () {
      expect(_faelle, hasLength(greaterThanOrEqualTo(14)));
      expect({for (final f in _faelle) f['width']}, containsAll([32, 42, 48]));
      for (final f in _faelle) {
        final info = _info(f['info']);
        final name = f['name'] as String;
        expect([for (final z in inspectionInfoRows(info)) z.toJson()], f['rows'], reason: name);
        expect(
          inspectionInfoLines(info, width: f['width'] as int, printedAt: DateTime.parse(f['printedAt'] as String)),
          f['lines'],
          reason: name,
        );
      }
    });

    test('das Modell liest jeden Fall verlustfrei (toJson ist die Drahtform), ausser einem unbekannten Stand', () {
      var unbekannt = 0;
      for (final f in _faelle) {
        final soll = jsonDecode(jsonEncode(f['info'])) as Map<String, dynamic>;
        final signatur = soll['signature'] as Map<String, dynamic>?;
        if (signatur != null && signatur['status'] != null && !['active', 'outage'].contains(signatur['status'])) {
          signatur.remove('status');
          unbekannt++;
        }
        expect(_info(f['info']).toJson(), soll, reason: f['name'] as String);
      }
      expect(unbekannt, 1, reason: 'der Fall mit unbekanntem Stand steht im Vertrag');
    });

    test('keine Zeile ist breiter als der Bon, von 24 bis 64 Zeichen, nie ein geschuetztes Leerzeichen', () {
      for (final f in _faelle) {
        final info = _info(f['info']);
        for (var breite = 24; breite <= 64; breite++) {
          for (final zeile in inspectionInfoLines(info, width: breite, printedAt: _gedruckt)) {
            expect(zeile.length, lessThanOrEqualTo(breite), reason: '${f['name']}, $breite: $zeile');
            expect(zeile.contains('\u00a0'), isFalse, reason: '${f['name']}, $breite: $zeile');
            expect(zeile, zeile.trimRight(), reason: '${f['name']}, $breite: Leerraum am Ende');
          }
        }
        for (final z in inspectionInfoRows(info)) {
          for (final w in z.value) {
            expect(w.contains('\u00a0'), isFalse, reason: '${f['name']}: $w');
          }
        }
      }
    });

    test('der freigegebene Wortlaut: Zeilen mit Bezeichnung bei 48 Zeichen wie freigegeben', () {
      final zeilen = inspectionInfoLines(_info(_fall('echte Karte von A-Trust, Breite 42')['info']),
          width: 48, printedAt: _gedruckt);
      expect(zeilen.sublist(0, 5), [
        'KASSENINFO FÜR DIE PRÜFUNG',
        '',
        'Kasseneck – cloudbasierte Registrierkasse',
        'Hersteller   Post Now e.U., UID ATU76279224',
        'Kassen-ID    KECK-1',
      ]);
      expect(zeilen, containsAllInOrder([
        'Zertifikat   Seriennr. 11c6c7cd (hex)',
        '             298239949 (dezimal)',
        'Gültig       05.10.2026 – 05.10.2031',
        'Abgleich     Inhaber mit A-Trust geprüft',
        'Status       in Betrieb',
        '',
        'DEP          online gespeichert, jederzeit',
        '             exportierbar (USB-Stick, Link)',
        'Abschlüsse   Monatsbeleg automatisch am',
        '             Monatsersten um 00:05, der',
        '             Dezember-Beleg ist der Jahresbeleg',
        'Kontakt      hello@kasseneck.at',
      ]));
      expect(zeilen.last, 'Gedruckt 29.10.2026, 14:05');
    });

    test('fehlt ein Wert, fehlt die Zeile: ohne Angaben bleibt nur das DEP', () {
      final zeilen = inspectionInfoRows(const RegisterInspectionInfo());
      expect([for (final z in zeilen) z.toJson()], [
        {
          'key': 'dep',
          'section': 'operation',
          'label': 'DEP',
          'value': ['online gespeichert, jederzeit exportierbar (USB-Stick, Link)'],
        },
      ]);
    });

    test('Breite unter 24 wirft vor dem Rechnen; Datum und Uhrzeit bleiben zusammen', () {
      final info = _info(_fall('echte Karte von A-Trust, Breite 42')['info']);
      for (final breite in [23, 0, -1]) {
        expect(
          () => inspectionInfoLines(info, width: breite, printedAt: _gedruckt),
          throwsA(isA<KasseneckValidationError>()
              .having((e) => e.kind, 'kind', 'request')
              .having((e) => e.functionName, 'functionName', 'inspectionInfoLines')),
          reason: '$breite',
        );
      }
      final schmal = inspectionInfoLines(info, width: 24, printedAt: _gedruckt);
      expect(schmal.sublist(schmal.length - 2), ['Gedruckt', '29.10.2026, 14:05']);
    });

    test('die Druckzeit in Wiener Zeit, auch wenn das Geraet anders tickt', () {
      final info = _info(_fall('echte Karte von A-Trust, Breite 42')['info']);
      // 31.12.2026 23:30 UTC ist in Wien schon der 1. Jaenner.
      final zeilen = inspectionInfoLines(info, width: 42, printedAt: DateTime.utc(2026, 12, 31, 23, 30));
      expect(zeilen.last, 'Gedruckt 01.01.2027, 00:30');
    });

    test('Ueberschriften in Grossschrift ohne ß: Web und Dart schreiben sie gleich gross', () {
      expect(labelText('inspection.title').contains('ß'), isFalse);
      expect(labelText('inspection.signature').contains('ß'), isFalse);
    });
  });

  group('RegisterInspectionInfo.fromJson', () {
    test('Positivliste: falsche Typen fallen weg, unbekannter Stand wird null, Geheimes wird nicht gelesen', () {
      final info = _info({
        'cashregisterId': 7,
        'product': 'Kasseneck',
        'manufacturer': {'name': '', 'vatId': null},
        'signature': {
          'serialHex': 12,
          'testCard': 'ja',
          'status': 'recovering',
          'holderChecked': 'true',
          'der': 'MIIB',
          'pin': '123456',
        },
        'closings': {'monthlyDay': '1', 'monthlyTime': 5, 'annualIsDecember': 1},
        'contactEmail': '',
        'apiKey': 'kr_live_x',
      });
      expect(info.toJson(), {
        'manufacturer': <String, dynamic>{},
        'signature': {'testCard': false},
        'closings': <String, dynamic>{},
      });
      expect(_info({'signature': 'keine'}).toJson(), {'signature': null});
      expect(_info({'closings': {'monthlyDay': 0, 'monthlyTime': '00:05'}}).closings!.monthlyDay, isNull);
      expect(_info({'closings': {'monthlyDay': 1.5, 'monthlyTime': '00:05'}}).closings!.monthlyDay, isNull);
      // Wie Number.isInteger in npm: 15.0 ist eine ganze Zahl.
      expect(_info({'closings': {'monthlyDay': 15.0, 'monthlyTime': '06:30'}}).closings!.monthlyDay, 15);
    });

    test('ein unlesbarer Zeitpunkt laesst nur seine Angabe weg', () {
      final zeilen = inspectionInfoRows(_info({
        'signature': {
          'holderChecked': false,
          'validFrom': 'gestern',
          'validTo': '2031-10-05T08:00:00.000Z',
          'testCard': false,
          'status': 'outage',
          'outageSince': '2026-10-29',
        },
      }));
      expect([for (final z in zeilen) if (z.section == 'signature') [z.key, z.value]], [
        ['valid', ['bis 05.10.2031']],
        ['status', ['ausgefallen']],
      ]);
    });
  });

  group('am Kassenweg (RegisterReceiptClient)', () {
    test('getRegisterInspectionInfo: ein Aufruf mit der Kasse der Sitzung, Antwort ueber das Modell', () async {
      final daten = _fall('echte Karte von A-Trust, Breite 42')['info'] as Map<String, dynamic>;
      final (kasse, log) = _kasse({'status': 'success', 'message': '', 'data': daten});
      final info = await kasse.getRegisterInspectionInfo();
      expect(log.single.url.toString(), 'https://kasse.kasseneck.at/api/v3/getRegisterInspectionInfo');
      expect(jsonDecode(log.single.body), {
        'params': {'cashregisterId': 'KECK-1'},
      });
      expect(info.toJson(), daten);
    });

    test('zeroReceipt: nur receiptType zero, ein Fehler behaelt seinen Code', () async {
      final (kasse, log) = _kasse({
        'status': 'error',
        'message': 'Keine Berechtigung.',
        'code': 'not_permitted',
        'data': {'code': 'not_permitted'},
      });
      await expectLater(kasse.zeroReceipt(), throwsA(isA<KasseneckApiError>().having((e) => e.code, 'code', 'not_permitted')));
      expect(log.single.url.toString(), 'https://kasse.kasseneck.at/api/v3/createReceipt');
      expect(jsonDecode(log.single.body), {
        'params': {'cashregisterId': 'KECK-1', 'receiptType': 'zero'},
      });
    });

    test('zeroReceipt: Erfolg ohne Beleg ist response_unreadable, Ausgang unklar', () async {
      final (kasse, _) = _kasse({'status': 'success', 'message': '', 'data': {'receipt': 'kaputt'}});
      await expectLater(
        kasse.zeroReceipt(),
        throwsA(predicate((Object? e) => isOutcomeUnknown(e), 'Ausgang unklar')),
      );
    });
  });

  group('Woerter des Reiters „Pruefung“', () {
    test('genau dieser Text, ohne Rechtssprache beim DEP', () {
      expect(labelText('nav.inspection'), 'Prüfung');
      expect(labelText('inspection.part_inspector'), 'Für den Prüfer');
      expect(labelText('inspection.part_zero_receipt'), 'Nullbeleg');
      expect(labelText('inspection.print'), 'Kasseninfo drucken');
      expect(labelText('zero_receipt.create'), 'Nullbeleg erstellen');
      expect(labelText('zero_receipt.created', {'number': 'KECK-1-17', 'time': '14:05'}), 'Nullbeleg KECK-1-17 erstellt, 14:05');
      expect(messageText('inspection.print_question'), 'Kasseninfo für den Prüfer auch drucken?');
      expect(messageText('dep.manager_only'), 'Den Export macht der Chef.');
      expect(messageText('dep.offline'), 'Ohne Internet geht der Export nicht.');
    });
  });
}
