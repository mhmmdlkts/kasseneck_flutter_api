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
/// **Die Einstellung kennt zwei Werte, der Drucker drei.** [KasseQrModus] ist
/// das, wonach der Wizard fragt: „welcher der beiden Probedrucke war lesbar?"
/// — zwei Antworten sind am Tresen zu prüfen, drei nicht mehr.
/// [QrPrintMode.imageBitImage] bleibt daneben für Aufrufer bestehen, die den
/// Modus selbst wählen; über die Einstellungen ist er nicht erreichbar.
extension KasseQrModusDruck on KasseQrModus {
  QrPrintMode get druckmodus => switch (this) {
        KasseQrModus.raster => QrPrintMode.imageRaster,
        KasseQrModus.escpos => QrPrintMode.native,
      };
}
