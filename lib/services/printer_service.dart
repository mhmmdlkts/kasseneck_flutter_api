import 'dart:io';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/print_paper.dart';
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
    try {
      _profile = await CapabilityProfile.load();
      return true;
    } catch (e) {
      print('Failed to connect to printer: $e');
      return false;
    }
  }

  static Future<bool> initBluetoothPrinter({KeckPaperSize size = KeckPaperSize.mm58, required String printerAddress}) async {
    paperSize = size;
    _profile ??= await CapabilityProfile.load();

    if (_devicePrinter == null || !_devicePrinter!.isConnected) {
      await FlutterBluePlus.adapterState
          .firstWhere((s) => s == BluetoothAdapterState.on)
          .timeout(const Duration(seconds: 10));
      _devicePrinter = BluetoothDevice.fromId(printerAddress);
      await _devicePrinter!.connect(autoConnect: false, license: License.free);
    }

    return true;
  }

  static CapabilityProfile? get profile => _profile;

  static Future<List<int>> _getListIntBytesFromReceipt(KasseneckReceipt receipt, KeckPaperSize paperSize) async {
    List<Uint8List> bytes = await getBytesFromReceipt(receipt, paperSize);
    return List<int>.from(bytes.expand((Uint8List uint8List) => uint8List));
  }

  static Future<List<Uint8List>> getBytesFromReceipt(KasseneckReceipt receipt, KeckPaperSize paperSize, {QrPrintMode qrMode = QrPrintMode.imageRaster}) async {
    PrintPaper paper = PrintPaper(paperSize: paperSize, profile: KeckPrinterService.profile??await CapabilityProfile.load());
    await paper.setKeckReceipt(receipt, qrMode: qrMode);
    return paper.bytes;
  }

  static Future<MyPosPaper> getMyPosPaperFromReceipt(KasseneckReceipt receipt) async {
    PrintPaper paper = PrintPaper(paperSize: paperSize, profile: KeckPrinterService.profile??await CapabilityProfile.load());
    // MyPos hat seinen eigenen QR-Renderer → nativer Pfad (myPosPaper.addQrCode).
    await paper.setKeckReceipt(receipt, qrMode: QrPrintMode.native);
    return paper.myPosPaper;
  }

  static Future<void> _sendToSocketPrinter(List<int> bytes) async {
    final String? ip = ipAddress;
    if (ip == null || ip.isEmpty) {
      // Kein WLAN-Drucker konfiguriert -> WLAN-Druck ueberspringen, statt mit
      // null in Socket.connect zu crashen ("Null is not a subtype of String").
      return;
    }
    Socket socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
    socket.add(bytes);
    await socket.flush();
    await socket.close();
  }

  static Future<PrintResponse> printReceiptMypos(KasseneckReceipt receipt) async {
    MyPosPaper paper = await getMyPosPaperFromReceipt(receipt);
    print('Printing receipt with MyPos: ${paper.commands.length} lines');
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
    final generator = Generator(paperSize.paperSize, await CapabilityProfile.load());
    final drawerBytes = generator.drawer();
    await _sendToSocketPrinter(drawerBytes);
  }
}