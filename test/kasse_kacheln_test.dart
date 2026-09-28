import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/kasse.dart';

/// Aus Artikelgruppen und Artikeln werden Kategorien und Kacheln — Zwilling
/// von `kacheln.ts` und `kasse/artikel.ts` im JS-Paket.
///
/// Sichtbar ist nur, was der Betrieb im Panel für die Kasse freigegeben hat;
/// buchbar nur, was einen Preis **und** einen bekannten Steuersatz hat. An
/// [VatRate] hängt der RKSV-Kategoriebuchstabe — eine Kachel mit unbekanntem
/// Satz gehört nicht auf einen unveränderlichen Beleg.

PosArticle artikel({
  String id = 'a1',
  String name = 'Kaffee',
  int? preisCents = 280,
  num? satz = 20,
  String? gruppe = 'g1',
  bool sichtbar = true,
  bool aktiv = true,
  int sort = 0,
  String einheit = 'stk',
  num? maxMenge,
}) =>
    PosArticle.fromJson({
      'id': id,
      'name': name,
      'unitPriceCents': preisCents,
      'vatRate': satz,
      'unit': einheit,
      'groupId': gruppe,
      'tile': {'visible': sichtbar, 'sort': sort},
      'active': aktiv,
      'maxQuantity': maxMenge,
    });

ArticleGroup gruppe({String id = 'g1', String name = 'Getränke', int sort = 0, String farbe = '#1B46F5'}) =>
    ArticleGroup.fromJson({'id': id, 'name': name, 'color': farbe, 'sort': sort});

