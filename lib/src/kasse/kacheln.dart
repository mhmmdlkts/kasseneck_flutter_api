/// Aus Artikelgruppen und Artikeln werden Kategorien und Kacheln — Zwilling
/// von `kacheln.ts` der Browser-Kasse.
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
import 'warenkorb.dart';

const String ohneGruppeId = '__ohne__';
const String ohneGruppeFarbe = '#64748B';

class Kategorie {
  const Kategorie({
    required this.id,
    required this.name,
    required this.farbe,
    required this.kacheln,
    this.symbol,
  });

  final String id;
  final String name;
  final String farbe;
  final String? symbol;
  final List<KasseArtikel> kacheln;
}

int _nachName(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

List<Kategorie> kategorien(List<Artikelgruppe> gruppen, List<KasseArtikel> artikel) {
  final sichtbar = [
    for (final a in artikel)
      if (a.sichtbar && a.aktiv) a,
  ];
  final sortiert = [...gruppen]..sort((a, b) {
      final s = a.sort.compareTo(b.sort);
      return s != 0 ? s : _nachName(a.name, b.name);
    });
  final bekannt = {for (final g in sortiert) g.id};

  List<KasseArtikel> kachelnJe(bool Function(KasseArtikel) passt) {
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

  final aus = <Kategorie>[];
  for (final g in sortiert) {
    final kacheln = kachelnJe((a) => a.gruppeId == g.id);
    // Eine leere Kategorie ist kein Angebot, sondern ein Griff ins Leere.
    if (kacheln.isEmpty) continue;
    aus.add(Kategorie(id: g.id, name: g.name, farbe: g.farbe, symbol: g.symbol, kacheln: kacheln));
  }

  // Artikel ohne (oder mit gelöschter) Gruppe gehen nicht verloren — sie
  // landen hinten, damit der Betrieb sie überhaupt bemerkt.
  final rest = kachelnJe((a) => a.gruppeId == null || !bekannt.contains(a.gruppeId));
  if (rest.isNotEmpty) {
    aus.add(Kategorie(id: ohneGruppeId, name: 'Ohne Gruppe', farbe: ohneGruppeFarbe, kacheln: rest));
  }
  return aus;
}

/// Suche über alle sichtbaren Kacheln (Name, ohne Groß/Klein, Teilwort).
List<KasseArtikel> suche(List<Kategorie> kategorien, String text) {
  final t = text.trim().toLowerCase();
  if (t.isEmpty) return const [];
  final gesehen = <String>{};
  final aus = <KasseArtikel>[];
  for (final k in kategorien) {
    for (final a in k.kacheln) {
      if (gesehen.contains(a.id)) continue;
      if (!a.name.toLowerCase().contains(t)) continue;
      gesehen.add(a.id);
      aus.add(a);
    }
  }
  return aus;
}

/// Der RKSV-Steuersatz zu einer Prozentzahl — oder `null` bei Unbekanntem.
VatRate? steuersatzZu(num rate) {
  for (final v in VatRate.values) {
    if (v.rate == rate) return v;
  }
  return null;
}

/// Was aus einer Kachel im Korb wird; `null`, wenn die Kachel nicht buchbar ist.
Positionsentwurf? alsEntwurf(KasseArtikel a) {
  final satz = a.steuersatz == null ? null : steuersatzZu(a.steuersatz!);
  final preis = a.preisCents;
  if (satz == null || preis == null || preis < 0) return null;
  return Positionsentwurf(
    bezeichnung: a.name,
    betragCents: preis,
    steuersatz: satz,
    maxMenge: a.maxMenge?.toInt(),
  );
}

/// Kontrastfarbe für Text auf voller Kachelfläche. Eine kaputte Farbe bekommt
/// hellen Text statt eines Absturzes.
String textAuf(String hex) {
  final h = hex.replaceFirst('#', '');
  if (h.length != 6) return '#ffffff';
  final r = int.tryParse(h.substring(0, 2), radix: 16);
  final g = int.tryParse(h.substring(2, 4), radix: 16);
  final b = int.tryParse(h.substring(4, 6), radix: 16);
  if (r == null || g == null || b == null) return '#ffffff';
  return (0.299 * r + 0.587 * g + 0.114 * b) > 165 ? '#0f172a' : '#ffffff';
}

/// Ergebnis eines Kachelgriffs: der neue Korb und die betroffene Zeile.
class Kachelbuchung {
  const Kachelbuchung({required this.korb, required this.zeileId, required this.menge});

  final Warenkorb korb;
  final String zeileId;
  final int menge;
}

/// Kachel in den Korb.
///
/// Mit [buendeln] wird eine gleiche Zeile (Name, Preis, Satz) hochgezählt, ohne
/// entsteht je Griff eine Zeile. Die Höchstmenge des Artikels hält auch hier —
/// [Warenkorb.mengeGesetzt] deckelt, egal woher der Griff kommt.
Kachelbuchung gebucht(Warenkorb korb, Positionsentwurf entwurf, {required bool buendeln}) {
  if (buendeln) {
    for (final p in korb.positionen) {
      if (p.name != entwurf.bezeichnung.trim()) continue;
      if (p.priceCents != entwurf.betragCents) continue;
      if (p.vat != entwurf.steuersatz) continue;
      final neu = korb.mengeGesetzt(p.id, p.quantity + 1);
      final zeile = neu.positionen.firstWhere((z) => z.id == p.id);
      return Kachelbuchung(korb: neu, zeileId: p.id, menge: zeile.quantity);
    }
  }
  final neu = korb.hinzugefuegt(entwurf);
  // Ohne Bezeichnung bleibt der Korb unverändert; dann gibt es keine Zeile.
  if (identical(neu, korb) || neu.positionen.isEmpty) {
    return Kachelbuchung(korb: korb, zeileId: '', menge: 0);
  }
  return Kachelbuchung(korb: neu, zeileId: neu.positionen.last.id, menge: 1);
}
