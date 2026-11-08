/// Zusatz-Kacheln (11.18.0): Tippt man eine Hauptleistung an, oeffnet die
/// Kasse ein Fenster mit ihren Zusaetzen. Die Liste steht an der Gruppe, je
/// Artikel abweichend (`addOns`: `null` = wie die Gruppe, leer = keine, sonst
/// eigene Liste). Jeder Zusatz wird eine eigene Belegposition mit `addOnOf` =
/// Index der Hauptposition.
///
/// Zwilling von `pos/zusaetze.ts` im JS-Paket; Backend `gemeinsam/zusatz-core.js`.
/// Der Vertrag sind die Pruefaelle `test/fixtures/vertrag/add-on-cases.json`.
library;

import '../../models/kasseneck_item.dart';
import 'artikel.dart';

/// Hoechstens so viele Zusaetze je Liste (der Server weist mehr ab).
const int addOnsMax = 30;

/// Warum ein Artikel kein Zusatz sein kann (Panel zeigt den Grund an).
const List<String> addOnBlockReasons = ['inactive', 'own_list', 'asks_price', 'reference', 'asks_quantity', 'no_price', 'service_voucher', 'external_voucher'];

bool _eigeneListe(PosArticle a) => a.addOns != null && a.addOns!.isNotEmpty;

/// Taugt der Artikel als Zusatz? `null` = ja, sonst ein Wert aus
/// [addOnBlockReasons]. Im Fenster wird ohne Abfrage gebucht: Betrag,
/// Referenz oder Menge fragen geht nicht, ein Preis muss feststehen (0
/// erlaubt), ein Leistungsgutschein oder fremder Gutschein liefe am
/// Gutschein-Weg vorbei, und ein Artikel mit eigener Liste oeffnete selbst ein
/// Fenster (eine Ebene).
String? isSelectableAddOn(PosArticle a) {
  if (!a.active) return 'inactive';
  if (_eigeneListe(a)) return 'own_list';
  if (a.askPrice) return 'asks_price';
  if (a.reference != null) return 'reference';
  if (a.askQuantity == true) return 'asks_quantity';
  if (a.unitPriceCents == null || a.unitPriceCents! < 0) return 'no_price';
  if (a.serviceVoucher) return 'service_voucher';
  if (a.externalVoucher != null) return 'external_voucher';
  return null;
}

/// Wirksame Zusatzliste eines Artikels: eigene Liste (auch leer) vor der der
/// Gruppe; still heraus fallen der Artikel selbst, Unbekanntes, Dubletten und
/// alles, was nicht als Zusatz taugt. Leer = kein Fenster.
List<String> addOnsFor(PosArticle article, ArticleGroup? group, Map<String, PosArticle> articleById) {
  final liste = article.addOns ?? group?.addOns ?? const <String>[];
  final raus = <String>[];
  for (final id in liste) {
    if (id == article.id || raus.contains(id)) continue;
    final z = articleById[id];
    if (z == null || isSelectableAddOn(z) != null) continue;
    raus.add(id);
  }
  return raus;
}

/// Positionsarten, die nie Zusatz oder Hauptposition sind (Trinkgeld, Rabatt, Gutschein).
const Set<String> _ohneZusatz = {'tip', 'discount', 'voucher', 'voucher_float'};

/// Halten die Verweise den Server-Regeln stand? Ganze Zahl, zeigt nach vorne
/// auf eine Warenposition, die selbst kein Zusatz ist (sonst antwortet
/// createReceipt mit `invalid_add_on_reference`).
bool addOnReferencesValid(List<KasseneckItem> items) {
  for (var i = 0; i < items.length; i++) {
    final z = items[i].addOnOf;
    if (z == null) continue;
    if (z < 0 || z >= i) return false;
    if (_ohneZusatz.contains(items[i].kind) || _ohneZusatz.contains(items[z].kind)) return false;
    if (items[z].addOnOf != null) return false;
  }
  return true;
}

/// Indizes der Zusaetze einer Hauptposition (Storno: mit vormerken, abwaehlbar).
List<int> addOnsOfItem(List<KasseneckItem> items, int index) => [
      for (var i = 0; i < items.length; i++)
        if (items[i].addOnOf == index) i,
    ];

/// Storno: Verweis je Storno-Position (in der Reihenfolge der stornierten
/// Positionen, Menge > 0). Ein Zusatz behaelt ihn nur, wenn seine
/// Hauptposition mit storniert wird, umgerechnet auf den neuen Index; sonst `null`.
List<int?> addOnRemap(List<KasseneckItem> items, List<num> quantities) {
  final neu = <int, int>{};
  final raus = <int?>[];
  for (var i = 0; i < items.length; i++) {
    if (!(i < quantities.length && quantities[i] > 0)) continue;
    neu[i] = raus.length;
    final z = items[i].addOnOf;
    raus.add(z != null && neu.containsKey(z) ? neu[z] : null);
  }
  return raus;
}

/// Ist Position [index] ein gueltiger Zusatz (Verweis nach vorne auf eine
/// Hauptposition)? Fuer Layout und Druck-Rueckfall.
bool isValidAddOnAt(List<KasseneckItem> items, int index) {
  final z = items[index].addOnOf;
  return z != null && z >= 0 && z < index && items[z].addOnOf == null;
}

/// Bon-Reihenfolge: jede Hauptposition, direkt gefolgt von ihren Zusaetzen
/// (stabil). Positionen mit ungueltigem Verweis bleiben an ihrem Platz.
List<int> addOnDisplayOrder(List<KasseneckItem> items) {
  final raus = <int>[];
  for (var i = 0; i < items.length; i++) {
    if (isValidAddOnAt(items, i)) continue;
    raus.add(i);
    for (var j = i + 1; j < items.length; j++) {
      if (isValidAddOnAt(items, j) && items[j].addOnOf == i) raus.add(j);
    }
  }
  return raus;
}

/// Eine Zeile nach [orderAddOnLines]: die Zeile und der Index ihrer Hauptzeile.
typedef OrderedAddOnLine<T> = ({T line, int? addOnOf});

/// Warenkorb -> Belegpositionen: Zeilen tragen die Zeilen-Id ihrer Hauptzeile
/// ([parentOf]). Sortiert jeden Zusatz hinter seine Hauptzeile (stabil) und
/// rechnet den Verweis in den Index um. Fehlt die Hauptzeile (geloescht oder
/// vorher herausgefiltert, etwa ein Gutschein-Verkauf), bleibt die Zeile ohne
/// Verweis an ihrem Platz.
List<OrderedAddOnLine<T>> orderAddOnLines<T>(List<T> lines, {required String Function(T) idOf, required String? Function(T) parentOf}) {
  final ids = {for (final l in lines) idOf(l)};
  bool istZusatz(T l) {
    final p = parentOf(l);
    if (p == null || p == idOf(l) || !ids.contains(p)) return false;
    return !lines.any((h) => idOf(h) == p && parentOf(h) != null && ids.contains(parentOf(h)));
  }

  final raus = <OrderedAddOnLine<T>>[];
  for (final l in lines) {
    if (istZusatz(l)) continue;
    final index = raus.length;
    raus.add((line: l, addOnOf: null));
    for (final z in lines) {
      if (istZusatz(z) && parentOf(z) == idOf(l)) raus.add((line: z, addOnOf: index));
    }
  }
  return raus;
}
