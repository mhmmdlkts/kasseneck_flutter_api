
import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_esc_pos_network/flutter_esc_pos_network.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/print_paper.dart';

import '../enums/keck_paper_size.dart';

class KeckPrinterService {

  static PrinterNetworkManager? _networkPrinter;
  static KeckPaperSize paperSize = KeckPaperSize.mm58;

  static Future<bool> initPrinter(String macAddress, KeckPaperSize size) async {
    paperSize = size;
    PrinterNetworkManager printer = PrinterNetworkManager(macAddress);
    final PosPrintResult res = await printer.connect();
    if (res == PosPrintResult.success) {
      _networkPrinter = printer;
    }
    return _networkPrinter != null;
  }

  static Future<List<int>> _getListIntBytesFromReceipt(KasseneckReceipt receipt, KeckPaperSize paperSize) async {
    List<Uint8List> bytes = await getBytesFromReceipt(receipt, paperSize);
    return List<int>.from(bytes.expand((Uint8List uint8List) => uint8List));
  }

  static Future<List<Uint8List>> getBytesFromReceipt(KasseneckReceipt receipt, KeckPaperSize paperSize, {bool qrAsImage = false}) async {
    PrintPaper paper = PrintPaper(paperSize: paperSize);
    await paper.setKeckReceipt(receipt, qrAsImage: qrAsImage);
    return paper.bytes;
  }

  static Future printReceipt(KasseneckReceipt receipt) async {
    if (_networkPrinter == null) {
      throw Exception('Printer not initialized');
    }
    await _networkPrinter!.printTicket(await _getListIntBytesFromReceipt(receipt, paperSize));
  }

  static Future openCashDrawer() async {
    if (_networkPrinter == null) {
      throw Exception('Printer not initialized');
    }
    await _networkPrinter!.printTicket(Generator(paperSize.paperSize, await CapabilityProfile.load()).drawer());
  }
}