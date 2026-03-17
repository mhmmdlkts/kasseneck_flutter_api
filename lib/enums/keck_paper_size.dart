import 'package:esc_pos_utils/esc_pos_utils.dart';

enum KeckPaperSize {
  mm58(PaperSize.mm58, 32, 58, 296),
  mm80(PaperSize.mm80, 48, 80, 504);

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