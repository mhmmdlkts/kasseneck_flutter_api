import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/pos.dart';

/// Zusatz-Kacheln gegen dieselben Pruefaelle wie npm und Backend
/// (`add-on-cases.json`); `save` rechnet nur der Server.
void main() {
  final faelle = jsonDecode(File('test/fixtures/vertrag/add-on-cases.json').readAsStringSync()) as Map<String, dynamic>;
  final roh = (faelle['articles'] as Map).cast<String, dynamic>();
  final artikel = {for (final e in roh.entries) e.key: PosArticle.fromJson((e.value as Map).cast<String, dynamic>())};
  final gruppen = {for (final e in (faelle['groups'] as Map).entries) e.key as String: ArticleGroup.fromJson((e.value as Map).cast<String, dynamic>())};
  List<Map<String, dynamic>> abschnitt(String name) => (faelle[name] as List).cast<Map<String, dynamic>>();
  List<KasseneckItem> positionen(List items) => [
        for (final it in items.cast<Map<String, dynamic>>())
          KasseneckItem(
            name: 'x',
            quantity: 1,
            vat: VatRate.vat20,
            priceCents: 100,
            kind: it['kind'] as String?,
            // Der Leser verwirft alles ausser einer ganzen Zahl >= 0; ungueltige
            // Werte (Text, Bruch, negativ, null) stehen hier fuer "kein Verweis"
            // oder werden unten ueber den rohen Wert geprueft.
            addOnOf: it['addOnOf'] is int ? it['addOnOf'] as int : null,
          ),
      ];

  test('Pruefaelle: waehlbar', () {
    for (final f in abschnitt('selectable')) {
      expect(isSelectableAddOn(artikel[f['article']]!), f['reason'], reason: f['article'] as String);
      if (f['reason'] != null) expect(addOnBlockReasons, contains(f['reason']));
    }
  });

  test('Pruefaelle: wirksame Liste', () {
    for (final f in abschnitt('effective')) {
      final g = f['group'] == null ? null : gruppen[f['group']];
      expect(addOnsFor(artikel[f['article']]!, g, artikel), f['addOns'], reason: f['name'] as String);
    }
  });

  test('Pruefaelle: Verweise', () {
    for (final f in abschnitt('references')) {
      final items = f['items'] as List;
      // Was der Leser nicht als Index annimmt, kommt am Draht nicht als Verweis an:
      // der Fall ist dann nur gueltig, wenn der Server ihn auch annaehme.
      final unlesbar = items.any((it) => (it as Map).containsKey('addOnOf') && !(it['addOnOf'] is int && (it['addOnOf'] as int) >= 0));
      if (unlesbar) {
        expect(f['valid'], isFalse, reason: f['name'] as String);
        continue;
      }
      expect(addOnReferencesValid(positionen(items)), f['valid'], reason: f['name'] as String);
    }
  });

  test('Pruefaelle: Storno-Vormerkung', () {
    for (final f in abschnitt('cancellation')) {
      expect(addOnsOfItem(positionen(f['items'] as List), f['index'] as int), f['addOns'], reason: f['name'] as String);
    }
  });

  test('Pruefaelle: Storno-Umrechnung', () {
    for (final f in abschnitt('remap')) {
      final mengen = (f['quantities'] as List).cast<num>();
      expect(addOnRemap(positionen(f['items'] as List), mengen), f['addOnOf'], reason: f['name'] as String);
    }
  });

  test('Pruefaelle: Bon-Reihenfolge', () {
    for (final f in abschnitt('displayOrder')) {
      expect(addOnDisplayOrder(positionen(f['items'] as List)), f['order'], reason: f['name'] as String);
    }
  });

  test('Pruefaelle: Warenkorb -> Beleg', () {
    for (final f in abschnitt('receiptOrder')) {
      final zeilen = (f['lines'] as List).cast<Map<String, dynamic>>();
      final r = orderAddOnLines(zeilen, idOf: (z) => z['id'] as String, parentOf: (z) => z['addOnOf'] as String?);
      expect([for (final z in r) z.line['id']], f['order'], reason: f['name'] as String);
      expect([for (final z in r) z.addOnOf], f['addOnOf'], reason: f['name'] as String);
    }
  });

  test('Hoechstzahl wie Server und npm', () => expect(addOnsMax, (faelle['saveTooMany'] as Map)['max']));

  group('Draht', () {
    test('KasseneckItem: addOnOf hin und zurueck, nur gesetzt', () {
      final mit = KasseneckItem(name: 'Nail Art', quantity: 1, vat: VatRate.vat20, priceCents: 1500, addOnOf: 0);
      expect(mit.toJson()['addOnOf'], 0);
      expect(KasseneckItem.fromJson(mit.toJson()).addOnOf, 0);
      expect(mit.negative.addOnOf, 0);
      final ohne = KasseneckItem(name: 'Tee', quantity: 1, vat: VatRate.vat20, priceCents: 320);
      expect(ohne.toJson().containsKey('addOnOf'), isFalse);
      for (final w in [-1, 0.5, '0', null]) {
        expect(KasseneckItem.fromJson({'name': 'x', 'quantity': 1, 'unitPriceCents': 1, 'vatRate': 20, 'addOnOf': w}).addOnOf, isNull, reason: '$w');
      }
    });

    test('Artikel und Gruppe: addOns gelesen, Fremdes faellt heraus, Zwischenspeicher behaelt es', () {
      final a = PosArticle.fromJson({'id': 'a', 'name': 'A', 'addOns': ['x', 7, '', 'y']});
      expect(a.addOns, ['x', 'y']);
      expect(PosArticle.fromJson(a.toJson()).addOns, ['x', 'y']);
      expect(PosArticle.fromJson({'id': 'a', 'name': 'A'}).addOns, isNull);
      expect(PosArticle.fromJson({'id': 'a', 'name': 'A', 'addOns': []}).addOns, isEmpty);
      final g = ArticleGroup.fromJson({'id': 'g', 'name': 'G', 'addOns': ['x']});
      expect(g.addOns, ['x']);
      expect(ArticleGroup.fromJson(g.toJson()).addOns, ['x']);
      expect(ArticleGroup.fromJson({'id': 'g', 'name': 'G'}).addOns, isNull);
    });
  });

  group('Warenkorb', () {
    CartItemDraft entwurf(String name, int cents, {String? addOnOf, String? articleId}) =>
        CartItemDraft(name: name, unitPriceCents: cents, vatRate: VatRate.vat20, articleId: articleId ?? name, addOnOf: addOnOf);

    test('Zusatz kommt hinter seine Hauptzeile und ihre bisherigen Zusaetze', () {
      var korb = const Cart.empty().added(entwurf('Maniküre', 3600)).added(entwurf('Pediküre', 4200));
      final m = korb.items[0].id;
      korb = korb.added(entwurf('Nail Art', 1500, addOnOf: m)).added(entwurf('Reparatur', 1100, addOnOf: m));
      expect([for (final p in korb.items) p.name], ['Maniküre', 'Nail Art', 'Reparatur', 'Pediküre']);
      expect(korb.hasAddOns(m), isTrue);
      expect(korb.hasAddOns(korb.items[3].id), isFalse);
    });

    test('Zusatz ohne vorhandene Hauptzeile wird eine gewoehnliche Position', () {
      final korb = const Cart.empty().added(entwurf('Nail Art', 1500, addOnOf: 'p-weg'));
      expect(korb.items.single.addOnOf, isNull);
    });

    test('Loeschen der Hauptzeile nimmt ihre Zusaetze mit, auch ueber Menge 0', () {
      var korb = const Cart.empty().added(entwurf('Maniküre', 3600)).added(entwurf('Pediküre', 4200));
      final m = korb.items[0].id;
      final p = korb.items[1].id;
      korb = korb.added(entwurf('Nail Art', 1500, addOnOf: m)).added(entwurf('Massage', 900, addOnOf: p));
      expect([for (final x in korb.removed(m).items) x.name], ['Pediküre', 'Massage']);
      expect([for (final x in korb.withQuantity(p, 0).items) x.name], ['Maniküre', 'Nail Art']);
      // Ein Zusatz allein: nur er.
      final zusatz = korb.items.firstWhere((x) => x.name == 'Nail Art').id;
      expect([for (final x in korb.removed(zusatz).items) x.name], ['Maniküre', 'Pediküre', 'Massage']);
    });

    test('bookTile: Zusatz buendelt nur unter derselben Hauptzeile, Hauptleistung mit Zusaetzen nie', () {
      var b = bookTile(const Cart.empty(), entwurf('Maniküre', 3600), bundle: true);
      final m1 = b.lineId;
      b = bookTile(b.cart, entwurf('Reparatur', 1100, addOnOf: m1), bundle: true);
      b = bookTile(b.cart, entwurf('Reparatur', 1100, addOnOf: m1), bundle: true);
      expect(b.quantity, 2);
      // Dieselbe Hauptleistung nochmal: eigene Zeile, weil die erste Zusaetze traegt.
      b = bookTile(b.cart, entwurf('Maniküre', 3600), bundle: true);
      final m2 = b.lineId;
      expect(m2, isNot(m1));
      // Derselbe Zusatz unter der zweiten Hauptzeile buendelt nicht mit dem der ersten.
      b = bookTile(b.cart, entwurf('Reparatur', 1100, addOnOf: m2), bundle: true);
      expect(b.quantity, 1);
      // Ein Zusatz-Artikel als eigene Kachel buendelt nicht mit dem Zusatz.
      b = bookTile(b.cart, entwurf('Reparatur', 1100), bundle: true);
      expect(b.quantity, 1);
      expect([for (final p in b.cart.items) '${p.name}:${p.quantity}'], ['Maniküre:1', 'Reparatur:2', 'Maniküre:1', 'Reparatur:1', 'Reparatur:1']);
      // Ohne Zusaetze buendelt die Hauptleistung wie bisher.
      var c = bookTile(const Cart.empty(), entwurf('Pediküre', 4200), bundle: true);
      c = bookTile(c.cart, entwurf('Pediküre', 4200), bundle: true);
      expect(c.cart.items.single.quantity, 2);
    });

    test('lines: Zusaetze hinter ihrer Hauptzeile, auch je Stueck', () {
      final m = Position(id: 'p1', name: 'Maniküre', quantity: 1, priceCents: 3600, vat: VatRate.vat20);
      final p = Position(id: 'p2', name: 'Pediküre', quantity: 1, priceCents: 4200, vat: VatRate.vat20);
      final z = Position(id: 'p3', name: 'Reparatur', quantity: 2, priceCents: 1100, vat: VatRate.vat20, addOnOf: 'p1');
      final korb = Cart(items: [m, p, z]);
      expect([for (final l in korb.lines(PosQuantity.x)) l.key], ['p1', 'p3', 'p2']);
      expect([for (final l in korb.lines(PosQuantity.off)) l.key], ['p1#0', 'p3#0', 'p3#1', 'p2#0']);
    });

    test('receiptItems: sortiert, Index nach dem Sortieren, Rabatt hinten', () {
      final m = Position(id: 'p1', name: 'Maniküre', quantity: 1, priceCents: 3600, vat: VatRate.vat20);
      final p = Position(id: 'p2', name: 'Pediküre', quantity: 1, priceCents: 4200, vat: VatRate.vat20);
      final z1 = Position(id: 'p3', name: 'Massage', quantity: 1, priceCents: 900, vat: VatRate.vat20, addOnOf: 'p2');
      final z2 = Position(id: 'p4', name: 'Nail Art', quantity: 1, priceCents: 1500, vat: VatRate.vat20, addOnOf: 'p1');
      final items = receiptItems(Cart(items: [m, p, z1, z2]), 100);
      expect([for (final it in items) it.name].take(4), ['Maniküre', 'Nail Art', 'Pediküre', 'Massage']);
      expect([for (final it in items) it.addOnOf].take(4), [null, 0, null, 2]);
      expect(items.skip(4).every((it) => it.isDiscount && it.addOnOf == null), isTrue);
      expect(addOnReferencesValid(items), isTrue);
      // Hauptzeile herausgefiltert (etwa ein Gutschein-Verkauf): Zusatz ohne Verweis.
      final ohne = receiptItems(Cart(items: [p, z2]), 0);
      expect([for (final it in ohne) it.addOnOf], [null, null]);
    });
  });
}
