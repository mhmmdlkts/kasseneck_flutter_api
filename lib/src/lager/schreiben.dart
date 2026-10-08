/// Pruefung der schreibenden Lager-Anfragen vor dem Senden. Paketintern,
/// nicht Teil der Oberflaeche – Zwilling der Pruefungen in
/// `src/inventory/schreiben.ts` im JS-Paket.
///
/// **Geprueft wird nur, was ohne Netz sicher falsch ist**, und zwar an der
/// Drahtform (`toJson()`), genau wie im JS-Zwilling:
/// - `idempotencyKey` leer, nur Leerraum oder laenger als 120 Zeichen. Ohne
///   gueltigen Schluessel gaebe es keine sichere Wiederholung, und der Server
///   wiese die Anfrage ohnehin ab. Er wird nie getrimmt oder gekuerzt: ein
///   veraenderter Schluessel waere ein anderer;
/// - eine Pflichtkennung fehlt oder ist leer;
/// - eine Ganzzahl liegt ausserhalb von ±(2^53 - 1). Der Server rechnet in
///   JavaScript; jenseits davon kaeme eine andere Zahl an, als gesendet wurde.
///   Bruchzahlen schliesst hier schon der Typ `int` aus;
/// - `expiresInMinutes` liegt ausserhalb 5 … 43 200;
/// - eine Aenderung nennt kein Feld oder leert ein Feld, das sich nicht leeren
///   laesst; eine Freigabe nennt eine leere Liste.
/// Alles Fachliche (Pruefziffer der EAN, Kataloge, Bestand, Rechte) prueft der
/// Server und meldet es mit seinem Code; zwei Pruefungen hiessen zwei
/// Wahrheiten. Eine abgewiesene Anfrage geht nie hinaus.
library;

import '../register/fehler.dart';
import 'vertrag.dart';

KasseneckValidationError anfragefehler(String name, String grund) => KasseneckValidationError(name, grund, 'request');

/// Eine Kennung, die gesendet werden muss: Text mit mindestens einem Zeichen
/// ausser Leerraum. Gesendet wird sie unveraendert.
String kennung(String name, String feld, Object? wert) {
  if (wert is! String || wert.trim().isEmpty) throw anfragefehler(name, '$feld fehlt');
  return wert;
}

/// `idempotencyKey`: Text mit 1–120 Zeichen, nicht nur Leerraum. Nur bei der
/// Vorschau darf er fehlen ([pflicht] `false`).
void pruefeSchluessel(String name, Map<String, dynamic> p, {bool pflicht = true}) {
  final w = p['idempotencyKey'];
  if (w == null) {
    if (pflicht) {
      throw anfragefehler(
          name, 'idempotencyKey fehlt (Pflicht bei jedem Schreiben); bei einer Wiederholung denselben Schluessel senden');
    }
    return;
  }
  if (w is! String || w.trim().isEmpty) throw anfragefehler(name, 'idempotencyKey muss ein nicht leerer Text sein');
  if (w.length > inventoryIdempotencyKeyMax) {
    throw anfragefehler(name, 'idempotencyKey ist laenger als $inventoryIdempotencyKeyMax Zeichen');
  }
}

const int _groessteSichere = 9007199254740991;

/// Jede Ganzzahl der Anfrage, auch in Listen und Abbildungen, im sicheren
/// Bereich von JavaScript.
void pruefeGanzzahlen(String name, Object? wert, [String pfad = '']) {
  switch (wert) {
    // Ohne `abs()`: der Betrag des kleinsten Werts (-2^63) liefe ueber.
    case int w when w > _groessteSichere || w < -_groessteSichere:
      throw anfragefehler(name, '$pfad liegt ausserhalb des sicheren Ganzzahlbereichs (±2^53 - 1)');
    case Map m:
      for (final e in m.entries) {
        pruefeGanzzahlen(name, e.value, pfad.isEmpty ? '${e.key}' : '$pfad.${e.key}');
      }
    case List l:
      for (final (i, e) in l.indexed) {
        pruefeGanzzahlen(name, e, '$pfad[$i]');
      }
  }
}

/// Positionen: jede mit einer Kennung `articleId`. Leer und zu lang
/// entscheidet der Server (`no_positions`, `too_many_positions`).
void pruefePositionen(String name, Object? items) {
  if (items is! List) return;
  for (final (i, p) in items.indexed) {
    kennung(name, 'items[$i].articleId', (p as Map)['articleId']);
  }
}

/// Haltedauer einer Reservierung in ganzen Minuten; `null` nur, wo sie
/// freigestellt ist.
void pruefeMinuten(String name, int? minuten, {required bool pflicht}) {
  if (minuten == null) {
    if (pflicht) throw anfragefehler(name, 'expiresInMinutes fehlt');
    return;
  }
  if (minuten < reservationMinutesMin || minuten > reservationMinutesMax) {
    throw anfragefehler(
        name, 'expiresInMinutes muss eine ganze Zahl von $reservationMinutesMin bis $reservationMinutesMax sein');
  }
}

/// Die Felder eines Artikels, die eine Aenderung leeren darf (`null` am Draht).
const Set<String> leerbareArtikelfelder = {
  'description',
  'unitPriceCents',
  'vatRate',
  'number',
  'groupId',
  'revenueGroupId',
  'minStock',
  'stockLocationIds',
  'externalIds',
  'metadata',
  'minStockByLocation',
  'purchasePriceMicros',
};

/// Die Vorgaben einer Variantengruppe, die eine Aenderung leeren darf
/// (`VariantGroupDefaultsInput.clear`): alle fuenf.
const Set<String> leerbareVorgaben = {'unitPriceCents', 'vatRate', 'unit', 'groupId', 'stockTracked'};

// ---- Inventur (seit 10.7) ------------------------------------------------------

/// Ein Grund (Storno, Nachzaehlen, Abbruch): nicht leer. Die Laenge prueft der Server.
void grundPruefen(String name, String grund) {
  if (grund.trim().isEmpty) throw anfragefehler(name, 'reason fehlt (Grund mit 1 bis 500 Zeichen)');
}

/// Pruefung einer Zaehlung vor dem Senden, geteilt mit dem Kassenweg: die
/// Kennung des Artikels und eine Menge im sicheren Ganzzahlbereich. Die Menge
/// selbst (auch negativ) und die Seriennummern prueft der Server.
void zaehlungPruefen(String name, Map<String, dynamic> p) {
  kennung(name, 'articleId', p['articleId']);
  pruefeGanzzahlen(name, p['quantity'], 'quantity');
}

/// Pruefung eines Stornos vor dem Senden, geteilt mit dem Kassenweg.
void stornoPruefen(String name, Map<String, dynamic> p) {
  kennung(name, 'countId', p['countId']);
  grundPruefen(name, p['reason'] as String);
}
