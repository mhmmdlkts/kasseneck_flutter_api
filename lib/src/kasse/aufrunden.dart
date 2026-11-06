/// Aufrunden-Vorschlaege fuer Trinkgeld: genau drei aufsteigende Gesamtbetraege
/// in Cent ueber dem Bezugsbetrag. Nur Ganzzahlen. Zwilling von
/// `pos/aufrunden.ts`; Vertrag sind die Pruefaelle
/// `test/fixtures/vertrag/tip-round-up-cases.json`.
library;

int _ceilDiv(int a, int b) => (a + b - 1) ~/ b;

(int, int) _steps(int t) {
  if (t < 1500) return (50, 100);
  if (t < 5000) return (100, 500);
  if (t < 20000) return (500, 1000);
  return (1000, 5000);
}

/// Drei Gesamtbetraege (Cent) zum Aufrunden von [amountCents]; bei einem
/// Betrag <= 0 keine.
List<int> roundUpSuggestions(int amountCents) {
  if (amountCents <= 0) return const [];
  final t = amountCents;
  final (small, large) = _steps(t);
  final lo0 = _ceilDiv(t * 102, 100);
  final lo = lo0 > t + 20 ? lo0 : t + 20;
  final hi = (t * (t < 1000 ? 125 : 120)) ~/ 100;

  final set = <int>{};
  for (final s in [small, large]) {
    for (var m = _ceilDiv(lo, s) * s; m <= hi; m += s) {
      set.add(m);
    }
  }
  final candidates = set.toList()..sort();

  final chosen = <int>{};
  if (candidates.isNotEmpty) {
    int? firstRound;
    for (final k in candidates) {
      if (k % large == 0) {
        firstRound = k;
        break;
      }
    }
    chosen.add(firstRound != null && (firstRound - t) * 100 <= t * 10 ? firstRound : candidates.first);
  }
  for (final target in [110, 115]) {
    final free = candidates.where((k) => !chosen.contains(k)).toList();
    if (free.isEmpty) break;
    int dist(int k) => (k * 100 - t * target).abs();
    int? round;
    for (final k in free) {
      if (k % large == 0 && dist(k) <= t * 3) {
        round = k;
        break;
      }
    }
    if (round != null) {
      chosen.add(round);
      continue;
    }
    var best = free.first;
    for (final k in free) {
      if (dist(k) < dist(best)) best = k;
    }
    chosen.add(best);
  }

  var next = chosen.isNotEmpty ? chosen.reduce((a, b) => a > b ? a : b) : _ceilDiv(lo, small) * small - small;
  while (chosen.length < 3) {
    next = (next ~/ small + 1) * small;
    if (next >= lo) chosen.add(next);
  }
  return chosen.toList()..sort();
}