void main() {
  group('Kategorien', () {
    test('Gruppen nach sort, Kacheln darin nach sort', () {
      final kats = tileCategories(
        [gruppe(id: 'g2', name: 'Speisen', sort: 1), gruppe(id: 'g1', name: 'Getränke')],
        [
          artikel(id: 'a2', name: 'Tee', sort: 1),
          artikel(id: 'a1', name: 'Kaffee'),
          artikel(id: 'a3', name: 'Semmel', gruppe: 'g2'),
        ],
      );

      expect(kats.map((k) => k.name), ['Getränke', 'Speisen']);
      expect(kats.first.tiles.map((a) => a.name), ['Kaffee', 'Tee']);
    });

    test('bei gleichem sort entscheidet der Name', () {
      final kats = tileCategories(
        [gruppe()],
        [artikel(id: 'a2', name: 'Tee'), artikel(id: 'a1', name: 'Kaffee')],
      );
      expect(kats.single.tiles.map((a) => a.name), ['Kaffee', 'Tee']);
    });

    test('unsichtbare und stillgelegte Artikel kommen nicht auf den Schirm', () {
      final kats = tileCategories(
        [gruppe()],
        [
          artikel(id: 'a1', name: 'Kaffee'),
          artikel(id: 'a2', name: 'Versteckt', sichtbar: false),
          artikel(id: 'a3', name: 'Stillgelegt', aktiv: false),
        ],
      );
      expect(kats.single.tiles.map((a) => a.name), ['Kaffee']);
    });

    test('eine Gruppe ohne sichtbare Kacheln erscheint gar nicht', () {
      final kats = tileCategories(
        [gruppe(id: 'g1'), gruppe(id: 'g2', name: 'Leer', sort: 1)],
        [artikel(gruppe: 'g1')],
      );
      expect(kats.map((k) => k.id), ['g1']);
    });

    test('Artikel ohne oder mit unbekannter Gruppe landen hinten unter „Ohne Gruppe"', () {
      final kats = tileCategories(
        [gruppe()],
        [
          artikel(id: 'a1', name: 'Kaffee'),
          artikel(id: 'a2', name: 'Loser', gruppe: null),
          artikel(id: 'a3', name: 'Waise', gruppe: 'weg'),
        ],
      );

      expect(kats.map((k) => k.name), ['Getränke', 'Ohne Gruppe']);
      expect(kats.last.tiles.map((a) => a.name), ['Loser', 'Waise']);
    });
  });

  group('Suche', () {
    final kats = tileCategories(
      [gruppe()],
      [artikel(id: 'a1', name: 'Kaffee'), artikel(id: 'a2', name: 'Käsesemmel')],
    );

    test('findet Teilwörter ohne Rücksicht auf Groß und Klein', () {
      expect(searchTiles(kats, 'kaf').map((a) => a.name), ['Kaffee']);
      expect(searchTiles(kats, 'SEMMEL').map((a) => a.name), ['Käsesemmel']);
    });

    test('ohne Text kein Ergebnis', () {
      expect(searchTiles(kats, '   '), isEmpty);
    });
  });

  group('als Korbeintrag', () {
    test('eine Kachel mit Preis und Satz ist buchbar', () {
      final e = draftFromArticle(artikel())!;
      expect(e.name, 'Kaffee');
      expect(e.unitPriceCents, 280);
      expect(e.vatRate, VatRate.vat20);
    });

    test('ohne Preis nicht buchbar', () {
      expect(draftFromArticle(artikel(preisCents: null)), isNull);
    });

    test('ohne Steuersatz nicht buchbar', () {
      // Am Steuersatz hängt der RKSV-Kategoriebuchstabe; raten wäre schlimmer
      // als die Kachel gesperrt zu lassen.
      expect(draftFromArticle(artikel(satz: null)), isNull);
    });

    test('ein Steuersatz, den die RKSV nicht kennt, sperrt die Kachel', () {
      expect(draftFromArticle(artikel(satz: 7)), isNull);
    });

    test('4,9 % kommen durch — der Satz für Grundnahrungsmittel', () {
      expect(draftFromArticle(artikel(satz: 4.9))!.vatRate, VatRate.vat4_9);
    });

    test('die Höchstmenge des Artikels wandert mit', () {
      expect(draftFromArticle(artikel(maxMenge: 3))!.maxQuantity, 3);
    });
  });

  group('Buchen', () {
    final entwurf = CartItemDraft(name: 'Kaffee', unitPriceCents: 280, vatRate: VatRate.vat20);

    test('gebündelt zählt eine gleiche Zeile hoch', () {
      var korb = const Cart.empty();
      korb = bookTile(korb, entwurf, bundle: true).cart;
      final zweiter = bookTile(korb, entwurf, bundle: true);

      expect(zweiter.cart.items, hasLength(1));
      expect(zweiter.cart.items.single.quantity, 2);
      expect(zweiter.quantity, 2);
    });

    test('ohne Bündeln entsteht je Griff eine Zeile', () {
      var korb = const Cart.empty();
      korb = bookTile(korb, entwurf, bundle: false).cart;
      korb = bookTile(korb, entwurf, bundle: false).cart;
      expect(korb.items, hasLength(2));
    });

    test('ein anderer Preis ist eine andere Zeile, auch beim Bündeln', () {
      var korb = const Cart.empty();
      korb = bookTile(korb, entwurf, bundle: true).cart;
      korb = bookTile(
        korb,
        CartItemDraft(name: 'Kaffee', unitPriceCents: 300, vatRate: VatRate.vat20),
        bundle: true,
      ).cart;
      expect(korb.items, hasLength(2));
    });

    test('die Höchstmenge hält auch beim Bündeln', () {
      var korb = const Cart.empty();
      final begrenzt = CartItemDraft(
        name: 'Kaffee',
        unitPriceCents: 280,
        vatRate: VatRate.vat20,
        maxQuantity: 2,
      );
      for (var i = 0; i < 5; i++) {
        korb = bookTile(korb, begrenzt, bundle: true).cart;
      }
      expect(korb.items.single.quantity, 2);
    });
  });

  group('Mengenregel je Einheit', () {
    test('Stück wird ganzzahlig gebucht und nicht gefragt', () {
      final v = quantityRuleForUnit('stk');
      expect(v.rule, QuantityRule.piece);
      expect(v.ask, isFalse);
    });

    test('Kilogramm ist eine Kommamenge und wird gefragt', () {
      final v = quantityRuleForUnit('kg');
      expect(v.rule, QuantityRule.decimal);
      expect(v.ask, isTrue);
      expect(v.decimals, 3);
    });

    test('Gramm wird gefragt, bleibt aber ganzzahlig', () {
      final v = quantityRuleForUnit('g');
      expect(v.rule, QuantityRule.piece);
      expect(v.ask, isTrue);
    });

    test('die gespeicherte Angabe des Artikels schlägt die Vorgabe', () {
      final a = PosArticle.fromJson({
        'id': 'a1',
        'name': 'Wurst',
        'unit': 'kg',
        'quantityRule': 'piece',
        'askQuantity': false,
      });
      final v = quantityDefaults(a);
      expect(v.rule, QuantityRule.piece);
      expect(v.ask, isFalse);
    });
  });

  group('Hin und zurück', () {
    test('ein Artikel überlebt den Weg durch JSON unverändert', () {
      // Der Zwischenspeicher der Kasse schreibt und liest ihn so.
      final vorher = artikel(maxMenge: 3, einheit: 'kg');
      final nachher = PosArticle.fromJson(vorher.toJson());

      expect(nachher.id, vorher.id);
      expect(nachher.name, vorher.name);
      expect(nachher.unitPriceCents, vorher.unitPriceCents);
      expect(nachher.vatRate, vorher.vatRate);
      expect(nachher.unit, vorher.unit);
      expect(nachher.groupId, vorher.groupId);
      expect(nachher.visible, vorher.visible);
      expect(nachher.maxQuantity, vorher.maxQuantity);
    });

    test('ein Preis mit Gleitkomma-Rest wird gerundet, nicht abgeschnitten', () {
      // Das Backend rechnet in JavaScript aus Euro hoch: 19.99 * 100 ist dort
      // exakt 1998.9999999999998. Abgeschnitten verkaufte sich der Artikel
      // dauerhaft einen Cent zu billig — auf einen signierten Beleg.
      for (final (double euro, int cents) in [
        (19.99, 1999),
        (8.70, 870),
        (1.15, 115),
        (0.29, 29),
      ]) {
        final a = PosArticle.fromJson({'id': 'a1', 'name': 'Ware', 'unitPriceCents': euro * 100});
        expect(a.unitPriceCents, cents, reason: '$euro EUR');
      }
      // Ganze Werte bleiben, wie sie sind.
      expect(PosArticle.fromJson({'unitPriceCents': 1999}).unitPriceCents, 1999);
      expect(PosArticle.fromJson({'unitPriceCents': null}).unitPriceCents, isNull);
    });

    test('auch ein Artikel ohne Preis und Gruppe kommt heil zurück', () {
      final vorher = artikel(preisCents: null, satz: null, gruppe: null);
      final nachher = PosArticle.fromJson(vorher.toJson());
      expect(nachher.unitPriceCents, isNull);
      expect(nachher.vatRate, isNull);
      expect(nachher.groupId, isNull);
    });

    test('eine Gruppe ebenso', () {
      final vorher = gruppe(farbe: '#ABCDEF', sort: 3);
      final nachher = ArticleGroup.fromJson(vorher.toJson());
      expect(nachher.color, '#ABCDEF');
      expect(nachher.sort, 3);
      expect(nachher.name, vorher.name);
    });
  });

  group('Kachelfarbe', () {
    test('auf Dunkel steht heller Text, auf Hell dunkler', () {
      expect(textColorOn('#1B46F5'), '#ffffff');
      expect(textColorOn('#FFE066'), '#0f172a');
    });

    test('eine kaputte Farbe bekommt hellen Text statt eines Absturzes', () {
      expect(textColorOn('quatsch'), '#ffffff');
    });
  });
}
