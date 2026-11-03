/// Was die Kasse ueber Kasseneck Connect an Kasseneck meldet (Bestand: welche
/// Connect-Version an welchem Kassengeraet laeuft). Zwilling von
/// `ConnectStateReport`/`reportConnectState` im npm-Paket (1.24.0).
///
/// Nur Angaben, die die Kasse von Connect liest -- nie IP, Rechner- oder
/// Benutzername. Aeltere Connect-Versionen kennen `osVersion`, `arch` und
/// `features` nicht: dann `null` bzw. leer.
library;

import '../register/fehler.dart';

class ConnectStateReport {
  const ConnectStateReport({
    required this.deviceId,
    required this.version,
    required this.os,
    this.osVersion,
    this.arch,
    this.features = const [],
    this.httpsTrusted,
    this.bluetooth,
  });

  /// Kassengeraet, an dem Connect laeuft.
  final String deviceId;

  /// Connect-Version, z. B. `1.4.0`.
  final String version;

  /// `macos`, `windows` oder `linux`.
  final String os;
  final String? osVersion;
  final String? arch;

  /// Faehigkeiten aus `GET /v1/status` (`bluetooth`, `https`, `update` ...).
  final List<String> features;

  /// Ob HTTPS vertraut ist (`tls.trusted`), `null` ohne HTTPS.
  final bool? httpsTrusted;

  /// Bluetooth-Stand (`poweredOn`, `poweredOff`, `unauthorized` ...), `null` ohne Bluetooth.
  final String? bluetooth;
}

/// Die Nutzlast von `reportConnectState`; prueft nur die Form, wie der Zwilling
/// (was der Server nicht annimmt, lehnt er mit `invalid_connect_report` ab).
Map<String, Object?> connectStateNutzlast(String name, ConnectStateReport r) {
  KasseneckValidationError anfrage(String grund) => KasseneckValidationError(name, grund, 'request');
  if (r.deviceId.isEmpty) throw anfrage('deviceId fehlt');
  if (r.version.isEmpty) throw anfrage('version fehlt');
  if (r.os.isEmpty) throw anfrage('os fehlt');
  // Was eine aeltere Connect-Version nicht kennt, faellt weg (wie der Vertragsfall
  // `success_old`); der Server liest ein fehlendes Feld wie `null` bzw. leer.
  return {
    'deviceId': r.deviceId,
    'version': r.version,
    'os': r.os,
    'osVersion': ?r.osVersion,
    'arch': ?r.arch,
    if (r.features.isNotEmpty) 'features': [...r.features],
    'httpsTrusted': ?r.httpsTrusted,
    'bluetooth': ?r.bluetooth,
  };
}
