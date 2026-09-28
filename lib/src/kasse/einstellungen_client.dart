/// Einstellungen lesen und schreiben, Zwilling von `pos/client.ts` im JS-Paket.
/// Am Draht `/api/v3` heißen Parameter und Antwort `business`/`device`,
/// Schlüssel und Werte englisch (Nachtrag §11.7.2).
///
/// **Geschrieben wird nur, was geändert wurde** ([posSettingsChanges]), nie
/// der ganze Stand. Zwei Kassen desselben Betriebs haben ihre Einstellungen
/// gleichzeitig offen; wer den vollen Stand zurückschickt, überschreibt die
/// Änderung der Nebenkasse. Und ein Wert, den dieses Paket nicht kennt
/// (`theme: 'sepia'`), bleibt nur so am Server stehen.
///
/// **Vor dem Senden** prüft dieser Weg nur die gesendeten Felder (ein Feld mit
/// `null` geht nicht hinaus und wird nicht geprüft), und nur, was der Server
/// sicher abweist: einen Schlüssel, den es nicht gibt (auch einen deutschen
/// aus 0.x wie `stil`), einen Wert außerhalb der Wertemenge (`'nacht'`), eine
/// Steuersatz-Karte ohne einen Satz an, eine unbekannte Tasten-Aktion und
/// eine doppelt belegte Taste. Der Fehler nennt den äußeren Pfad wie das
/// Backend (`business.theme`). Alles Weitere (Bereiche, Chips, Farbformat)
/// entscheidet der Server und meldet es als `validation` mit
/// `details.errors[].field` ([posFieldErrors]).
///
/// Zurück kommt jeweils der **gemischte** Stand: Standardwerte plus
/// Gespeichertes. Die Kasse bekommt nie ein halbes Bild.
library;

import '../aufrufe.dart';
import '../register/fehler.dart';
import '../register/transport.dart';
import 'einstellungen.dart';

class PosSettingsClient {
  const PosSettingsClient(this.transport, {required this.deviceId});

  final RegisterTransport transport;

  /// Dieses Gerät, für die gerätebezogenen Einstellungen.
  final String deviceId;

  /// Betriebsweite und gerätebezogene Einstellungen, mit den Standardwerten
  /// gemischt (`getKasseSettings`).
  Future<PosSettings> load() async {
    final daten = await transport.call(
      Aufrufe.getKasseSettings,
      params: {if (deviceId.trim().isNotEmpty) 'deviceId': deviceId},
    );
    return PosSettings.fromJson({'business': daten['business'], 'device': daten['device']});
  }

  /// Betriebsweite Einstellungen schreiben (Recht `layout`). [aenderung] mit
  /// englischen Schlüsseln, am besten aus [posSettingsChanges]; `vatRates`
  /// immer als ganze Karte.
  Future<PosBusinessSettings> saveBusiness(Map<String, dynamic> aenderung) async {
    const name = Aufrufe.setMyKasseSettings;
    final gesendet = _pruefeTeil(name, 'business', aenderung, const PosBusinessSettings().toJson(), posBusinessValues);
    if (gesendet.containsKey('vatRates')) {
      final karte = gesendet['vatRates'];
      // Unter /v3 prüft der Server die übergebene Karte für sich: ein
      // einzelner Schalter wie {20: false} wäre dort „kein Satz an".
      if (karte is! Map || !karte.values.any((an) => an == true)) {
        throw const KasseneckValidationError(
            name, 'business.vatRates: mindestens ein Steuersatz muss an sein (immer die ganze Karte senden)', 'request');
      }
    }
    final daten = await transport.call(name, params: {'business': gesendet});
    return PosBusinessSettings.fromJson(_stand(name, daten, 'business'));
  }

