import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/enums/voucher_action.dart';
import 'package:kasseneck_api/enums/voucher_type.dart';
import 'package:kasseneck_api/kasseneck_api.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/models/keck_voucher.dart';
import 'package:kasseneck_api/services/logo_service.dart';
import 'package:kasseneck_api/services/vienna_time.dart';

import 'helpers/test_receipts.dart';

KasseneckApi apiWith(MockClient client) => KasseneckApi(
      apiKey: 'test-key',
      cashregisterToken: base64Encode(utf8.encode('CASHBOX-9:secret')),
      httpClient: client,
    );

MockClient successClient(void Function(http.Request) capture) => MockClient((request) async {
      capture(request);
      return http.Response(
        jsonEncode({'status': 'success', 'data': buildReceipt().toJson()}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

/// Darf nie aufgerufen werden — fuer Tests, die VOR dem HTTP-Call scheitern muessen.
MockClient neverCalled() => MockClient((request) async {
      fail('HTTP-Request darf hier nicht passieren: ${request.url}');
    });

final validItem = KasseneckItem(name: 'x', quantity: 1, vat: VatRate.vat20, priceCents: 100);

void main() {
  group('Request-Anatomie', () {
    test('Header, Endpoint und Body-Struktur', () async {
      late http.Request captured;
      final api = apiWith(successClient((r) => captured = r));

      await api.sellReceipt(paymentMethod: KeckPaymentMethod.cash, items: [validItem]);

      expect(captured.url.toString(), 'https://api.kasseneck.at/v1/createReceipt');
      expect(captured.headers['Authorization'], 'Bearer test-key');
      expect(captured.headers['cashregister-token'], base64Encode(utf8.encode('CASHBOX-9:secret')));
      expect(captured.headers['content-type'], startsWith('application/json'));

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body.keys, ['params']);
      final params = body['params'] as Map<String, dynamic>;
      expect(params['receiptType'], 'standard');
      expect(params['paymentMethod'], 'cash');
      final item = (params['items'] as List).first as Map<String, dynamic>;
      expect(item['quantity'], 1);
      expect(item['unitPriceCents'], 100); // v2: ganze Cent (Integer)
      expect(item['vatRate'], 20);
    });

    test('sellReceipt parst die Antwort zu einem Beleg', () async {
      final api = apiWith(successClient((_) {}));
      final receipt = await api.sellReceipt(paymentMethod: KeckPaymentMethod.cash, items: [validItem]);
      expect(receipt, isNotNull);
      expect(receipt!.receiptId, 'TEST-ID-1');
    });
  });

  group('Fehlerpfade', () {
    test('status error -> Exception mit Backend-Message', () async {
      final api = apiWith(MockClient((_) async =>
          http.Response(jsonEncode({'status': 'error', 'message': 'Kasse gesperrt'}), 200)));
      expect(
        () => api.sellReceipt(paymentMethod: KeckPaymentMethod.cash, items: [validItem]),
        throwsA(predicate((e) => e.toString().contains('Kasse gesperrt'))),
      );
    });
    test('HTTP 500 -> Exception mit Statuscode', () async {
      final api = apiWith(MockClient((_) async => http.Response('kaputt', 500)));
      expect(
        () => api.sellReceipt(paymentMethod: KeckPaymentMethod.cash, items: [validItem]),
        throwsA(predicate((e) => e.toString().contains('500'))),
      );
    });
    test('leerer Body -> Exception', () async {
      final api = apiWith(MockClient((_) async => http.Response('', 200)));
      expect(
        () => api.sellReceipt(paymentMethod: KeckPaymentMethod.cash, items: [validItem]),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('sellReceipt-Validierung (wirft VOR dem HTTP-Call)', () {
    test('standard ohne Items -> ArgumentError', () {
      final api = apiWith(neverCalled());
      expect(() => api.sellReceipt(paymentMethod: KeckPaymentMethod.cash, items: []),
          throwsArgumentError);
      expect(() => api.sellReceipt(paymentMethod: KeckPaymentMethod.cash),
          throwsArgumentError);
    });
    test('ungueltiges Item (leerer Name) -> ArgumentError', () {
      final api = apiWith(neverCalled());
      final bad = KasseneckItem(name: '', quantity: 1, vat: VatRate.vat20, priceCents: 1);
      expect(() => api.sellReceipt(paymentMethod: KeckPaymentMethod.cash, items: [bad]),
          throwsArgumentError);
    });
    test('ungueltiger Voucher -> ArgumentError', () {
      final api = apiWith(neverCalled());
      final bad = KeckVoucher(action: VoucherAction.sell, type: VoucherType.value, valueCents: 0);
      expect(
        () => api.sellReceipt(paymentMethod: KeckPaymentMethod.cash, items: [validItem], vouchers: [bad]),
        throwsArgumentError,
      );
    });
    test('NUR Sell-Voucher ohne Items ist erlaubt (geht bis zum HTTP-Call)', () async {
      final api = apiWith(successClient((_) {}));
      final voucher = KeckVoucher(action: VoucherAction.sell, type: VoucherType.value, valueCents: 1000);
      final receipt = await api.sellReceipt(paymentMethod: KeckPaymentMethod.cash, vouchers: [voucher]);
      expect(receipt, isNotNull);
    });
  });

  group('checkVoucherCombinationError-Vollmatrix', () {
    final api = apiWith(neverCalled());
    KeckVoucher promoRedeem() => KeckVoucher(action: VoucherAction.redeem, type: VoucherType.promo, valueCents: 100);
    KeckVoucher promoSell() => KeckVoucher(action: VoucherAction.sell, type: VoucherType.promo, valueCents: 100);
    KeckVoucher valueRedeem() => KeckVoucher(action: VoucherAction.redeem, type: VoucherType.value, valueCents: 100);
    KeckVoucher valueSell() => KeckVoucher(action: VoucherAction.sell, type: VoucherType.value, valueCents: 100);

    test('Promo darf nicht verkauft werden', () {
      expect(api.checkVoucherCombinationError([promoSell()], [validItem]), contains('nicht verkauft'));
    });
    test('nur EIN Promo einloesbar', () {
      expect(api.checkVoucherCombinationError([promoRedeem(), promoRedeem()], [validItem]),
          contains('nur ein Gutschein'));
    });
    test('Promo nicht mit anderen Einloesungen kombinierbar', () {
      expect(api.checkVoucherCombinationError([promoRedeem(), valueRedeem()], [validItem]),
          contains('nicht mit anderen Gutscheinen kombiniert'));
    });
    test('Promo nicht mit Gutschein-Verkauf kombinierbar', () {
      expect(api.checkVoucherCombinationError([promoRedeem(), valueSell()], [validItem]),
          contains('nicht andere Gutscheine verkauft'));
    });
    test('Einloesung braucht mindestens ein Item', () {
      expect(api.checkVoucherCombinationError([valueRedeem()], []), contains('mindestens ein item'));
    });
    test('gueltige Kombinationen -> null', () {
      expect(api.checkVoucherCombinationError([promoRedeem()], [validItem]), isNull);
      expect(api.checkVoucherCombinationError([valueRedeem(), valueSell()], [validItem]), isNull);
      expect(api.checkVoucherCombinationError([valueSell()], []), isNull);
    });
  });

  group('Weitere API-Helfer', () {
    test('cancelReceipt negiert die Items des Originals', () async {
      late http.Request captured;
      final api = apiWith(successClient((r) => captured = r));
      final original = cartA();
      await api.cancelReceipt(receipt: original);

      final params = (jsonDecode(captured.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;
      expect(params['receiptType'], 'cancellation');
      final cents = (params['items'] as List).map((i) => i['unitPriceCents'] as int).toList();
      expect(cents, [-1999, -29, -105]);
    });
    test('zeroReceipt sendet keine Items', () async {
      late http.Request captured;
      final api = apiWith(successClient((r) => captured = r));
      await api.zeroReceipt();
      final params = (jsonDecode(captured.body) as Map<String, dynamic>)['params'] as Map<String, dynamic>;
      expect(params['receiptType'], 'zero');
      expect(params.containsKey('items'), isFalse);
    });
    test('getReceipts: start nach end -> ArgumentError', () {
      final api = apiWith(neverCalled());
      expect(() => api.getReceipts(DateTime(2026, 6, 2), DateTime(2026, 6, 1)), throwsArgumentError);
    });
    test('cashregisterId dekodiert den Token', () {
      final api = apiWith(neverCalled());
      expect(api.cashregisterId, 'CASHBOX-9');
    });
    group('listTipRecipients', () {
      MockClient empfaengerClient(void Function(http.Request) capture, Object daten) =>
          MockClient((request) async {
            capture(request);
            return http.Response(
              jsonEncode({'status': 'success', 'data': daten}),
              200,
              headers: {'content-type': 'application/json'},
            );
          });

      test('ruft listMyTipRecipients und liest data.recipients', () async {
        late http.Request captured;
        final api = apiWith(empfaengerClient((r) => captured = r, {
          'recipients': [
            {'registerUserId': 'ru_1', 'name': 'Anna', 'owner': false},
            {'registerUserId': 'ru_2', 'name': 'Chef', 'owner': true},
          ],
        }));

        final personen = await api.listTipRecipients();

        expect(captured.url.toString(), 'https://api.kasseneck.at/v1/listMyTipRecipients');
        expect(captured.headers['Authorization'], 'Bearer test-key');
        expect(personen.map((p) => p.registerUserId), ['ru_1', 'ru_2']);
        expect(personen.first.name, 'Anna');
        // Am Flag haengt die steuerliche Behandlung; es darf nicht verloren gehen.
        expect(personen.first.owner, isFalse);
        expect(personen.last.owner, isTrue);
      });

      test('aus der Liste laesst sich der Anteil bauen', () async {
        final api = apiWith(empfaengerClient((_) {}, {
          'recipients': [
            {'registerUserId': 'ru_1', 'name': 'Anna', 'owner': false},
          ],
        }));

        final anteil = (await api.listTipRecipients()).single.mit(cents: 500);

        expect(anteil.registerUserId, 'ru_1');
        expect(anteil.cents, 500);
      });

      test('fehlende Liste -> Exception, keine leere Liste', () async {
        final api = apiWith(empfaengerClient((_) {}, <String, dynamic>{}));
        await expectLater(api.listTipRecipients(), throwsA(isA<Exception>()));
      });
    });
    test('newHobexTransactionId: 19 Zeichen, rein numerisch', () {
      final id = KasseneckApi.newHobexTransactionId();
      expect(id.length, 19);
      expect(RegExp(r'^\d+$').hasMatch(id), isTrue);
    });
    // Der Aufruf ohne Parameter wuerfelte bisher: nur wenn die Mikrosekunden
    // zufaellig 0 waren, liess Dart sie in toString() weg und der Zuschnitt
    // stuerzte ab (RangeError). Die folgenden Faelle treffen genau das.
    group('newHobexTransactionId mit gesetztem Zeitpunkt', () {
      void pruefe(String was, DateTime zeitpunkt) {
        test(was, () {
          final id = KasseneckApi.newHobexTransactionId(zeitpunkt: zeitpunkt);
          expect(id.length, 19, reason: 'Hobex erwartet genau 19 Stellen');
          expect(RegExp(r'^\d+$').hasMatch(id), isTrue, reason: 'rein numerisch');
        });
      }

      pruefe('Mikrosekunden 0', DateTime(2026, 8, 24, 13, 45, 12, 789, 0));
      pruefe('Millisekunden und Mikrosekunden 0', DateTime(2026, 8, 24, 13, 45, 12, 0, 0));
      pruefe('einstellige Werte in Monat, Tag und Stunde', DateTime(2026, 1, 2, 3, 4, 5, 6, 7));
      pruefe('Jahreswechsel, Mikrosekunden 0', DateTime(2027, 1, 1, 0, 0, 0, 0, 0));
      pruefe('volle Stellen', DateTime(2026, 12, 31, 23, 59, 59, 999, 999));
    });

    test('newHobexTransactionId: Zeitanteil in den ersten 15, Zufall in den letzten 4 Stellen', () {
      final id = KasseneckApi.newHobexTransactionId(
          zeitpunkt: DateTime.utc(2026, 1, 2, 2, 4, 5, 0));
      expect(id.substring(0, 15), '260102030405000');
      expect(int.parse(id.substring(15)), inInclusiveRange(0, 9999));
      expect(id.substring(15).length, 4, reason: 'der Zufallsanteil ist immer vierstellig');
    });

    test('newHobexTransactionId: Zeitanteil folgt der Wiener Wanduhrzeit ueber 500 Zeitpunkte', () {
      // Der Zeitanteil ist die Wiener Wanduhrzeit des Zeitpunkts, Stelle fuer
      // Stelle aufgefuellt -- nicht die Geraetezeit. Ueber Winter und Sommer
      // hinweg gerechnet; welche Umstellung dabei gilt, nageln die beiden
      // Golden-Werte weiter unten fest.
      String zwei(int wert) => wert.toString().padLeft(2, '0');
      final zufall = Random(4711);
      for (var i = 0; i < 500; i++) {
        final zeitpunkt = DateTime.utc(
          2020 + zufall.nextInt(30),
          1 + zufall.nextInt(12),
          1 + zufall.nextInt(28),
          zufall.nextInt(24),
          zufall.nextInt(60),
          zufall.nextInt(60),
          zufall.nextInt(1000),
          1 + zufall.nextInt(999),
        );
        final wand = ViennaTime.toWallClock(zeitpunkt);
        final erwartet = '${zwei(wand.year % 100)}${zwei(wand.month)}${zwei(wand.day)}'
            '${zwei(wand.hour)}${zwei(wand.minute)}${zwei(wand.second)}'
            '${wand.millisecond.toString().padLeft(3, '0')}';
        final id = KasseneckApi.newHobexTransactionId(zeitpunkt: zeitpunkt);
        expect(id.length, 19, reason: 'Kennung zu $zeitpunkt');
        expect(id.substring(0, 15), erwartet, reason: 'Zeitanteil von $zeitpunkt');
      }
    });

    // --- Gemeinsame Golden-Werte mit dem JS-Zwilling -----------------------
    //
    // **Dieselben zwei Zeichenketten stehen im npm-Paket
    // @kreiseck/kasseneck-api in test/payments.test.ts** ("Golden-Wert
    // Winterzeit/Sommerzeit, wie im Dart-Zwilling"). Beide Pakete bilden die
    // Kennung nach demselben Verfahren und rechnen die Wiener Wanduhrzeit
    // jedes fuer sich aus. Weicht eine Seite kuenftig ab -- anderer Aufbau,
    // andere Auffuellung, andere Sommerzeitgrenze --, faellt ihr Test, statt
    // dass es am Terminal auffaellt.
    //
    // Der Zeitpunkt ist so gewaehlt, dass er etwas beweist: einstellige Werte
    // in Monat, Tag und Stunde und Millisekunde 0 -- genau die Stellen, an
    // denen das Auffuellen zaehlt. Der feste Zufallswert 0.00071 ergibt 7 und
    // muss auf vier Stellen aufgefuellt werden.
    test('newHobexTransactionId: Golden-Wert Winterzeit (wie im JS-Zwilling)', () {
      // 02.01.2026 02:04:05.000 UTC = 03:04:05.000 Wiener Zeit (CET, +1).
      final id = KasseneckApi.newHobexTransactionId(
        zeitpunkt: DateTime.utc(2026, 1, 2, 2, 4, 5, 0),
        zufall: () => 0.00071,
      );
      expect(id, '2601020304050000007');
      expect(RegExp(r'^\d{19}$').hasMatch(id), isTrue);
    });

    test('newHobexTransactionId: Golden-Wert Sommerzeit (wie im JS-Zwilling)', () {
      // 08.07.2026 07:04:05.000 UTC = 09:04:05.000 Wiener Zeit (CEST, +2).
      // Gegen den Winter-Wert steht hier allein die Sommerzeit: rechnet eine
      // der beiden Seiten die Umstellung anders, faellt genau dieser Wert.
      final id = KasseneckApi.newHobexTransactionId(
        zeitpunkt: DateTime.utc(2026, 7, 8, 7, 4, 5, 0),
        zufall: () => 0.00071,
      );
      expect(id, '2607080904050000007');
      expect(RegExp(r'^\d{19}$').hasMatch(id), isTrue);
    });

    test('newHobexTransactionId: Wiener Tageswechsel, nicht der des Geraets', () {
      // 13.08.2026 22:30:05.123 UTC = 14.08.2026 00:30:05.123 in Wien. Der
      // Tageswechsel liegt zwischen beiden -- die Kennung muss den Wiener
      // Geschaeftstag tragen. Auch dieser Wert steht so im JS-Zwilling.
      final id = KasseneckApi.newHobexTransactionId(
        zeitpunkt: DateTime.utc(2026, 8, 13, 22, 30, 5, 123),
        zufall: () => 0.5,
      );
      expect(id, '2608140030051235000');
    });

    test('newHobexTransactionId: fremde Zufallsquelle bleibt in vier Stellen', () {
      // Eine eingespeiste Quelle haelt sich nicht an [0, 1). 1 ergaebe ohne
      // Begrenzung 10000 -- also eine 20-stellige Kennung.
      expect(KasseneckApi.newHobexTransactionId(
              zeitpunkt: DateTime.utc(2026, 1, 2, 2, 4, 5, 0), zufall: () => 1.0)
          .substring(15), '9999');
      expect(KasseneckApi.newHobexTransactionId(
              zeitpunkt: DateTime.utc(2026, 1, 2, 2, 4, 5, 0), zufall: () => -3.0)
          .substring(15), '0000');
      expect(KasseneckApi.newHobexTransactionId(
              zeitpunkt: DateTime.utc(2026, 1, 2, 2, 4, 5, 0), zufall: () => double.nan)
          .substring(15), '0000');
    });

    test('newHobexTransactionId: zwei Kennungen derselben Millisekunde unterscheiden sich', () {
      final zeitpunkt = DateTime.utc(2026, 8, 13, 22, 30, 5, 123);
      final erste = KasseneckApi.newHobexTransactionId(zeitpunkt: zeitpunkt, zufall: () => 0.1234);
      final zweite = KasseneckApi.newHobexTransactionId(zeitpunkt: zeitpunkt, zufall: () => 0.9876);
      expect(erste, isNot(zweite),
          reason: 'ohne Zufallsanteil waeren zwei Zahlungen derselben Millisekunde dieselbe Kennung');
      expect(erste.substring(0, 15), zweite.substring(0, 15), reason: 'der Zeitanteil ist derselbe');
    });

    test('newHobexTransactionId: 2000 Aufrufe ohne Parameter, immer 19 Stellen', () {
      // Der Absturz traf rund 1 von 1000 Aufrufen; diese Runde faengt ihn auch
      // dann, wenn die Naht einmal nicht benutzt wird.
      for (var i = 0; i < 2000; i++) {
        final id = KasseneckApi.newHobexTransactionId();
        expect(id.length, 19);
        expect(RegExp(r'^\d+$').hasMatch(id), isTrue);
      }
    });
  });

  group('Logo haelt den Verkauf nicht auf', () {
    setUp(() {
      LogoService.frist = LogoService.standardFrist;
      LogoService.httpClient = http.Client();
    });

    test('haengender Logo-Host: sellReceipt kehrt trotzdem zurueck', () async {
      // Der Logo-Abruf laeuft HINTER dem bereits signierten Beleg. Haengt er,
      // steht die Kasse mit dem Gast am Tresen — und ein Neustart mit erneutem
      // Kassieren erzeugt einen zweiten Umsatz in der Signaturkette.
      LogoService.frist = const Duration(milliseconds: 20);
      LogoService.httpClient = MockClient((_) => Completer<http.Response>().future);

      final api = apiWith(MockClient((_) async => http.Response(
            jsonEncode({
              'status': 'success',
              'data': {
                ...buildReceipt().toJson(),
                'logo_url': 'https://example.test/haengendes-logo.png',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          )));

      final beleg = await api
          .sellReceipt(paymentMethod: KeckPaymentMethod.cash, items: [validItem])
          .timeout(const Duration(seconds: 5),
              onTimeout: () => fail('sellReceipt haengt am Logo-Abruf'));

      expect(beleg!.receiptId, 'TEST-ID-1', reason: 'der Beleg kommt heraus, nur ohne Logo');
      expect(beleg.logo, isNull);
    });
  });
}
