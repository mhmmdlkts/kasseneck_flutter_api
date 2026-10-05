/// Eine leere Artikel-ID gilt als keine: `''` und `null` vergleichen und
/// reisen gleich (Kachel, Warenkorb, Belegzeile). Paketintern, nicht exportiert.
String? artikelIdOderNull(String? id) => id == null || id.isEmpty ? null : id;
