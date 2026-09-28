import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_payment_method.dart';
import 'package:kasseneck_api/enums/receipt_type.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/enums/voucher_action.dart';
import 'package:kasseneck_api/enums/voucher_type.dart';
import 'package:kasseneck_api/kasseneck_api.dart' as wurzel;
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/models/keck_payment.dart';
import 'package:kasseneck_api/models/keck_voucher.dart';
import 'package:kasseneck_api/src/receipt/due.dart';

/// Zahlbetrag als Zwilling des Backends (npm `test/due.test.ts`): jeder Fall
/// aus `v3/zahlbetrag-faelle.json` (20, gegen den echten Handler geprueft) und
/// aus `receipt-due-generated.json` (1206, mit dem echten Backend-Code
/// gerechnet) muss auf den Cent stimmen, Toepfe inklusive. Hier wird nichts
/// nachgerechnet, nur verglichen.
final _wurzel = Directory('test/fixtures/vertrag');

Map<String, dynamic> _json(String pfad) => jsonDecode(File('${_wurzel.path}/$pfad').readAsStringSync()) as Map<String, dynamic>;

ReceiptType _typ(String name) => ReceiptType.values.byName(name);

/// Eine Position des Vertrags (v1- oder v2-Form, auch Bruchmengen) als Zeile.
ReceiptDueLine _zeile(Map<String, dynamic> p) {
  final owner = p['owner'] == true || (p['recipient'] is Map && (p['recipient'] as Map)['owner'] == true);
  return ReceiptDueLine(
    quantity: (p['quantity'] ?? p['amount']) as num,
    priceCents: (p['priceCents'] ?? p['unitPriceCents'] ?? p['priceOneCents']) as int,
    vatRate: (p['vatRate'] ?? p['vat']) as num,
    tip: p['kind'] == 'tip' ? (owner ? ReceiptDueTipRecipient.owner : ReceiptDueTipRecipient.staff) : null,
  );
}

KeckVoucher _gutschein(Map<String, dynamic> v) => KeckVoucher(
      action: VoucherAction.values.byName(v['action'] as String),
      type: VoucherType.values.byName(v['type'] as String),
      valueCents: v['valueCents'] as int,
    );

Map<String, Object?> _alsMap(ReceiptDueBreakdown e) => {
      'dueCents': e.dueCents,
      'counterDeltaCents': e.counterDeltaCents,
      'valueVoucherFlowCents': e.valueVoucherFlowCents,
      'bucketsCents': e.bucketsCents,
    };

ReceiptDueTip? _tipAus(Object? roh) {
  if (roh == null) return null;
  if (roh is int) return ReceiptDueTip(roh);
  final m = roh as Map<String, dynamic>;
  final r = m['recipients'] as List?;
  return ReceiptDueTip(
    m['cents'] as int,
    recipients: r == null
        ? null
        : [for (final e in r.cast<Map<String, dynamic>>()) ReceiptDueTipShare(cents: e['cents'] as int, owner: e['owner'] as bool)],
  );
}

List<KeckPaymentInput>? _zahlungenAus(Object? roh) {
  if (roh == null) return null;
  return [
    for (final z in (roh as List).cast<Map<String, dynamic>>())
      KeckPaymentInput(
        method: KeckPaymentMethod.values.byName(z['method'] as String),
        amountCents: 1,
        tipCents: z['tipCents'] as int?,
      ),
  ];
}

ReceiptDueBreakdown _genRechnen(Map<String, dynamic> input) => receiptDueBreakdownForLines(
      [for (final p in (input['items'] as List).cast<Map<String, dynamic>>()) _zeile(p)],
      [for (final v in (input['vouchers'] as List).cast<Map<String, dynamic>>()) _gutschein(v)],
      _typ(input['receiptType'] as String),
      tip: _tipAus(input['tip']),
      payments: _zahlungenAus(input['payments']),
      tipRecipient: switch (input['tipRecipient']) {
        'owner' => ReceiptDueTipRecipient.owner,
        'staff' => ReceiptDueTipRecipient.staff,
        _ => null,
      },
    );

