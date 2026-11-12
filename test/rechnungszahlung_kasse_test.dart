import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kasseneck_api/models/receipt_layout.dart';
import 'package:kasseneck_api/pos.dart';
import 'package:kasseneck_api/register.dart';

/// Zahlung auf Rechnung an der Kasse (Zwilling von `rechnungszahlung-kasse.test.ts`, npm 1.38.0): Satz und
/// Fall des abgelehnten Stornos stehen im Vertrag der Kassen, Schichtabschluss und Kassenstand tragen die
/// Zeile „Zahlungen auf Rechnungen“ (`invoicePaymentCents`, nur Information).
Map<String, dynamic> _json(String pfad) => jsonDecode(File(pfad).readAsStringSync()) as Map<String, dynamic>;

const _satz = 'Diese Zahlung gehört zu einer Rechnung. Storniere sie im Kundenbereich bei der Rechnung.';
final _kasse = (_json('test/fixtures/vertrag/v3/antworten/kasse.json')['endpoints'] as Map).cast<String, dynamic>();

Map<String, dynamic> _fall(String endpunkt) =>
    ((_kasse[endpunkt] as Map)['cases'] as List).cast<Map<String, dynamic>>().firstWhere((f) => f['case'] == 'success_manager');

RegisterReceiptClient _client(Map<String, dynamic> fall, Map<String, dynamic> antwort) {
  final transport = RegisterTransport(
    idToken: () async => 'id-token',
    sessionId: () async => 'sess-1',
    cashregisterId: 'KASSE1',
    httpClient: MockClient((_) async => http.Response.bytes(utf8.encode(jsonEncode(antwort)), 200, headers: {
          'content-type': 'application/json',
          for (final e in (fall['headers'] as Map).cast<String, String>().entries) e.key.toLowerCase(): e.value,
        })),
  );
  return RegisterReceiptClient(transport);
}

Map<String, dynamic> _kopie(Map<String, dynamic> fall) => jsonDecode(jsonEncode(fall['response'])) as Map<String, dynamic>;

Future<ShiftSummaryReceipt> _zBon(Object? invoicePaymentCents) async {
  final fall = _fall('closeMyShift');
  final antwort = _kopie(fall);
  final bon = (antwort['data'] as Map)['receipt'] as Map<String, dynamic>;
  if (invoicePaymentCents != null) bon['invoicePaymentCents'] = invoicePaymentCents;
  return (await _client(fall, antwort).closeMyShift(idempotencyKey: 'k', shiftId: 's', countedCents: 0)).receipt!;
}

Future<ShiftRunningTotals> _laufstand(Object? invoicePaymentCents) async {
  final fall = _fall('getMyDrawerState');
  final antwort = _kopie(fall);
  final summen = (((antwort['data'] as Map)['shift'] as Map)['runningTotals']) as Map<String, dynamic>;
  if (invoicePaymentCents != null) summen['invoicePaymentCents'] = invoicePaymentCents;
  return (await _client(fall, antwort).getMyDrawerState()).shift!.runningTotals!;
}

List<List<String>> _paare(ReceiptLayout layout) => [
      for (final z in layout.lines)
        if (z is LayoutColumnsLine) [for (final c in z.columns) c.text],
    ];

void main() {
  test('Satz und Fall stehen im Vertrag der Kassen (pos-texts.json, pos-message-cases.json)', () {
    final vertrag = _json('test/fixtures/vertrag/pos-texts.json');
    expect((vertrag['messages'] as Map)['cancellation.invoice_payment_not_cancellable'], {'text': _satz});
    expect(((vertrag['labels'] as Map)['shift_receipt.invoice_payments'] as Map)['text'], 'Zahlungen auf Rechnungen');
    final fall = (_json('test/fixtures/vertrag/pos-message-cases.json')['cases'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((f) => (f['error'] as Map)['code'] == 'invoice_payment_not_cancellable');
    expect(fall['expected'], {'key': 'cancellation.invoice_payment_not_cancellable'});
  });

  test('Fehlerregel: der Code ordnet sich dem Satz der Kasse zu', () {
    final regel = findErrorRule(ErrorKind.api, code: 'invoice_payment_not_cancellable');
    expect(regel.key, 'cancellation.invoice_payment_not_cancellable');
  });

  test('Schichtzeile: Beschriftung', () {
    expect(labelText('shift_receipt.invoice_payments'), 'Zahlungen auf Rechnungen');
  });

  group('Z-Bon', () {
    test('mit Zahlungen auf Rechnungen eine Zeile im Informationsteil, ohne sie (oder bei 0) keine', () async {
      final ohne = shiftReceiptLayout(await _zBon(null));
      final mit = shiftReceiptLayout(await _zBon(156960));
      expect(_paare(mit).where((p) => p[0] == 'Zahlungen auf Rechnungen').toList(), [
        ['Zahlungen auf Rechnungen', '1569,60'],
      ]);
      final regeln = [for (var i = 0; i < mit.lines.length; i++) if (mit.lines[i] is LayoutRuleLine) i];
      final zeile = mit.lines.indexWhere((z) => z is LayoutColumnsLine && z.columns[0].text == 'Zahlungen auf Rechnungen');
      expect(zeile, greaterThan(regeln[1]), reason: 'nach der zweiten Trennlinie, nicht im Bargeldblock');
      expect(mit.lines.length, ohne.lines.length + 1);
      expect(shiftReceiptLayout(await _zBon(0)).toJson(), ohne.toJson());
    });

    test('ein Storno ueberwiegt: die Zeile steht mit Vorzeichen; kein ganzzahliger Betrag wird abgewiesen', () async {
      final negativ = shiftReceiptLayout(await _zBon(-4990));
      expect(_paare(negativ).any((p) => p[0] == 'Zahlungen auf Rechnungen' && p[1] == '-49,90'), isTrue);
      await expectLater(_zBon(1.5), throwsA(anything));
    });
  });

  test('Kassenstand: invoicePaymentCents im Laufstand wird gelesen wie gesendet, fehlt sonst null', () async {
    expect((await _laufstand(null)).invoicePaymentCents, isNull);
    final summen = await _laufstand(156960);
    expect(summen.invoicePaymentCents, 156960);
    expect(summen.toJson()['invoicePaymentCents'], 156960);
    await expectLater(_laufstand(1.5), throwsA(anything));
  });
}
