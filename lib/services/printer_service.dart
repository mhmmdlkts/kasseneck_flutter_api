import 'dart:io';

import 'package:kasseneck_api/src/printing/escpos/escpos.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:kasseneck_api/models/keck_print_result.dart';
import 'package:my_pos/models/my_pos_paper.dart';
import 'package:my_pos/enums/my_pos_print_response.dart';
import 'package:my_pos/my_pos.dart';

import '../enums/keck_paper_size.dart';
import '../enums/qr_print_mode.dart';

class KeckPrinterService {

  static CapabilityProfile? _profile;
  static KeckPaperSize paperSize = KeckPaperSize.mm58;
  static BluetoothDevice? _devicePrinter;
  static String? ipAddress;
  static int port = 9100;

  static Future<bool> initWifiPrinter(String ipAddress, KeckPaperSize size, {int port = 9100}) async {
    paperSize = size;
    KeckPrinterService.ipAddress = ipAddress;
    KeckPrinterService.port = port;
    _profile = CapabilityProfile();
    return true;
  }

  static Future<bool> initBluetoothPrinter({KeckPaperSize size = KeckPaperSize.mm58, required String printerAddress}) async {
    paperSize = size;
    _profile ??= CapabilityProfile();

    if (_devicePrinter == null || !_devicePrinter!.isConnected) {
      await FlutterBluePlus.adapterState
          .firstWhere((s) => s == BluetoothAdapterState.on)
          .timeout(const Duration(seconds: 10));
      _devicePrinter = BluetoothDevice.fromId(printerAddress);
      await _devicePrinter!.connect(autoConnect: false, license: License.nonprofit);
    }

    return true;
  }

  static CapabilityProfile? get profile => _profile;

  static Future<List<int>> _getListIntBytesFromReceipt(KasseneckReceipt receipt, KeckPaperSize paperSize) async {
    List<Uint8List> bytes = await getBytesFromReceipt(receipt, paperSize);
    return List<int>.from(bytes.expand((Uint8List uint8List) => uint8List));
  }

  static Future<List<Uint8List>> getBytesFromReceipt(KasseneckReceipt receipt, KeckPaperSize paperSize, {QrPrintMode qrMode = QrPrintMode.imageRaster}) async {
    PrintPaper paper = PrintPaper(paperSize: paperSize, profile: KeckPrinterService.profile ?? CapabilityProfile());
    await paper.setKeckReceipt(receipt, qrMode: qrMode);
    return paper.bytes;
  }

  static Future<MyPosPaper> getMyPosPaperFromReceipt(KasseneckReceipt receipt) async {
    PrintPaper paper = PrintPaper(paperSize: paperSize, profile: KeckPrinterService.profile ?? CapabilityProfile());
    // MyPos hat seinen eigenen QR-Renderer → nativer Pfad (myPosPaper.addQrCode).
    await paper.setKeckReceipt(receipt, qrMode: QrPrintMode.native);
    return paper.myPosPaper;
  }

  /// Öffnet eine kurzlebige TCP-Verbindung zu [ip]:[port], sendet [bytes] und
  /// schließt wieder. Wirft bei Verbindungs-/Sendefehler. Gemeinsame Basis für
  /// den WLAN-Beleg-Druck und [printRawBytesWifi].
  static Future<void> _rawSocketSend(List<int> bytes, String ip, int port, Duration timeout) async {
    Socket? socket;
    try {
      socket = await Socket.connect(ip, port, timeout: timeout);
      socket.add(bytes);
      await socket.flush().timeout(timeout);
    } finally {
      try {
        await socket?.close();
      } catch (_) {/* Schließen-Fehler ignorieren — gesendet ist gesendet. */}
    }
  }

  static Future<void> _sendToSocketPrinter(List<int> bytes) async {
    final String? ip = ipAddress;
    if (ip == null || ip.isEmpty) {
      // Kein WLAN-Drucker konfiguriert -> WLAN-Druck ueberspringen, statt mit
      // null in Socket.connect zu crashen ("Null is not a subtype of String").
      return;
    }
    await _rawSocketSend(bytes, ip, port, const Duration(seconds: 5));
  }

