/// Positionen und Rueckgabe-Wahl eines Stornos fuer die Nutzlast – der eine
/// Bau fuer beide Storno-Wege (`RegisterReceiptClient.cancelReceipt` und
/// `KasseneckApi.cancelReceipt`). Zwilling von `pruefeRueckgabeWahl` und dem
/// Nutzlastbau in `cancelReceipt` des JS-Pakets. Paketintern.
library;

import '../register/fehler.dart' show KasseneckValidationError;
import 'belege.dart' show CancellationItem;
import 'rueckgabe.dart';

/// `items` und `returnDisposition` der Storno-Nutzlast, geprueft **bevor**
/// etwas hinausgeht.
///
/// Ohne Wahl ist die Nutzlast genau die von bisher (`{index, quantity}` je
/// Position, kein `returnDisposition`). Eine Wahl je Position haengt hinter
/// `quantity`; sie braucht ihre Position in [items] (ohne [items] ist es ein
/// Vollstorno, dann gilt allein [returnDisposition]). Ein Wert ausserhalb von
/// [returnDispositions] wirft [KasseneckValidationError] (`request`).
({List<Map<String, Object>>? items, String? returnDisposition}) cancellationPayload(
  String name, {
  List<CancellationItem>? items,
  String? returnDisposition,
  Map<int, String>? itemReturnDispositions,
}) {
  if (returnDisposition != null) _gueltig(name, returnDisposition, 'returnDisposition');
  final wahl = itemReturnDispositions ?? const <int, String>{};
  if (wahl.isNotEmpty) {
    if (items == null) {
      throw KasseneckValidationError(
          name, 'itemReturnDispositions gibt es nur mit items; fuer den ganzen Beleg returnDisposition angeben', 'request');
    }
    final indizes = {for (final p in items) p.index};
    for (final index in wahl.keys) {
      if (!indizes.contains(index)) {
        throw KasseneckValidationError(name, 'itemReturnDispositions[$index]: die Position steht nicht in items', 'request');
      }
    }
  }
  final positionen = items == null
      ? null
      : [
          for (final (i, p) in items.indexed)
            {
              'index': p.index,
              'quantity': p.quantity,
              if (wahl[p.index] case final w?) 'returnDisposition': _gueltig(name, w, 'items[$i].returnDisposition'),
            },
        ];
  return (items: positionen, returnDisposition: returnDisposition);
}

/// [wert] unveraendert, wenn er eine Rueckgabe-Wahl ist; sonst wirft es.
String _gueltig(String name, String wert, String pfad) {
  if (!isReturnDisposition(wert)) {
    throw KasseneckValidationError(name, '$pfad: erlaubt sind ${returnDispositions.join(', ')}', 'request');
  }
  return wert;
}
