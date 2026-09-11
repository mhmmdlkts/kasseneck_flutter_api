import 'package:qr/qr.dart';

/// Wie gross die Module des Beleg-QR werden duerfen — ein **Deckel**, keine
/// Vorgabe: gedruckt wird immer die groesste Groesse, die noch aufs Papier
/// passt, hoechstens aber diese hier.
///
/// [auto] und [mittel] decken beide bei 6 — das ist kein Versehen. 6 ist der
/// Wert, den der native Weg seit jeher fest gedruckt hat; ohne diesen Deckel
/// bekaeme jedes 80-mm-Geraet ab sofort ungefragt einen groesseren QR als
/// gestern. [auto] heisst also "rechne, aber aendere den Bestand nicht", und
/// [gross] ist der einzige Weg darueber hinaus — den waehlt ein Mensch.
enum QrModulGroesse {
  /// Gerechnet, gedeckelt auf den Bestandswert 6. Vorgabe ueberall.
  auto(6),

  /// Kleiner Deckel fuer Geraete, die viel Nutzlast auf schmales Papier
  /// bringen muessen.
  klein(4),

  /// Wie [auto], nur ausdruecklich gewaehlt.
  mittel(6),

  /// Bis 8 Punkte je Modul — auf 80 mm sichtbar groesser und aus der Ferne
  /// leichter zu scannen.
  gross(8);

  const QrModulGroesse(this.deckelPunkte);

  /// Groesste Modulgroesse in Druckpunkten, die dieser Deckel zulaesst.
  final int deckelPunkte;
}

/// Ergebnis der Modulgroessen-Rechnung.
///
/// Traegt bewusst mehr als die Zahl: ob ueberhaupt etwas passt ([passt]), ob
/// nur unter der Mindestgroesse ([unterMindestmass]) und wie breit das Symbol
/// wird ([breitePunkte]). Ein blosser `int` haette die Ausnahme verschwiegen.
class QrGroesse {
  const QrGroesse._(this.punkte, this.module, this.breitePunkte, this.unterMindestmass);

  /// Modulgroesse in Druckpunkten, `null` wenn das Symbol auch mit der
  /// Ausnahmegroesse nicht aufs Papier passt.
  final int? punkte;

  /// Modulanzahl des Symbols (ohne Ruhezone).
  final int module;

  /// Gesamtbreite inklusive Ruhezone in Druckpunkten; 0, wenn nichts passt.
  final int breitePunkte;

  /// Gedruckt wird unter [QrMass.mindestPunkte]. Erlaubt, aber eine Ausnahme,
  /// von der der Aufrufer erfahren muss — billige Thermodrucker und
  /// Handykameras tun sich damit schwer, besonders auf gewelltem Papier.
  final bool unterMindestmass;

  bool get passt => punkte != null;

  @override
  String toString() => passt
      ? 'QrGroesse($punkte Punkte, $module Module, $breitePunkte Punkte breit'
          '${unterMindestmass ? ', unter Mindestmass' : ''})'
      : 'QrGroesse(passt nicht, $module Module)';
}

/// Die Rechenregel fuer die Modulgroesse des Beleg-QR — rein, ohne Drucker.
///
/// Vorgeschichte: der native Weg druckte jedes Modul fest mit sechs Punkten.
/// Ein Beleg-QR mit realer RKSV-Nutzlast hat 57 Module, mit Ruhezone also
/// (57 + 8) * 6 = 390 Druckpunkte. Ein 58-mm-Drucker hat 384. Zu breit heisst
/// bei den meisten Geraeten nicht "abgeschnitten", sondern **gar kein QR** —
/// und das ist auf einem Pflichtbeleg der schlechteste aller Ausgaenge.
abstract final class QrMass {
  /// Ruhezone je Seite, in Modulen (QR-Norm).
  static const int ruhezoneModule = 4;

  /// Untergrenze: 4 Punkte sind bei 203 dpi rund 0,5 mm je Modul.
  static const int mindestPunkte = 4;

  /// Ausnahme, wenn [mindestPunkte] nicht passt — gemeldet, nicht still.
  static const int ausnahmePunkte = 3;

  /// Obergrenze des Druckbefehls in diesem Stack (`QRSize.size1..size8`).
  static const int hoechstPunkte = 8;

  /// Modulanzahl, die [nutzlast] bei Fehlerkorrektur **M** braucht.
  ///
  /// Warum M, obwohl der native Befehl mit L druckt: M braucht bei gleicher
  /// Nutzlast gleich viele oder mehr Module als L. Wer mit M rechnet und mit L
  /// druckt, druckt nie breiter als gerechnet — die Rechnung ist konservativ,
  /// nie knapp. Umgekehrt waere sie eine Rechnung, die aufgeht, und ein Symbol,
  /// das ueber den Papierrand laeuft. Der Bildweg (`renderQrMatrix`) rastert
  /// ohnehin mit M; zwei Rechenwege fuer denselben Code darf es nicht geben.
  static int modulAnzahl(String nutzlast) => QrCode.fromData(
        data: nutzlast,
        errorCorrectLevel: QrErrorCorrectLevel.M,
      ).moduleCount;

  /// Groesste Modulgroesse, mit der [moduleAnzahl] Module **samt Ruhezone** in
  /// [papierbreitePunkte] passen, gedeckelt durch [groesse].
  ///
  /// Wirft bei sinnlosen Eingaben: eine Papierbreite von 0 oder ein Symbol
  /// ohne Module ist ein Programmierfehler, und ein still zurueckgegebenes
  /// "passt nicht" haette ihn als Druckerproblem getarnt.
  static QrGroesse berechne({
    required int papierbreitePunkte,
    required int moduleAnzahl,
    QrModulGroesse groesse = QrModulGroesse.auto,
  }) {
    if (papierbreitePunkte <= 0) {
      throw ArgumentError.value(papierbreitePunkte, 'papierbreitePunkte', 'muss positiv sein');
    }
    if (moduleAnzahl <= 0) {
      throw ArgumentError.value(moduleAnzahl, 'moduleAnzahl', 'muss positiv sein');
    }
    final int gesamtModule = moduleAnzahl + ruhezoneModule * 2;
    final int passend = papierbreitePunkte ~/ gesamtModule;
    if (passend < ausnahmePunkte) {
      return QrGroesse._(null, moduleAnzahl, 0, false);
    }
    final int deckel = groesse.deckelPunkte.clamp(ausnahmePunkte, hoechstPunkte);
    final int punkte = passend < mindestPunkte ? ausnahmePunkte : (passend < deckel ? passend : deckel);
    return QrGroesse._(punkte, moduleAnzahl, gesamtModule * punkte, punkte < mindestPunkte);
  }

  /// Wie [berechne], nur mit der Modulanzahl aus [nutzlast].
  ///
  /// Eine leere Nutzlast ergibt kein Symbol — sie "passt nicht", statt zu
  /// werfen: der Aufrufer behandelt den Fall ohnehin schon (leerer QR am
  /// Beleg ist ein Datenfehler, kein Papierfehler).
  static QrGroesse fuer({
    required String nutzlast,
    required int papierbreitePunkte,
    QrModulGroesse groesse = QrModulGroesse.auto,
  }) {
    if (nutzlast.isEmpty) return const QrGroesse._(null, 0, 0, false);
    return berechne(
      papierbreitePunkte: papierbreitePunkte,
      moduleAnzahl: modulAnzahl(nutzlast),
      groesse: groesse,
    );
  }
}
