import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/enums/receipt_type.dart';
import 'package:kasseneck_api/enums/vat_rate.dart';
import 'package:kasseneck_api/enums/voucher_action.dart';
import 'package:kasseneck_api/enums/voucher_type.dart';
import 'package:kasseneck_api/models/kasseneck_item.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/keck_voucher.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/models/receipt_grid.dart';
import 'package:kasseneck_api/models/receipt_layout.dart';
import 'package:kasseneck_api/src/printing/escpos/escpos.dart';
import 'package:kasseneck_api/widgets/keck_receipt_lines_widget.dart';
import 'package:kasseneck_api/widgets/keck_receipt_widget.dart';

import 'helpers/test_receipts.dart';

/// Bon der neuen Gutscheinform (Spec 2026-10-14, „Bon und Beleg“) im
/// Rueckfall ohne Server-Layout: Summen, Druck (`setKeckReceipt`) und
/// Beleg-Widget. Zwilling von `test/layout-gutschein-neu.test.ts` im
/// npm-Paket: dieselben Beispiele, dieselben Zeilen.
///
/// Die Erwartung kommt aus den Golden-Belegen des Vertrags
/// (`receipts/voucher-*.json` -> `expected/voucher-*.lines.json`, gebaut vom
/// npm-Paket): der Rueckfall muss im Positions- und im Zahlungsteil dieselben
/// Zeilen setzen wie das Layout des Pakets. Abweichungen des alten
/// Druckwegs: „EUR“ statt „€“, Zeichen ausserhalb CP437 als „?“.
///
/// Vorfall 16.10.2026: ein Verkauf ueber 30 € zeigte „Gesamt 60,00“, weil
/// die Position im 0-%-Topf und der Gutscheineintrag beide zaehlten.
final _wurzel = Directory('test/fixtures/vertrag');

Map<String, dynamic> _json(String pfad) => jsonDecode(File(pfad).readAsStringSync()) as Map<String, dynamic>;

final List<String> _gutscheinBelege = (_json('${_wurzel.path}/manifest.json')['receipts'] as Map<String, dynamic>)
    .keys
    .where((n) => n.startsWith('voucher-'))
    .toList()
  ..sort();

KasseneckReceipt _golden(String name) {
  final ein = _json('${_wurzel.path}/receipts/$name.json');
  return KasseneckReceipt.fromMetadata(ein['receipt'], {'company': (ein['company'] as Map)['companyName']});
}

ReceiptLayout _goldenLayout(String name) => ReceiptLayout.fromJson(_json('${_wurzel.path}/expected/$name.lines.json'))!;

int _bezahlt(String name) {
  final r = _json('${_wurzel.path}/receipts/$name.json')['receipt'] as Map<String, dynamic>;
  return [for (final p in (r['payments'] as List).cast<Map<String, dynamic>>()) p['amountCents'] as int]
      .fold(0, (a, b) => a + b);
}

/// Eine Zeile als Text: Spalten mit " | " getrennt (wie `texte` im npm-Test).
String _zeile(LayoutLine z) => switch (z) {
      LayoutColumnsLine() => z.columns.map((c) => c.text).join(' | '),
      LayoutTextLine() => z.text,
      LayoutRuleLine() => '---',
      _ => '',
    };

/// Positions- und Zahlungsteil des Layouts: von der ersten Zeile nach
/// „Beleg-ID:“ bis zur Steuertabelle, und von „Zwischensumme“ bis zum Strich.
({List<String> positionen, List<String> zahlung}) _teile(List<String> zeilen, {required String kopf}) {
  final start = zeilen.indexWhere((z) => z.startsWith('Beleg-ID:')) + 1;
  final steuer = zeilen.indexWhere((z) => z.startsWith('MwSt%'));
  final positionen = zeilen.sublist(start, steuer).where((z) => z.trim().isNotEmpty).toList();
  final zs = zeilen.indexWhere((z) => z.startsWith('Zwischensumme'));
  final zahlung = <String>[];
  if (zs >= 0) {
    for (var i = zs; i < zeilen.length && !zeilen[i].startsWith('---'); i++) {
      zahlung.add(zeilen[i]);
    }
  }
  return (positionen: positionen, zahlung: zahlung);
}

