import 'package:kasseneck_api/src/printing/escpos/enums.dart';

enum KeckPaperSize {
  mm58(EscPaperSize.mm58, 32, 58, 296),
  mm80(EscPaperSize.mm80, 48, 80, 504);

  final int mm;
  final int defaultCharCount;
  final EscPaperSize paperSize;
  final int imageWidth;

  const KeckPaperSize(this.paperSize, this.defaultCharCount, this.mm, this.imageWidth);

  bool operator <(KeckPaperSize other) => mm < other.mm;
  bool operator >(KeckPaperSize other) => mm > other.mm;
  bool operator >=(KeckPaperSize other) => mm >= other.mm;
  bool operator <=(KeckPaperSize other) => mm <= other.mm;
}