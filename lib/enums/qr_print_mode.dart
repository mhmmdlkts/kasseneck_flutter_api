import '../src/kasse/einstellungen.dart';

/// Druckmodus für den Beleg-QR-Code.
///
/// Verschiedene Thermodrucker unterstützen unterschiedliche Befehle — daher
/// umschaltbar, damit pro Drucker der funktionierende Modus gewählt werden kann.
enum QrPrintMode {
  /// GS v 0 Raster-Bild (neuere Drucker). Bisheriger Standard.
  imageRaster,

  /// ESC * Bit-Image — sehr breit unterstützt, auch von älteren Druckern, die
  /// GS v 0 als Zeichensalat ausgeben.
  imageBitImage,

  /// Nativer QR-Befehl GS ( k — schärfer/schneller, aber nicht von jedem
  /// Drucker unterstützt (sonst wird gar kein QR gedruckt).
  native,
}

/// Der eingestellte QR-Modus des Geräts als Druckbefehl.
///
/// **Die Einstellung kennt zwei entschiedene Werte, der Drucker drei Befehle.**
/// [KasseQrModus] ist das, wonach der Wizard fragt: „welcher der beiden
/// Probedrucke war lesbar?" — zwei Antworten sind am Tresen zu prüfen, drei
/// nicht mehr. [QrPrintMode.imageBitImage] bleibt daneben für Aufrufer
/// bestehen, die den Modus selbst wählen; über die Einstellungen ist er nicht
/// erreichbar.
///
/// **[vorgabe] ist Pflicht und hat keinen Standardwert.** [KasseQrModus.auto]
/// heißt „hier hat niemand entschieden", und was dann gilt, weiß nur der
/// Aufrufer: die App druckt seit jeher das Rasterbild, die Browser-Kasse den
/// nativen Befehl. Ein Standardwert an dieser Stelle hätte eine der beiden
/// Kassen still umgestellt.
extension KasseQrModusDruck on KasseQrModus {
  QrPrintMode druckmodusOder(QrPrintMode vorgabe) => switch (this) {
        KasseQrModus.auto => vorgabe,
        KasseQrModus.raster => QrPrintMode.imageRaster,
        KasseQrModus.escpos => QrPrintMode.native,
      };
}
