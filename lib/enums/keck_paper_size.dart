import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

enum KeckPaperSize {
  mm58(PaperSize.mm58, 58, 300),
  mm72(PaperSize.mm72, 72, 400),
  mm80(PaperSize.mm80, 80, 500);

  final int mm;
  final PaperSize paperSize;
  final int imageWidth;

  const KeckPaperSize(this.paperSize, this.mm, this.imageWidth);

  // imlemeptation of comparable with < and > operators
  bool operator <(KeckPaperSize other) => mm < other.mm;
  bool operator >(KeckPaperSize other) => mm > other.mm;
  bool operator >=(KeckPaperSize other) => mm >= other.mm;
  bool operator <=(KeckPaperSize other) => mm <= other.mm;

}