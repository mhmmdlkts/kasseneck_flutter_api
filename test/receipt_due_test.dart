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
import 'package:kasseneck_api/src/register/fehler.dart' show ErrorOutcome, isOutcomeUnknown;

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
        } on ReceiptDueError catch (e) {
          // Der eine Fehlerfall der Datei ist Trinkgeld ohne Ware.
          if (e.reason != 'tip_without_goods') abweichend.add('${f['name']}: ${e.reason} statt tip_without_goods');
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

  test('Unbrauchbare Eingaben werfen ReceiptDueError mit Grund statt still falsch zu rechnen', () {
    Matcher grund(String reason, [String? text]) => throwsA(isA<ReceiptDueError>()
        .having((e) => e.reason, 'reason', reason)
        .having((e) => e.code, 'code', 'receipt_due_unavailable')
        .having((e) => e.message, 'message', contains(text ?? '')));
    final gut = KasseneckItem(name: 'A', quantity: 1, priceCents: 100, vat: VatRate.vat20);
    expect(() => receiptDueCents([gut], [KeckVoucher(action: VoucherAction.redeem, type: VoucherType.value, valueCents: null)], ReceiptType.standard),
        grund('invalid_voucher'));
    expect(() => receiptDueCents([gut], const [], ReceiptType.zero, tip: ReceiptDueTip(100), tipRecipient: ReceiptDueTipRecipient.staff),
        grund('tip_not_allowed'));
    expect(() => receiptDueCents(const [], const [], ReceiptType.standard, tip: ReceiptDueTip(100), tipRecipient: ReceiptDueTipRecipient.owner),
        grund('tip_without_goods'));
    expect(() => receiptDueCents([gut], const [], ReceiptType.standard, tip: ReceiptDueTip(100)), grund('tip_recipient_missing', 'tipRecipient'));
    expect(
        () => receiptDueCents([gut], const [], ReceiptType.standard,
            payments: const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 110, tipCents: 10)]),
        grund('tip_recipient_missing', 'tipRecipient'));
    expect(
        () => receiptDueCents([gut], const [], ReceiptType.standard,
            tip: ReceiptDueTip(10),
            tipRecipient: ReceiptDueTipRecipient.staff,
            payments: const [KeckPaymentInput(method: KeckPaymentMethod.cash, amountCents: 110, tipCents: 10)]),
        grund('tip_conflict', 'tip_conflict'));
    expect(() => receiptDueCents([gut], const [], ReceiptType.standard, tip: ReceiptDueTip(0), tipRecipient: ReceiptDueTipRecipient.staff),
        grund('invalid_tip'));
    expect(
        () => receiptDueCents([gut], const [], ReceiptType.standard,
            tip: ReceiptDueTip(10, recipients: const [ReceiptDueTipShare(cents: 9, owner: false)])),
        grund('invalid_tip'));
    expect(() => receiptDueCents([gut], const [], ReceiptType.standard, tip: ReceiptDueTip(10, recipients: const [])), grund('invalid_tip'));
    expect(
        () => receiptDueCents([gut], const [], ReceiptType.standard,
            tipRecipient: ReceiptDueTipRecipient.staff,
            payments: const [KeckPaymentInput(method: KeckPaymentMethod.mixed, amountCents: 110, tipCents: 10)]),
        grund('unknown_payment_method'));
    expect(() => receiptDueBreakdownForLines(const [ReceiptDueLine(quantity: double.nan, priceCents: 1, vatRate: 20)], const [], ReceiptType.standard),
        grund('invalid_item'));
    expect(() => receiptDueBreakdownForLines(const [ReceiptDueLine(quantity: 1, priceCents: 1, vatRate: double.infinity)], const [], ReceiptType.standard),
        grund('invalid_item'));
  });

  test('ReceiptDueError: Ausgang abgelehnt, nie unklar, kein ArgumentError', () {
    const e = ReceiptDueError('tip_without_goods', 'x');
    expect(e.outcome, ErrorOutcome.rejected);
    expect(isOutcomeUnknown(e), isFalse);
    expect(isReceiptDueError(e), isTrue);
    expect(isReceiptDueError(ArgumentError('x')), isFalse);
    expect(e, isNot(isA<ArgumentError>()));
    expect(e.toString(), 'ReceiptDueError(tip_without_goods): Zahlbetrag: x');
  });

  group('Nicht rechenbare Faelle (receipt-due-errors.json, auch fuer npm)', () {
    final datei = _json('receipt-due-errors.json');
    final faelle = (datei['cases'] as List).cast<Map<String, dynamic>>();

    // Was der Dart-Typ gar nicht erst annimmt: ein fremder Belegtyp ist kein
    // ReceiptType, eine unbekannte Zahlart kein KeckPaymentMethod, ein halber
    // Cent kein int. Der Fall geht dann den naechsten Weg, den Dart hat.
    Object? rechne(Map<String, dynamic> input) {
      final typ = ReceiptType.values.asNameMap()[input['receiptType']];
      if (typ == null) return 'kein ReceiptType';
      final zahlungen = (input['payments'] as List?)?.cast<Map<String, dynamic>>();
      return receiptDueBreakdownForLines(
        [
          for (final p in (input['items'] as List).cast<Map<String, dynamic>>())
            ReceiptDueLine.fromJson({'name': p['name'], 'quantity': p['quantity'], 'unitPriceCents': p['priceCents'], 'vatRate': p['vatRate']}),
        ],
        [
          for (final v in (input['vouchers'] as List).cast<Map<String, dynamic>>())
            KeckVoucher(
              action: VoucherAction.values.byName(v['action'] as String),
              type: VoucherType.values.byName(v['type'] as String),
              valueCents: v['valueCents'] is int ? v['valueCents'] as int : null,
            ),
        ],
        typ,
        tip: _tipAus(input['tip']),
        payments: zahlungen == null
            ? null
            : [
                for (final z in zahlungen)
                  KeckPaymentInput(
                    // Der einzige Wert, den der Server als Trinkgeld-Zahlart nicht kennt.
                    method: KeckPaymentMethod.values.asNameMap()[z['method']] ?? KeckPaymentMethod.mixed,
                    amountCents: 1,
                    tipCents: z['tipCents'] as int?,
                  ),
              ],
        tipRecipient: switch (input['tipRecipient']) {
          'owner' => ReceiptDueTipRecipient.owner,
          'staff' => ReceiptDueTipRecipient.staff,
          _ => null,
        },
      );
    }

    test('Kopf: Code und Gruende wie in diesem Paket, jeder Grund hat einen Fall', () {
      expect(datei['code'], receiptDueErrorCode);
      expect(datei['reasons'], receiptDueErrorReasons);
      expect(receiptDueErrorReasons.toSet().difference({for (final f in faelle) (f['expected'] as Map)['reason']}), isEmpty);
      expect(faelle.where((f) => (f['expected'] as Map)['reason'] == 'tip_without_goods').length, greaterThanOrEqualTo(3));
    });

    for (final f in faelle) {
      final reason = (f['expected'] as Map)['reason'] as String;
      test('${f['name']} -> $reason', () {
        final input = f['input'] as Map<String, dynamic>;
        if (reason == 'unknown_receipt_type') {
          // In Dart nicht darstellbar: der Typ laesst den Wert nicht zu.
          expect(rechne(input), 'kein ReceiptType');
          return;
        }
        expect(() => rechne(input), throwsA(isA<ReceiptDueError>().having((e) => e.reason, 'reason', reason)));
      });
    }
  });

  test('Serverpositionen mit Bruchmenge oder unbekanntem Satz: nie still falsch, sondern ein Fehler mit Ausweg', () {
    final roh = {'name': 'Kaese', 'quantity': 0.375, 'unitPriceCents': 2400, 'vatRate': 10};
    final unbekannt = {'name': 'Tee', 'quantity': 2, 'unitPriceCents': 300, 'vatRate': 5.5};
    for (final p in [roh, unbekannt]) {
      final item = KasseneckItem.fromJson(p);
      expect(item.lossyRead, isNotNull, reason: '$p');
      expect(
        () => receiptDueCents([item], const [], ReceiptType.standard),
        throwsA(isA<ReceiptDueError>()
            .having((e) => e.reason, 'reason', 'invalid_item')
            .having((e) => e.message, 'message', contains('receiptDueBreakdownForLines'))),
        reason: '$p',
      );
    }
    // Der Ausweg rechnet exakt wie der Server: 0,375 x 24,00 = 9,00; 2 x 3,00 zu 5,5 % im Topf der uebrigen Saetze.
    expect(receiptDueBreakdownForLines([ReceiptDueLine.fromJson(roh)], const [], ReceiptType.standard).dueCents, 900);
    final e = receiptDueBreakdownForLines([ReceiptDueLine.fromJson(unbekannt)], const [], ReceiptType.standard);
    expect(e.bucketsCents!['amountRatOthers'], 600);
    // Exakt gelesene Positionen (auch 2.0 als Menge) bleiben ohne Vermerk.
    expect(KasseneckItem.fromJson({'name': 'A', 'quantity': 2.0, 'unitPriceCents': 1, 'vatRate': 20}).lossyRead, isNull);
    expect(KasseneckItem.fromJson({'name': 'A', 'amount': 1, 'priceOneCents': 1, 'vat': 4.9}).lossyRead, isNull);
    expect(() => ReceiptDueLine.fromJson({'name': 'A', 'quantity': 1, 'vatRate': 20}),
        throwsA(isA<ReceiptDueError>().having((e) => e.reason, 'reason', 'invalid_item')));
  });

  test('Die Paketwurzel exportiert den Zwilling', () {
    expect(wurzel.receiptDueCents, same(receiptDueCents));
    expect(wurzel.receiptDueBreakdown, same(receiptDueBreakdown));
    expect(wurzel.receiptDueBreakdownForLines, same(receiptDueBreakdownForLines));
    expect(wurzel.isReceiptDueError, same(isReceiptDueError));
    expect(wurzel.receiptDueErrorReasons, same(receiptDueErrorReasons));
    expect(wurzel.receiptDueErrorCode, receiptDueErrorCode);
    expect(const wurzel.ReceiptDueError('invalid_tip', 'x'), isA<ReceiptDueError>());
  });
}
