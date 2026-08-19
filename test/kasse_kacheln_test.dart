import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/kasse.dart';

/// Aus Artikelgruppen und Artikeln werden Kategorien und Kacheln — Zwilling
/// von `kacheln.ts` und `kasse/artikel.ts` im JS-Paket.
///
/// Sichtbar ist nur, was der Betrieb im Panel für die Kasse freigegeben hat;
/// buchbar nur, was einen Preis **und** einen bekannten Steuersatz hat. An
/// [VatRate] hängt der RKSV-Kategoriebuchstabe — eine Kachel mit unbekanntem
/// Satz gehört nicht auf einen unveränderlichen Beleg.

KasseArtikel artikel({
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
    KasseArtikel.aus({
      'id': id,
      'name': name,
      'unitPriceCents': preisCents,
      'vatRate': satz,
      'unit': einheit,
      'groupId': gruppe,
      'kasse': {'sichtbar': sichtbar, 'sort': sort},
      'active': aktiv,
      'maxMenge': maxMenge,
    });

Artikelgruppe gruppe({String id = 'g1', String name = 'Getränke', int sort = 0, String farbe = '#1B46F5'}) =>
    Artikelgruppe.aus({'id': id, 'name': name, 'color': farbe, 'sort': sort});

void main() {
  group('Kategorien', () {
    test('Gruppen nach sort, Kacheln darin nach sort', () {
      final kats = kategorien(
        [gruppe(id: 'g2', name: 'Speisen', sort: 1), gruppe(id: 'g1', name: 'Getränke')],
        [
          artikel(id: 'a2', name: 'Tee', sort: 1),
          artikel(id: 'a1', name: 'Kaffee'),
          artikel(id: 'a3', name: 'Semmel', gruppe: 'g2'),
        ],
      );

      expect(kats.map((k) => k.name), ['Getränke', 'Speisen']);
      expect(kats.first.kacheln.map((a) => a.name), ['Kaffee', 'Tee']);
    });

    test('bei gleichem sort entscheidet der Name', () {
      final kats = kategorien(
        [gruppe()],
        [artikel(id: 'a2', name: 'Tee'), artikel(id: 'a1', name: 'Kaffee')],
      );
      expect(kats.single.kacheln.map((a) => a.name), ['Kaffee', 'Tee']);
    });

    test('unsichtbare und stillgelegte Artikel kommen nicht auf den Schirm', () {
      final kats = kategorien(
        [gruppe()],
        [
          artikel(id: 'a1', name: 'Kaffee'),
          artikel(id: 'a2', name: 'Versteckt', sichtbar: false),
          artikel(id: 'a3', name: 'Stillgelegt', aktiv: false),
        ],
      );
      expect(kats.single.kacheln.map((a) => a.name), ['Kaffee']);
    });

    test('eine Gruppe ohne sichtbare Kacheln erscheint gar nicht', () {
      final kats = kategorien(
        [gruppe(id: 'g1'), gruppe(id: 'g2', name: 'Leer', sort: 1)],
        [artikel(gruppe: 'g1')],
      );
      expect(kats.map((k) => k.id), ['g1']);
    });

    test('Artikel ohne oder mit unbekannter Gruppe landen hinten unter „Ohne Gruppe"', () {
      final kats = kategorien(
        [gruppe()],
        [
          artikel(id: 'a1', name: 'Kaffee'),
          artikel(id: 'a2', name: 'Loser', gruppe: null),
          artikel(id: 'a3', name: 'Waise', gruppe: 'weg'),
        ],
      );

      expect(kats.map((k) => k.name), ['Getränke', 'Ohne Gruppe']);
      expect(kats.last.kacheln.map((a) => a.name), ['Loser', 'Waise']);
    });
  });

  group('Suche', () {
    final kats = kategorien(
      [gruppe()],
      [artikel(id: 'a1', name: 'Kaffee'), artikel(id: 'a2', name: 'Käsesemmel')],
    );

    test('findet Teilwörter ohne Rücksicht auf Groß und Klein', () {
      expect(suche(kats, 'kaf').map((a) => a.name), ['Kaffee']);
      expect(suche(kats, 'SEMMEL').map((a) => a.name), ['Käsesemmel']);
    });

    test('ohne Text kein Ergebnis', () {
      expect(suche(kats, '   '), isEmpty);
    });
  });

  group('als Korbeintrag', () {
    test('eine Kachel mit Preis und Satz ist buchbar', () {
      final e = alsEntwurf(artikel())!;
      expect(e.bezeichnung, 'Kaffee');
      expect(e.betragCents, 280);
      expect(e.steuersatz, VatRate.vat20);
    });

    test('ohne Preis nicht buchbar', () {
      expect(alsEntwurf(artikel(preisCents: null)), isNull);
    });

    test('ohne Steuersatz nicht buchbar', () {
      // Am Steuersatz hängt der RKSV-Kategoriebuchstabe; raten wäre schlimmer
      // als die Kachel gesperrt zu lassen.
      expect(alsEntwurf(artikel(satz: null)), isNull);
    });

    test('ein Steuersatz, den die RKSV nicht kennt, sperrt die Kachel', () {
      expect(alsEntwurf(artikel(satz: 7)), isNull);
    });

    test('4,9 % kommen durch — der Satz für Grundnahrungsmittel', () {
      expect(alsEntwurf(artikel(satz: 4.9))!.steuersatz, VatRate.vat4komma9);
    });

    test('die Höchstmenge des Artikels wandert mit', () {
      expect(alsEntwurf(artikel(maxMenge: 3))!.maxMenge, 3);
    });
  });

  group('Buchen', () {
    final entwurf = Positionsentwurf(bezeichnung: 'Kaffee', betragCents: 280, steuersatz: VatRate.vat20);

    test('gebündelt zählt eine gleiche Zeile hoch', () {
      var korb = const Warenkorb.leer();
      korb = gebucht(korb, entwurf, buendeln: true).korb;
      final zweiter = gebucht(korb, entwurf, buendeln: true);

      expect(zweiter.korb.positionen, hasLength(1));
      expect(zweiter.korb.positionen.single.quantity, 2);
      expect(zweiter.menge, 2);
    });

    test('ohne Bündeln entsteht je Griff eine Zeile', () {
      var korb = const Warenkorb.leer();
      korb = gebucht(korb, entwurf, buendeln: false).korb;
      korb = gebucht(korb, entwurf, buendeln: false).korb;
      expect(korb.positionen, hasLength(2));
    });

    test('ein anderer Preis ist eine andere Zeile, auch beim Bündeln', () {
      var korb = const Warenkorb.leer();
      korb = gebucht(korb, entwurf, buendeln: true).korb;
      korb = gebucht(
        korb,
        Positionsentwurf(bezeichnung: 'Kaffee', betragCents: 300, steuersatz: VatRate.vat20),
        buendeln: true,
      ).korb;
      expect(korb.positionen, hasLength(2));
    });

    test('die Höchstmenge hält auch beim Bündeln', () {
      var korb = const Warenkorb.leer();
      final begrenzt = Positionsentwurf(
        bezeichnung: 'Kaffee',
        betragCents: 280,
        steuersatz: VatRate.vat20,
        maxMenge: 2,
      );
      for (var i = 0; i < 5; i++) {
        korb = gebucht(korb, begrenzt, buendeln: true).korb;
      }
      expect(korb.positionen.single.quantity, 2);
    });
  });

  group('Mengenregel je Einheit', () {
    test('Stück wird ganzzahlig gebucht und nicht gefragt', () {
      final v = mengenregelFuerEinheit('stk');
      expect(v.regel, Mengenregel.stueck);
      expect(v.fragen, isFalse);
    });

    test('Kilogramm ist eine Kommamenge und wird gefragt', () {
      final v = mengenregelFuerEinheit('kg');
      expect(v.regel, Mengenregel.dezimal);
      expect(v.fragen, isTrue);
      expect(v.stellen, 3);
    });

    test('Gramm wird gefragt, bleibt aber ganzzahlig', () {
      final v = mengenregelFuerEinheit('g');
      expect(v.regel, Mengenregel.stueck);
      expect(v.fragen, isTrue);
    });

    test('die gespeicherte Angabe des Artikels schlägt die Vorgabe', () {
      final a = KasseArtikel.aus({
        'id': 'a1',
        'name': 'Wurst',
        'unit': 'kg',
        'mengenregel': 'stueck',
        'mengeFragen': false,
      });
      final v = mengenVorgabe(a);
      expect(v.regel, Mengenregel.stueck);
      expect(v.fragen, isFalse);
    });
  });

  group('Hin und zurück', () {
    test('ein Artikel überlebt den Weg durch JSON unverändert', () {
      // Der Zwischenspeicher der Kasse schreibt und liest ihn so.
      final vorher = artikel(maxMenge: 3, einheit: 'kg');
      final nachher = KasseArtikel.aus(vorher.toJson());

      expect(nachher.id, vorher.id);
      expect(nachher.name, vorher.name);
      expect(nachher.preisCents, vorher.preisCents);
      expect(nachher.steuersatz, vorher.steuersatz);
      expect(nachher.einheit, vorher.einheit);
      expect(nachher.gruppeId, vorher.gruppeId);
      expect(nachher.sichtbar, vorher.sichtbar);
      expect(nachher.maxMenge, vorher.maxMenge);
    });

    test('auch ein Artikel ohne Preis und Gruppe kommt heil zurück', () {
      final vorher = artikel(preisCents: null, satz: null, gruppe: null);
      final nachher = KasseArtikel.aus(vorher.toJson());
      expect(nachher.preisCents, isNull);
      expect(nachher.steuersatz, isNull);
      expect(nachher.gruppeId, isNull);
    });

    test('eine Gruppe ebenso', () {
      final vorher = gruppe(farbe: '#ABCDEF', sort: 3);
      final nachher = Artikelgruppe.aus(vorher.toJson());
      expect(nachher.farbe, '#ABCDEF');
      expect(nachher.sort, 3);
      expect(nachher.name, vorher.name);
    });
  });

  group('Kachelfarbe', () {
    test('auf Dunkel steht heller Text, auf Hell dunkler', () {
      expect(textAuf('#1B46F5'), '#ffffff');
      expect(textAuf('#FFE066'), '#0f172a');
    });

    test('eine kaputte Farbe bekommt hellen Text statt eines Absturzes', () {
      expect(textAuf('quatsch'), '#ffffff');
    });
  });
}
