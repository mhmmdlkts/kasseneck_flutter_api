/// Kassen-Einstellungen — Zwilling von `kasse/settings.ts` im JS-Paket und von
/// `functions/kasse-settings-core.js` im Backend (dort mit Validator).
///
/// Betriebsweit (`register_settings.kasse` am Konto) und je Gerät
/// (`register_devices/{id}.kasse`). Die Standardwerte stehen an allen drei
/// Stellen; die Golden-Datei `fixtures/kasse-settings-standard.json` des
/// JS-Pakets hält sie deckungsgleich. Weichen sie ab, steht am Tresen ein
/// Schalter anders als im Panel.
///
/// **Beim Lesen tolerant, beim Raten streng.** Ein unbekannter Wert (neue
/// Version, Tippfehler) fällt auf den Standard zurück, statt die Kasse mit
/// etwas laufen zu lassen, das sie nicht kennt.
library;

// ------------------------------------------------------------------ Enums

enum KasseStil { klar, warm, nacht, kontrast }

enum KasseSchrift {
  s('S'),
  m('M'),
  l('L'),
  xl('XL');

  const KasseSchrift(this.wert);
  final String wert;
}

enum KasseEinstellSchrift {
  s('S'),
  m('M'),
  l('L');

  const KasseEinstellSchrift(this.wert);
  final String wert;
}

enum KasseGroesse {
  s('S'),
  m('M'),
  l('L');

  const KasseGroesse(this.wert);
  final String wert;
}

enum KasseWasserzeichen { aus, anmeldung, ueberall }

enum KasseKachelstil { streifen, voll }

enum KasseMenge { aus, x, kg }

enum KasseRabatt { aus, an }

/// Karte gibt es erst mit eingerichtetem Anbieter; `extern` = eigenes Terminal
/// ohne Anbindung.
enum KasseKartenanbieter { keiner, extern, hobex, mypos, stripe }

enum KasseTgModus { betrag, gesamt, beides }

enum KasseKassierenModus { seite, panel }

enum KasseBelegAusgabe { qr, druck, mail, sms, fragen }

enum KasseLayout { rechts, links, vollbild }

enum KasseKatpos { oben, links }

enum KasseHoehe {
  s('S'),
  m('M'),
  l('L');

  const KasseHoehe(this.wert);
  final String wert;
}

/// `sdp` = Netzwerk über Epson Server Direct Print (der Drucker holt die Jobs
/// vom Backend), `netz` = direkt per IP (ePOS), `bt` = Bluetooth, `usb` = Kabel.
enum KasseDruckerArt { sdp, netz, bt, usb }

enum KassePapier { mm58, mm80 }

enum KasseZeichensatz {
  cp1252('CP1252'),
  cp437('CP437');

  const KasseZeichensatz(this.wert);
  final String wert;
}

enum KasseSchnitt { partial, full, none }

enum KasseLadeAuto { bar, immer, nie }

/// Aktionen der Kasse, die eine Taste bekommen können.
const List<String> kasseTastenAktionen = [
  'kassieren', 'abschliessen', 'abbrechen', 'frei', 'bar', 'karte', 'passend', 'belege', 'letzteZurueck',
];

/// Tastenbelegung: Aktion → Tasten (`Mod+F`, `Enter`, `Escape`, `F5` …;
/// `Mod` = ⌘ auf dem Mac, Strg sonst).
const Map<String, List<String>> kasseTastenStandard = {
  'kassieren': ['Enter'],
  'abschliessen': ['Enter'],
  'abbrechen': ['Escape'],
  'frei': ['Mod+F'],
  'bar': ['Mod+B'],
  'karte': ['Mod+K'],
  'passend': ['Mod+P'],
  'belege': ['Mod+E'],
  'letzteZurueck': ['Mod+Backspace'],
};

/// Steuersätze in der Reihenfolge, in der die Kasse sie zeigt.
const List<double> kasseSaetzeReihenfolge = [20, 19, 13, 10, 4.9, 0];

const Map<String, bool> _saetzeStandard = {'20': true, '19': false, '13': true, '10': true, '4.9': true, '0': true};
const Map<String, bool> _tgStufenStandard = {'5': true, '10': true, '15': false, '20': false};

// ------------------------------------------------------------- Betriebsteil

