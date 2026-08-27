import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Das Betriebslogo fuer Beleganzeige und Belegdruck.
///
/// **Das Logo ist Zierde, kein Belegbestandteil.** Es wird im Verkaufsweg
/// geholt — `createReceipt` gibt die Adresse in der Antwort mit, und
/// `KasseneckReceipt.init` laedt es —, also **hinter** dem bereits signierten
/// Beleg. Alles, was hier haengen bleibt, haengt an einem Vorgang, der laengst
/// stattgefunden hat. Deshalb gilt: harte Frist, und ein Fehlschlag heisst
/// schlicht „kein Logo".
class LogoService {
  static final Map<String, Uint8List> _logoBytes = {};

  /// Laufende Abrufe je Adresse — siehe [loadLogo].
  static final Map<String, Future<void>> _laufend = {};

  /// HTTP-Client; austauschbar (Tests/Mocking).
  static http.Client httpClient = http.Client();

  /// Vorgabe fuer [frist].
  ///
  /// Drei Sekunden sind ein Kompromiss zwischen zwei Kosten: eine langsame
  /// Mobilverbindung soll das Logo noch schaffen, und ein Host, der gar nicht
  /// antwortet, soll **jeden** Verkauf um hoechstens diese Spanne verzoegern.
  /// Hoehere Werte verlagern die Kosten auf den Regelbetrieb am Tresen.
  static const Duration standardFrist = Duration(seconds: 3);

  /// Harte Obergrenze fuer einen Logo-Abruf.
  ///
  /// Ohne Frist blieb ein Host, der die Verbindung annimmt und nie antwortet
  /// (haengender Proxy, Captive Portal, ueberlasteter CDN-Knoten), fuer immer
  /// offen: `sellReceipt` kehrte nie zurueck und warf nie, obwohl der Beleg
  /// schon in der Signaturkette stand. Wer die App daraufhin neu startete und
  /// erneut kassierte, erzeugte einen zweiten Umsatz.
  ///
  /// Prozessweit — wie [httpClient]. Wer sie setzt, setzt sie fuer alle.
  static Duration frist = standardFrist;

  /// Laedt das Bild einmal und behaelt es.
  ///
  /// Wirft nie: ein Fehlschlag (Frist, Netz, unbrauchbare Adresse, Nicht-200)
  /// bedeutet „kein Logo", nicht „Beleg fehlgeschlagen".
  static Future<void> loadLogo(String? imageUrl) async {
    if (imageUrl == null) {
      return;
    }
    if (_logoBytes.containsKey(imageUrl)) {
      return;
    }

    // Ein laufender Abruf wird geteilt statt verdoppelt: `getReceipts` ruft
    // `init()` fuer jeden Beleg des Zeitraums, und die tragen fast immer
    // dieselbe Adresse. Die Cache-Pruefung oben liegt vor dem `await`, also
    // gingen sonst N gleiche Requests gleichzeitig hinaus.
    final laufend = _laufend[imageUrl];
    if (laufend != null) {
      return laufend;
    }

    final abruf = _holen(imageUrl);
    _laufend[imageUrl] = abruf;
    try {
      await abruf;
    } finally {
      _laufend.remove(imageUrl);
    }
  }

  static Future<void> _holen(String imageUrl) async {
    try {
      // Die Frist deckt den ganzen Abruf: `Client.get` liest den Rumpf
      // vollstaendig aus, bevor das Future abschliesst — Kopf und Rumpf sind
      // damit gedeckt, nicht nur der Antwortkopf.
      final response = await httpClient.get(Uri.parse(imageUrl)).timeout(frist);
      if (response.statusCode == 200) {
        _logoBytes[imageUrl] = response.bodyBytes;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Fehler beim Laden des Bildes: $e');
      }
    }
  }

  /// Gibt das Bild als `Uint8List` für den Belegdruck zurück
  static Uint8List? getLogoBytes(String? imageUrl) => imageUrl==null?null:_logoBytes[imageUrl];
}
