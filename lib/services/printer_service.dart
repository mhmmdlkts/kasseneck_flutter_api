import 'dart:typed_data';
import 'dart:io';

import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/print_paper.dart';
import 'package:my_pos/models/my_pos_paper.dart';
import 'package:my_pos/enums/my_pos_print_response.dart';
import 'package:my_pos/my_pos.dart';

import '../enums/keck_paper_size.dart';

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
      await FlutterBluePlus.adapterState.firstWhere((s) => s == BluetoothAdapterState.on);
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

  static Future<List<Uint8List>> getBytesFromReceipt(KasseneckReceipt receipt, KeckPaperSize paperSize, {bool qrAsImage = false}) async {
    PrintPaper paper = PrintPaper(paperSize: paperSize, profile: KeckPrinterService.profile??await CapabilityProfile.load());
    await paper.setKeckReceipt(receipt, qrAsImage: qrAsImage);
    return paper.bytes;
  }

  static Future<MyPosPaper> getMyPosPaperFromReceipt(KasseneckReceipt receipt) async {
    PrintPaper paper = PrintPaper(paperSize: paperSize, profile: KeckPrinterService.profile??await CapabilityProfile.load());
    await paper.setKeckReceipt(receipt, qrAsImage: false);
    return paper.myPosPaper;
  }

  static Future<void> _sendToSocketPrinter(List<int> bytes) async {
    Socket socket = await Socket.connect(ipAddress, port, timeout: const Duration(seconds: 5));
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

  static Future printReceiptBluetooth(KasseneckReceipt receipt, {bool qrAsImage = true}) async {
    List<Uint8List> bytes = await receipt.getPrintBytes(paperSize: paperSize, qrAsImage: qrAsImage);
    const int maxChunkSize = 150;

    List<BluetoothService> services = await _devicePrinter!.discoverServices();

    for (var service in services) {
      for (var characteristic in service.characteristics) {
        // Check if the characteristic is writable
        if (characteristic.properties.write || characteristic.properties.writeWithoutResponse) {
          try {
            for (var element in bytes) {
              for (int i = 0; i < element.length; i += maxChunkSize) {
                int end = (i + maxChunkSize < element.length) ? i + maxChunkSize : element.length;
                await characteristic.write(element.sublist(i, end), withoutResponse: true);
              }
            }
            return true; // Successfully sent to a writable characteristic, exit early
          } catch (e) {
            if (kDebugMode) {
              print("Fehler beim Senden an ${characteristic.uuid}: $e");
            }
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