  /// Einstellungen dieses Geräts schreiben (Recht `layout`). `shortcuts` nur
  /// als ganze Karte aller bekannten Aktionen ([posSettingsChanges] liefert
  /// sie bei jeder Tastenänderung); sie wird vorab auf Doppelbelegung geprüft.
  Future<PosDeviceSettings> saveDevice(Map<String, dynamic> aenderung) async {
    const name = Aufrufe.setMyRegisterDeviceSettings;
    if (deviceId.trim().isEmpty) {
      throw const KasseneckValidationError(name, 'deviceId fehlt', 'request');
    }
    final gesendet = _pruefeTeil(name, 'device', aenderung, const PosDeviceSettings().toJson(), posDeviceValues);
    if (gesendet.containsKey('shortcuts')) {
      final karte = gesendet['shortcuts'];
      if (karte is! Map) {
        throw const KasseneckValidationError(name, 'device.shortcuts: keine Tastenkarte', 'request');
      }
      final tasten = <String, Object?>{};
      for (final e in karte.entries) {
        if (e.value == null) continue;
        final aktion = e.key.toString();
        if (!posShortcutActions.contains(aktion)) {
          throw KasseneckValidationError(name, 'device.shortcuts.$aktion: unbekannte Aktion', 'request');
        }
        tasten[aktion] = e.value;
      }
      // Nur die ganze Karte: der Server prüft Doppelbelegungen nur in der
      // gesendeten Karte, eine halbe (`{cash: ['Mod+K']}`) ließe eine
      // Doppelbelegung mit einer gespeicherten Taste durch.
      final fehlt = posShortcutActions.where((a) => !tasten.containsKey(a)).toList();
      if (fehlt.isNotEmpty) {
        throw KasseneckValidationError(
            name,
            'device.shortcuts: ganze Karte senden (posSettingsChanges), es fehlen ${fehlt.join(', ')}',
            'request');
      }
      // Doppelbelegung in der ganzen Karte, also in der ganzen Belegung.
      final konflikt = posShortcutConflict(tasten);
      if (konflikt != null) {
        throw KasseneckValidationError(
            name,
            'device.shortcuts.${konflikt.action}: Taste ${konflikt.key} schon belegt (${konflikt.heldBy})',
            'request');
      }
      gesendet['shortcuts'] = tasten;
    }
    final daten = await transport.call(name, params: {'deviceId': deviceId, 'device': gesendet});
    return PosDeviceSettings.fromJson(_stand(name, daten, 'device'));
  }

  /// Bild-Logo der Kasse hochladen (Recht `layout`, `setMyKasseLogo`).
  /// [bild] ist eine Data-URL (PNG, JPEG, SVG). Liefert die neue Adresse für
  /// `logoImage`. Formatfehler meldet der Server als `logo_invalid_type`,
  /// `logo_too_large` oder `logo_invalid`.
  Future<String> setLogo(String bild) async {
    const name = Aufrufe.setMyKasseLogo;
    if (bild.isEmpty) {
      throw const KasseneckValidationError(name, 'image fehlt (oder logoEntfernen)', 'request');
    }
    return _logo(name, await transport.call(name, params: {'image': bild}));
  }

  /// Bild-Logo entfernen; liefert `''`.
  Future<String> removeLogo() async {
    const name = Aufrufe.setMyKasseLogo;
    return _logo(name, await transport.call(name, params: {'remove': true}));
  }

  String _logo(String name, Map<String, dynamic> daten) {
    final bild = daten['logoImage'];
    if (bild is! String) {
      throw KasseneckValidationError(name, 'Antwort enthaelt kein Feld "logoImage"', 'response');
    }
    return bild;
  }

  /// Der neue Stand aus der Antwort eines Schreibaufrufs.
  ///
  /// Fehlt er, ist das ein **Antwortfehler** und kein leerer Stand: ein
  /// Standardsatz als angeblich neuer Stand ließe den Bediener erneut
  /// speichern, diesmal gegen den Standard statt gegen den echten Stand.
  Map<String, dynamic> _stand(String name, Map<String, dynamic> daten, String feld) {
    final wert = daten[feld];
    if (wert is! Map) {
      throw KasseneckValidationError(name, 'Antwort enthaelt keinen neuen Stand (data.$feld fehlt)', 'response');
    }
    return Map<String, dynamic>.from(wert);
  }

  /// Prüft die gesendeten Felder eines Teils und liefert sie ohne `null`.
  Map<String, dynamic> _pruefeTeil(
    String name,
    String teil,
    Map<String, dynamic> block,
    Map<String, dynamic> standard,
    Map<String, List<Object>> werte,
  ) {
    final gesendet = <String, dynamic>{
      for (final e in block.entries)
        if (e.value != null) e.key: e.value,
    };
    if (gesendet.isEmpty) {
      // Ein leerer Aufruf wäre kein Speichern, und der Bildschirm meldete
      // danach fälschlich „gespeichert".
      throw KasseneckValidationError(name, '$teil: keine Einstellungen uebergeben', 'request');
    }
    for (final e in gesendet.entries) {
      if (!standard.containsKey(e.key)) {
        throw KasseneckValidationError(name, '$teil.${e.key}: unbekanntes Feld', 'request');
      }
      final erlaubt = werte[e.key];
      if (erlaubt != null && !erlaubt.contains(e.value)) {
        // Kein Altwert: dann ein Wert, den der Server kennt und dieses Paket
        // nicht. Wer den ganzen Block zurückschickt, braucht den Hinweis.
        final hinweis = isLegacyValue0x(e.key, e.value)
            ? 'ungueltiger Wert (innere Form 0.x)'
            : 'ungueltiger Wert (vom Server unbekannt? nur geaenderte Felder senden: posSettingsChanges)';
        throw KasseneckValidationError(name, '$teil.${e.key}: $hinweis', 'request');
      }
    }
    return gesendet;
  }
}