/// Was für den ganzen Betrieb gilt (im Panel eingestellt).
class KasseSettingsBetrieb {
  const KasseSettingsBetrieb({
    this.logoText = 'K',
    this.logoAn = true,
    this.logoGroesse = KasseGroesse.m,
    this.wasserzeichen = KasseWasserzeichen.anmeldung,
    this.farbe = '#1B46F5',
    this.stil = KasseStil.klar,
    this.schrift = KasseSchrift.m,
    this.schriftEinst = KasseEinstellSchrift.s,
    this.kachelstil = KasseKachelstil.streifen,
    this.uhr = true,
    this.sperrbild = true,
    this.foto = true,
    this.autoAbMin = 0,
    this.abNachVerkauf = false,
    this.schnellLogin = true,
    this.preisAnzeigen = true,
    this.ustAnzeigen = false,
    this.emoji = true,
    this.katFarben = true,
    this.freiErlaubt = true,
    this.saetze = _saetzeStandard,
    this.menge = KasseMenge.x,
    this.notiz = false,
    this.suche = false,
    this.rabatt = KasseRabatt.aus,
    this.zahlBar = true,
    this.zahlKarte = false,
    this.kartenanbieter = KasseKartenanbieter.keiner,
    this.trinkgeld = false,
    this.tgModus = KasseTgModus.beides,
    this.tgStufen = _tgStufenStandard,
    this.tgChips = const [5, 10],
    this.tgSplit = true,
    this.rueckgeld = true,
    this.schnellbar = false,
    this.kassierenModus = KasseKassierenModus.seite,
    this.belegAusgabe = KasseBelegAusgabe.qr,
    this.fertigSekunden = 0,
  });

  final String logoText;
  final bool logoAn;
  final KasseGroesse logoGroesse;
  final KasseWasserzeichen wasserzeichen;
  final String farbe;
  final KasseStil stil;
  final KasseSchrift schrift;

  /// Schriftgröße im Einstellungsbereich (dort darf es kleiner sein).
  final KasseEinstellSchrift schriftEinst;
  final KasseKachelstil kachelstil;
  final bool uhr;
  final bool sperrbild;
  final bool foto;

  /// Nach so vielen Minuten ohne Bedienung sperren; 0 = nie.
  final int autoAbMin;
  final bool abNachVerkauf;

  /// Schnelles Entsperren mit gemerkter PIN; aus = jeder Login wartet auf den Server.
  final bool schnellLogin;
  final bool preisAnzeigen;
  final bool ustAnzeigen;
  final bool emoji;
  final bool katFarben;
  final bool freiErlaubt;

  /// Eingeschaltete Steuersätze (Schlüssel = Satz als Text).
  final Map<String, bool> saetze;
  final KasseMenge menge;
  final bool notiz;
  final bool suche;
  final KasseRabatt rabatt;
  final bool zahlBar;
  final bool zahlKarte;
  final KasseKartenanbieter kartenanbieter;
  final bool trinkgeld;
  final KasseTgModus tgModus;
  final Map<String, bool> tgStufen;

  /// Trinkgeld-Chips in Prozent (eine Nachkommastelle, höchstens 5).
  final List<double> tgChips;
  final bool tgSplit;
  final bool rueckgeld;
  final bool schnellbar;
  final KasseKassierenModus kassierenModus;
  final KasseBelegAusgabe belegAusgabe;

  /// Wie lange der Fertig-Bildschirm stehen bleibt; 0 = bis zum Tippen.
  final int fertigSekunden;

  /// Kartenzahlung ist möglich: eingeschaltet **und** ein Anbieter eingerichtet.
  /// Der Schalter allein nützt nichts — ohne Anbieter nimmt niemand die Zahlung an.
  bool get kartenAktiv => zahlKarte && kartenanbieter != KasseKartenanbieter.keiner;

  /// Die eingeschalteten Steuersätze in der Reihenfolge des Bildschirms.
  List<double> get aktiveSaetze =>
      kasseSaetzeReihenfolge.where((s) => saetze[_satzSchluessel(s)] == true).toList();

