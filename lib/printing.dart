/// Oeffentliches Barrel fuer den vendierten ESC/POS-Druck-Stack.
///
/// Integratoren, die selbst Bytes bauen wollen, importieren dieses Barrel und
/// senden das Ergebnis via [KeckPrinterService.printRawBytes]:
///
/// ```dart
/// import 'package:kasseneck_api/printing.dart';
///
/// final gen = EscPosGenerator(EscPaperSize.mm80, CapabilityProfile());
/// final bytes = <int>[
///   ...gen.text('Hallo', styles: const PosStyles(align: PosAlign.center)),
///   ...gen.cut(),
/// ];
/// await KeckPrinterService.printRawBytes(bytes);
/// ```
library;

export 'src/printing/escpos/generator.dart' show EscPosGenerator;
export 'src/printing/escpos/enums.dart'
    show
        PosAlign,
        PosCutMode,
        PosFontType,
        PosDrawer,
        PosImageFn,
        PosTextSize,
        EscPaperSize;
export 'src/printing/escpos/pos_styles.dart' show PosStyles;
export 'src/printing/escpos/pos_column.dart' show PosColumn;
export 'src/printing/escpos/qrcode.dart' show QRSize, QRCorrection, QRCode;
export 'src/printing/escpos/capability_profile.dart' show CapabilityProfile;
export 'src/printing/raster/raster_image.dart' show RasterImage;
export 'services/printer_service.dart' show KeckPrinterService, CustomPrintJob;
export 'models/keck_print_result.dart' show KeckPrintResult;
