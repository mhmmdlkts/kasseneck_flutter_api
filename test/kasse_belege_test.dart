import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/kasse.dart';
import 'package:kasseneck_api/register.dart';

/// Die Belegaufrufe der Kasse: verkaufen, auflisten, stornieren.
///
/// Der Verkauf ist der einzige Aufruf der ganzen App, der **nicht folgenlos
/// wiederholbar** ist — ein zweiter wäre ein zweiter Umsatz.

/// Die Firmen-/Belegdaten, wie sie das Backend neben dem Beleg liefert.
Map<String, dynamic> huelleMitBeleg({
  String receiptId = 'KASSE1-ID-42',
  String receiptType = 'standard',
  List<Map<String, dynamic>>? items,
}) =>
    {
      'receipt': {
        'receiptId': receiptId,
        'fullReceiptId': 'voll-42',
        'receiptType': receiptType,
        'cashregisterId': 'KASSE1',
        'timeStamp': '2026-08-19T10:15:00',
        'paymentMethod': 'cash',
        'items': items ?? [
              {'name': 'Kaffee', 'quantity': 1, 'unitPriceCents': 280, 'vatRate': 20},
            ],
        'qr': '_R1-AT1_KASSE1_...',
        'sig': 'sig',
        'certificateSerialNumber': 'cert',
        'signaturePreviousReceipt': 'prev',
        'turnoverCounterAES256ICM': 'aes',
        'signatureSuccess': true,
      },
      'company': 'Testbetrieb',
      'is_small_business': false,
      'uid': 'ATU12345678',
      'taxnr': '12/345',
      'phone': '+43 1 234',
      'street': 'Teststrasse 1',
      'zip': '1010',
      'city': 'Wien',
      'footer1': 'Danke',
      'footer2': '',
      'thanks_message': 'Auf Wiedersehen',
    };

