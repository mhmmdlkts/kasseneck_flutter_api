import 'package:kasseneck_api/src/printing/escpos/enums.dart';

enum KeckPaperSize {
  mm58(EscPaperSize.mm58, 32, 58, 296, 384),
  mm80(EscPaperSize.mm80, 48, 80, 504, 576);

  final int mm;
  final int defaultCharCount;
  final EscPaperSize paperSize;
  final int imageWidth;

  /// Druckbreite des Kopfes in Punkten (203 dpi): 58 mm = 384, 80 mm = 576.
  ///
  /// Nicht dasselbe wie [imageWidth] — die ist die Breite, auf die Bilder
  /// skaliert werden, und laesst absichtlich Rand. Wer rechnet, ob ein Symbol
  /// aufs Papier passt, braucht die echte Kopfbreite: ein QR, der auch nur
  /// einen Punkt zu breit ist, wird von den meisten Geraeten **gar nicht**
  /// gedruckt.
  final int druckPunkte;

  const KeckPaperSize(this.paperSize, this.defaultCharCount, this.mm, this.imageWidth,
      this.druckPunkte);

  bool operator <(KeckPaperSize other) => mm < other.mm;
  bool operator >(KeckPaperSize other) => mm > other.mm;
  bool operator >=(KeckPaperSize other) => mm >= other.mm;
  bool operator <=(KeckPaperSize other) => mm <= other.mm;
}