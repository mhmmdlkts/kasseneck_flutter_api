/// Ein Geheimnis eines fremden Betriebs -- der `api_key` und die Kassen-Token,
/// die `getCustomerCredentials` liefert.
///
/// **Warum ein eigener Typ und nicht `String`:** diese Werte gehoeren einem
/// Dritten. Wer sie hat, kann in seinem Namen Belege signieren, und ein Beleg
/// ist nach RKSV nicht zuruecknehmbar. Ein `String` in einem Antwortobjekt
/// landet aber genau dort, wo Werte nun einmal landen: in `print(antwort)`, im
/// `toString()` eines Modells, in `jsonEncode(...)` unter einem Fehler, in
/// einem Absturzbericht. Kein einziger dieser Wege ist boese gemeint, und jeder
/// einzelne gibt den Schluessel weiter.
///
/// Deshalb kommt man hier nur ueber **einen** benannten Weg an den Wert:
/// [reveal]. Der Name ist mit Absicht so gewaehlt, dass eine Suche nach
/// `.reveal()` in einer fremden Codebasis genau die Stellen zeigt, an denen ein
/// Geheimnis das Objekt verlaesst.
///
/// **Wie die Maskierung haelt.** Der Klartext liegt in einer [Expando] neben
/// dem Objekt, nicht *in* ihm: die Instanz hat kein Feld mit dem Klartext, und
/// was nicht da ist, findet auch kein Ausgabeweg -- auch keiner, den dieses
/// Paket nicht kennt. [toString] und [toJson] kommen **zusaetzlich**, damit die
/// Maske nicht als `Instance of 'KasseneckSecret'` erscheint, sondern als
/// Angabe, was fehlt und warum.
///
/// Der Zwilling im JS-Paket loest dasselbe mit einer `WeakMap`.
library;

/// Der Klartext, ausserhalb der Instanz. [Expando] haelt keine starke Referenz
/// auf den Schluessel -- ein weggeworfenes Geheimnis nimmt seinen Wert mit.
final Expando<String> _werte = Expando<String>('KasseneckSecret');

/// Wie ein maskiertes Geheimnis in Text erscheint.
const String kSecretMaske = '«verborgen»';

class KasseneckSecret {
  KasseneckSecret(this.label, String wert) {
    _werte[this] = wert;
  }

  /// Wofuer dieses Geheimnis steht (`apiKey`, `cashregisterToken`). Kein
  /// Geheimnis, nur eine Beschriftung -- sie steht in der Maske, damit ein
  /// Protokoll erkennen laesst, WELCHER Wert fehlt.
  final String label;

  /// Der Klartext. Der einzige Weg heraus -- und die Stelle, an der ein
  /// Aufrufer sich entscheidet, das Geheimnis weiterzugeben.
  ///
  /// Verschluesselt speichern. Nie protokollieren, nie in eine Mail, nie in
  /// einen Fehlerbericht.
  String reveal() => _werte[this] ?? '';

  /// Ob ueberhaupt ein Wert da ist -- ohne ihn anzufassen.
  bool get vorhanden => (_werte[this] ?? '').isNotEmpty;

  /// Greift bei `print`, bei jeder Zeichenketten-Einbettung und beim
  /// `toString()` jedes umschliessenden Objekts.
  @override
  String toString() => '[$label $kSecretMaske]';

  /// Greift bei `jsonEncode`, sofern der Aufrufer eine `toEncodable`-Funktion
  /// mitgibt -- und liefert die Maske statt eines Absturzes, wenn nicht.
  ///
  /// Ohne diese Methode wuerfe `jsonEncode` hier ein
  /// `JsonUnsupportedObjectError`. Das waere zwar auch sicher, aber die Maske
  /// ist die bessere Antwort: der Aufrufer sieht, was fehlt, statt an einer
  /// Stelle abzustuerzen, die mit dem Geheimnis nichts zu tun hat.
  String toJson() => toString();

  /// Damit `jsonEncode(zugang, toEncodable: KasseneckSecret.encode)` ohne
  /// eigene Funktion auskommt.
  static Object? encode(Object? wert) =>
      wert is KasseneckSecret ? wert.toString() : wert;
}

/// Baut ein Geheimnis aus einem Antwortfeld; fehlt es, entsteht ein leeres.
///
/// Bewusst nie `null`: ein `KasseneckSecret?` haette den Aufrufer dazu
/// gebracht, den fehlenden Fall mit `?? ''` zu ueberbruecken -- und damit
/// wieder eine rohe Zeichenkette in der Hand zu halten.
KasseneckSecret alsSecret(String label, Object? wert) =>
    KasseneckSecret(label, wert is String ? wert : '');
