import 'package:kasseneck_api/src/printing/escpos/escpos.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/keck_print_result.dart';

import '../enums/keck_paper_size.dart';
import '../enums/qr_print_mode.dart';
import 'printer_service.dart';

/// Transport-Abstraktion fuer den ESC/POS-Druck.
///
/// Trennt den *Byte-Bau* (in [KeckPrinter]) vom *Byte-Versand* (hier). Damit
/// laesst sich derselbe Druckcode ueber WLAN ([WifiTransport]), Bluetooth
/// ([BluetoothTransport]) oder — spaeter — USB/eigene Kanaele fahren, ohne die
/// Fassade anzufassen. Eigene Transporte muessen nur dieses Interface erfuellen.
///
/// Bewusst zustandsarm gegenueber dem globalen [KeckPrinterService]: eine
/// Transport-Instanz haelt (wenn ueberhaupt) ihre *eigene* Verbindung, statt
/// den prozessweiten Drucker-Zustand zu teilen.
abstract class PrinterTransport {
  /// Sendet fertige ESC/POS-[bytes]. Wirft **nicht** — das Ergebnis (gesendet
  /// oder Fehler) kommt im [KeckPrintResult].
  Future<KeckPrintResult> send(List<int> bytes);

  /// Gibt die Verbindung frei (Bluetooth: trennen; WLAN: no-op).
  Future<void> dispose();
}

/// [PrinterTransport] ueber einen WLAN-/Netzwerkdrucker (Roh-TCP, Port 9100).
///
/// Zustandslos im Sinne des Verbindungshaltens: jeder [send] oeffnet eine
/// eigene, kurzlebige Socket-Verbindung zu [ip]:[port] und schliesst wieder —
/// delegiert an [KeckPrinterService.printRawBytesWifi] und beruehrt den
/// globalen aktiven Drucker nicht.
class WifiTransport implements PrinterTransport {
  /// Ziel-IP des Netzwerkdruckers.
  final String ip;

  /// Ziel-Port (Standard 9100 fuer Roh-ESC/POS).
  final int port;

  /// Verbindungs-/Sende-Timeout.
  final Duration timeout;

  /// Erzeugt einen WLAN-Transport zu [ip]:[port].
  WifiTransport({
    required this.ip,
    this.port = 9100,
    this.timeout = const Duration(seconds: 5),
  });

  @override
  Future<KeckPrintResult> send(List<int> bytes) =>
      KeckPrinterService.printRawBytesWifi(bytes, ip: ip, port: port, timeout: timeout);

  /// No-op — der WLAN-Transport haelt keine dauerhafte Verbindung.
  @override
  Future<void> dispose() async {}
}

/// [PrinterTransport] ueber einen Bluetooth-Drucker.
///
/// Verwaltet eine **eigene** [BluetoothDevice]-Instanz (adressiert ueber
/// [address]) — NICHT den globalen `KeckPrinterService._devicePrinter`. Beim
/// ersten [send] wird bei Bedarf verbunden (Adapter-State abwarten, dann
/// `connect`); der eigentliche Byte-Versand nutzt die gemeinsame, in der Praxis
/// bewaehrte Sendelogik [writeToBluetoothDevice] (MTU/Chunking/Flow-Control).
class BluetoothTransport implements PrinterTransport {
  /// Bluetooth-Adresse (Remote-ID) des Druckers.
  final String address;

  /// Timeout fuer das Abwarten des Adapter-States beim Verbinden.
  final Duration timeout;

  BluetoothDevice? _device;

  /// Erzeugt einen Bluetooth-Transport fuer den Drucker mit [address].
  BluetoothTransport({
    required this.address,
    this.timeout = const Duration(seconds: 10),
  });

  Future<BluetoothDevice> _ensureConnected() async {
    final BluetoothDevice? existing = _device;
    if (existing != null && existing.isConnected) return existing;

    // Adapter-State abwarten wie in KeckPrinterService.initBluetoothPrinter.
    await FlutterBluePlus.adapterState
        .firstWhere((s) => s == BluetoothAdapterState.on)
        .timeout(timeout);
    final BluetoothDevice device = BluetoothDevice.fromId(address);
    await device.connect(autoConnect: false, license: License.nonprofit);
    _device = device;
    return device;
  }

  @override
  Future<KeckPrintResult> send(List<int> bytes) async {
    if (bytes.isEmpty) return const KeckPrintResult.failure('Keine Bytes zum Drucken.');
    try {
      final BluetoothDevice device = await _ensureConnected();
      await writeToBluetoothDevice(device, bytes);
      return const KeckPrintResult.success();
    } catch (e) {
      return KeckPrintResult.failure('Bluetooth-Druck fehlgeschlagen ($address): $e');
    }
  }

  /// Trennt die (eigene) Bluetooth-Verbindung, falls verbunden.
  @override
  Future<void> dispose() async {
    final BluetoothDevice? device = _device;
    if (device == null) return;
    try {
      await device.disconnect();
    } catch (e) {
      if (kDebugMode) print('Fehler beim Trennen von $address: $e');
    } finally {
      _device = null;
    }
  }
}

