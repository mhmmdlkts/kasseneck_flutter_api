import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:kasseneck_api/models/beleg_blatt.dart';
import 'package:kasseneck_api/models/beleg_layout.dart';
import 'package:kasseneck_api/models/logo_raster.dart';
import 'package:kasseneck_api/services/logo_service.dart';
import 'package:kasseneck_api/src/printing/qr_groesse.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Das Blatt am Bildschirm -- Zeile fuer Zeile dieselben Zeichen wie am Bon
/// und im PDF (Zwilling von `BelegBlattView` im npm-Paket). Eine Zeile ist
/// zwei Zeichenbreiten hoch, Logo und QR stehen in ihrem Blattanteil. Die
/// Zeichenbreite wird an der Schrift gemessen, nicht angenommen.
class KeckBelegBlattWidget extends StatefulWidget {
  final BelegLayout layout;
  final int? zeichen;
  final String? logoUrl;
  final LogoStufe logoStufe;
  final bool marke;
  final QrModulGroesse qrGroesse;
  final Color paperColor;
  final Color textColor;
  final bool qrCovered;
  final String qrCoveredText;
  final double fontSize;
  final Widget Function(String nutzlast)? qrFehltBuilder;

  const KeckBelegBlattWidget({
    required this.layout,
    this.zeichen,
    this.logoUrl,
    this.logoStufe = LogoStufe.m,
    this.marke = false,
    this.qrGroesse = QrModulGroesse.auto,
    this.paperColor = Colors.white,
    this.textColor = Colors.black,
    this.qrCovered = false,
    this.qrCoveredText = 'Antippen zum Anzeigen',
    this.fontSize = 12,
    this.qrFehltBuilder,
    super.key,
  });

  @override
  State<KeckBelegBlattWidget> createState() => _KeckBelegBlattWidgetState();
}

class _KeckBelegBlattWidgetState extends State<KeckBelegBlattWidget> {
  bool _qrOffen = false;
  ({String url, int breite, int hoehe})? _logo;

  @override
  void initState() {
    super.initState();
    _ladeLogo();
  }

  @override
  void didUpdateWidget(KeckBelegBlattWidget alt) {
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
      if (!logoPixelZulaessig(breite, hoehe)) return;
      final mass = (url: url, breite: breite, hoehe: hoehe);
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
    final blatt = belegBlatt(
      widget.layout,
      zeichen: widget.zeichen,
      logo: geladen ? BlattLogo(stufe: widget.logoStufe, pxBreite: _logo!.breite, pxHoehe: _logo!.hoehe) : null,
      marke: widget.marke,
      qrGroesse: widget.qrGroesse,
    );
    final breite = blatt.zeichen * cw;
    // Align loest eine straffe Breite von aussen (die App setzt den Beleg in
    // `SizedBox(width: 280/380)`): das Papier bleibt `zeichen x cw` breit und
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
              for (final (i, b) in blatt.bloecke.indexed)
                switch (b) {
                  BlattZeile() => SizedBox(
                      key: Key('keck-blatt-zeile-$i'),
                      height: 2 * cw,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(b.text,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.clip,
                            style: stil.copyWith(fontWeight: b.fett ? FontWeight.w500 : FontWeight.w400)),
                      ),
                    ),
                  // Die Zeilen darueber stehen in einer Column mit
                  // CrossAxisAlignment.stretch -- ein direktes Kind bekaeme
                  // eine straffe Breitenzwang auf die volle Blattbreite. Erst
                  // Center loest den Zwang; nur so wird das Logo tatsaechlich
                  // schmaler als das Blatt (wie beim QR unten).
                  BlattLogoBlock() => Center(
                      child: SizedBox(
                        key: const Key('keck-blatt-logo'),
                        width: b.breiteAnteil * breite,
                        height: b.hoeheZeilen * 2 * cw,
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
                                cacheWidth: math.max(1, (b.breiteAnteil * breite * MediaQuery.devicePixelRatioOf(context)).round()),
                              ),
                      ),
                    ),
                  BlattQr() => Center(child: _qr(b, breite, stil)),
                },
            ],
          ),
        ),
      ),
    );
  }

  Widget _qr(BlattQr b, double breite, TextStyle stil) {
    // Anteil 0: der QR hat auf dem Blatt keinen Platz. Eine leere Nutzlast
    // ist kein Ausfall dieses Blatts -- wie Bon und PDF zeigt das Widget dann
    // einfach keinen QR. Eine nicht-leere Nutzlast, die in keine QR-Version
    // passt, ist dagegen der eigentliche Ausfall (Registrierkasse: der QR ist
    // die maschinenlesbare Signatur) -- das muss sichtbar sein, sonst ginge
    // ein Beleg ohne Hinweis und ohne Signatur raus.
    if (b.breiteAnteil <= 0) {
      if (b.nutzlast.isEmpty) return const SizedBox.shrink();
      return widget.qrFehltBuilder?.call(b.nutzlast) ?? _qrFehltHinweis(stil);
    }
    final seite = b.breiteAnteil * breite;
    // Die Breite enthaelt die Ruhezone (4 Module je Seite) -- wie am Drucker.
    final module = b.nutzlast.isEmpty ? 1 : qrModulAnzahlWieNpm(b.nutzlast);
    final rand = seite * QrMass.ruhezoneModule / (module + 2 * QrMass.ruhezoneModule);
    final qr = SizedBox(
      key: const Key('keck-blatt-qr'),
      width: seite,
      height: seite,
      child: Padding(
        padding: EdgeInsets.all(rand),
        child: QrImageView(
          data: b.nutzlast,
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