  /// Sendet fertige ESC/POS-Bytes direkt an einen WiFi-Drucker — ohne den
  /// globalen aktiven Drucker zu verändern. Liefert Erfolg/Fehler zurück.
  ///
  /// Stateless: nutzt eine eigene, kurzlebige Socket-Verbindung zu [ip]:[port]
  /// und rührt weder [ipAddress]/[port] noch den initialisierten Drucker an.
  /// Wirft nicht — das Ergebnis kommt im [KeckPrintResult]. `success` heißt
  /// **gesendet**, nicht garantiert *gedruckt* (kein TCP-ACK; siehe [KeckPrintResult]).
  static Future<KeckPrintResult> printRawBytesWifi(
    List<int> bytes, {
    required String ip,
    int port = 9100,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (bytes.isEmpty) return const KeckPrintResult.failure('Keine Bytes zum Drucken.');
    if (ip.trim().isEmpty) return const KeckPrintResult.failure('Keine Drucker-IP angegeben.');
    try {
      await _rawSocketSend(bytes, ip, port, timeout);
      return const KeckPrintResult.success();
    } catch (e) {
      return KeckPrintResult.failure('WiFi-Druck fehlgeschlagen ($ip:$port): $e');
    }
  }

  static Future<PrintResponse> printReceiptMypos(KasseneckReceipt receipt) async {
    MyPosPaper paper = await getMyPosPaperFromReceipt(receipt);
    if (kDebugMode) print('Printing receipt with MyPos: ${paper.commands.length} lines');
    return await MyPos.printPaper(paper);
  }

  static Future printReceiptWifi(KasseneckReceipt receipt) async {
    await _sendToSocketPrinter(await _getListIntBytesFromReceipt(receipt, paperSize));
  }

  static BluetoothDevice get devicePrinter => _devicePrinter!;

  static Future printReceiptBluetooth(KasseneckReceipt receipt, {QrPrintMode qrMode = QrPrintMode.imageRaster}) async {
    final List<Uint8List> parts = await receipt.getPrintBytes(paperSize: paperSize, qrMode: qrMode);
    // Ein durchgehender Byte-Strom -> einheitliches Chunking ueber den ganzen Beleg.
    final List<int> data = <int>[for (final p in parts) ...p];
    return _sendToBluetoothPrinter(data);
  }

  /// Sendet einen fertigen Byte-Strom an den aktuell verbundenen Bluetooth-Drucker.
  /// Nutzt exakt den Sende-Pfad (MTU-Aushandlung, Flow-Control/Pacing) von
  /// [printReceiptBluetooth].
  static Future _sendToBluetoothPrinter(List<int> data) async {
    // Groessere MTU aushandeln, wo unterstuetzt (Android); sonst aktuellen Wert nehmen.
    int mtu;
    try {
      mtu = await _devicePrinter!.requestMtu(512);
    } catch (_) {
      mtu = _devicePrinter!.mtuNow;
    }
    final int chunkSize = (mtu - 3).clamp(20, 182).toInt();

    final List<BluetoothService> services = await _devicePrinter!.discoverServices();

    for (final service in services) {
      for (final characteristic in service.characteristics) {
        final bool canWrite = characteristic.properties.write;
        final bool canWriteNoResp = characteristic.properties.writeWithoutResponse;
        if (!canWrite && !canWriteNoResp) continue;

        // Kernproblem war fehlendes Flow-Control: grosse Raster (QR/Logo) wurden mit
        // withoutResponse ohne Backpressure rausgeblasen -> der Drucker-Puffer laeuft
        // ueber -> Zeichensalat + Abbruch. Loesung: write-with-response (wartet aufs
        // ACK = Backpressure) wo moeglich, sonst withoutResponse mit Pacing.
        final bool withoutResponse = !canWrite;
        try {
          for (int i = 0; i < data.length; i += chunkSize) {
            final int end = (i + chunkSize < data.length) ? i + chunkSize : data.length;
            await characteristic.write(data.sublist(i, end), withoutResponse: withoutResponse);
            if (withoutResponse) {
              await Future.delayed(const Duration(milliseconds: 20));
            }
          }
          return true; // erfolgreich gesendet
        } catch (e) {
          if (kDebugMode) {
            print("Fehler beim Senden an ${characteristic.uuid}: $e");
          }
        }
      }
    }

    throw Exception("Kein geeignetes Bluetooth-Charakteristikum zum Schreiben gefunden.");
  }

  static Future openCashDrawer() async {
    final generator = EscPosGenerator(paperSize.paperSize, CapabilityProfile());
    final drawerBytes = generator.drawer();
    await _sendToSocketPrinter(drawerBytes);
  }

  // ************************ Custom-Print-API ************************
  // Additive, generische Druck-Schnittstelle auf Basis des vendierten
  // [EscPosGenerator]. Bricht die RKSV-Beleglogik nicht — sie nutzt denselben
  // Sende-Pfad wie printReceiptBluetooth/printReceiptWifi.

  /// Frischer Generator mit aktueller Papiergroesse und dem initialisierten
  /// CapabilityProfile (Fallback: Default-Profil).
  static EscPosGenerator _generator() =>
      EscPosGenerator(paperSize.paperSize, _profile ?? CapabilityProfile());

  /// Sendet einen fertigen Byte-Strom an den aktuell initialisierten Drucker.
  ///
  /// Wenn ein Bluetooth-Drucker verbunden ist, geht es ueber den BT-Pfad
  /// (MTU/Chunking/Flow-Control wie beim Beleg-Druck); sonst ueber den
  /// WLAN-Socket-Pfad. So funktionieren die Custom-Befehle unabhaengig davon,
  /// welcher Drucker gerade aktiv ist.
  static Future<void> _sendToActivePrinter(List<int> bytes) async {
    if (bytes.isEmpty) return;
    if (_devicePrinter != null && _devicePrinter!.isConnected) {
      await _sendToBluetoothPrinter(bytes);
    } else {
      await _sendToSocketPrinter(bytes);
    }
  }

  /// Sendet beliebige, bereits fertige ESC/POS-Bytes an den aktiven Drucker.
  static Future<void> printRawBytes(List<int> bytes) => _sendToActivePrinter(bytes);

  /// Druckt einen Text (mit optionalen [styles]) und sendet ihn sofort.
  static Future<void> printText(String text, {PosStyles? styles}) async {
    final gen = _generator();
    await _sendToActivePrinter(
      gen.text(text, styles: styles ?? const PosStyles()),
    );
  }

  /// Druckt einen QR-Code und sendet ihn sofort. [size] entspricht den
  /// nativen ESC/POS-QR-Groessen 1–8.
  static Future<void> printQr(String data, {int size = 4}) async {
    final gen = _generator();
    await _sendToActivePrinter(gen.qrcode(data, size: _qrSize(size)));
  }

  /// Schneidet das Papier ab (falls vom Drucker unterstuetzt).
  static Future<void> cut() async {
    await _sendToActivePrinter(_generator().cut());
  }

  /// Oeffnet die Kassenlade am aktiven Drucker.
  static Future<void> openDrawer() async {
    await _sendToActivePrinter(_generator().drawer());
  }

  /// Papiervorschub um [n] Zeilen.
  static Future<void> feed(int n) async {
    await _sendToActivePrinter(_generator().feed(n));
  }

  /// Druckt einen zusammengesetzten Auftrag in EINEM Sendevorgang
  /// (bevorzugt fuer Bluetooth — ein einziger Byte-Strom statt vieler Writes).
  static Future<void> printJob(CustomPrintJob job) async {
    await _sendToActivePrinter(job.build(_generator()));
  }

  /// Mappt eine Groessenzahl 1–8 auf die passende [QRSize].
  static QRSize _qrSize(int size) {
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
  // ************************ (end) Custom-Print-API ************************
}

/// Sammelt mehrere Custom-Druckbefehle und baut daraus EINEN Byte-Strom, der
/// mit [KeckPrinterService.printJob] in einem einzigen Sendevorgang gedruckt
/// wird (fuer Bluetooth deutlich robuster als viele Einzel-Sends).
///
/// Fluent-API — die Aufrufe lassen sich verketten:
/// ```dart
/// final job = CustomPrintJob()
///   ..text('Hallo')
///   ..qr('https://kasseneck.at')
///   ..feed(2)
///   ..cut();
/// await KeckPrinterService.printJob(job);
/// ```
class CustomPrintJob {
  // Die Befehle werden erst beim [build] gegen einen konkreten Generator
  // aufgeloest — so gilt immer die aktuelle Papiergroesse/das Profil.
  final List<List<int> Function(EscPosGenerator)> _ops =
      <List<int> Function(EscPosGenerator)>[];

  /// Text (mit optionalen [styles]).
  CustomPrintJob text(String text, {PosStyles? styles}) {
    _ops.add((gen) => gen.text(text, styles: styles ?? const PosStyles()));
    return this;
  }

  /// QR-Code. [size] = native ESC/POS-QR-Groesse 1–8.
  CustomPrintJob qr(String data, {int size = 4}) {
    _ops.add((gen) => gen.qrcode(data, size: KeckPrinterService._qrSize(size)));
    return this;
  }

  /// 1D-Barcode (GS k, Form 2). [type] waehlt die Symbologie, [data] den
  /// Inhalt; [height]/[width]/[hri] steuern Hoehe, Modulbreite und Klartext.
  CustomPrintJob barcode(
    BarcodeType type,
    String data, {
    PosAlign align = PosAlign.center,
    int height = 100,
    int width = 3,
    BarcodeHri hri = BarcodeHri.below,
  }) {
    _ops.add((gen) => gen.barcode(
          type,
          data,
          align: align,
          height: height,
          width: width,
          hri: hri,
        ));
    return this;
  }

  /// Papier abschneiden.
  CustomPrintJob cut({PosCutMode mode = PosCutMode.full}) {
    _ops.add((gen) => gen.cut(mode: mode));
    return this;
  }

  /// Kassenlade oeffnen.
  CustomPrintJob drawer({PosDrawer pin = PosDrawer.pin2}) {
    _ops.add((gen) => gen.drawer(pin: pin));
    return this;
  }

  /// Papiervorschub um [n] Zeilen.
  CustomPrintJob feed(int n) {
    _ops.add((gen) => gen.feed(n));
    return this;
  }

  /// Beliebige, bereits fertige ESC/POS-Bytes.
  CustomPrintJob raw(List<int> bytes) {
    _ops.add((_) => bytes);
    return this;
  }

  /// Loest alle gesammelten Befehle gegen [gen] auf und liefert EINEN
  /// zusammenhaengenden Byte-Strom.
  List<int> build(EscPosGenerator gen) {
    final List<int> bytes = <int>[];
    for (final op in _ops) {
      bytes.addAll(op(gen));
    }
    return bytes;
  }
}