/// Einheitliche Druck-Fassade ueber einer [PrinterTransport].
///
/// Loest den gespaltenen/globalen Druck-Zustand des statischen
/// [KeckPrinterService] fuer neuen Code ab: eine [KeckPrinter]-Instanz kapselt
/// *einen* Transport und *eine* Papiergroesse und baut die ESC/POS-Bytes
/// transport-agnostisch, exakt wie der bestehende Stack (gleicher
/// [EscPosGenerator], gleicher Beleg-Byte-Bau). Jede Methode liefert das
/// [KeckPrintResult] des Transports zurueck (wirft nicht).
///
/// ```dart
/// final printer = KeckPrinter.wifi(ip: '192.168.0.50');
/// await printer.printReceipt(receipt);
/// await printer.cut();
/// await printer.dispose();
/// ```
///
/// Der statische [KeckPrinterService] und `printReceiptBluetooth/Wifi` bleiben
/// unveraendert nutzbar — [KeckPrinter] ist rein additiv.
class KeckPrinter {
  /// Der Kanal, ueber den die gebauten Bytes gesendet werden.
  final PrinterTransport transport;

  /// Papiergroesse fuer den Byte-Bau (Generator + Beleg-Layout).
  final KeckPaperSize size;

  /// Baut einen [KeckPrinter] ueber einem beliebigen [transport] — fuer DI,
  /// Tests oder eigene Transporte.
  KeckPrinter(this.transport, {this.size = KeckPaperSize.mm80});

  /// Bequemer WLAN-Drucker (Roh-TCP, Port 9100).
  factory KeckPrinter.wifi({
    required String ip,
    int port = 9100,
    KeckPaperSize size = KeckPaperSize.mm80,
    Duration timeout = const Duration(seconds: 5),
  }) =>
      KeckPrinter(
        WifiTransport(ip: ip, port: port, timeout: timeout),
        size: size,
      );

  /// Bequemer Bluetooth-Drucker (eigene Device-Instanz, kein globaler Zustand).
  factory KeckPrinter.bluetooth({
    required String address,
    KeckPaperSize size = KeckPaperSize.mm58,
  }) =>
      KeckPrinter(
        BluetoothTransport(address: address),
        size: size,
      );

  /// Frischer Generator mit der Papiergroesse dieses Druckers.
  EscPosGenerator _generator() => EscPosGenerator(size.paperSize, CapabilityProfile());

  /// Druckt einen RKSV-Beleg [r]. Baut die Bytes exakt wie
  /// [KeckPrinterService.getBytesFromReceipt] (gleiches Layout) und sendet sie
  /// in EINEM Byte-Strom.
  Future<KeckPrintResult> printReceipt(
    KasseneckReceipt r, {
    QrPrintMode qrMode = QrPrintMode.imageRaster,
  }) async {
    final List<Uint8List> parts =
        await KeckPrinterService.getBytesFromReceipt(r, size, qrMode: qrMode);
    final List<int> bytes = <int>[for (final p in parts) ...p];
    return transport.send(bytes);
  }

  /// Druckt einen Text (mit optionalen [styles]).
  Future<KeckPrintResult> printText(String text, {PosStyles? styles}) =>
      transport.send(_generator().text(text, styles: styles ?? const PosStyles()));

  /// Druckt einen QR-Code (nativer ESC/POS-Befehl). [size] = 1..8.
  Future<KeckPrintResult> printQr(String data, {int size = 4}) =>
      transport.send(_generator().qrcode(data, size: _qrSize(size)));

  /// Druckt einen 1D-Barcode (GS k, Form 2).
  Future<KeckPrintResult> printBarcode(
    BarcodeType type,
    String data, {
    int height = 100,
    int width = 3,
    BarcodeHri hri = BarcodeHri.below,
  }) =>
      transport.send(_generator().barcode(
        type,
        data,
        height: height,
        width: width,
        hri: hri,
      ));

  /// Schneidet das Papier ab (falls vom Drucker unterstuetzt).
  Future<KeckPrintResult> cut() => transport.send(_generator().cut());

  /// Oeffnet die Kassenlade.
  Future<KeckPrintResult> openDrawer() => transport.send(_generator().drawer());

  /// Papiervorschub um [n] Zeilen.
  Future<KeckPrintResult> feed(int n) => transport.send(_generator().feed(n));

  /// Druckt einen zusammengesetzten [CustomPrintJob] in EINEM Sendevorgang.
  Future<KeckPrintResult> printJob(CustomPrintJob job) =>
      transport.send(job.build(_generator()));

  /// Sendet beliebige, bereits fertige ESC/POS-[bytes].
  Future<KeckPrintResult> printRawBytes(List<int> bytes) => transport.send(bytes);

  /// Gibt den Transport frei (siehe [PrinterTransport.dispose]).
  Future<void> dispose() => transport.dispose();

  /// Mappt eine Groessenzahl 1..8 auf die passende [QRSize].
  QRSize _qrSize(int size) {
    switch (size.clamp(1, 8)) {
      case 1:
        return QRSize.size1;
      case 2:
        return QRSize.size2;
      case 3:
        return QRSize.size3;
      case 5:
        return QRSize.size5;
      case 6:
        return QRSize.size6;
      case 7:
        return QRSize.size7;
      case 8:
        return QRSize.size8;
      case 4:
      default:
        return QRSize.size4;
    }
  }
}
