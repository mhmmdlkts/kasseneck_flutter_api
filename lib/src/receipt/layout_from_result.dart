import 'package:kasseneck_api/enums/keck_paper_size.dart';
import 'package:kasseneck_api/models/beleg_layout.dart';
import 'package:kasseneck_api/models/kasseneck_receipt.dart';

/// Was zum Drucken und Anzeigen eines Belegs aus einer Antwort gilt
/// (Ergebnis von [receiptLayoutFromResult]).
class ReceiptPrintLayout {
  /// Das Zeilenmodell des Servers (`data.layout`); `null`, wenn die Antwort
  /// keines trug. Dann zeichnet der lokale Rueckfall (`setKeckReceipt`) in
  /// [paperSize].
  final BelegLayout? layout;

  /// Breite, nach der das Layout gebaut ist: beim Server-Layout seine eigene
  /// (80 mm), sonst die Rueckfallbreite.
  final KeckPaperSize paperSize;

  const ReceiptPrintLayout._(this.layout, this.paperSize);

  /// Kommt das Layout vom Server?
  bool get fromServer => layout != null;
}

/// Das Zeilenmodell zum Drucken und Anzeigen eines Belegs aus einer Antwort
/// (Zwilling von `receiptLayoutFromResult` im npm-Paket).
///
/// **Ein Server-Layout gewinnt immer.** Traegt der Beleg `data.layout`, gilt
/// genau dieses, in seiner Breite (80 mm): im oeffentlichen Kanal traegt nur
/// es den Kartenblock (der Beleg selbst kommt dort ohne Anbieterdaten), und
/// Bildschirm, Bon und PDF zeigen so denselben Beleg. Fehlt es, bleibt
/// [ReceiptPrintLayout.layout] `null` und der lokale Rueckfall zeichnet in
/// [fallbackPaperSize] (Vorgabe `mm58` wie in 9.x). Die Druckbreite waehlt
/// allein der Druckweg, nie dieser Helfer.
ReceiptPrintLayout receiptLayoutFromResult(
  KasseneckReceipt receipt, {
  KeckPaperSize fallbackPaperSize = KeckPaperSize.mm58,
}) {
  final BelegLayout? server = receipt.layout;
  if (server != null) {
    return ReceiptPrintLayout._(server, KeckPaperSize.values.asNameMap()[server.paperSize] ?? KeckPaperSize.mm80);
  }
  return ReceiptPrintLayout._(null, fallbackPaperSize);
}
