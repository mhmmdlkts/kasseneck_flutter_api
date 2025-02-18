import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_esc_pos_network/flutter_esc_pos_network.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';
import 'package:kasseneck_api/models/print_paper.dart';

class PrinterService {

  static PrinterNetworkManager? _printer;
  static PaperSize paperSize = PaperSize.mm58;

  static Future<bool> initPrinter(String macAddress, PaperSize size) async {
    paperSize = size;
    PrinterNetworkManager printer = PrinterNetworkManager(macAddress);
    final PosPrintResult res = await printer.connect();
    if (res == PosPrintResult.success) {
      _printer = printer;
    }
    return _printer != null;
  }

  static Future printReceipt(KasseneckReceipt receipt) async {
    if (_printer == null) {
      throw Exception('Printer not initialized');
    }
    PrintPaper paper = PrintPaper(paperSize: paperSize);
    await paper.setKeckReceipt(receipt);
    await _printer!.printTicket(paper.bytes);
  }

  static Future openCashDrawer() async {
    if (_printer == null) {
      throw Exception('Printer not initialized');
    }
    await _printer!.printTicket(Generator(paperSize, await CapabilityProfile.load()).drawer());
  }
}