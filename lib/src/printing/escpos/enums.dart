enum PosAlign { left, center, right }
enum PosCutMode { full, partial }
enum PosFontType { fontA, fontB }
enum PosDrawer { pin2, pin5 }

/// 1D-Barcode-Symbologien fuer GS k (Form 2). Der Wert [m] ist der
/// ESC/POS-Selektor (65..73) im Befehl `GS k m n <payload>`.
enum BarcodeType {
  upcA(65),
  upcE(66),
  ean13(67),
  ean8(68),
  code39(69),
  itf(70),
  codabar(71),
  code93(72),
  code128(73);

  final int m;
  const BarcodeType(this.m);
}

/// Position der HRI-Klartextzeichen (Human Readable Interpretation) relativ
/// zum Barcode. Der Wert geht als n in `GS H n`.
enum BarcodeHri {
  none(0),
  above(1),
  below(2),
  both(3);

  final int value;
  const BarcodeHri(this.value);
}

/// bitImageRaster: GS v 0 (obsolete); graphics: GS ( L
enum PosImageFn { bitImageRaster, graphics }

class PosTextSize {
  const PosTextSize._internal(this.value);
  final int value;
  static const size1 = PosTextSize._internal(1);
  static const size2 = PosTextSize._internal(2);
  static const size3 = PosTextSize._internal(3);
  static const size4 = PosTextSize._internal(4);
  static const size5 = PosTextSize._internal(5);
  static const size6 = PosTextSize._internal(6);
  static const size7 = PosTextSize._internal(7);
  static const size8 = PosTextSize._internal(8);

  static int decSize(PosTextSize height, PosTextSize width) =>
      16 * (width.value - 1) + (height.value - 1);
}

class EscPaperSize {
  const EscPaperSize._internal(this.value);
  final int value;
  static const mm58 = EscPaperSize._internal(1);
  static const mm80 = EscPaperSize._internal(2);

  int get width => value == EscPaperSize.mm58.value ? 372 : 558;
}
