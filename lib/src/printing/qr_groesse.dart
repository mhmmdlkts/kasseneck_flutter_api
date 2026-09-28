import 'package:qr/qr.dart';

/// Wie gross die Module des Beleg-QR werden duerfen — ein **Deckel**, keine
/// Vorgabe: gedruckt wird immer die groesste Groesse, die noch aufs Papier
/// passt, hoechstens aber diese hier.
///
/// [auto] und [medium] decken beide bei 6 – das ist kein Versehen. 6 ist der
/// Wert, den der native Weg seit jeher fest gedruckt hat; ohne diesen Deckel
/// bekaeme jedes 80-mm-Geraet ab sofort ungefragt einen groesseren QR als
/// gestern. [auto] heisst also "rechne, aber aendere den Bestand nicht", und
/// [large] ist der einzige Weg darueber hinaus – den waehlt ein Mensch.
enum QrModuleSize {
  /// Gerechnet, gedeckelt auf den Bestandswert 6. Vorgabe ueberall.
  auto(6),

  /// Kleiner Deckel fuer Geraete, die viel Nutzlast auf schmales Papier
  /// bringen muessen.
  small(4),

  /// Wie [auto], nur ausdruecklich gewaehlt.
  medium(6),

  /// Bis 8 Punkte je Modul — auf 80 mm sichtbar groesser und aus der Ferne
  /// leichter zu scannen.
  large(8);

  const QrModuleSize(this.capDots);

  /// Groesste Modulgroesse in Druckpunkten, die dieser Deckel zulaesst.
  final int capDots;
}

/// Ergebnis der Modulgroessen-Rechnung.
///
/// Traegt bewusst mehr als die Zahl: ob ueberhaupt etwas passt ([fits]), ob
/// nur unter der Mindestgroesse ([belowMinimum]) und wie breit das Symbol
/// wird ([widthDots]). Ein blosser `int` haette die Ausnahme verschwiegen.
class QrSizing {
  const QrSizing._(this.moduleDots, this.modules, this.widthDots, this.belowMinimum);

  /// Modulgroesse in Druckpunkten, `null` wenn das Symbol auch mit der
  /// Ausnahmegroesse nicht aufs Papier passt.
  final int? moduleDots;

  /// Modulanzahl des Symbols (ohne Ruhezone).
  final int modules;

  /// Gesamtbreite inklusive Ruhezone in Druckpunkten; 0, wenn nichts passt.
  final int widthDots;

  /// Gedruckt wird unter [QrMetrics.minModuleDots]. Erlaubt, aber eine Ausnahme,
  /// von der der Aufrufer erfahren muss — billige Thermodrucker und
  /// Handykameras tun sich damit schwer, besonders auf gewelltem Papier.
  final bool belowMinimum;

  bool get fits => moduleDots != null;

  @override
  String toString() => fits
      ? 'QrGroesse($moduleDots Punkte, $modules Module, $widthDots Punkte breit'
          '${belowMinimum ? ', unter Mindestmass' : ''})'
      : 'QrGroesse(passt nicht, $modules Module)';
}

/// Die Rechenregel fuer die Modulgroesse des Beleg-QR — rein, ohne Drucker.
///
/// Vorgeschichte: der native Weg druckte jedes Modul fest mit sechs Punkten.
/// Ein Beleg-QR mit realer RKSV-Nutzlast hat 57 Module, mit Ruhezone also
/// (57 + 8) * 6 = 390 Druckpunkte. Ein 58-mm-Drucker hat 384. Zu breit heisst
/// bei den meisten Geraeten nicht "abgeschnitten", sondern **gar kein QR** —
/// und das ist auf einem Pflichtbeleg der schlechteste aller Ausgaenge.
abstract final class QrMetrics {
  /// Ruhezone je Seite, in Modulen (QR-Norm).
  static const int quietZoneModules = 4;

  /// Untergrenze: 4 Punkte sind bei 203 dpi rund 0,5 mm je Modul.
  static const int minModuleDots = 4;

  /// Ausnahme, wenn [minModuleDots] nicht passt – gemeldet, nicht still.
  static const int exceptionModuleDots = 3;

  /// Obergrenze des Druckbefehls in diesem Stack (`QRSize.size1..size8`).
  static const int maxModuleDots = 8;

  /// Modulanzahl, die [payload] bei Fehlerkorrektur **M** braucht.
  ///
  /// M, weil alle Wege mit M drucken: der native Befehl (`PrintPaper.addQrCode`),
  /// der Bildweg (`renderQrMatrix`), ePOS und das Blatt. Frueher druckte der
  /// native Befehl mit L -- dann stand der QR bei mancher Nutzlast kleiner am
  /// Bon, als das Blatt ihm Platz gab. Zwei Rechenwege fuer denselben Code
  /// darf es nicht geben.
  static int moduleCount(String payload) => QrCode.fromData(
        data: payload,
        errorCorrectLevel: QrErrorCorrectLevel.M,
      ).moduleCount;

  /// Groesste Modulgroesse, mit der [moduleCount] Module **samt Ruhezone** in
  /// [paperWidthDots] passen, gedeckelt durch [moduleSize].
  ///
  /// Wirft bei sinnlosen Eingaben: eine Papierbreite von 0 oder ein Symbol
  /// ohne Module ist ein Programmierfehler, und ein still zurueckgegebenes
  /// "passt nicht" haette ihn als Druckerproblem getarnt.
  static QrSizing compute({
    required int paperWidthDots,
    required int moduleCount,
    QrModuleSize moduleSize = QrModuleSize.auto,
  }) {
    if (paperWidthDots <= 0) {
      throw ArgumentError.value(paperWidthDots, 'papierbreitePunkte', 'muss positiv sein');
    }
    if (moduleCount <= 0) {
      throw ArgumentError.value(moduleCount, 'moduleAnzahl', 'muss positiv sein');
    }
    final int gesamtModule = moduleCount + quietZoneModules * 2;
    final int passend = paperWidthDots ~/ gesamtModule;
    if (passend < exceptionModuleDots) {
      return QrSizing._(null, moduleCount, 0, false);
    }
    final int deckel = moduleSize.capDots.clamp(exceptionModuleDots, maxModuleDots);
    final int punkte = passend < minModuleDots ? exceptionModuleDots : (passend < deckel ? passend : deckel);
    return QrSizing._(punkte, moduleCount, gesamtModule * punkte, punkte < minModuleDots);
  }

  /// Wie [compute], nur mit der Modulanzahl aus [payload].
  ///
  /// Eine leere Nutzlast ergibt kein Symbol — sie "passt nicht", statt zu
  /// werfen: der Aufrufer behandelt den Fall ohnehin schon (leerer QR am
  /// Beleg ist ein Datenfehler, kein Papierfehler).
  static QrSizing forPayload({
    required String payload,
    required int paperWidthDots,
    QrModuleSize moduleSize = QrModuleSize.auto,
  }) {
    if (payload.isEmpty) return const QrSizing._(null, 0, 0, false);
    return compute(
      paperWidthDots: paperWidthDots,
      moduleCount: moduleCount(payload),
      moduleSize: moduleSize,
    );
  }
}