/// Was der Rueckfall druckt, als Zeilen (Zweispalter mit " | ").
Future<List<String>> _gedruckt(KasseneckReceipt beleg, {KeckPaperSize papier = KeckPaperSize.mm80}) async {
  final paper = PrintPaper(paperSize: papier, profile: CapabilityProfile());
  await paper.setKeckReceipt(beleg);
  return [
    for (final c in paper.myPosPaper.commands)
      switch (c['type']) {
        'doubleText' => '${c['leftValue']} | ${c['rightValue']}',
        'text' => c['value'] as String,
        _ => '',
      }
  ];
}

String _gesamt(List<String> zeilen) => zeilen.firstWhere((z) => z.startsWith('Gesamt:')).split(' | ').last;

KasseneckReceipt _specBeispiel({String? taxedWith = 'K1-ID-4711', bool? exempt}) => buildReceipt(
      items: [
        KasseneckItem(name: 'Maniküre', quantity: 1, vat: VatRate.vat20, priceCents: 3500),
        KasseneckItem(name: 'Gutschein ····-9DWT', quantity: 1, vat: VatRate.vat20, priceCents: -3050, kind: 'voucher'),
      ],
      vouchers: [_einzweck(amountCents: 3050, balanceAfterCents: 1950, taxedWith: taxedWith, exempt: exempt)],
    );

