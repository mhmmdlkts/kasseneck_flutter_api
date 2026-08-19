/// Einstellungen lesen und schreiben — Zwilling von `kasse/client.ts` im
/// JS-Paket.
///
/// **Geschrieben wird nur, was geändert wurde**, nie der ganze Stand. Zwei
/// Kassen desselben Betriebs haben ihre Einstellungen gleichzeitig offen; wer
/// den vollen Stand zurückschickt, überschreibt die Änderung der Nebenkasse,
/// die zufällig eine Sekunde früher gespeichert hat — und niemand merkt es.
///
/// Zurück kommt jeweils der **gemischte** Stand: Standardwerte plus
/// Gespeichertes. Die Kasse bekommt nie ein halbes Bild.
library;

import '../register/fehler.dart';
import '../register/transport.dart';
import 'einstellungen.dart';

class KasseEinstellungenClient {
  const KasseEinstellungenClient(this.transport, {required this.deviceId});

  final RegisterTransport transport;

  /// Dieses Gerät — für die gerätebezogenen Einstellungen.
  final String deviceId;

  /// Betriebsweite und gerätebezogene Einstellungen, mit den Standardwerten
  /// gemischt.
  Future<KasseSettings> laden() async {
    final daten = await transport.rufen(
      'getKasseSettings',
      params: {if (deviceId.trim().isNotEmpty) 'deviceId': deviceId},
    );
    return KasseSettings.aus(daten);
  }

  /// Betriebsweite Einstellungen schreiben (Recht `layout`).
  Future<KasseSettingsBetrieb> betriebSpeichern(Map<String, dynamic> aenderung) async {
    const name = 'setMyKasseSettings';
    _nichtLeer(name, aenderung);
    final daten = await transport.rufen(name, params: {'betrieb': aenderung});
    return KasseSettings.aus({'betrieb': daten['betrieb']}).betrieb;
  }

  /// Einstellungen dieses Geräts schreiben (Recht `layout`).
  Future<KasseSettingsGeraet> geraetSpeichern(Map<String, dynamic> aenderung) async {
    const name = 'setMyRegisterDeviceSettings';
    if (deviceId.trim().isEmpty) {
      throw const KasseneckValidationError(name, 'deviceId fehlt', 'request');
    }
    _nichtLeer(name, aenderung);
    final daten = await transport.rufen(name, params: {'deviceId': deviceId, 'geraet': aenderung});
    return KasseSettings.aus({'geraet': daten['geraet']}).geraet;
  }

  void _nichtLeer(String name, Map<String, dynamic> aenderung) {
    if (aenderung.isEmpty) {
      // Ein leerer Aufruf wäre kein Speichern, sondern nur ein Aufruf — und
      // der Bildschirm meldete danach fälschlich „gespeichert".
      throw KasseneckValidationError(name, 'Keine Einstellungen uebergeben', 'request');
    }
  }
}
