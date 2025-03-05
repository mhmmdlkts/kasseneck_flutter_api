import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

enum KeckPaperSize {
  mm58(PaperSize.mm58, 32, 58, 300),
  mm72(PaperSize.mm72, 42, 72, 400), // TODO: what is the correct char count?
  mm80(PaperSize.mm80, 48, 80, 500);

  final int mm;
  final int defaultCharCount;
  final PaperSize paperSize;
  final int imageWidth;

  const KeckPaperSize(this.paperSize, this.defaultCharCount, this.mm, this.imageWidth);

  // imlemeptation of comparable with < and > operators
  bool operator <(KeckPaperSize other) => mm < other.mm;
  bool operator >(KeckPaperSize other) => mm > other.mm;
  bool operator >=(KeckPaperSize other) => mm >= other.mm;
  bool operator <=(KeckPaperSize other) => mm <= other.mm;

}