  KasseSettingsBetrieb _mit(Map<String, dynamic> g) {
    return KasseSettingsBetrieb(
      logoText: _text(g['logoText'], logoText),
      logoAn: _bool(g['logoAn'], logoAn),
      logoGroesse: _enumWert(g['logoGroesse'], KasseGroesse.values, (e) => e.wert, logoGroesse),
      wasserzeichen: _enumName(g['wasserzeichen'], KasseWasserzeichen.values, wasserzeichen),
      farbe: _text(g['farbe'], farbe),
      stil: _enumName(g['stil'], KasseStil.values, stil),
      schrift: _enumWert(g['schrift'], KasseSchrift.values, (e) => e.wert, schrift),
      schriftEinst: _enumWert(g['schriftEinst'], KasseEinstellSchrift.values, (e) => e.wert, schriftEinst),
      kachelstil: _enumName(g['kachelstil'], KasseKachelstil.values, kachelstil),
      uhr: _bool(g['uhr'], uhr),
      sperrbild: _bool(g['sperrbild'], sperrbild),
      foto: _bool(g['foto'], foto),
      autoAbMin: _ausListe(g['autoAbMin'], const [0, 1, 5, 15, 30], autoAbMin),
      abNachVerkauf: _bool(g['abNachVerkauf'], abNachVerkauf),
      schnellLogin: _bool(g['schnellLogin'], schnellLogin),
      preisAnzeigen: _bool(g['preisAnzeigen'], preisAnzeigen),
      ustAnzeigen: _bool(g['ustAnzeigen'], ustAnzeigen),
      emoji: _bool(g['emoji'], emoji),
      katFarben: _bool(g['katFarben'], katFarben),
      freiErlaubt: _bool(g['freiErlaubt'], freiErlaubt),
      saetze: _karte(g['saetze'], saetze),
      menge: _enumName(g['menge'], KasseMenge.values, menge),
      notiz: _bool(g['notiz'], notiz),
      suche: _bool(g['suche'], suche),
      rabatt: _enumName(g['rabatt'], KasseRabatt.values, rabatt),
      zahlBar: _bool(g['zahlBar'], zahlBar),
      zahlKarte: _bool(g['zahlKarte'], zahlKarte),
      kartenanbieter: _enumName(g['kartenanbieter'], KasseKartenanbieter.values, kartenanbieter),
      trinkgeld: _bool(g['trinkgeld'], trinkgeld),
      tgModus: _enumName(g['tgModus'], KasseTgModus.values, tgModus),
      tgStufen: _karte(g['tgStufen'], tgStufen),
      tgChips: _zahlenliste(g['tgChips'], tgChips),
      tgSplit: _bool(g['tgSplit'], tgSplit),
      rueckgeld: _bool(g['rueckgeld'], rueckgeld),
      schnellbar: _bool(g['schnellbar'], schnellbar),
      kassierenModus: _enumName(g['kassierenModus'], KasseKassierenModus.values, kassierenModus),
      belegAusgabe: _enumName(g['belegAusgabe'], KasseBelegAusgabe.values, belegAusgabe),
      fertigSekunden: _ausListe(g['fertigSekunden'], const [0, 3, 5, 10, 15, 30, 60], fertigSekunden),
    );
  }

  Map<String, dynamic> toJson() => {
        'logoText': logoText,
        'logoAn': logoAn,
        'logoGroesse': logoGroesse.wert,
        'wasserzeichen': wasserzeichen.name,
        'farbe': farbe,
        'stil': stil.name,
        'schrift': schrift.wert,
        'schriftEinst': schriftEinst.wert,
        'kachelstil': kachelstil.name,
        'uhr': uhr,
        'sperrbild': sperrbild,
        'foto': foto,
        'autoAbMin': autoAbMin,
        'abNachVerkauf': abNachVerkauf,
        'schnellLogin': schnellLogin,
        'preisAnzeigen': preisAnzeigen,
        'ustAnzeigen': ustAnzeigen,
        'emoji': emoji,
        'katFarben': katFarben,
        'freiErlaubt': freiErlaubt,
        'saetze': {...saetze},
        'menge': menge.name,
        'notiz': notiz,
        'suche': suche,
        'rabatt': rabatt.name,
        'zahlBar': zahlBar,
        'zahlKarte': zahlKarte,
        'kartenanbieter': kartenanbieter.name,
        'trinkgeld': trinkgeld,
        'tgModus': tgModus.name,
        'tgStufen': {...tgStufen},
        'tgChips': [...tgChips],
        'tgSplit': tgSplit,
        'rueckgeld': rueckgeld,
        'schnellbar': schnellbar,
        'kassierenModus': kassierenModus.name,
        'belegAusgabe': belegAusgabe.name,
        'fertigSekunden': fertigSekunden,
      };
}

// --------------------------------------------------------------- Gerteteil

