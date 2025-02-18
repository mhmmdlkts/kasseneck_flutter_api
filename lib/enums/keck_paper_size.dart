import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

enum KeckPaperSize {
  mm58(PaperSize.mm58),
  mm72(PaperSize.mm72),
  mm80(PaperSize.mm80);

  final PaperSize paperSize;

  const KeckPaperSize(this.paperSize);
}