KeckVoucher _einzweck({
  required int amountCents,
  int? balanceAfterCents,
  String? taxedWith,
  bool? exempt,
  String voucherId = 'gez9',
  VoucherAction action = VoucherAction.redeem,
  String? reason,
}) =>
    KeckVoucher(
      action: action,
      type: VoucherType.singlePurpose,
      voucherType: 'single_purpose',
      amountCents: amountCents,
      vatRateBp: 2000,
      balanceAfterCents: balanceAfterCents,
      taxedWith: taxedWith,
      exempt: exempt,
      reason: reason,
      name: 'Gutschein',
      code: '····-····-9DWT',
      codeSuffix: '9DWT',
      voucherId: voucherId,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('die acht Gutschein-Belege des Vertrags sind da', () {
    expect(_gutscheinBelege, [
      'voucher-cancellation',
      'voucher-multi-purpose-redeem',
      'voucher-multi-purpose-sale',
      'voucher-payout',
      'voucher-service-redeem',
      'voucher-single-purpose-redeem',
      'voucher-single-purpose-redeem-exempt',
      'voucher-single-purpose-sale',
    ]);
  });

  group('Summen: jeder Betrag zaehlt genau einmal', () {
    for (final name in _gutscheinBelege) {
      test('$name: sumCents = Summe der Zahlungen = „Gesamt“ des Golden-Layouts', () {
        final r = _golden(name);
        final zeilen = _goldenLayout(name).lines.map(_zeile).toList();
        expect(r.sumCents, _bezahlt(name));
        expect('${formatCents(r.sumCents)} €', _gesamt(zeilen));
      });
    }

    test('Mehrzweck-Verkauf im 0-%-Topf (zeroRateBucket): 30,00 statt 60,00 (Vorfall 16.10.2026)', () {
      final r = _golden('voucher-multi-purpose-sale');
      expect(r.vouchers!.single.zeroRateBucket, isTrue);
      expect(r.subSumCents, 3000);
      expect(r.sumCents, 3000);
    });

    test('Auszahlung eines Wertgutscheins ohne zeroRateBucket mindert wie eine Einloesung (zahlungen-core)', () async {
      final r = buildReceipt(vouchers: [
        KeckVoucher(action: VoucherAction.payout, type: VoucherType.value, valueCents: 1200, reason: 'Rest bar', codeSuffix: '8CN5'),
      ]);
      expect(r.subSumCents, 0);
      expect(r.sumCents, -1200);
      // Beschriftung wie npm (layout.ts, `Auszahlung ${gutscheinText}`): ohne voucherType multi_purpose
      // keine Endung, sondern Art, Code und Name (Werte aus dem npm-Layout 1.12.0).
      final z = await _gedruckt(r);
      expect(z, containsAllInOrder(['Zwischensumme | 0,00 EUR', 'Auszahlung Wertgutschein | -12,00 EUR', 'Gesamt: | -12,00 EUR']));
      final mitName = buildReceipt(vouchers: [
        KeckVoucher(action: VoucherAction.payout, type: VoucherType.value, valueCents: 1200, reason: 'Rest bar', code: 'GS-9', name: 'Geschenk'),
      ]);
      expect(await _gedruckt(mitName), contains('Auszahlung Wertgutschein GS-9 - Geschenk | -12,00 EUR'));
    });

    test('Einzweck und Leistung zaehlen nur ueber ihre Positionen', () {
      final r = _specBeispiel();
      expect(r.subSumCents, 450);
      expect(r.sumCents, 450);
    });

    test('jedes Vertragsbeispiel mit Zahlungen: sumCents = Summe der Zahlungen', () {
      var n = 0;
      for (final datei in ['belege', 'kasse-belege', 'storno']) {
        for (final f in (_json('${_wurzel.path}/v3/antworten/$datei.json')['cases'] as List).cast<Map<String, dynamic>>()) {
          final daten = (f['response'] as Map?)?['data'];
          if (daten is! Map || daten['receipt'] is! Map || (daten['receipt'] as Map)['payments'] is! List) continue;
          final zahlungen = ((daten['receipt'] as Map)['payments'] as List).cast<Map<String, dynamic>>();
          final bezahlt = zahlungen.fold<int>(0, (s, p) => s + (p['amountCents'] as int));
          final r = KasseneckReceipt.fromJson(daten.cast<String, dynamic>());
          expect(r.sumCents, bezahlt, reason: '$datei/${f['name']}${f['channel'] == null ? '' : '/${f['channel']}'}');
          n++;
        }
      }
      expect(n, greaterThan(20));
    });
  });

  group('Druck im Rueckfall (setKeckReceipt) gegen die Golden-Layouts', () {
    for (final name in _gutscheinBelege) {
      test('$name: Positionen und Zahlungsteil wie das Layout des Pakets', () async {
        final soll = _teile(_goldenLayout(name).lines.map(_zeile).toList(), kopf: name);
        final ist = _teile(await _gedruckt(_golden(name)), kopf: name);
        // Der alte Druckweg schreibt „EUR“ und ersetzt in Positionsnamen, was
        // CP437 nicht kennt, durch „?“ (CP437Checker.check, wie bisher).
        String alt(String z) => z.replaceAll('€', 'EUR').check();
        expect(ist.positionen, soll.positionen.map(alt).toList(), reason: '$name: Positionen');
        expect(ist.zahlung, soll.zahlung.map(alt).toList(), reason: '$name: Zahlungsteil');
      });
    }

    test('Spec-Beispiel Einzweck: Gutscheinzeile, Vermerk, Rest, Gesamt 4,50 und der Gutschein nur einmal', () async {
      final z = await _gedruckt(_specBeispiel());
      final i = z.indexOf('Gutschein ····-9DWT | -30,50 A');
      expect(z.sublist(i, i + 3), [
        'Gutschein ····-9DWT | -30,50 A',
        '  Einzweck, versteuert mit Beleg K1-ID-4711',
        '  Rest am Gutschein | 19,50  ',
      ]);
      expect(z.where((t) => t.contains('9DWT')), hasLength(1));
      expect(z.any((t) => t.startsWith('Zwischensumme')), isFalse);
      expect(_gesamt(z), '4,50 EUR');
    });

    test('Kleinunternehmer: Vermerk „befreit verkauft (Kleinunternehmer)“ statt Belegnummer', () async {
      final z = await _gedruckt(_specBeispiel(taxedWith: null, exempt: true));
      expect(z, contains('  Einzweck, befreit verkauft (Kleinunternehmer)'));
      expect(z.any((t) => t.contains('versteuert mit')), isFalse);
    });

    test('Vermerke brechen auf 58 mm mit demselben Einzug um wie das Raster', () async {
      final z = await _gedruckt(_specBeispiel(), papier: KeckPaperSize.mm58);
      final i = z.indexOf('Gutschein ····-9DWT | -30,50 A');
      expect(z.sublist(i + 1, i + 3), ['  Einzweck, versteuert mit Beleg', '  K1-ID-4711']);
      final befreit = await _gedruckt(_specBeispiel(taxedWith: null, exempt: true), papier: KeckPaperSize.mm58);
      final k = befreit.indexOf('  Einzweck, befreit verkauft');
      expect(befreit.sublist(k, k + 2), ['  Einzweck, befreit verkauft', '  (Kleinunternehmer)']);
    });

    test('zwei Gutscheine mit derselben Endung: jede Position genau einem Eintrag, der Reihe nach', () async {
      final r = buildReceipt(
        items: [
          KasseneckItem(name: 'Maniküre', quantity: 1, vat: VatRate.vat20, priceCents: 5000),
          KasseneckItem(name: 'Gutschein ····-9DWT', quantity: 1, vat: VatRate.vat20, priceCents: -1000, kind: 'voucher'),
          KasseneckItem(name: 'Gutschein ····-9DWT', quantity: 1, vat: VatRate.vat20, priceCents: -500, kind: 'voucher'),
        ],
        vouchers: [
          _einzweck(amountCents: 1000, balanceAfterCents: 4000, taxedWith: 'K1-ID-1', voucherId: 'a'),
          _einzweck(amountCents: 500, balanceAfterCents: 0, taxedWith: 'K1-ID-2', voucherId: 'b'),
        ],
      );
      final z = await _gedruckt(r);
      final i = z.indexOf('Gutschein ····-9DWT | -10,00 A');
      expect(z.sublist(i, i + 6), [
        'Gutschein ····-9DWT | -10,00 A',
        '  Einzweck, versteuert mit Beleg K1-ID-1',
        '  Rest am Gutschein | 40,00  ',
        'Gutschein ····-9DWT | -5,00 A',
        '  Einzweck, versteuert mit Beleg K1-ID-2',
        '  Rest am Gutschein | 0,00  ',
      ]);
      expect(r.sumCents, 3500);
    });

    test('Auszahlungsposition nur zum Auszahlungseintrag, Einloesungsposition nur zur Einloesung', () async {
      final spec = _specBeispiel();
      final r = buildReceipt(
        items: [
          ...spec.items,
          KasseneckItem(name: 'Auszahlung Gutschein ····-9DWT', quantity: 1, vat: VatRate.vat20, priceCents: -500, kind: 'voucher'),
        ],
        vouchers: [
          _einzweck(action: VoucherAction.payout, amountCents: 500, reason: 'Rest bar', voucherId: 'p'),
          ...spec.vouchers!,
        ],
      );
      final z = await _gedruckt(r);
      final i = z.indexOf('Gutschein ····-9DWT | -30,50 A');
      expect(z.sublist(i, i + 3),
          ['Gutschein ····-9DWT | -30,50 A', '  Einzweck, versteuert mit Beleg K1-ID-4711', '  Rest am Gutschein | 19,50  ']);
      final k = z.indexOf('Auszahlung Gutschein ····-9DWT | -5,00 A');
      expect(z.sublist(k, k + 2), ['Auszahlung Gutschein ····-9DWT | -5,00 A', '  Grund: Rest bar']);
    });

    test('Mehrzweck-Verkauf vor dem Stichtag (nur Eintrag): Zeile mit Code und „USt bei Einlösung“, 0-%-Zeile einmal', () async {
      final r = buildReceipt(vouchers: [
        KeckVoucher(
          action: VoucherAction.sell,
          type: VoucherType.value,
          voucherType: 'multi_purpose',
          valueCents: 5000,
          name: 'Mehrzweckgutschein',
          code: '····-····-NNNY',
          codeSuffix: 'NNNY',
          voucherId: 'm',
        ),
      ]);
      final z = await _gedruckt(r);
      expect(z, containsAllInOrder(['1  x Mehrzweckgutschein ····-····-NNNY | 50,00 D', '  USt bei Einlösung']));
      expect(z.where((t) => t.contains('NNNY')), hasLength(1));
      expect(_gesamt(z), '50,00 EUR');
    });

    test('Platzhalter „no-code“ des Servers steht nie an der Verkaufszeile', () async {
      final r = buildReceipt(
        items: [KasseneckItem(name: 'Mehrzweckgutschein', quantity: 1, vat: VatRate.vat0, priceCents: 5000, kind: 'voucher_float')],
        vouchers: [
          KeckVoucher(action: VoucherAction.sell, type: VoucherType.value, valueCents: 5000, name: 'Wertgutschein', code: 'no-code', zeroRateBucket: true),
        ],
      );
      final z = await _gedruckt(r);
      expect(z, contains('1  x Mehrzweckgutschein | 50,00 D'));
      expect(z.any((t) => t.contains('no-code')), isFalse);
      expect(_gesamt(z), '50,00 EUR');
    });

    test('Storno einer Einzweck-Einloesung (Spiegel ohne Rest und Vermerk): Gutscheinzeile plus, Gesamt = Rueckzahlung', () async {
      final r = buildReceipt(
        receiptType: ReceiptType.cancellation,
        items: [
          KasseneckItem(name: 'Maniküre', quantity: 1, vat: VatRate.vat20, priceCents: -3500),
          KasseneckItem(name: 'Gutschein ····-9DWT', quantity: 1, vat: VatRate.vat20, priceCents: 3050, kind: 'voucher'),
        ],
        vouchers: [_einzweck(amountCents: 3050)],
      );
      final z = await _gedruckt(r);
      expect(z, contains('Gutschein ····-9DWT | 30,50 A'));
      expect(z.any((t) => t.contains('Rest am Gutschein') || t.contains('versteuert')), isFalse);
      expect(_gesamt(z), '-4,50 EUR');
    });

    test('Altbeleg ohne neue Form: Wertgutschein-Zeilen wie bisher', () async {
      final r = buildReceipt(
        items: [KasseneckItem(name: 'Torte', quantity: 1, vat: VatRate.vat10, priceCents: 2240)],
        vouchers: [KeckVoucher(code: 'GS-7', action: VoucherAction.redeem, type: VoucherType.value, valueCents: 1750)],
      );
      final z = await _gedruckt(r);
      expect(z, containsAllInOrder(['Zwischensumme | 22,40 EUR', 'Wertgutschein 17,50 EUR | -17,50 EUR']));
      expect(z.any((t) => t.contains('Rest am Gutschein')), isFalse);
    });
  });

  group('Zeichenraster: haengender Einzug (32 und 48 Zeichen)', () {
    test('ein langer Grund bricht auf jeder Breite mit zwei Zeichen Einzug um', () {
      const grund = '  Grund: Kundin zieht in ein anderes Bundesland und kommt nicht mehr vorbei';
      final layout = ReceiptLayout(paperSize: 'mm80', ruleset: 1, lines: const [LayoutTextLine(text: grund)]);
      for (final zeichen in [32, 48]) {
        final z = ReceiptGrid.render(layout, charsPerLine: zeichen).lines.map((l) => l.text).toList();
        expect(z.length, greaterThan(1), reason: '$zeichen');
        expect(z.first, startsWith('  Grund:'));
        for (final f in z.skip(1)) {
          expect(f.startsWith('  ') && f[2] != ' ', isTrue, reason: '$zeichen: "$f"');
        }
        expect(z.every((f) => f.length == zeichen), isTrue);
      }
    });

    test('ohne fuehrende Leerzeichen und zentriert: wie bisher (wortweise, ohne Einzug)', () {
      const ohne = 'Kundin zieht in ein anderes Bundesland und kommt nicht mehr vorbei';
      const zentriert = '  zentriert mit Leerzeichen und einem langen Satz dahinter';
      final layout = ReceiptLayout(paperSize: 'mm58', ruleset: 1, lines: const [
        LayoutTextLine(text: ohne),
        LayoutTextLine(text: zentriert, align: LayoutAlign.center),
      ]);
      String mitte(String t) {
        final rest = 32 - t.length;
        return ' ' * (rest ~/ 2) + t + ' ' * (rest - rest ~/ 2);
      }

      final z = ReceiptGrid.render(layout, charsPerLine: 32).lines.map((l) => l.text).toList();
      expect(z, [
        for (final t in wrapWords(ohne, 32)) t.padRight(32),
        for (final t in wrapWords(zentriert, 32)) mitte(t),
      ]);
      expect(z[1], 'Bundesland und kommt nicht mehr ');
    });

    test('Golden voucher-single-purpose-redeem-exempt @32: Vermerk in zwei Zeilen mit Einzug', () {
      final z = ReceiptGrid.render(_goldenLayout('voucher-single-purpose-redeem-exempt'), charsPerLine: 32).toText().split('\n');
      final i = z.indexOf('  Einzweck, befreit verkauft    ');
      expect(z.sublist(i, i + 2), ['  Einzweck, befreit verkauft    ', '  (Kleinunternehmer)            ']);
    });
  });

  group('Bildschirm', () {
    Future<List<String>> texte(WidgetTester tester, Widget w) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w))));
      return tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').toList();
    }

    testWidgets('Beleg-Widget: Spec-Beispiel Einzweck mit Vermerk, Rest und Gesamt 4,50', (tester) async {
      final t = await texte(tester, KeckReceiptWidget(receipt: _specBeispiel()));
      expect(t, containsAllInOrder(['Gutschein ····-9DWT', '-30,50 A', 'Einzweck, versteuert mit Beleg K1-ID-4711', '  Rest am Gutschein', '19,50  ']));
      expect(t.where((x) => x.contains('9DWT')), hasLength(1));
      expect(t, contains('4,50 EUR'));
      expect(t, isNot(contains('Zwischensumme')));
      // Haengender Einzug: der Vermerk steht rechts von der Gutscheinzeile.
      final vermerk = tester.getTopLeft(find.text('Einzweck, versteuert mit Beleg K1-ID-4711')).dx;
      expect(vermerk, greaterThan(tester.getTopLeft(find.text('Gutschein ····-9DWT')).dx));
    });

    for (final name in _gutscheinBelege) {
      testWidgets('Beleg-Widget $name: Gutscheinzeilen und Gesamt wie das Golden-Layout', (tester) async {
        final t = await texte(tester, KeckReceiptWidget(receipt: _golden(name)));
        final soll = _goldenLayout(name).lines.map(_zeile).toList();
        final teile = _teile(soll, kopf: name);
        for (final z in [...teile.positionen, ...teile.zahlung]) {
          for (final s in z.split(' | ')) {
            // Das Widget schreibt „EUR“ und die Menge mit einem Leerzeichen („1 x“).
            final text = s.replaceAll('€', 'EUR').replaceFirstMapped(RegExp(r'^(\d+) +x '), (m) => '${m[1]} x ');
            // Vermerke stehen eingerueckt ohne ihre fuehrenden Leerzeichen.
            expect(t.contains(text) || t.contains(text.trimLeft()), isTrue, reason: '$name: "$text" fehlt in $t');
          }
        }
        expect(t, contains('${formatCents(_bezahlt(name))} EUR'));
      });
    }

    testWidgets('Zeilen-Widget: Vermerk mit fuehrenden Leerzeichen steht eingerueckt, Text ohne die Leerzeichen', (tester) async {
      final layout = ReceiptLayout(paperSize: 'mm80', ruleset: 1, lines: const [
        LayoutTextLine(text: '  Grund: Kundin zieht weg'),
        LayoutTextLine(text: 'ohne Einzug'),
      ]);
      final t = await texte(tester, KeckReceiptLinesWidget(layout: layout));
      expect(t, ['Grund: Kundin zieht weg', 'ohne Einzug']);
      final eingerueckt = tester.getTopLeft(find.text('Grund: Kundin zieht weg')).dx;
      final buendig = tester.getTopLeft(find.text('ohne Einzug')).dx;
      expect(eingerueckt, greaterThan(buendig));
    });
  });
}