/// Was nur für dieses Gerät gilt (in der Kasse selbst eingestellt).
class KasseSettingsGeraet {
  const KasseSettingsGeraet({
    this.layout = KasseLayout.rechts,
    this.katpos = KasseKatpos.oben,
    this.spaltenExtra = 0,
    this.hoehe = KasseHoehe.m,
    this.touch = false,
    this.tasten = kasseTastenStandard,
    this.druckerAn = false,
    this.druckerArt = KasseDruckerArt.sdp,
    this.druckerIp = '',
    this.druckerPort = 9100,
    this.druckerBt = '',
    this.druckerId = '',
    this.druckerDevid = 'local_printer',
    this.papier = KassePapier.mm80,
    this.zeichensatz = KasseZeichensatz.cp1252,
    this.schnitt = KasseSchnitt.partial,
    this.ladeAn = false,
    this.ladeAuto = KasseLadeAuto.bar,
    this.terminalIp = '',
    this.terminalPort = 20008,
  });

  final KasseLayout layout;
  final KasseKatpos katpos;

  /// Zusätzliche Kachelspalten gegenüber der berechneten Breite (−2 … 4).
  final int spaltenExtra;
  final KasseHoehe hoehe;
  final bool touch;

  /// Tastenbelegung dieses Geräts.
  final Map<String, List<String>> tasten;
  final bool druckerAn;
  final KasseDruckerArt druckerArt;
  final String druckerIp;
  final int druckerPort;
  final String druckerBt;

  /// Kennung des Netzwerk-Druckers (Server Direct Print); '' = keiner gewählt.
  final String druckerId;

  /// ePOS Device-ID bei [KasseDruckerArt.netz] (Epson direkt per IP).
  final String druckerDevid;
  final KassePapier papier;
  final KasseZeichensatz zeichensatz;
  final KasseSchnitt schnitt;
  final bool ladeAn;
  final KasseLadeAuto ladeAuto;
  final String terminalIp;
  final int terminalPort;

  KasseSettingsGeraet _mit(Map<String, dynamic> g) {
    return KasseSettingsGeraet(
      layout: _enumName(g['layout'], KasseLayout.values, layout),
      katpos: _enumName(g['katpos'], KasseKatpos.values, katpos),
      spaltenExtra: _ganz(g['spaltenExtra'], -2, 4, spaltenExtra),
      hoehe: _enumWert(g['hoehe'], KasseHoehe.values, (e) => e.wert, hoehe),
      touch: _bool(g['touch'], touch),
      tasten: _tastenkarte(g['tasten'], tasten),
      druckerAn: _bool(g['druckerAn'], druckerAn),
      druckerArt: _enumName(g['druckerArt'], KasseDruckerArt.values, druckerArt),
      druckerIp: _text(g['druckerIp'], druckerIp),
      druckerPort: _ganz(g['druckerPort'], 1, 65535, druckerPort),
      druckerBt: _text(g['druckerBt'], druckerBt),
      druckerId: _text(g['druckerId'], druckerId),
      druckerDevid: _text(g['druckerDevid'], druckerDevid),
      papier: _enumName(g['papier'], KassePapier.values, papier),
      zeichensatz: _enumWert(g['zeichensatz'], KasseZeichensatz.values, (e) => e.wert, zeichensatz),
      schnitt: _enumName(g['schnitt'], KasseSchnitt.values, schnitt),
      ladeAn: _bool(g['ladeAn'], ladeAn),
      ladeAuto: _enumName(g['ladeAuto'], KasseLadeAuto.values, ladeAuto),
      terminalIp: _text(g['terminalIp'], terminalIp),
      terminalPort: _ganz(g['terminalPort'], 1, 65535, terminalPort),
    );
  }

  Map<String, dynamic> toJson() => {
        'layout': layout.name,
        'katpos': katpos.name,
        'spaltenExtra': spaltenExtra,
        'hoehe': hoehe.wert,
        'touch': touch,
        'tasten': {for (final e in tasten.entries) e.key: [...e.value]},
        'druckerAn': druckerAn,
        'druckerArt': druckerArt.name,
        'druckerIp': druckerIp,
        'druckerPort': druckerPort,
        'druckerBt': druckerBt,
        'druckerId': druckerId,
        'druckerDevid': druckerDevid,
        'papier': papier.name,
        'zeichensatz': zeichensatz.wert,
        'schnitt': schnitt.name,
        'ladeAn': ladeAn,
        'ladeAuto': ladeAuto.name,
        'terminalIp': terminalIp,
        'terminalPort': terminalPort,
      };
}

