/// Aus Artikelgruppen und Artikeln werden Kategorien und Kacheln — Zwilling
/// von `tiles.ts` der Browser-Kasse.
///
/// Reine Ableitung ohne Netz: sichtbar ist nur, was der Betrieb im Panel für
/// die Kasse freigegeben hat und was nicht stillgelegt ist. Die Sortierung
/// folgt der Gruppe (`sort`, dann Name) bzw. dem Artikel.
///
/// **Buchbar ist nur, was einen Preis und einen bekannten Steuersatz hat.** An
/// [VatRate] hängt der RKSV-Kategoriebuchstabe (A/B/C/D/E/G), und der hängt an
/// der Signaturkette des Backends — einen unbekannten Satz zu raten wäre
/// schlimmer, als die Kachel gesperrt zu lassen.
library;

import '../../enums/vat_rate.dart';
import 'artikel.dart';
import 'artikel_id.dart';
import 'warenkorb.dart';

const String ungroupedId = '__ohne__';
const String ungroupedColor = '#64748B';

class TileCategory {
  const TileCategory({
    required this.id,
    required this.name,
    required this.color,
    required this.tiles,
    this.symbol,
  });

  final String id;
  final String name;
  final String color;
  final String? symbol;
  final List<PosArticle> tiles;
}

int _nachName(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

List<TileCategory> tileCategories(List<ArticleGroup> groups, List<PosArticle> articles) {
  final sichtbar = [
    for (final a in articles)
      if (a.visible && a.active) a,
  ];
  final sortiert = [...groups]..sort((a, b) {
      final s = a.sort.compareTo(b.sort);
      return s != 0 ? s : _nachName(a.name, b.name);
    });
  final bekannt = {for (final g in sortiert) g.id};

  List<PosArticle> kachelnJe(bool Function(PosArticle) passt) {
    final aus = [
      for (final a in sichtbar)
        if (passt(a)) a,
    ];
    aus.sort((a, b) {
      final s = a.sort.compareTo(b.sort);
      return s != 0 ? s : _nachName(a.name, b.name);
    });
    return aus;
  }

  final aus = <TileCategory>[];
  for (final g in sortiert) {
    final kacheln = kachelnJe((a) => a.groupId == g.id);
    // Eine leere Kategorie ist kein Angebot, sondern ein Griff ins Leere.
    if (kacheln.isEmpty) continue;
    aus.add(TileCategory(id: g.id, name: g.name, color: g.color, symbol: g.symbol, tiles: kacheln));
  }

  // Artikel ohne (oder mit gelöschter) Gruppe gehen nicht verloren — sie
  // landen hinten, damit der Betrieb sie überhaupt bemerkt.
  final rest = kachelnJe((a) => a.groupId == null || !bekannt.contains(a.groupId));
  if (rest.isNotEmpty) {
    aus.add(TileCategory(id: ungroupedId, name: 'Ohne Gruppe', color: ungroupedColor, tiles: rest));
  }
  return aus;
}

/// Suche über alle sichtbaren Kacheln (Name, ohne Groß/Klein, Teilwort).
List<PosArticle> searchTiles(List<TileCategory> categories, String text) {
  final t = text.trim().toLowerCase();
  if (t.isEmpty) return const [];
  final gesehen = <String>{};
  final aus = <PosArticle>[];
  for (final k in categories) {
    for (final a in k.tiles) {
      if (gesehen.contains(a.id)) continue;
      if (!a.name.toLowerCase().contains(t)) continue;
      gesehen.add(a.id);
      aus.add(a);
    }
  }
  return aus;
}

/// Der RKSV-Steuersatz zu einer Prozentzahl — oder `null` bei Unbekanntem.
VatRate? vatRateFor(num rate) {
  for (final v in VatRate.values) {
    if (v.rate == rate) return v;
  }
  return null;
}

/// Was aus einer Kachel im Korb wird; `null`, wenn die Kachel nicht buchbar ist.
CartItemDraft? draftFromArticle(PosArticle a) {
  final satz = a.vatRate == null ? null : vatRateFor(a.vatRate!);
  final preis = a.unitPriceCents;
  if (satz == null || preis == null || preis < 0) return null;
  return CartItemDraft(
    name: a.name,
    unitPriceCents: preis,
    vatRate: satz,
    maxQuantity: a.maxQuantity?.toInt(),
    articleId: artikelIdOderNull(a.id),
  );
}

/// Kontrastfarbe für Text auf voller Kachelfläche. Eine kaputte Farbe bekommt
/// hellen Text statt eines Absturzes.
String textColorOn(String hex) {
  final h = hex.replaceFirst('#', '');
  if (h.length != 6) return '#ffffff';
  final r = int.tryParse(h.substring(0, 2), radix: 16);
  final g = int.tryParse(h.substring(2, 4), radix: 16);
  final b = int.tryParse(h.substring(4, 6), radix: 16);
  if (r == null || g == null || b == null) return '#ffffff';
  return (0.299 * r + 0.587 * g + 0.114 * b) > 165 ? '#0f172a' : '#ffffff';
}

/// Ergebnis eines Kachelgriffs: der neue Korb und die betroffene Zeile.
class TileBooking {
  const TileBooking({required this.cart, required this.lineId, required this.quantity});

  final Cart cart;
  final String lineId;
  final int quantity;
}

/// Kachel in den Korb.
///
/// Mit [bundle] wird eine gleiche Zeile (Name, Preis, Satz **und**
/// Artikel-ID) hochgezählt, ohne entsteht je Griff eine Zeile. Zwei Artikel
/// gleichen Aussehens bleiben zwei Zeilen (jeder bucht sein eigenes Lager),
/// ebenso ein Artikel und eine freie Position; freie Positionen ohne ID
/// bündeln wie bisher. Eine leere Artikel-ID gilt auf beiden Seiten als
/// keine (auch an einer von Hand gebauten [Position]). Die Höchstmenge des
/// Artikels hält auch hier — [Cart.withQuantity] deckelt, egal woher der
/// Griff kommt.
TileBooking bookTile(Cart cart, CartItemDraft draft, {required bool bundle}) {
  if (bundle) {
    final artikel = artikelIdOderNull(draft.articleId);
    for (final p in cart.items) {
      if (p.name != draft.name.trim()) continue;
      if (p.priceCents != draft.unitPriceCents) continue;
      if (p.vat != draft.vatRate) continue;
      if (artikelIdOderNull(p.articleId) != artikel) continue;
      final neu = cart.withQuantity(p.id, p.quantity + 1);
      final zeile = neu.items.firstWhere((z) => z.id == p.id);
      return TileBooking(cart: neu, lineId: p.id, quantity: zeile.quantity);
    }
  }
  final neu = cart.added(draft);
  // Ohne Bezeichnung bleibt der Korb unverändert; dann gibt es keine Zeile.
  if (identical(neu, cart) || neu.items.isEmpty) {
    return TileBooking(cart: cart, lineId: '', quantity: 0);
  }
  return TileBooking(cart: neu, lineId: neu.items.last.id, quantity: 1);
}

