import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:kasseneck_api/models/receipt_sheet.dart';
import 'package:kasseneck_api/models/receipt_layout.dart';
import 'package:kasseneck_api/models/logo_raster.dart';
import 'package:kasseneck_api/services/logo_service.dart';
import 'package:kasseneck_api/src/printing/qr_groesse.dart';
import 'package:kreiseck_design/kreiseck_design.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Das Blatt am Bildschirm -- Zeile fuer Zeile dieselben Zeichen wie am Bon
/// und im PDF (Zwilling von `BelegBlattView` im npm-Paket). Eine Zeile ist
/// zwei Zeichenbreiten hoch, Logo und QR stehen in ihrem Blattanteil. Die
/// Zeichenbreite wird an der Schrift gemessen, nicht angenommen.
class KeckReceiptSheetWidget extends StatefulWidget {
  final ReceiptLayout layout;

  /// Ein fertiges Blatt statt eines Layouts (etwa das Testblatt des
  /// Zeichensatzes, `codeTableTestSheet`); gesetzt nur ueber
  /// [KeckReceiptSheetWidget.fromSheet]. Dann gilt [layout] nicht.
  final ReceiptSheet? sheet;
  final int? charsPerLine;
  final String? logoUrl;
  final SheetLogoSize logoSize;
  final bool brandMark;
  final QrModuleSize qrModuleSize;
  final Color paperColor;
  final Color textColor;
  final bool qrCovered;
  final String qrCoveredText;
  final double fontSize;
  final Widget Function(String payload)? qrMissingBuilder;

  const KeckReceiptSheetWidget({
    required this.layout,
    this.charsPerLine,
    this.logoUrl,
    this.logoSize = SheetLogoSize.m,
    this.brandMark = false,
    this.qrModuleSize = QrModuleSize.auto,
    this.paperColor = Colors.white,
    this.textColor = Colors.black,
    this.qrCovered = false,
    this.qrCoveredText = 'Antippen zum Anzeigen',
    this.fontSize = 12,
    this.qrMissingBuilder,
    super.key,
  }) : sheet = null;

  /// Zeichnet ein fertiges [sheet] -- dieselben Zeilen, die das Papier traegt.
  /// Eine Zeile mit `doubleSizeLead` steht zwei Zeilen hoch, ihre Nummer
  /// doppelt gross und fett wie am Papier (`GS !` + `ESC E`).
  const KeckReceiptSheetWidget.fromSheet({
    required ReceiptSheet this.sheet,
    this.logoUrl,
    this.paperColor = Colors.white,
    this.textColor = Colors.black,
    this.qrCovered = false,
    this.qrCoveredText = 'Antippen zum Anzeigen',
    this.fontSize = 12,
    this.qrMissingBuilder,
    super.key,
  })  : layout = const ReceiptLayout(lines: [], paperSize: 'mm58', ruleset: 2),
        charsPerLine = null,
        logoSize = SheetLogoSize.m,
        brandMark = false,
        qrModuleSize = QrModuleSize.auto;

  @override
  State<KeckReceiptSheetWidget> createState() => _KeckBelegBlattWidgetState();
}

class _KeckBelegBlattWidgetState extends State<KeckReceiptSheetWidget> {
  bool _qrOffen = false;
  ({String url, int width, int height})? _logo;

  @override
  void initState() {
    super.initState();
    _ladeLogo();
  }

  @override
  void didUpdateWidget(KeckReceiptSheetWidget alt) {
    super.didUpdateWidget(alt);
    if (alt.logoUrl != widget.logoUrl) _ladeLogo();
  }

  Future<void> _ladeLogo() async {
    final url = widget.logoUrl;
    if (url == null) return;
    await LogoService.loadLogo(url);
    final bytes = LogoService.getLogoBytes(url);
    if (bytes == null || !mounted) return;
    try {
      // Nur den Bildkopf lesen (Breite/Hoehe), nicht das ganze Bild
      // dekodieren: Bildschirm und Bon teilen denselben Pixel-Deckel
      // (logoPixelZulaessig, lib/models/logo_raster.dart) -- ohne den waere
      // ein Logo auf der Fertig-Seite und im PDF zu sehen, das am Drucker
      // verworfen wird. `Image.memory` unten dekodiert das zulaessige Logo
      // ohnehin nur in der angezeigten Groesse (cacheWidth); ein voller
      // Decode hier waere fuer ein zu grosses Logo verschwendete Arbeit und
      // fuer ein zulaessiges doppelte.
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final int breite;
      final int hoehe;
      // Freigeben auf JEDEM Weg: `ImageDescriptor.encoded` wirft bei einer
      // kaputten Datei, die der Puffer noch angenommen hat -- ohne `finally`
      // bliebe dann je Aufruf (jeder Beleg) ein nativer Puffer liegen.
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          breite = descriptor.width;
          hoehe = descriptor.height;
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
      // Ein zu grosses Logo ist wie ein Logo, das nicht geladen hat: kein
      // Logo-Block, dieselben Zeilen wie ohne Logo -- kein Merken des Fehlers.
      if (!isLogoPixelSizeAllowed(breite, hoehe)) return;
      final mass = (url: url, width: breite, height: hoehe);
      if (mounted && widget.logoUrl == url) setState(() => _logo = mass);
    } catch (_) {
      // Ein Logo, das sich nicht lesen laesst, kostet den Beleg nicht: das Blatt steht ohne Logo.
    }
  }

