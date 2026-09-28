import 'dart:io';
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
      'vatId': 'ATU12345678',
      'taxNumber': '12/345',
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
      headers: {'content-type': 'application/json', 'kasseneck-api-version': 'v3'},
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
    const bar = KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 280, tenderedCents: 500);

    test('Positionen und Zahlungen gehen hinaus, der signierte Beleg kommt zurück', () async {
      final f = clientMit([{'status': 'success', 'data': huelleMitBeleg()}]);
      final beleg = await f.client.sell(items: [kaffee], payments: [bar]);

      expect(beleg.receiptId, 'KASSE1-ID-42');
      expect(beleg.companyName, 'Testbetrieb');
      expect(beleg.qr, isNotEmpty);

      final anfrage = f.log.single;
      expect(anfrage.url.toString(), endsWith('/createReceipt'));
      final params = jsonDecode(anfrage.body)['params'] as Map<String, dynamic>;
      expect(params['cashregisterId'], 'KASSE1');
      expect(params['receiptType'], 'standard');
      expect(params['payments'], [
        {'method': 'cash', 'amountCents': 280, 'tenderedCents': 500},
      ]);
      expect(params['items'], [
        {'name': 'Kaffee', 'quantity': 1, 'unitPriceCents': 280, 'vatRate': 20},
      ]);
    });

    test('nie die Einzelfelder aus 0.x: paymentMethod, creditCardProvider, cardPaymentId, cardPaymentData', () async {
      // Unter /v3 ist payments Pflicht; ein zusaetzliches paymentMethod waere
      // payment_method_not_supported.
      final f = clientMit([{'status': 'success', 'data': huelleMitBeleg()}]);
      await f.client.sell(items: [kaffee], payments: const [
        KeckPaymentInput(
          method: KeckPaymentMethod.creditCard,
          amountCents: 280,
          provider: CreditCardProvider.gpTomAndroid,
          providerPaymentId: 'tx-1',
          providerData: {'trasanctionID': 'tx-1'},
        ),
      ]);
      final params = jsonDecode(f.log.single.body)['params'] as Map<String, dynamic>;
      for (final alt in ['paymentMethod', 'creditCardProvider', 'cardPaymentId', 'cardPaymentData']) {
        expect(params.containsKey(alt), isFalse, reason: alt);
      }
      expect(params['payments'], [
        {
          'method': 'creditCard',
          'amountCents': 280,
          'provider': 'gpTomAndroid',
          'providerPaymentId': 'tx-1',
          'providerData': {'trasanctionID': 'tx-1'},
        },
      ]);
    });

    test('Quelltext-Waechter: der Verkauf der Kasse kennt keine 0.x-Zahlfelder mehr', () {
      final quelle = File('lib/src/kasse/belege.dart').readAsStringSync();
      final verkauf = quelle.substring(quelle.indexOf('Future<KasseneckReceipt> sell('),
          quelle.indexOf('Future<List<ReceiptSummary>> list('));
      for (final alt in ["'paymentMethod'", "'creditCardProvider'", "'cardPaymentId'", "'cardPaymentData'"]) {
        expect(verkauf, isNot(contains(alt)), reason: alt);
      }
    });

    test('ohne Positionen geht gar nichts hinaus', () async {
      // Ein leerer Verkauf ist kein Verkauf, und der Fehler soll fallen,
      // bevor irgendetwas in die Signaturkette gerät.
      final f = clientMit([{'status': 'success', 'data': huelleMitBeleg()}]);
      await expectLater(
        f.client.sell(items: const [], payments: [bar]),
        throwsA(isA<KasseneckValidationError>()),
      );
      expect(f.log, isEmpty);
    });

    test('eine ungueltige Zahlung (mixed, negativ) geht nicht hinaus', () async {
      final f = clientMit([{'status': 'success', 'data': huelleMitBeleg()}]);
      for (final z in const [
        KeckPaymentInput(method: KeckPaymentMethod.mixed, amountCents: 280),
        KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: -1),
      ]) {
        await expectLater(f.client.sell(items: [kaffee], payments: [z]),
            throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'request')));
      }
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
        client.sell(items: [kaffee], payments: [bar]),
        throwsA(isA<KasseneckHttpError>().having((e) => e.outcome, 'outcome', ErrorOutcome.unknown)),
      );
      expect(versuche, 1, reason: 'genau ein Aufruf, egal wie es ausgeht');
    });

    test('Trinkgeld und Kundendaten gehen mit, wenn sie da sind', () async {
      final f = clientMit([{'status': 'success', 'data': huelleMitBeleg()}]);
      await f.client.sell(
        items: [kaffee],
        payments: [bar],
        tipCents: 50,
        customerLines: const ['Firma Muster', 'Musterweg 3'],
      );

      final params = jsonDecode(f.log.single.body)['params'] as Map<String, dynamic>;
      expect(params['tip'], 50);
      expect(params['customerDetails'], 'Firma Muster\nMusterweg 3');
    });

    test('ohne Trinkgeld steht das Feld nicht im Rumpf', () async {
      final f = clientMit([{'status': 'success', 'data': huelleMitBeleg()}]);
      await f.client.sell(items: [kaffee], payments: [bar]);
      expect(jsonDecode(f.log.single.body)['params'], isNot(contains('tip')));
    });
  });

  group('Kartenanbieter am Verkauf', () {
    test('jeder Anbieter geht unter seinem Enum-Namen in der Zahlung hinaus', () async {
      // Der Name ist das Drahtformat; ohne ihn findet der Bon keinen Zweig
      // fuer den Kartenblock.
      for (final anbieter in CreditCardProvider.values) {
        final f = clientMit([{'status': 'success', 'data': huelleMitBeleg()}]);
        await f.client.sell(items: [kaffee], payments: [
          KeckPaymentInput(method: KeckPaymentMethod.creditCard, amountCents: 280, provider: anbieter, providerPaymentId: 'tx-1'),
        ]);
        final params = jsonDecode(f.log.single.body)['params'] as Map<String, dynamic>;
        expect((params['payments'] as List).single['provider'], anbieter.name, reason: '$anbieter');
      }
    });

    test('der Anbieter geht auch ohne Kennung mit', () async {
      // Ein eigenes Terminal meldet keine Transaktionskennung. Der Verkauf
      // scheitert daran NICHT: das Geld ist geflossen.
      final f = clientMit([{'status': 'success', 'data': huelleMitBeleg()}]);
      await f.client.sell(items: [kaffee], payments: const [
        KeckPaymentInput(method: KeckPaymentMethod.creditCard, amountCents: 280, provider: CreditCardProvider.custom),
      ]);
      final zahlung = (jsonDecode(f.log.single.body)['params']['payments'] as List).single as Map;
      expect(zahlung['provider'], 'custom');
      expect(zahlung, isNot(contains('providerPaymentId')));
    });
  });

  group('auflisten', () {
    test('die Kasse geht als cashregisterId hinaus (unter /v3 wie ueberall)', () async {
      // So heisst der Pflichtparameter dieses Endpunkts unter /v3; das alte
      // `cashregisterid` weist der Server dort als unbekanntes Feld ab.
      final f = clientMit([
        {'status': 'success', 'data': {'receipts': []}},
      ]);
      await f.client.list(from: '2026-08-19', to: '2026-08-19', limit: 20);

      final params = jsonDecode(f.log.single.body)['params'] as Map<String, dynamic>;
      expect(params['cashregisterId'], 'KASSE1');
      expect(params.containsKey('cashregisterid'), isFalse);
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
                'cancellationStatus': 'none',
              },
            ],
          },
        },
      ]);
      final liste = await f.client.list();

      expect(liste, hasLength(1));
      final b = liste.single;
      expect(b.receiptId, 'KASSE1-ID-42');
      // Das Backend liefert Euro; die Kasse rechnet in Cent — sonst schleicht
      // sich der Fliesskomma-Fehler bis in die Tagessumme.
      expect(b.totalCents, 280);
      expect(b.operator?.name, 'Ali');
      expect(b.isSale, isTrue);
      expect(b.isCancellation, isFalse);
      expect(b.cancellationState, CancellationState.none);
    });

    test('fehlende Liste ist ein Antwortfehler, keine leere Liste', () async {
      final f = clientMit([{'status': 'success', 'data': {}}]);
      await expectLater(f.client.list(), throwsA(isA<KasseneckValidationError>()));
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
                'cancellationStatus': 'none',
              },
            ],
          },
        },
      ]);
      final b = (await f.client.list()).single;
      expect(b.isCancellation, isTrue);
      expect(b.isSale, isFalse);
      expect(b.totalCents, -280);
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
      final ergebnis = await f.client.cancel(originalReceiptId: 'KASSE1-ID-42', reason: 'input_error');

      expect(ergebnis.receipt.receiptId, 'KASSE1-ID-43');
      expect(ergebnis.originalReceiptId, 'KASSE1-ID-42');
      expect(ergebnis.remaining, [0]);

      final params = jsonDecode(f.log.single.body)['params'] as Map<String, dynamic>;
      expect(params['originalReceiptId'], 'KASSE1-ID-42');
      expect(params['reason'], 'input_error');
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
      await f.client.cancel(
        originalReceiptId: 'KASSE1-ID-42',
        reason: 'duplicate',
        items: const [(index: 0, quantity: 1)],
        note: 'Gast hat zurückgegeben',
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
        f.client.cancel(originalReceiptId: 'KASSE1-ID-42', reason: '  '),
        throwsA(isA<KasseneckValidationError>()),
      );
      expect(f.log, isEmpty);
    });

    test('eine Storno-Menge unter 1 geht nicht hinaus', () async {
      final f = clientMit([{'status': 'success', 'data': {}}]);
      await expectLater(
        f.client.cancel(
          originalReceiptId: 'KASSE1-ID-42',
          reason: 'retoure',
          items: const [(index: 0, quantity: 0)],
        ),
        throwsA(isA<KasseneckValidationError>()),
      );
      expect(f.log, isEmpty);
    });

    test('eine leere Positionsliste ist kein Vollstorno, sondern ein Fehler', () async {
      // Sonst wuerde aus einem missglueckten Teilstorno still ein Vollstorno.
      final f = clientMit([{'status': 'success', 'data': {}}]);
      await expectLater(
        f.client.cancel(originalReceiptId: 'KASSE1-ID-42', reason: 'retoure', items: const []),
        throwsA(isA<KasseneckValidationError>()),
      );
      expect(f.log, isEmpty);
    });

    test('fehlender Bezug in der Antwort ist response_unreadable mit Ausgang unklar', () async {
      final f = clientMit([
        {'status': 'success', 'data': {...huelleMitBeleg(), 'remaining': [0]}},
      ]);
      await expectLater(
        f.client.cancel(originalReceiptId: 'KASSE1-ID-42', reason: 'input_error'),
        throwsA(isA<KasseneckApiError>()
            .having((e) => e.code, 'code', 'response_unreadable')
            .having((e) => e.outcome, 'outcome', ErrorOutcome.unknown)),
      );
    });

    test('ein unbekannter oder alter deutscher Grund geht nicht hinaus', () async {
      for (final grund in ['retoure', 'fehleingabe']) {
        final f = clientMit([{'status': 'success', 'data': {}}]);
        await expectLater(
          f.client.cancel(originalReceiptId: 'KASSE1-ID-42', reason: grund),
          throwsA(isA<KasseneckValidationError>()),
        );
        expect(f.log, isEmpty, reason: grund);
      }
    });

    test('kaputte Antwort verliert den signierten Storno-Beleg nicht: die Kennung faehrt mit', () async {
      // Der Storno-Beleg ist zu diesem Zeitpunkt ausgestellt, signiert und in
      // der Kette — RKSV schreibt ihn vor. Ohne die Kennung kaeme der Aufrufer
      // nicht mehr an ihn heran: weder drucken noch nachholen, und ein zweiter
      // Storno waere eine zweite Ruecknahme.
      for (final kaputt in [
        {...huelleMitBeleg(receiptId: 'KASSE1-ID-43'), 'remaining': [0]},
        {...huelleMitBeleg(receiptId: 'KASSE1-ID-43'), 'cancellationOf': {'receiptId': 'KASSE1-ID-42'}},
        {
          ...huelleMitBeleg(receiptId: 'KASSE1-ID-43'),
          'cancellationOf': {'receiptId': 'KASSE1-ID-42'},
          'remaining': [1.0],
        },
      ]) {
        final f = clientMit([{'status': 'success', 'data': kaputt}]);
        await expectLater(
          f.client.cancel(originalReceiptId: 'KASSE1-ID-42', reason: 'input_error'),
          throwsA(isA<KasseneckApiError>()
              .having((e) => e.code, 'code', 'response_unreadable')
              .having((e) => isOutcomeUnknown(e), 'unklar', isTrue)
              .having((e) => e.details['receiptId'], 'receiptId', 'KASSE1-ID-43')),
          reason: '$kaputt',
        );
      }
    });
  });

  group('Kacheldaten laden', () {
    test('Gruppen und Artikel kommen gelesen zurück', () async {
      final f = clientMit([
        {
          'status': 'success',
          'data': {
            'groups': [
              {'id': 'g1', 'name': 'Getränke', 'color': '#1B46F5', 'sort': 0},
            ],
          },
        },
      ]);
      final gruppen = await f.client.articleGroups();

      expect(gruppen.single.name, 'Getränke');
      expect(f.log.single.url.toString(), endsWith('/listMyArticleGroups'));
    });

    test('eine fehlende Liste ist ein Antwortfehler, keine leere Liste', () async {
      final f = clientMit([{'status': 'success', 'data': {}}]);
      await expectLater(f.client.articles(), throwsA(isA<KasseneckValidationError>()));
    });
  });

  group('Trinkgeld-Empfaenger laden', () {
    test('ruft listMyTipRecipients und liest data.recipients', () async {
      final f = clientMit([
        {
          'status': 'success',
          'data': {
            'recipients': [
              {'registerUserId': 'ru_1', 'name': 'Anna', 'owner': false},
              {'registerUserId': 'ru_2', 'name': 'Chef', 'owner': true},
            ],
          },
        },
      ]);
      final personen = await f.client.tipRecipients();

      expect(f.log.single.url.toString(), endsWith('/listMyTipRecipients'));
      expect(personen.map((p) => p.registerUserId), ['ru_1', 'ru_2']);
      expect(personen.first.name, 'Anna');
      // Am Flag haengt die Bezeichnung am Beleg — „Trinkgeld Personal"
      // (durchlaufender Posten) gegen „Trinkgeld" (Entgelt des Betriebs).
      expect(personen.first.owner, isFalse);
      expect(personen.last.owner, isTrue);
    });

    test('aus der Liste laesst sich der Anteil bauen, ohne die Kennung abzutippen', () async {
      final f = clientMit([
        {
          'status': 'success',
          'data': {
            'recipients': [
              {'registerUserId': 'ru_1', 'name': 'Anna', 'owner': false},
            ],
          },
        },
      ]);
      final anteil = (await f.client.tipRecipients()).single.share(cents: 500);

      expect(anteil.registerUserId, 'ru_1');
      expect(anteil.cents, 500);
    });

    test('eine fehlende Liste ist ein Antwortfehler, keine leere Liste', () async {
      final f = clientMit([{'status': 'success', 'data': {}}]);
      await expectLater(f.client.tipRecipients(), throwsA(isA<KasseneckValidationError>()));
    });
  });

  group('einzelnen Beleg holen', () {
    test('holt Beleg samt Firmendaten', () async {
      final f = clientMit([{'status': 'success', 'data': huelleMitBeleg()}]);
      final beleg = await f.client.get('KASSE1-ID-42');

      expect(beleg.receiptId, 'KASSE1-ID-42');
      expect(f.log.single.url.toString(), endsWith('/getReceipt'));
      expect(jsonDecode(f.log.single.body)['params']['receiptId'], 'KASSE1-ID-42');
    });
  });

  // Ruling F3 am Kassenweg: Erfolg gemeldet, Antwort unlesbar heisst, der
  // Beleg ist signiert. Das ist `response_unreadable` mit Ausgang unklar und
  // der Kennung, sofern die Antwort sie trug; nie ein gewoehnlicher Fehler,
  // der die Kasse ein zweites Mal verkaufen oder stornieren liesse.
  group('signiert, aber unlesbar', () {
    Matcher unlesbar(String name, Object? kennung) => isA<KasseneckApiError>()
        .having((e) => e.functionName, 'functionName', name)
        .having((e) => e.code, 'code', 'response_unreadable')
        .having((e) => isOutcomeUnknown(e), 'isOutcomeUnknown', isTrue)
        .having((e) => e.details['receiptId'], 'receiptId', kennung);

    Map<String, dynamic> ohneZeit() {
      final h = huelleMitBeleg(receiptId: 'KASSE1-ID-44');
      (h['receipt'] as Map).remove('timeStamp');
      return h;
    }

    test('verkaufen: kaputter Beleg mit Kennung, Beleg fehlt, data kein Objekt; je genau ein Aufruf', () async {
      for (final (data, kennung) in <(Object?, Object?)>[
        (ohneZeit(), 'KASSE1-ID-44'),
        (<String, dynamic>{'company': 'Testbetrieb'}, null),
        (<dynamic>[], null),
        ('ja', null),
      ]) {
        final f = clientMit([{'status': 'success', 'data': data}]);
        await expectLater(
          f.client.sell(items: [kaffee], payments: const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 280)]),
          throwsA(unlesbar('createReceipt', kennung)),
          reason: jsonEncode(data),
        );
        expect(f.log, hasLength(1), reason: jsonEncode(data));
      }
    });

    test('stornieren: data kein Objekt ist ebenfalls response_unreadable', () async {
      for (final data in <Object>[<dynamic>[], 'ja']) {
        final f = clientMit([{'status': 'success', 'data': data}]);
        await expectLater(
          f.client.cancel(originalReceiptId: 'KASSE1-ID-42', reason: 'input_error'),
          throwsA(unlesbar('cancelReceipt', null)),
        );
        expect(f.log, hasLength(1));
      }
    });

    test('lesende Aufrufe bleiben beim alten Fehler (holen: data kein Objekt)', () async {
      final f = clientMit([{'status': 'success', 'data': <dynamic>[]}]);
      await expectLater(
        f.client.get('KASSE1-ID-42'),
        throwsA(isA<KasseneckHttpError>().having((e) => e.reason, 'reason', 'data-not-object')),
      );
    });

    test('stornieren: original muss der Beleg originalReceiptId sein, sonst geht nichts hinaus', () async {
      final f = clientMit([{'status': 'success', 'data': {}}]);
      final original = KasseneckReceipt.fromJson(huelleMitBeleg(receiptId: 'KASSE1-ID-41'));
      await expectLater(
        f.client.cancel(originalReceiptId: 'KASSE1-ID-42', reason: 'input_error', original: original),
        throwsA(isA<KasseneckValidationError>().having((e) => e.kind, 'kind', 'request')),
      );
      expect(f.log, isEmpty);
    });
  });
}
