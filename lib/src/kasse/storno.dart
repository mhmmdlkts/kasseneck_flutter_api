/// Storno-Regeln der Kasse — Zwilling von `models/cancellation.ts` und der
/// Storno-Regeln in `belege.ts` der Browser-Kasse.
///
/// **Die Wahrheit hat der Server.** Er hält die Restmengen, die Reichweite des
/// Rechts und die Verkettung; er negiert und signiert. Was hier steht,
/// entscheidet nur, was die Kasse **anbietet** — ein Knopf, der sicher auf
/// einen Fehler läuft, gehört nicht auf den Schirm, und eine Menge, die es
/// nicht mehr gibt, auch nicht.
///
/// Ein Storno-Beleg ist ein eigener signierter Beleg nach RKSV. Es gibt kein
/// Zurücknehmen — nur einen weiteren Beleg.
library;

import '../../models/kasseneck_receipt.dart';
import '../register/pairing.dart' show RegisterScope;
import 'belege.dart';

/// Die Gründe, die das Backend annimmt — Schlüssel wie dort, Beschriftung für
/// den Bildschirm. Reihenfolge wie im Katalog des Backends.
const Map<String, String> stornogruende = {
  'fehleingabe': 'Fehleingabe',
  'kunde_storniert': 'Kunde hat storniert',
  'falsche_zahlart': 'Falsche Zahlart',
  'doppelt_erfasst': 'Doppelt erfasst',
  'sonstiges': 'Sonstiges',
};

/// Ab wann eine liegengebliebene Reservierung nicht mehr zählt (wie im
/// Backend). Ohne diese Grenze bliebe eine Position für immer gesperrt, weil
/// ein Abbruch irgendwann einmal eine Reservierung stehen ließ.
const int stornoReservierungMs = 120000;

/// Restmenge je Position: Belegmenge minus alles, was storniert oder **frisch**
/// reserviert ist; nie unter null.
List<int> restmengen(KasseneckReceipt beleg, {int? jetzt}) {
  final rest = [for (final p in beleg.items) p.quantity];
  final zeit = jetzt ?? DateTime.now().millisecondsSinceEpoch;
  for (final eintrag in beleg.cancellations) {
    final at = eintrag['at'];
    // Eine Reservierung zählt nur, solange sie frisch ist.
    if (eintrag['pending'] == true && (at is! num || at < zeit - stornoReservierungMs)) continue;
    for (final pos in (eintrag['items'] as List?) ?? const []) {
      if (pos is! Map) continue;
      final index = pos['index'];
      final menge = pos['quantity'];
      if (index is! int || index < 0 || index >= rest.length) continue;
      if (menge is! int) continue;
      rest[index] = rest[index] - menge < 0 ? 0 : rest[index] - menge;
    }
  }
  return rest;
}

/// Darf dieser Beleg storniert werden?
///
/// Kein Storno von einem Storno, keines von Null-, Start- oder
/// Trainingsbelegen, keines von einem bereits voll stornierten Beleg — und mit
/// der Reichweite `own` nur die eigenen.
bool stornoErlaubt(Belegzusammenfassung beleg, RegisterScope reichweite, String eigeneUid) {
  if (reichweite == RegisterScope.none) return false;
  if (!beleg.istVerkauf) return false;
  if (beleg.stornoStand == StornoStand.voll) return false;
  if (reichweite == RegisterScope.own && beleg.bediener?.uid != eigeneUid) return false;
  return true;
}

/// Sieht dieser Kassier den Beleg überhaupt?
bool belegSichtbar(Belegzusammenfassung beleg, RegisterScope reichweite, String eigeneUid) {
  if (reichweite == RegisterScope.none) return false;
  if (reichweite == RegisterScope.own) return beleg.bediener?.uid == eigeneUid;
  return true;
}

/// Höchstzahl der Stellen, die eine Belegnummer hat.
const int idHoechststellen = 7;

/// Die Nummer aus einer vollen Beleg-Kennung — für die Anzeige „ID 809".
/// Passt sie nicht auf das Muster, steht die Kennung selbst da; eine erfundene
/// Nummer wäre schlimmer als eine lange.
String idNummer(String receiptId) {
  final treffer = RegExp(r'-ID-(\d+)$').firstMatch(receiptId);
  return treffer?.group(1) ?? receiptId;
}

/// Aus der getippten Nummer die volle Kennung; `null`, wenn keine Ziffer dabei
/// ist. Der Kassier tippt nur die Nummer — das Kassenkürzel steht ohnehin fest.
String? volleId(String cashregisterId, String nummer) {
  final ziffern = nummer.replaceAll(RegExp(r'\D'), '');
  final gekuerzt = ziffern.length > idHoechststellen ? ziffern.substring(0, idHoechststellen) : ziffern;
  return gekuerzt.isEmpty ? null : '$cashregisterId-ID-$gekuerzt';
}
