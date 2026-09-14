import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

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

  /// Ordner fuer die dauerhafte Ablage geladener Logos; `null` = keine Ablage.
  ///
  /// Ohne Ablage lebt ein Logo nur so lange wie der Prozess: nach jedem
  /// App-Start muss es wieder binnen [frist] ueber das Netz kommen, sonst
  /// steht der erste Bon ohne Logo da. Mit Ablage kommt es sofort von der
  /// Platte. Die App setzt den Ordner beim Start ([dauerhaftAblegen]); das
  /// Paket ruft beim Laden selbst kein Plugin auf.
  static Directory? speicherOrdner;

  /// Hoechstens so viele Logos bleiben abgelegt — ein Betrieb hat eines, ein
  /// Geraet selten mehr als eine Handvoll. Die aeltesten gehen zuerst.
  static const int maxDateien = 20;

  /// Groessere Antworten werden nicht abgelegt (ein Logo hat einige hundert KB).
  static const int maxDateiBytes = 5 * 1024 * 1024;

  /// Nach dieser Spanne wird ein abgelegtes Logo neu geholt.
  ///
  /// Neue Logos bekommen eine neue Adresse (Dateiname mit Zeitstempel), unter
  /// einer Adresse steht also kein anderes Bild. Aeltere Uploads mit festem
  /// Namen koennten ueberschrieben worden sein — die Auffrischung haelt deren
  /// Abweichung klein. Schlaegt sie fehl, bleibt das abgelegte Logo.
  static Duration auffrischenNach = const Duration(days: 7);

  /// Setzt [speicherOrdner] auf den App-Support-Ordner des Geraets.
  ///
  /// Wirft nie: ohne Ordner (Plattform ohne Dateisystem, Plugin fehlt) laeuft
  /// alles wie bisher, nur ohne Ablage.
  static Future<void> dauerhaftAblegen() async {
    try {
      final basis = await getApplicationSupportDirectory();
      speicherOrdner = Directory('${basis.path}${Platform.pathSeparator}kasseneck_logos');
    } catch (e) {
      if (kDebugMode) {
        print('Logo-Ablage nicht verfuegbar: $e');
      }
    }
  }

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
    final datei = _dateiFuer(imageUrl);
    final abgelegt = await _lesen(datei);
    if (abgelegt != null && !abgelegt.alt) {
      _logoBytes[imageUrl] = abgelegt.bytes;
      return;
    }
    try {
      // Die Frist deckt den ganzen Abruf: `Client.get` liest den Rumpf
      // vollstaendig aus, bevor das Future abschliesst — Kopf und Rumpf sind
      // damit gedeckt, nicht nur der Antwortkopf.
      final response = await httpClient.get(Uri.parse(imageUrl)).timeout(frist);
      if (response.statusCode == 200) {
        _logoBytes[imageUrl] = response.bodyBytes;
        await _ablegen(datei, response.bodyBytes);
        return;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Fehler beim Laden des Bildes: $e');
      }
    }
    // Die Auffrischung ist gescheitert: ein eine Woche altes Logo ist besser
    // als keines.
    if (abgelegt != null) {
      _logoBytes[imageUrl] = abgelegt.bytes;
    }
  }

  static File? _dateiFuer(String imageUrl) {
    final ordner = speicherOrdner;
    if (ordner == null) return null;
    return File('${ordner.path}${Platform.pathSeparator}${_dateiname(imageUrl)}.logo');
  }

  /// Stabiler Name aus der Adresse (FNV-1a, 64 Bit). Die Adresse selbst taugt
  /// nicht als Name (Laenge, Sonderzeichen, Token im Klartext auf der Platte).
  static String _dateiname(String imageUrl) {
    var h = 0xcbf29ce484222325;
    for (final b in utf8.encode(imageUrl)) {
      h ^= b;
      h *= 0x100000001b3;
    }
    return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }

  static Future<({Uint8List bytes, bool alt})?> _lesen(File? datei) async {
    if (datei == null) return null;
    try {
      if (!await datei.exists()) return null;
      final bytes = await datei.readAsBytes();
      if (!istBilddatei(bytes)) {
        // Abgebrochenes Schreiben oder fremde Datei: weg damit, neu holen.
        await datei.delete();
        return null;
      }
      final alter = DateTime.now().difference(await datei.lastModified());
      return (bytes: bytes, alt: alter >= auffrischenNach);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _ablegen(File? datei, Uint8List bytes) async {
    if (datei == null || bytes.length > maxDateiBytes || !istBilddatei(bytes)) return;
    try {
      await datei.parent.create(recursive: true);
      // Erst unter anderem Namen schreiben, dann umbenennen: ein Abbruch
      // mitten im Schreiben hinterlaesst keine halbe Logo-Datei.
      final teil = File('${datei.path}.teil');
      await teil.writeAsBytes(bytes, flush: true);
      await teil.rename(datei.path);
      await _aufraeumen(datei.parent);
    } catch (e) {
      if (kDebugMode) {
        print('Logo nicht abgelegt: $e');
      }
    }
  }

  static Future<void> _aufraeumen(Directory ordner) async {
    final dateien = <({File datei, DateTime zeit})>[];
    await for (final e in ordner.list()) {
      if (e is File && e.path.endsWith('.logo')) {
        dateien.add((datei: e, zeit: await e.lastModified()));
      }
    }
    if (dateien.length <= maxDateien) return;
    dateien.sort((a, b) => b.zeit.compareTo(a.zeit));
    for (final alt in dateien.skip(maxDateien)) {
      await alt.datei.delete();
    }
  }

  /// PNG, JPEG oder WebP am Dateikopf — nur solche Dateien werden abgelegt
  /// und von der Platte uebernommen.
  @visibleForTesting
  static bool istBilddatei(Uint8List b) {
    bool beginntMit(List<int> kopf, [int ab = 0]) {
      if (b.length < ab + kopf.length) return false;
      for (var i = 0; i < kopf.length; i++) {
        if (b[ab + i] != kopf[i]) return false;
      }
      return true;
    }

    return beginntMit(const [0x89, 0x50, 0x4E, 0x47]) ||
        beginntMit(const [0xFF, 0xD8, 0xFF]) ||
        (beginntMit(const [0x52, 0x49, 0x46, 0x46]) && beginntMit(const [0x57, 0x45, 0x42, 0x50], 8));
  }

  /// Vergisst alle Logos im Speicher — wie ein Neustart der App. Die Ablage
  /// auf der Platte bleibt.
  @visibleForTesting
  static void speicherLeeren() => _logoBytes.clear();

  /// Gibt das Bild als `Uint8List` für den Belegdruck zurück
  static Uint8List? getLogoBytes(String? imageUrl) => imageUrl==null?null:_logoBytes[imageUrl];
}