  @override
  Widget build(BuildContext context) {
    final stil = TextStyle(
      // fontFamily/package wie kdMonoStyle (kreiseck_design)
      fontFamily: 'DM Mono',
      package: 'kreiseck_design',
      fontSize: widget.fontSize,
      height: 1.0,
      color: widget.textColor,
      fontFeatures: const [ui.FontFeature.disable('liga'), ui.FontFeature.disable('calt')],
    );
    final messer = TextPainter(text: TextSpan(text: '0', style: stil), textDirection: TextDirection.ltr)..layout();
    final cw = messer.width;
    messer.dispose();

    // Ohne Bytes kein Logo-Block -- auch wenn das Mass schon bekannt ist.
    final logoBytes = LogoService.getLogoBytes(widget.logoUrl);
    final geladen = _logo != null && _logo!.url == widget.logoUrl && logoBytes != null;
    final blatt = widget.sheet ?? receiptSheet(
      widget.layout,
      charsPerLine: widget.charsPerLine,
      logo: geladen ? SheetLogo(size: widget.logoSize, pixelWidth: _logo!.width, pixelHeight: _logo!.height) : null,
      brandMark: widget.brandMark,
      qrModuleSize: widget.qrModuleSize,
    );
    final breite = blatt.charsPerLine * cw;
    // Align loest eine straffe Breite von aussen (die App setzt den Beleg in
    // `SizedBox(width: 280/380)`): das Papier bleibt `charsPerLine x cw` breit und
    // steht oben mittig, statt auf die Huelle gezogen zu werden.
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        color: widget.paperColor,
        padding: EdgeInsets.all(cw * 2),
        child: SizedBox(
          key: const Key('keck-blatt'),
          width: breite,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, b) in blatt.blocks.indexed)
                switch (b) {
                  SheetLine(:final doubleSizeLead?) when doubleSizeLead > 0 => _grosseZeile(i, b, doubleSizeLead, cw, stil),
                  SheetLine() => SizedBox(
                      key: Key('keck-blatt-zeile-$i'),
                      height: 2 * cw,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(b.text,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.clip,
                            style: stil.copyWith(fontWeight: b.bold ? FontWeight.w500 : FontWeight.w400)),
                      ),
                    ),
                  // Die Zeilen darueber stehen in einer Column mit
                  // CrossAxisAlignment.stretch -- ein direktes Kind bekaeme
                  // eine straffe Breitenzwang auf die volle Blattbreite. Erst
                  // Center loest den Zwang; nur so wird das Logo tatsaechlich
                  // schmaler als das Blatt (wie beim QR unten).
                  SheetLogoBlock() => Center(
                      child: SizedBox(
                        key: const Key('keck-blatt-logo'),
                        width: b.widthFraction * breite,
                        height: b.heightLines * 2 * cw,
                        // `geladen` setzt Bytes voraus; ohne sie entsteht kein Logo-Block.
                        // `cacheWidth` laesst Flutter nur in der angezeigten
                        // Groesse dekodieren statt in der vollen Bildaufloesung
                        // -- sonst kostet jeder Beleg einen Mehr-Megapixel-Decode
                        // fuer ein Logo, das nur wenige Dutzend Punkte breit steht.
                        child: logoBytes == null
                            ? null
                            : Image.memory(
                                logoBytes,
                                fit: BoxFit.contain,
                                cacheWidth: math.max(1, (b.widthFraction * breite * MediaQuery.devicePixelRatioOf(context)).round()),
                              ),
                      ),
                    ),
                  SheetQr() => Center(child: _qr(b, breite, stil)),
                  // Nicht das Druckraster: die Logo-Komponente aus
                  // kreiseck_design zeichnet die Marke am Bildschirm als
                  // Vektor, scharf in jeder Aufloesung (siehe
                  // docs/specs/2026-09-21-marke-einheitlich-design.md, § 3.2).
                  // Die Hoehe folgt derselben Rechnung wie beim Firmenlogo:
                  // Druckpunkte -> Zeilen -> Bildschirm-Pixel.
                  SheetBrandMark() => Center(
                      child: KdLogo(
                        key: const Key('keck-blatt-marke'),
                        height: (b.height / dotsPerLine) * 2 * cw,
                        ink: widget.textColor,
                        accent: widget.textColor,
                      ),
                    ),
                },
            ],
          ),
        ),
      ),
    );
  }

  /// Wie am Papier (`GS !` doppelt): die ersten [lead] Spalten sind eine
  /// Zelle mit der Nummer in doppelter Schrift und fett, die Zeile ist zwei
  /// Zeilen hoch, der Rest steht auf der Grundlinie unter seinen Spalten.
  Widget _grosseZeile(int i, SheetLine b, int lead, double cw, TextStyle stil) {
    final gewicht = b.bold ? FontWeight.w500 : FontWeight.w400;
    return SizedBox(
      key: Key('keck-blatt-zeile-$i'),
      height: 4 * cw,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            key: Key('keck-blatt-zeile-$i-nummer'),
            width: lead * cw,
            height: 4 * cw,
            child: Center(
              child: Text(b.text.substring(0, lead).trim(),
                  maxLines: 1,
                  softWrap: false,
                  style: stil.copyWith(fontSize: 2 * widget.fontSize, fontWeight: FontWeight.bold)),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 2 * cw,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(b.text.substring(lead),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: stil.copyWith(fontWeight: gewicht)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _qr(SheetQr b, double breite, TextStyle stil) {
    // Anteil 0: der QR hat auf dem Blatt keinen Platz. Eine leere Nutzlast
    // ist kein Ausfall dieses Blatts -- wie Bon und PDF zeigt das Widget dann
    // einfach keinen QR. Eine nicht-leere Nutzlast, die in keine QR-Version
    // passt, ist dagegen der eigentliche Ausfall (Registrierkasse: der QR ist
    // die maschinenlesbare Signatur) -- das muss sichtbar sein, sonst ginge
    // ein Beleg ohne Hinweis und ohne Signatur raus.
    if (b.widthFraction <= 0) {
      if (b.payload.isEmpty) return const SizedBox.shrink();
      return widget.qrMissingBuilder?.call(b.payload) ?? _qrFehltHinweis(stil);
    }
    final seite = b.widthFraction * breite;
    // Die Breite enthaelt die Ruhezone (4 Module je Seite) -- wie am Drucker.
    final module = b.payload.isEmpty ? 1 : qrModuleCount(b.payload);
    final rand = seite * QrMetrics.quietZoneModules / (module + 2 * QrMetrics.quietZoneModules);
    final qr = SizedBox(
      key: const Key('keck-blatt-qr'),
      width: seite,
      height: seite,
      child: Padding(
        padding: EdgeInsets.all(rand),
        child: QrImageView(
          data: b.payload,
          // Korrektur M wie Bon, ePOS und Blatt; qr_flutter setzt sonst L und
          // zeichnete bei mancher Nutzlast weniger Module, als das Blatt rechnet.
          errorCorrectionLevel: QrErrorCorrectLevel.M,
          padding: EdgeInsets.zero,
          eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: widget.textColor),
          dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: widget.textColor),
          backgroundColor: Colors.transparent,
        ),
      ),
    );
    if (!widget.qrCovered) return qr;
    return Semantics(
      button: true,
      label: _qrOffen ? 'QR-Code verdecken' : 'QR-Code anzeigen',
      child: GestureDetector(
        key: const Key('keck-blatt-qr-toggle'),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _qrOffen = !_qrOffen),
        child: Stack(alignment: Alignment.center, children: [
          if (_qrOffen) qr else ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6), child: qr),
          if (!_qrOffen)
            Text(widget.qrCoveredText,
                style: TextStyle(color: widget.textColor, fontWeight: FontWeight.bold, fontSize: 12),
                textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  // Wortlaut wie im npm-Paket (Browser-Kasse): dieselben Worte in Web und App
  // sind Hausregel, nicht Zufall.
  static const _qrFehltText = 'Der QR-Code konnte nicht erzeugt werden. Bitte einen Papierbeleg ausgeben.';

  Widget _qrFehltHinweis(TextStyle stil) {
    // Natuerliche Hoehe statt der QR-Kastengroesse (die waere hier 0) -- der
    // Hinweis darf die Zeilenhoehen der Textzeilen nicht verbiegen. Farbe
    // traegt hier nichts allein: die Worte selbst sind der Hinweis.
    return Semantics(
      liveRegion: true,
      child: Text(
        _qrFehltText,
        key: const Key('keck-blatt-qr-fehlt'),
        textAlign: TextAlign.center,
        style: stil,
      ),
    );
  }
}