void main() {
  final faelle = (_json('v3/zahlbetrag-faelle.json')['cases'] as List).cast<Map<String, dynamic>>();
  final generiert = (_json('receipt-due-generated.json')['cases'] as List).cast<Map<String, dynamic>>();

  test('Zahlbetrag-Faelle: die Datei deckt alle Arten ab', () {
    final namen = faelle.map((f) => f['name'] as String).toList();
    expect(faelle.length, greaterThanOrEqualTo(20));
    for (final muster in [RegExp('^promo_'), RegExp('^value_voucher_'), RegExp('^tip_staff'), RegExp('^tip_owner'), RegExp('^cancellation_'), RegExp('float'), RegExp('decimal'), RegExp('^zero')]) {
      expect(namen.any(muster.hasMatch), isTrue, reason: '$muster');
    }
  });

  group('Vertragsfaelle (zahlbetrag-faelle.json)', () {
    for (final fall in faelle) {
      test('${fall['name']} stimmt exakt (${fall['verifiedBy']})', () {
        final input = fall['input'] as Map<String, dynamic>;
        final tip = input['tip'] as Map<String, dynamic>?;
        final e = receiptDueBreakdownForLines(
          [for (final p in (input['items'] as List).cast<Map<String, dynamic>>()) _zeile(p)],
          [for (final v in (input['vouchers'] as List).cast<Map<String, dynamic>>()) _gutschein(v)],
          _typ(input['receiptType'] as String),
          // Der Vertrag rechnet Personal-Trinkgeld ohne Empfaenger, Inhaber-Trinkgeld mit dem Inhaber.
          tip: tip == null ? null : ReceiptDueTip(tip['cents'] as int),
          tipRecipient: tip == null ? null : (tip['owner'] == true ? ReceiptDueTipRecipient.owner : ReceiptDueTipRecipient.staff),
        );
        expect(_alsMap(e), fall['expected']);
      });
    }
  });

  test('Vertragsfaelle ueber KasseneckItem (ganze Mengen) ergeben denselben Betrag', () {
    var geprueft = 0;
    for (final fall in faelle) {
      final input = fall['input'] as Map<String, dynamic>;
      final roh = (input['items'] as List).cast<Map<String, dynamic>>();
      if (roh.any((p) => (p['quantity'] ?? p['amount']) is! int)) continue;
      final tip = input['tip'] as Map<String, dynamic>?;
      final cents = receiptDueCents(
        [for (final p in roh) KasseneckItem.fromJson(p)],
        [for (final v in (input['vouchers'] as List).cast<Map<String, dynamic>>()) _gutschein(v)],
        _typ(input['receiptType'] as String),
        tip: tip == null ? null : ReceiptDueTip(tip['cents'] as int),
        tipRecipient: tip == null ? null : (tip['owner'] == true ? ReceiptDueTipRecipient.owner : ReceiptDueTipRecipient.staff),
      );
      expect(cents, (fall['expected'] as Map)['dueCents'], reason: fall['name'] as String);
      geprueft++;
    }
    expect(geprueft, greaterThanOrEqualTo(18));
  });

  test('Trinkgeld als fertige Position (Beleg, Storno) ergibt denselben Betrag wie der Parameter tip', () {
    final mitPositionen = faelle.where((f) => f['serverItems'] != null).toList();
    expect(mitPositionen.length, greaterThanOrEqualTo(3));
    for (final fall in mitPositionen) {
      final input = fall['input'] as Map<String, dynamic>;
      final alle = [
        ...(input['items'] as List).cast<Map<String, dynamic>>(),
        ...(fall['serverItems'] as List).cast<Map<String, dynamic>>(),
      ];
      final ueberItems = receiptDueCents(
        [for (final p in alle) KasseneckItem.fromJson(p)],
        [for (final v in (input['vouchers'] as List).cast<Map<String, dynamic>>()) _gutschein(v)],
        _typ(input['receiptType'] as String),
      );
      expect(ueberItems, (fall['expected'] as Map)['dueCents'], reason: fall['name'] as String);
    }
  });

  test('Generierte Faelle: mindestens 1000, mit Bruchmengen, Gutscheinen, Trinkgeld und tipCents', () {
    expect(generiert.length, greaterThanOrEqualTo(1000));
    bool alle(Map<String, dynamic> f, bool Function(Map<String, dynamic>) p) => (f['input']['items'] as List).cast<Map<String, dynamic>>().any(p);
    expect(generiert.where((f) => alle(f, (p) => p['quantity'] is! int)).length, greaterThanOrEqualTo(300));
    expect(generiert.any((f) => (f['input']['vouchers'] as List).any((v) => v['type'] == 'promo')), isTrue);
    expect(generiert.any((f) => (f['input']['vouchers'] as List).any((v) => v['type'] == 'value')), isTrue);
    expect(generiert.any((f) => f['input']['tipRecipient'] == 'owner' && f['input']['tip'] != null), isTrue);
    expect(generiert.any((f) => f['input']['payments'] != null), isTrue);
    expect(generiert.any((f) => f['input']['receiptType'] == 'cancellation' && alle(f, (p) => p['kind'] == 'tip')), isTrue);
  });

  test('Generierte Faelle: jeder stimmt exakt mit dem Backend ueberein (Euro-Gleitkomma wie der Server)', () {
    final abweichend = <String>[];
    for (final f in generiert) {
      final erwartet = f['expected'] as Map<String, dynamic>;
      final input = f['input'] as Map<String, dynamic>;
      if (erwartet.containsKey('error')) {
        try {
          _genRechnen(input);
          abweichend.add('${f['name']}: Fehler erwartet');
        } on ArgumentError {
          // erwartet
        }
        continue;
      }
      Object? ist;
      try {
        ist = _alsMap(_genRechnen(input));
      } catch (e) {
        ist = '$e';
      }
      if (jsonEncode(ist) != jsonEncode(erwartet)) abweichend.add('${f['name']}: ${jsonEncode(ist)} statt ${jsonEncode(erwartet)}');
    }
    expect(abweichend.take(5).toList(), isEmpty, reason: '${abweichend.length} Abweichungen');
  });

  test('Review-Faelle: 0,5 x 29 ct ist 14, der Mischfall ist 464, die Inhaber-Aufteilung 48/96', () {
    ReceiptDueBreakdown nach(String name) => _genRechnen(generiert.firstWhere((f) => f['name'] == name)['input'] as Map<String, dynamic>);
    expect(nach('half_cent_single').dueCents, 14);
    expect(nach('half_cent_promo_value_staff_tip').dueCents, 464);
    final split = nach('half_cent_owner_split').bucketsCents!;
    expect([split['amountRateStandard'], split['amountRateReduced1']], [48, 96]);
    expect(nach('owner_login_promo_exceeds').dueCents, 0);
  });

  test('Inhaber-Trinkgeld ist Umsatz und wird rabattiert, Personal-Trinkgeld nie', () {
    final ware = [KasseneckItem(name: 'Semmel', quantity: 1, priceCents: 100, vat: VatRate.vat10)];
    final rabatt = [KeckVoucher(action: VoucherAction.redeem, type: VoucherType.promo, valueCents: 500, code: 'R')];
    expect(receiptDueCents(ware, rabatt, ReceiptType.standard, tip: ReceiptDueTip(50), tipRecipient: ReceiptDueTipRecipient.staff), 50);
    expect(receiptDueCents(ware, rabatt, ReceiptType.standard, tip: ReceiptDueTip(50), tipRecipient: ReceiptDueTipRecipient.owner), 0);
    expect(
        receiptDueCents(ware, rabatt, ReceiptType.standard,
            tip: ReceiptDueTip(50, recipients: const [ReceiptDueTipShare(cents: 50, owner: true)])),
        0);
  });

  test('Kein Gleitkomma-Fehler: 3 x 0,10 + 7 x 0,70 ergibt 5,20; Null- und Startbeleg sind 0', () {
    final items = [
      KasseneckItem(name: 'A', quantity: 3, priceCents: 10, vat: VatRate.vat20),
      KasseneckItem(name: 'B', quantity: 7, priceCents: 70, vat: VatRate.vat10),
    ];
    expect(receiptDueCents(items, const [], ReceiptType.standard), 520);
    expect(receiptDueCents(const [], const [], ReceiptType.start), 0);
    expect(receiptDueBreakdown(const [], const [], ReceiptType.zero).bucketsCents, isNull);
  });

  test('JS-Rundung: halbe Cent am Storno runden Richtung plus unendlich wie Math.round', () {
    // -0,5 x 29 ct = -14,5 ct: Math.round gibt -14, Dart .round() gaebe -15.
    final e = receiptDueBreakdownForLines(
      const [ReceiptDueLine(quantity: -0.5, priceCents: 29, vatRate: 20)],
      const [],
      ReceiptType.cancellation,
    );
    expect(e.dueCents, -14);
  });

  test('Unbrauchbare Eingaben werfen statt still falsch zu rechnen', () {
    final gut = KasseneckItem(name: 'A', quantity: 1, priceCents: 100, vat: VatRate.vat20);
    expect(() => receiptDueCents([gut], [KeckVoucher(action: VoucherAction.redeem, type: VoucherType.value, valueCents: null)], ReceiptType.standard),
        throwsArgumentError);
    expect(() => receiptDueCents([gut], const [], ReceiptType.zero, tip: ReceiptDueTip(100), tipRecipient: ReceiptDueTipRecipient.staff),
        throwsArgumentError);
    expect(() => receiptDueCents(const [], const [], ReceiptType.standard, tip: ReceiptDueTip(100), tipRecipient: ReceiptDueTipRecipient.owner),
        throwsArgumentError);
    expect(() => receiptDueCents([gut], const [], ReceiptType.standard, tip: ReceiptDueTip(100)),
        throwsA(isA<ArgumentError>().having((e) => '${e.message}', 'message', contains('tipRecipient'))));
    expect(
        () => receiptDueCents([gut], const [], ReceiptType.standard,
            payments: const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 110, tipCents: 10)]),
        throwsA(isA<ArgumentError>().having((e) => '${e.message}', 'message', contains('tipRecipient'))));
    expect(
        () => receiptDueCents([gut], const [], ReceiptType.standard,
            tip: ReceiptDueTip(10),
            tipRecipient: ReceiptDueTipRecipient.staff,
            payments: const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 110, tipCents: 10)]),
        throwsA(isA<ArgumentError>().having((e) => '${e.message}', 'message', contains('tip_conflict'))));
    expect(() => receiptDueCents([gut], const [], ReceiptType.standard, tip: ReceiptDueTip(0), tipRecipient: ReceiptDueTipRecipient.staff),
        throwsArgumentError);
    expect(
        () => receiptDueCents([gut], const [], ReceiptType.standard,
            tip: ReceiptDueTip(10, recipients: const [ReceiptDueTipShare(cents: 9, owner: false)])),
        throwsArgumentError);
    expect(() => receiptDueBreakdownForLines(const [ReceiptDueLine(quantity: double.nan, priceCents: 1, vatRate: 20)], const [], ReceiptType.standard),
        throwsArgumentError);
  });

  test('Die Paketwurzel exportiert den Zwilling', () {
    expect(wurzel.receiptDueCents, same(receiptDueCents));
    expect(wurzel.receiptDueBreakdown, same(receiptDueBreakdown));
    expect(wurzel.receiptDueBreakdownForLines, same(receiptDueBreakdownForLines));
  });
}