// ------------------------------------------------------------------ Ganzes

class KasseSettings {
  const KasseSettings({required this.betrieb, required this.geraet});

  /// Die Standardwerte — deckungsgleich mit Backend und Browser-Kasse.
  const KasseSettings.standard()
      : betrieb = const KasseSettingsBetrieb(),
        geraet = const KasseSettingsGeraet();

  final KasseSettingsBetrieb betrieb;
  final KasseSettingsGeraet geraet;

  /// Standard + Gespeichertes. Was fehlt, bleibt beim Standard; was die Kasse
  /// nicht kennt, bleibt draußen (die Wahrheit über Gültigkeit hat der Server).
  factory KasseSettings.aus(Map<String, dynamic>? gespeichert) {
    final betriebRoh = gespeichert?['betrieb'];
    final geraetRoh = gespeichert?['geraet'];
    return KasseSettings(
      betrieb: const KasseSettingsBetrieb()._mit(betriebRoh is Map ? Map<String, dynamic>.from(betriebRoh) : const {}),
      geraet: const KasseSettingsGeraet()._mit(geraetRoh is Map ? Map<String, dynamic>.from(geraetRoh) : const {}),
    );
  }

  Map<String, dynamic> toJson() => {'betrieb': betrieb.toJson(), 'geraet': geraet.toJson()};
}

// ------------------------------------------------------------------ Helfer

/// Steuersatz als Schlüssel, wie ihn das Backend schreibt: ganze Sätze ohne
/// Nachkomma („20"), gebrochene mit („4.9").
String _satzSchluessel(double satz) =>
    satz == satz.roundToDouble() ? satz.toInt().toString() : satz.toString();

bool _bool(Object? wert, bool standard) => wert is bool ? wert : standard;

String _text(Object? wert, String standard) => wert is String ? wert : standard;

int _ganz(Object? wert, int min, int max, int standard) =>
    wert is int && wert >= min && wert <= max ? wert : standard;

int _ausListe(Object? wert, List<int> erlaubt, int standard) =>
    wert is int && erlaubt.contains(wert) ? wert : standard;

/// Enum über seinen Namen (`stil: 'nacht'`).
T _enumName<T extends Enum>(Object? wert, List<T> werte, T standard) {
  if (wert is! String) return standard;
  for (final e in werte) {
    if (e.name == wert) return e;
  }
  return standard;
}

/// Enum über eine eigene Schreibweise (`schrift: 'XL'`), weil Dart-Namen nicht
/// großgeschrieben sein dürfen.
T _enumWert<T extends Enum>(Object? wert, List<T> werte, String Function(T) schreibweise, T standard) {
  if (wert is! String) return standard;
  for (final e in werte) {
    if (schreibweise(e) == wert) return e;
  }
  return standard;
}

/// Landkarte je Schlüssel mischen: neue Sätze/Stufen kommen beim Altbestand an,
/// unbekannte Schlüssel bleiben draußen.
Map<String, bool> _karte(Object? wert, Map<String, bool> standard) {
  if (wert is! Map) return standard;
  final out = <String, bool>{...standard};
  for (final e in wert.entries) {
    final schluessel = e.key.toString();
    if (!out.containsKey(schluessel)) continue;
    if (e.value is bool) out[schluessel] = e.value as bool;
  }
  return out;
}

/// Tastenbelegung je Aktion mischen; unbekannte Aktionen bleiben draußen.
Map<String, List<String>> _tastenkarte(Object? wert, Map<String, List<String>> standard) {
  final out = <String, List<String>>{for (final e in standard.entries) e.key: [...e.value]};
  if (wert is! Map) return out;
  for (final e in wert.entries) {
    final aktion = e.key.toString();
    if (!out.containsKey(aktion)) continue;
    final tasten = e.value;
    if (tasten is List) out[aktion] = tasten.whereType<String>().toList();
  }
  return out;
}

/// Zahlenliste (Trinkgeld-Chips): höchstens fünf, eindeutig, in der Reihenfolge
/// des Chefs.
List<double> _zahlenliste(Object? wert, List<double> standard) {
  if (wert is! List) return standard;
  final out = <double>[];
  for (final e in wert) {
    final zahl = e is num ? e.toDouble() : null;
    if (zahl == null || out.contains(zahl)) continue;
    out.add(zahl);
    if (out.length == 5) break;
  }
  return out;
}
