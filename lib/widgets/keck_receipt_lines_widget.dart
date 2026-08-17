import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:kasseneck_api/models/beleg_layout.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Zeichnet ein Beleg-Zeilenmodell des Backends ([BelegLayout]) — genau die
/// Zeilen, die Browser-Kasse, Bondrucker und PDF zeigen. Kein eigenes
/// Beleg-Wissen: Reihenfolge, Texte und Aufdrucke kommen aus dem Modell.
///
/// [qrCovered]: RKSV-QR zunächst weichgezeichnet, ein Tipp macht ihn lesbar
/// (wie [KeckReceiptWidget.qrCovered]).
class KeckReceiptLinesWidget extends StatefulWidget {
  final BelegLayout layout;
  final Color paperColor;
  final Color textColor;
  final bool qrCovered;
  final String qrCoveredText;
  final double fontSize;

  const KeckReceiptLinesWidget({
    required this.layout,
    this.paperColor = Colors.white,
    this.textColor = Colors.black,
    this.qrCovered = false,
    this.qrCoveredText = 'Antippen zum Anzeigen',
    this.fontSize = 12,
    super.key,
  });

  @override
  State<KeckReceiptLinesWidget> createState() => _KeckReceiptLinesWidgetState();
}

class _KeckReceiptLinesWidgetState extends State<KeckReceiptLinesWidget> {
  bool _qrRevealed = false;

  TextStyle get _mono => TextStyle(fontFamily: 'monospace', fontFamilyFallback: const ['Courier', 'Menlo'], fontSize: widget.fontSize, color: widget.textColor, height: 1.35);

  TextAlign _ta(BelegAlign a) => switch (a) { BelegAlign.center => TextAlign.center, BelegAlign.right => TextAlign.right, BelegAlign.left => TextAlign.left };

  Widget _qr(String data) {
    final qr = QrImageView(
      data: data,
      size: 200,
      eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: widget.textColor),
      dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: widget.textColor),
      backgroundColor: Colors.transparent,
    );
    if (!widget.qrCovered) return Center(child: qr);
    return Center(
      child: Semantics(
        button: true,
        label: _qrRevealed ? 'QR-Code verdecken' : 'QR-Code anzeigen',
        child: GestureDetector(
          key: const Key('keck-receipt-lines-qr-toggle'),
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _qrRevealed = !_qrRevealed),
          child: Stack(alignment: Alignment.center, children: [
            if (_qrRevealed) qr else ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6), child: qr),
            if (!_qrRevealed) Text(widget.qrCoveredText, style: TextStyle(color: widget.textColor, fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }

  Widget _zeile(BelegZeile z) {
    switch (z) {
      case BelegText():
        return Text(z.text, textAlign: _ta(z.align), style: _mono.copyWith(fontWeight: z.bold ? FontWeight.bold : FontWeight.normal));
      case BelegBanner():
        return Container(
          key: Key('keck-receipt-banner-${z.warnung ? 'warnung' : 'belegart'}'),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
          decoration: BoxDecoration(
            border: Border.all(color: widget.textColor, width: 1.5),
            color: z.warnung ? widget.textColor : null,
          ),
          child: Text(z.text, textAlign: TextAlign.center, style: _mono.copyWith(fontWeight: FontWeight.bold, letterSpacing: 0.8, color: z.warnung ? widget.paperColor : widget.textColor)),
        );
      case BelegSpalten():
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: z.columns
              .map((c) => Expanded(flex: c.width, child: Text(c.text, textAlign: _ta(c.align), style: _mono, softWrap: true)))
              .toList(),
        );
      case BelegLinie():
        return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Divider(color: widget.textColor, height: 1, thickness: 0.6));
      case BelegLeerraum():
        return SizedBox(height: widget.fontSize * 1.35 * z.lines);
      case BelegQr():
        return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: _qr(z.data));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.paperColor,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: widget.layout.lines.map(_zeile).toList(),
      ),
    );
  }
}