({RegisterReceiptClient client, List<http.Request> log}) clientMit(List<Object> antworten) {
  final log = <http.Request>[];
  var i = 0;
  final mock = MockClient((request) async {
    log.add(request);
    final antwort = antworten[i < antworten.length ? i : antworten.length - 1];
    i += 1;
    return http.Response(
      antwort is String ? antwort : jsonEncode(antwort),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  return (
    client: RegisterReceiptClient(
      RegisterTransport(
        idToken: () async => 'id-token-1',
        sessionId: () async => 'sess-1',
        cashregisterId: 'KASSE1',
        httpClient: mock,
      ),
    ),
    log: log,
  );
}

final kaffee = KasseneckItem(name: 'Kaffee', quantity: 1, priceCents: 280, vat: VatRate.vat20);

void main() {
  group('verkaufen', () {
    test('Positionen und Zahlungsart gehen hinaus, der signierte Beleg kommt zurück', () async {
      final f = clientMit([{'status': 'success', 'data': huelleMitBeleg()}]);
      final beleg = await f.client.verkaufen(positionen: [kaffee], zahlungsart: KeckPaymentMethod.cash);

      expect(beleg.receiptId, 'KASSE1-ID-42');
      expect(beleg.companyName, 'Testbetrieb');
      expect(beleg.qr, isNotEmpty);

      final anfrage = f.log.single;
      expect(anfrage.url.toString(), endsWith('/createReceipt'));
      final params = jsonDecode(anfrage.body)['params'] as Map<String, dynamic>;
      expect(params['cashregisterId'], 'KASSE1');
      expect(params['receiptType'], 'standard');
      expect(params['paymentMethod'], 'cash');
      expect(params['items'], [
        {'name': 'Kaffee', 'quantity': 1, 'unitPriceCents': 280, 'vatRate': 20},
      ]);
    });

    test('ohne Positionen geht gar nichts hinaus', () async {
      // Ein leerer Verkauf ist kein Verkauf — und der Fehler soll fallen,
      // bevor irgendetwas in die Signaturkette gerät.
      final f = clientMit([{'status': 'success', 'data': huelleMitBeleg()}]);
      await expectLater(
        f.client.verkaufen(positionen: const [], zahlungsart: KeckPaymentMethod.cash),
        throwsA(isA<KasseneckValidationError>()),
      );
      expect(f.log, isEmpty);
    });

    test('ein Netzfehler wird NICHT wiederholt', () async {
      // Der Beleg kann laengst signiert sein, auch wenn die Antwort nie ankam.
      var versuche = 0;
      final client = RegisterReceiptClient(
        RegisterTransport(
          idToken: () async => 'id-token-1',
          sessionId: () async => 'sess-1',
          cashregisterId: 'KASSE1',
          httpClient: MockClient((r) async {
            versuche += 1;
            throw http.ClientException('Netz weg');
          }),
        ),
      );

      await expectLater(
        client.verkaufen(positionen: [kaffee], zahlungsart: KeckPaymentMethod.cash),
        throwsA(isA<KasseneckHttpError>()),
      );
      expect(versuche, 1, reason: 'genau ein Aufruf, egal wie es ausgeht');
    });

    test('Trinkgeld und Kundendaten gehen mit, wenn sie da sind', () async {
      final f = clientMit([{'status': 'success', 'data': huelleMitBeleg()}]);
      await f.client.verkaufen(
        positionen: [kaffee],
        zahlungsart: KeckPaymentMethod.cash,
        trinkgeldCents: 50,
        kundendaten: const ['Firma Muster', 'Musterweg 3'],
      );

      final params = jsonDecode(f.log.single.body)['params'] as Map<String, dynamic>;
      expect(params['tip'], 50);
      expect(params['customerDetails'], 'Firma Muster\nMusterweg 3');
    });

    test('ohne Trinkgeld steht das Feld nicht im Rumpf', () async {
      final f = clientMit([{'status': 'success', 'data': huelleMitBeleg()}]);
      await f.client.verkaufen(positionen: [kaffee], zahlungsart: KeckPaymentMethod.cash);
      expect(jsonDecode(f.log.single.body)['params'], isNot(contains('tip')));
    });
  });

  group('auflisten', () {
    test('die Kasse geht als cashregisterid hinaus — klein geschrieben', () async {
      // So heisst der Pflichtparameter dieses Endpunkts im Backend; ein
      // Tippfehler faellt sonst erst im Betrieb auf.
      final f = clientMit([
        {'status': 'success', 'data': {'receipts': []}},
      ]);
      await f.client.auflisten(von: '2026-08-19', bis: '2026-08-19', hoechstens: 20);

      final params = jsonDecode(f.log.single.body)['params'] as Map<String, dynamic>;
      expect(params['cashregisterid'], 'KASSE1');
      expect(params['from'], '2026-08-19');
      expect(params['to'], '2026-08-19');
      expect(params['limit'], 20);
    });

    test('Zusammenfassungen kommen gelesen zurück, Summe in Cent', () async {
      final f = clientMit([
        {
          'status': 'success',
          'data': {
            'receipts': [
              {
                'receiptId': 'KASSE1-ID-42',
                'receiptType': 'standard',
                'timeStamp': '2026-08-19T10:15:00',
                'total': 2.8,
                'paymentMethod': 'cash',
                'signature_ok': true,
                'items': [
                  {'name': 'Kaffee', 'quantity': 1},
                ],
                'operator': {'uid': 'u1', 'name': 'Ali'},
                'stornoStand': 'offen',
              },
            ],
          },
        },
      ]);
      final liste = await f.client.auflisten();

      expect(liste, hasLength(1));
      final b = liste.single;
      expect(b.receiptId, 'KASSE1-ID-42');
      // Das Backend liefert Euro; die Kasse rechnet in Cent — sonst schleicht
      // sich der Fliesskomma-Fehler bis in die Tagessumme.
      expect(b.summeCents, 280);
      expect(b.bediener?.name, 'Ali');
      expect(b.istVerkauf, isTrue);
      expect(b.istStorno, isFalse);
      expect(b.stornoStand, StornoStand.offen);
    });

    test('fehlende Liste ist ein Antwortfehler, keine leere Liste', () async {
      final f = clientMit([{'status': 'success', 'data': {}}]);
      await expectLater(f.client.auflisten(), throwsA(isA<KasseneckValidationError>()));
    });

    test('ein Storno-Beleg ist als solcher erkennbar', () async {
      final f = clientMit([
        {
          'status': 'success',
          'data': {
            'receipts': [
              {
                'receiptId': 'KASSE1-ID-43',
                'receiptType': 'cancellation',
                'timeStamp': '2026-08-19T10:20:00',
                'total': -2.8,
                'paymentMethod': 'cash',
                'cancellationOf': {'receiptId': 'KASSE1-ID-42'},
                'stornoStand': 'offen',
              },
            ],
          },
        },
      ]);
      final b = (await f.client.auflisten()).single;
      expect(b.istStorno, isTrue);
      expect(b.istVerkauf, isFalse);
      expect(b.summeCents, -280);
    });
  });

  group('stornieren', () {
    test('Vollstorno: Original und Grund gehen hinaus, Restmengen kommen zurück', () async {
      final f = clientMit([
        {
          'status': 'success',
          'data': {
            ...huelleMitBeleg(receiptId: 'KASSE1-ID-43', receiptType: 'cancellation'),
            'cancellationOf': {'receiptId': 'KASSE1-ID-42', 'fullReceiptId': 'voll-42'},
            'remaining': [0],
          },
        },
      ]);
      final ergebnis = await f.client.stornieren(originalReceiptId: 'KASSE1-ID-42', grund: 'fehleingabe');

      expect(ergebnis.beleg.receiptId, 'KASSE1-ID-43');
      expect(ergebnis.originalReceiptId, 'KASSE1-ID-42');
      expect(ergebnis.restmengen, [0]);

      final params = jsonDecode(f.log.single.body)['params'] as Map<String, dynamic>;
      expect(params['originalReceiptId'], 'KASSE1-ID-42');
      expect(params['reason'], 'fehleingabe');
      expect(params, isNot(contains('items')), reason: 'ohne Positionen ist es ein Vollstorno');
    });

    test('Teilstorno nennt Position und Menge', () async {
      final f = clientMit([
        {
          'status': 'success',
          'data': {
            ...huelleMitBeleg(receiptId: 'KASSE1-ID-43', receiptType: 'cancellation'),
            'cancellationOf': {'receiptId': 'KASSE1-ID-42'},
            'remaining': [1, 0],
          },
        },
      ]);
      await f.client.stornieren(
        originalReceiptId: 'KASSE1-ID-42',
        grund: 'retoure',
        positionen: const [(index: 0, menge: 1)],
        anmerkung: 'Gast hat zurückgegeben',
      );

      final params = jsonDecode(f.log.single.body)['params'] as Map<String, dynamic>;
      expect(params['items'], [
        {'index': 0, 'quantity': 1},
      ]);
      expect(params['note'], 'Gast hat zurückgegeben');
    });

    test('ohne Grund geht nichts hinaus', () async {
      final f = clientMit([{'status': 'success', 'data': {}}]);
      await expectLater(
        f.client.stornieren(originalReceiptId: 'KASSE1-ID-42', grund: '  '),
        throwsA(isA<KasseneckValidationError>()),
      );
      expect(f.log, isEmpty);
    });

    test('eine Storno-Menge unter 1 geht nicht hinaus', () async {
      final f = clientMit([{'status': 'success', 'data': {}}]);
      await expectLater(
        f.client.stornieren(
          originalReceiptId: 'KASSE1-ID-42',
          grund: 'retoure',
          positionen: const [(index: 0, menge: 0)],
        ),
        throwsA(isA<KasseneckValidationError>()),
      );
      expect(f.log, isEmpty);
    });

    test('eine leere Positionsliste ist kein Vollstorno, sondern ein Fehler', () async {
      // Sonst wuerde aus einem missglueckten Teilstorno still ein Vollstorno.
      final f = clientMit([{'status': 'success', 'data': {}}]);
      await expectLater(
        f.client.stornieren(originalReceiptId: 'KASSE1-ID-42', grund: 'retoure', positionen: const []),
        throwsA(isA<KasseneckValidationError>()),
      );
      expect(f.log, isEmpty);
    });

    test('fehlender Bezug in der Antwort ist ein Fehler', () async {
      final f = clientMit([
        {'status': 'success', 'data': {...huelleMitBeleg(), 'remaining': [0]}},
      ]);
      await expectLater(
        f.client.stornieren(originalReceiptId: 'KASSE1-ID-42', grund: 'fehleingabe'),
        throwsA(isA<KasseneckValidationError>()),
      );
    });
  });

  group('einzelnen Beleg holen', () {
    test('holt Beleg samt Firmendaten', () async {
      final f = clientMit([{'status': 'success', 'data': huelleMitBeleg()}]);
      final beleg = await f.client.holen('KASSE1-ID-42');

      expect(beleg.receiptId, 'KASSE1-ID-42');
      expect(f.log.single.url.toString(), endsWith('/getReceipt'));
      expect(jsonDecode(f.log.single.body)['params']['receiptId'], 'KASSE1-ID-42');
    });
  });
}
