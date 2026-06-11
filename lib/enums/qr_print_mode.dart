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
