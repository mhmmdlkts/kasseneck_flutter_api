import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/rechnung.dart';

/// USt-Saetze mit Nachkommastelle in der Rechnungs-API.
///
/// Anlass: Eine im Panel geschriebene Rechnung mit 4,9 % (Grundnahrungsmittel
/// ab 01.07.2026) liess `getInvoice` mit `FormatException: rate` scheitern —
/// die Antwort wurde gelesen, nachdem der Aufruf schon gewirkt hatte. Der
/// Server fuehrt den Satz als Zahl (`rate: number` im JS-Zwilling), das Paket
/// las ihn als `int`. Gelesen wird darum jeder Satz, den der Server schickt;
/// **gesendet** bleibt der dokumentierte Satzbestand [vatRates].
///
/// Auf dem Web ist jede Zahl ein `double`: dort trifft `20 is int` zu und
/// `4.9 is int` nicht — der Fehler zeigte sich also auf beiden Plattformen
/// genau bei den krummen Saetzen.
const _apiKey = 'kr_test_Beispielschluessel0123456789';

Map<String, dynamic> _erfolg(Object? daten) => {'status': 'success', 'message': '', 'data': daten};

RechnungApi _apiMit(Object antwort) {
  final mock = MockClient((_) async => http.Response.bytes(
        utf8.encode(jsonEncode(antwort)),
        200,
        headers: {'content-type': 'application/json'},
      ));
  return RechnungApi(apiKey: _apiKey, httpClient: mock);
}

/// Eine Rechnung, wie der Server sie nach einer Panel-Erfassung mit
/// Grundnahrungsmitteln (4,9 %) und einem Altsatz 19 % ausliefert.
final _rechnungMit4komma9 = <String, dynamic>{
  'id': 'inv7',
  'number': '2026-0099',
  'docType': 'RE',
  'status': 'final',
  'invoiceDate': '2026-09-17',
  'totals': {
    'netCents': 2000,
    'vatCents': 239,
    'grossCents': 2239,
    'byRate': [
      {'rate': 19, 'netCents': 1000, 'vatCents': 190, 'grossCents': 1190},
      {'rate': 4.9, 'netCents': 1000, 'vatCents': 49, 'grossCents': 1049},
    ],
  },
  'items': [
    {'description': 'Kaese', 'subtitle': '', 'quantity': 1, 'unit': 'Stk', 'unitPriceCents': 1000, 'vatRate': 4.9, 'discountPct': 0},
    {'description': 'Altbestand', 'subtitle': '', 'quantity': 1, 'unit': 'Stk', 'unitPriceCents': 1000, 'vatRate': 19, 'discountPct': 0},
  ],
};

void main() {
  group('gelesen wird jeder Satz', () {
    test('getInvoice liest eine Rechnung mit 4,9 % (fruehere FormatException: rate)', () async {
      final api = _apiMit(_erfolg({'invoice': _rechnungMit4komma9}));
      final r = await api.getInvoice(number: '2026-0099');

      expect(r.totals.byRate.map((e) => e.rate).toList(), [19, 4.9]);
      expect(r.totals.byRate.last.netCents, 1000);
      expect(r.totals.byRate.last.vatCents, 49);
      expect(r.totals.byRate.last.grossCents, 1049);
      expect(r.items!.map((e) => e.vatRate).toList(), [4.9, 19]);
    });

    test('VatRateTotal.fromJson nimmt 4,9 und 19 und gibt sie unveraendert zurueck', () {
      final krumm = VatRateTotal.fromJson({'rate': 4.9, 'netCents': 1000, 'vatCents': 49, 'grossCents': 1049});
      expect(krumm.rate, 4.9);
      expect(krumm.toJson()['rate'], 4.9);

      // Der Altsatz 19 % kommt als ganze Zahl und bleibt eine.
      expect(VatRateTotal.fromJson({'rate': 19, 'netCents': 1000, 'vatCents': 190}).rate, 19);

      // Kein Satz ist weiterhin ein Antwortfehler -- ein fehlendes Feld darf
      // nicht als 0 % durchrutschen.
      expect(() => VatRateTotal.fromJson({'netCents': 1000, 'vatCents': 49}), throwsFormatException);
      expect(() => VatRateTotal.fromJson({'rate': '4.9', 'netCents': 1000, 'vatCents': 49}), throwsFormatException);
    });

    test('InvoiceItemInput.fromJson nimmt 4,9 -- eine Gutschrift uebernimmt die Zeilen des Originals', () {
      final zeile = InvoiceItemInput.fromJson({
        'description': 'Kaese',
        'quantity': 2,
        'unitPriceCents': 1000,
        'vatRate': 4.9,
      });
      expect(zeile.vatRate, 4.9);
      expect(zeile.toJson()['vatRate'], 4.9);

      final gutschrift = CreditNoteRequest.fromJson({
        'idempotencyKey': 'g-1',
        'invoiceId': 'inv7',
        'reason': 'return',
        'items': [
          {'description': 'Kaese', 'quantity': 1, 'unitPriceCents': 1000, 'vatRate': 4.9},
        ],
      });
      expect(gutschrift.items.single.vatRate, 4.9);
    });
  });

  group('gerechnet wird mit jedem Satz', () {
    test('rechnungSummen: 4,9 % netto und brutto', () {
      final netto = rechnungSummen(
        [const SummenPosition(quantity: 1, unitPriceCents: 1000, vatRate: 4.9)],
        'net',
      );
      expect(netto.toJson(), {
        'netCents': 1000,
        'vatCents': 49,
        'grossCents': 1049,
        'byRate': [
          {'rate': 4.9, 'netCents': 1000, 'vatCents': 49, 'grossCents': 1049},
        ],
      });

      // Im Brutto-Modus bleibt der vereinbarte Preis stehen, die USt ist die
      // Differenz -- wie am Server.
      final brutto = rechnungSummen(
        [const SummenPosition(quantity: 1, unitPriceCents: 1049, vatRate: 4.9)],
        'gross',
      );
      expect(brutto.grossCents, 1049);
      expect(brutto.byRate.single.netCents, 1000);
      expect(brutto.byRate.single.vatCents, 49);
    });

    test('Saetze bleiben getrennt und absteigend sortiert, 4,9 sortiert unter 10', () {
      final summen = rechnungSummen(
        [
          const SummenPosition(quantity: 1, unitPriceCents: 1000, vatRate: 4.9),
          const SummenPosition(quantity: 1, unitPriceCents: 1000, vatRate: 20),
          const SummenPosition(quantity: 1, unitPriceCents: 1000, vatRate: 10),
          // Derselbe Satz noch einmal: eine Zeile mehr, kein zweiter Eintrag.
          const SummenPosition(quantity: 1, unitPriceCents: 500, vatRate: 4.9),
        ],
        'net',
      );
      expect(summen.byRate.map((e) => e.rate).toList(), [20, 10, 4.9]);
      expect(summen.byRate.last.netCents, 1500);
      expect(summen.byRate.last.vatCents, 74); // 15,00 x 4,9 % = 0,735 -> 0,74
      expect(summen.netCents, 3500);
    });

    test('steuerfreier Fall stellt auch eine 4,9-Zeile auf 0 %', () {
      final summen = rechnungSummen(
        [const SummenPosition(quantity: 1, unitPriceCents: 1000, vatRate: 4.9)],
        'net',
        'igLieferung',
      );
      expect(summen.byRate.single.rate, 0);
      expect(summen.vatCents, 0);
    });
  });
}
