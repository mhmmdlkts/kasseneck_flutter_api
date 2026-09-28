/// Kassen-Einstellungen in der Form des Drahts `/api/v3` (Nachtrag Stufe 4,
/// §11.7.2): Schluessel und Werte englisch. Zwilling von `pos/settings.ts` im
/// JS-Paket und von `functions-kasse/kasse-settings-core.js` im Backend (dort
/// mit Validator und in der inneren, deutschen Form).
///
/// Betriebsweit (`business`, am Konto) und je Gerät (`device`). Die
/// Standardwerte stehen an allen drei Stellen; die Golden-Datei
/// `fixtures/pos-settings-defaults.json` des JS-Pakets hält sie deckungsgleich.
/// Weichen sie ab, steht am Tresen ein Schalter anders als im Panel.
///
/// **Unbekannte Werte des Servers bleiben erhalten.** Kommt ein Wert, den
/// dieses Paket nicht kennt (`theme: 'sepia'`, ein neuer Wert einer neueren
/// Backend-Version), arbeitet die Kasse mit dem Standard, hält den Wert aber
/// wörtlich fest: [KasseSettingsBetrieb.fremdeWerte] bzw.
/// [KasseSettingsGeraet.fremdeWerte], `toJson` gibt ihn unverändert aus, und
/// [unknownPosSettingValues] nennt die Felder. Geschrieben wird nur, was sich
/// geändert hat ([posSettingsChanges]); so bleibt der Wert am Server stehen.
///
/// **Werte der inneren Form 0.x** (`stil: 'nacht'`, `layout: 'rechts'`) fallen
/// auf den Standard zurück, nie in das englische Modell. Ein zwischengespeicherter
/// Stand der Version 9.x (`{betrieb, geraet}`, deutsche Schlüssel und Werte)
/// wird beim Lesen übersetzt ([KasseSettings.aus]): nach dem Update geht keine
/// Einstellung verloren.
library;

// ------------------------------------------------------------------ Enums

/// Gemeinsame Sicht auf die Aufzählungen der Einstellungen: [wert] ist der
/// Wert am Draht.
abstract interface class KasseWert {
  Object get wert;
}

enum KasseStil implements KasseWert {
  clear,
  warm,
  night,
  contrast;

  @override
  String get wert => name;
}

enum KasseSchrift implements KasseWert {
  s('S'),
  m('M'),
  l('L'),
  xl('XL');

  const KasseSchrift(this.wert);
  @override
  final String wert;
}

enum KasseEinstellSchrift implements KasseWert {
  s('S'),
  m('M'),
  l('L');

  const KasseEinstellSchrift(this.wert);
  @override
  final String wert;
}

/// Größe des Kürzel-Logos in der Kopfzeile der Kasse (`logoSize`).
enum KasseGroesse implements KasseWert {
  s('S'),
  m('M'),
  l('L');

  const KasseGroesse(this.wert);
  @override
  final String wert;
}

/// Größe des Bild-Logos am Beleg (`logoScale`) bzw. des Wasserzeichens
/// (`watermarkScale`).
enum KasseSkala implements KasseWert {
  s('S'),
  m('M'),
  l('L'),
  xl('XL');

  const KasseSkala(this.wert);
  @override
  final String wert;
}

enum KasseWasserzeichen implements KasseWert {
  off,
  login,
  everywhere;

  @override
  String get wert => name;
}

/// Seite des Wasserzeichens; alt, abgelöst von `watermarkX`, bleibt fürs
/// Mischen alter Stände.
enum KasseWasserzeichenSeite implements KasseWert {
  left,
  center,
  right;

  @override
  String get wert => name;
}

enum KasseKachelstil implements KasseWert {
  stripe,
  full;

  @override
  String get wert => name;
}

enum KasseMenge implements KasseWert {
  off,
  x,
  kg;

  @override
  String get wert => name;
}

enum KasseRabatt implements KasseWert {
  off,
  on;

  @override
  String get wert => name;
}

/// Karte gibt es erst mit eingerichtetem Anbieter.
///
/// - `external`: ein Terminal, das die Kasse nicht anspricht. Der Kassier
///   tippt den Betrag dort selbst ein und bestätigt in der Kasse; das ist ein
///   gültiger Weg, kein Notbehelf.
/// - `gptom`: GP Tom, angesprochen über die Terminal-App auf demselben Gerät.
/// - `hobex`: Hobex HPS über die Terminal-Adresse im Kassennetz
///   ([KasseSettingsGeraet.terminalIp] / `terminalPort`).
enum KasseKartenanbieter implements KasseWert {
  none,
  external,
  gptom,
  hobex,
  mypos,
  stripe;

  @override
  String get wert => name;
}

enum KasseTgModus implements KasseWert {
  amount,
  total,
  both;

  @override
  String get wert => name;
}

enum KasseKassierenModus implements KasseWert {
  page,
  panel;

  @override
  String get wert => name;
}

enum KasseBelegAusgabe implements KasseWert {
  qr,
  print,
  email,
  sms,
  ask;

  @override
  String get wert => name;
}

enum KasseLayout implements KasseWert {
  right,
  left,
  fullscreen;

  @override
  String get wert => name;
}

enum KasseKatpos implements KasseWert {
  top,
  left;

  @override
  String get wert => name;
}

enum KasseHoehe implements KasseWert {
  s('S'),
  m('M'),
  l('L');

  const KasseHoehe(this.wert);
  @override
  final String wert;
}

/// `sdp` = Netzwerk über Epson Server Direct Print (der Drucker holt die Jobs
/// vom Backend), `network` = direkt per IP (ePOS), `bluetooth`, `usb` = Kabel,
/// `connect` = Kasseneck Connect (lokaler Agent auf dem Kassen-Rechner).
enum KasseDruckerArt implements KasseWert {
  sdp,
  network,
  bluetooth,
  usb,
  connect;

  @override
  String get wert => name;
}

/// Terminal-Ansprache: direkt per IP oder über Kasseneck Connect.
enum KasseTerminalVia implements KasseWert {
  direct,
  connect;

  @override
  String get wert => name;
}

/// Art des Kartenterminals an dieser Kasse: keines oder Hobex HPS.
enum KasseTerminalArt implements KasseWert {
  none,
  hps;

  @override
  String get wert => name;
}

enum KassePapier implements KasseWert {
  mm58,
  mm80;

  @override
  String get wert => name;
}

enum KasseZeichensatz implements KasseWert {
  cp1252('CP1252'),
  cp437('CP437');

  const KasseZeichensatz(this.wert);
  @override
  final String wert;
}

enum KasseSchnitt implements KasseWert {
  partial,
  full,
  none;

  @override
  String get wert => name;
}

/// Mit welchem Befehl der Signatur-QR auf den Bon kommt.
///
/// - [auto]: **unbestimmt**: an diesem Gerät hat noch niemand am Papier
///   entschieden. Die Vorgabe; jede Kasse bleibt dann bei ihrer bisherigen
///   Praxis (die App beim Rasterbild, die Browser-Kasse beim ESC/POS-Befehl).
///   Eine harte Vorgabe hätte den ganzen Altbestand still umgestellt: jedes
///   Gerät, das nie durch den Drucker-Wizard läuft, druckte plötzlich anders,
///   und über BLE kostet ein Rasterbild mehrere Sekunden je Bon.
/// - [raster]: der QR wird als Bild gerastert (`GS v 0`), geht durch jeden
///   Drucker, der Bilder kann.
/// - [escpos]: der native QR-Befehl (`GS ( k`), schärfer und schneller, aber
///   ältere Geräte drucken dann gar keinen QR oder Zeichensalat.
///
/// **Am Gerät und nicht am Betrieb:** welchen Befehl ein Thermodrucker
/// versteht, entscheidet das Modell an dieser einen Kasse. Und die Wahl ist
/// nicht kosmetisch: nach § 132a BAO ist der QR Teil des Belegs; im falschen
/// Modus kommt ein Bon ohne lesbare Signatur heraus, und das fällt am Tresen
/// niemandem auf.
enum KasseQrModus implements KasseWert {
  auto,
  raster,
  escpos;

  @override
  String get wert => name;
}

enum KasseLadeAuto implements KasseWert {
  cash,
  always,
  never;

  @override
  String get wert => name;
}

/// Automatisches Abmelden nach Minuten Ruhe; 0 = nie.
const List<int> kasseAutoAbmeldenMinuten = [0, 1, 5, 15, 30];

/// Wie lange die Fertig-Seite stehen bleibt, in Sekunden; 0 = bis zum Tippen.
const List<int> kasseFertigSekunden = [0, 3, 5, 10, 15, 30, 60];

/// Deckkraft des Wasserzeichens in Prozent, bewusst Stufen.
const List<int> kasseWasserzeichenStaerken = [3, 6, 10, 16];

/// Aktionen der Kasse, die eine Taste bekommen können (Schlüssel von
/// `device.shortcuts`), Zwilling von `POS_SHORTCUT_ACTIONS`.
const List<String> kasseTastenAktionen = [
  'checkout', 'complete', 'cancel', 'customAmount', 'cash', 'card', 'exactAmount', 'receipts', 'undoLast',
  'settings', 'logout', 'tip', 'fullscreen', 'clearTendered', 'clearCart', 'splitPayment',
];

/// Tastenbelegung: Aktion -> Tasten (`Mod+F`, `Enter`, `Escape`, `F5` ...;
/// `Mod` = Cmd auf dem Mac, Strg sonst). Zwilling von `POS_SHORTCUT_DEFAULTS`.
const Map<String, List<String>> kasseTastenStandard = {
  'checkout': ['Enter'],
  'complete': ['Enter'],
  'cancel': ['Escape'],
  // Mod+F gehört dem Vollbild; Betrag frei liegt auf D.
  'customAmount': ['Mod+D'],
  'cash': ['Mod+B'],
  'card': ['Mod+K'],
  'exactAmount': ['Mod+P'],
  // Nicht Mod+E: das fängt Chrome auf dem Mac selbst ab.
  'receipts': ['Mod+J'],
  'undoLast': ['Mod+Backspace'],
  'settings': ['Mod+S'],
  'logout': ['Mod+L'],
  // Nicht Mod+T: im Browser reserviert (neuer Tab).
  'tip': ['Mod+G'],
  'fullscreen': ['Mod+F'],
  // Bewusst dieselbe Taste: die beiden leben in verschiedenen Momenten.
  'clearTendered': ['Mod+C'],
  'clearCart': ['Mod+C'],
  // Bewusst ohne Vorgabe: der Chef vergibt sie, wenn er sie braucht.
  'splitPayment': [],
};

/// Aktionen, die sich eine Taste teilen dürfen (Backend `TASTEN_PAARE`),
/// Zwilling von `POS_SHORTCUT_SHARED_PAIRS`. Jede andere Doppelbelegung weist
/// der Server ab, und dieses Paket schon vor dem Senden.
const List<(String, String)> posShortcutSharedPairs = [
  ('checkout', 'complete'),
  ('clearTendered', 'clearCart'),
];

bool _darfTeilen(String a, String b) =>
    posShortcutSharedPairs.any((p) => (p.$1 == a && p.$2 == b) || (p.$1 == b && p.$2 == a));

/// Die erste Doppelbelegung einer Tastenkarte oder `null`. Geprüft wird die
/// ganze Karte, so wie der Server sie nach dem Speichern hält. Zwilling von
/// `posShortcutConflict`.
({String action, String key, String heldBy})? posShortcutConflict(Map<String, Object?> shortcuts) {
  final belegt = <String, String>{};
  for (final aktion in shortcuts.keys) {
    final tasten = shortcuts[aktion];
    if (tasten is! List) continue;
    for (final t in tasten) {
      if (t is! String) continue;
      final vorher = belegt[t];
      if (vorher != null && vorher != aktion && !_darfTeilen(vorher, aktion)) {
        return (action: aktion, key: t, heldBy: vorher);
      }
      belegt[t] = aktion;
    }
  }
  return null;
}

/// Steuersätze in der Reihenfolge, in der die Kasse sie zeigt.
const List<double> kasseSaetzeReihenfolge = [20, 19, 13, 10, 4.9, 0];

const Map<String, bool> _saetzeStandard = {'20': true, '19': false, '13': true, '10': true, '4.9': true, '0': true};
const Map<String, bool> _tgStufenStandard = {'5': true, '10': true, '15': false, '20': false};

// ------------------------------------------------------------- Betriebsteil

/// Was für den ganzen Betrieb gilt (im Panel eingestellt).
class KasseSettingsBetrieb {
  const KasseSettingsBetrieb({
    this.logoText = 'K',
    this.logoEnabled = true,
    this.logoSize = KasseGroesse.m,
    this.watermark = KasseWasserzeichen.login,
    // Die Farbe der Marke Kasseneck (Rolle `brand` des Design-Systems), wie
    // im Vertrag ab npm 0.14.0.
    this.color = '#136B6B',
    this.theme = KasseStil.clear,
    this.fontSize = KasseSchrift.m,
    this.settingsFontSize = KasseEinstellSchrift.s,
    this.tileStyle = KasseKachelstil.stripe,
    this.clock = true,
    this.lockScreen = true,
    this.staffPhotos = true,
    this.autoLogoutMinutes = 0,
    this.logoutAfterSale = false,
    this.fastLogin = true,
    this.showPrices = true,
    this.showVat = false,
    this.emoji = true,
    this.categoryColors = true,
    this.customAmountAllowed = true,
    this.vatRates = _saetzeStandard,
    this.quantity = KasseMenge.x,
    this.note = false,
    this.search = false,
    this.discount = KasseRabatt.off,
    this.payCash = true,
    this.payCard = false,
    this.paySplit = false,
    this.cardProvider = KasseKartenanbieter.none,
    this.tip = false,
    this.tipMode = KasseTgModus.both,
    this.tipSteps = _tgStufenStandard,
    this.tipSplit = true,
    this.change = true,
    this.tipChips = const [5, 10],
    this.exactCash = false,
    this.checkoutMode = KasseKassierenModus.panel,
    // Die Fertig-Seite fragt: QR oder Bon. Ein Betrieb ohne eigene
    // Einstellung soll am Tresen nicht ungefragt auf den QR festgelegt sein.
    this.receiptOutput = KasseBelegAusgabe.ask,
    this.doneScreenSeconds = 0,
    this.logoImage = '',
    this.watermarkSide = KasseWasserzeichenSeite.center,
    this.watermarkX = 50,
    this.watermarkY = 50,
    this.watermarkStrength = 6,
    this.logoScale = KasseSkala.m,
    this.watermarkScale = KasseSkala.m,
    this.glass = true,
    this.hints = true,
    this.discountChips = const [5, 10, 15, 20],
    this.fremdeWerte = const {},
  });

  final String logoText;
  final bool logoEnabled;
  final KasseGroesse logoSize;
  final KasseWasserzeichen watermark;
  final String color;
  final KasseStil theme;
  final KasseSchrift fontSize;

  /// Schriftgröße im Einstellungsbereich (dort darf es kleiner sein).
  final KasseEinstellSchrift settingsFontSize;
  final KasseKachelstil tileStyle;
  final bool clock;
  final bool lockScreen;

  /// Fotos der Mitarbeiter am Anmeldebildschirm.
  final bool staffPhotos;

  /// Nach so vielen Minuten ohne Bedienung abmelden; 0 = nie
  /// ([kasseAutoAbmeldenMinuten]).
  final int autoLogoutMinutes;
  final bool logoutAfterSale;

  /// Schnelles Entsperren mit gemerkter PIN; aus = jeder Login wartet auf den Server.
  final bool fastLogin;
  final bool showPrices;
  final bool showVat;
  final bool emoji;
  final bool categoryColors;
  final bool customAmountAllowed;

  /// Eingeschaltete Steuersätze (Schlüssel = Satz als Text). Beim Schreiben
  /// immer die ganze Karte senden (Nachtrag §11.7.2).
  final Map<String, bool> vatRates;
  final KasseMenge quantity;
  final bool note;
  final bool search;
  final KasseRabatt discount;
  final bool payCash;
  final bool payCard;

  /// Getrennt zahlen: dritter Knopf neben Bar und Karte, ein Beleg mit
  /// mehreren Zahlungen.
  final bool paySplit;
  final KasseKartenanbieter cardProvider;
  final bool tip;
  final KasseTgModus tipMode;
  final Map<String, bool> tipSteps;
  final bool tipSplit;

  /// Rückgeld-Rechner.
  final bool change;

  /// Trinkgeld-Chips in Prozent (eine Nachkommastelle, höchstens 5).
  final List<double> tipChips;

  /// „Bar passend": schließt den Betrag ohne Eintippen bar ab.
  final bool exactCash;
  final KasseKassierenModus checkoutMode;
  final KasseBelegAusgabe receiptOutput;

  /// Wie lange der Fertig-Bildschirm stehen bleibt; 0 = bis zum Tippen
  /// ([kasseFertigSekunden]).
  final int doneScreenSeconds;

  /// Bild-Logo (Adresse aus `setMyKasseLogo`); '' = Kürzel verwenden.
  final String logoImage;
  final KasseWasserzeichenSeite watermarkSide;

  /// Lage der Wasserzeichen-Mitte in Prozent (-25 bis 125).
  final int watermarkX;
  final int watermarkY;

  /// Deckkraft in Prozent ([kasseWasserzeichenStaerken]).
  final int watermarkStrength;

  /// Größe des Bild-Logos am Beleg.
  final KasseSkala logoScale;
  final KasseSkala watermarkScale;

  /// Glas-Optik: Kacheln und Korb leicht durchscheinend.
  final bool glass;

  /// Hilfetexte in den Chef-Einstellungen.
  final bool hints;

  /// Rabatt-Chips in Prozent, dieselben Regeln wie [tipChips].
  final List<double> discountChips;

  /// Werte des Servers, die dieses Paket nicht kennt, wörtlich (Feld ->
  /// Wert). Die Kasse arbeitet für diese Felder mit dem Standard; `toJson`
  /// gibt den Wert unverändert aus.
  final Map<String, Object> fremdeWerte;

  /// Kartenzahlung ist möglich: eingeschaltet **und** ein Anbieter eingerichtet.
  bool get kartenAktiv => payCard && cardProvider != KasseKartenanbieter.none;

  /// Die eingeschalteten Steuersätze in der Reihenfolge des Bildschirms.
  List<double> get aktiveSaetze =>
      kasseSaetzeReihenfolge.where((s) => vatRates[_satzSchluessel(s)] == true).toList();

  /// Diesen Stand mit einer Änderung (englische Schlüssel) mischen. Karten
  /// (`vatRates`, `tipSteps`) werden je Eintrag gemischt.
  ///
  /// Gebraucht, wo eine Einstellung **sofort** gelten soll, während der Server
  /// noch antwortet: der Bildschirm zeigt, was der Chef gewählt hat, und
  /// nimmt es zurück, falls der Server ablehnt.
  ///
  /// **Wirft [ArgumentError]** bei einem Schlüssel, den es nicht gibt (auch
  /// einem deutschen aus 9.x wie `stil`), und bei einem Wert der inneren Form
  /// 0.x (`'nacht'`): eine Änderung, die still nichts bewirkt, fiele am Tresen
  /// niemandem auf.
  KasseSettingsBetrieb mit(Map<String, dynamic> aenderung) {
    _pruefeAenderung('business', aenderung, _betriebSchluessel, altformBetriebSchluessel);
    return KasseSettingsBetrieb.ausJson(_mische(toJson(), aenderung));
  }

  /// Aus der Drahtform (schon mit den Standardwerten gemischt oder nicht).
  factory KasseSettingsBetrieb.ausJson(Map<String, dynamic> roh) {
    const s = KasseSettingsBetrieb();
    final g = _mische(s.toJson(), roh);
    final fremd = <String, Object>{};
    return KasseSettingsBetrieb(
      logoText: _text(g['logoText'], s.logoText),
      logoEnabled: _bool(g['logoEnabled'], s.logoEnabled),
      logoSize: _wahl(g, 'logoSize', KasseGroesse.values, s.logoSize, fremd),
      watermark: _wahl(g, 'watermark', KasseWasserzeichen.values, s.watermark, fremd),
      color: _text(g['color'], s.color),
      theme: _wahl(g, 'theme', KasseStil.values, s.theme, fremd),
      fontSize: _wahl(g, 'fontSize', KasseSchrift.values, s.fontSize, fremd),
      settingsFontSize: _wahl(g, 'settingsFontSize', KasseEinstellSchrift.values, s.settingsFontSize, fremd),
      tileStyle: _wahl(g, 'tileStyle', KasseKachelstil.values, s.tileStyle, fremd),
      clock: _bool(g['clock'], s.clock),
      lockScreen: _bool(g['lockScreen'], s.lockScreen),
      staffPhotos: _bool(g['staffPhotos'], s.staffPhotos),
      autoLogoutMinutes: _ausListe(g, 'autoLogoutMinutes', kasseAutoAbmeldenMinuten, s.autoLogoutMinutes, fremd),
      logoutAfterSale: _bool(g['logoutAfterSale'], s.logoutAfterSale),
      fastLogin: _bool(g['fastLogin'], s.fastLogin),
      showPrices: _bool(g['showPrices'], s.showPrices),
      showVat: _bool(g['showVat'], s.showVat),
      emoji: _bool(g['emoji'], s.emoji),
      categoryColors: _bool(g['categoryColors'], s.categoryColors),
      customAmountAllowed: _bool(g['customAmountAllowed'], s.customAmountAllowed),
      vatRates: _karte(g['vatRates'], s.vatRates),
      quantity: _wahl(g, 'quantity', KasseMenge.values, s.quantity, fremd),
      note: _bool(g['note'], s.note),
      search: _bool(g['search'], s.search),
      discount: _wahl(g, 'discount', KasseRabatt.values, s.discount, fremd),
      payCash: _bool(g['payCash'], s.payCash),
      payCard: _bool(g['payCard'], s.payCard),
      paySplit: _bool(g['paySplit'], s.paySplit),
      cardProvider: _wahl(g, 'cardProvider', KasseKartenanbieter.values, s.cardProvider, fremd),
      tip: _bool(g['tip'], s.tip),
      tipMode: _wahl(g, 'tipMode', KasseTgModus.values, s.tipMode, fremd),
      tipSteps: _karte(g['tipSteps'], s.tipSteps),
      tipSplit: _bool(g['tipSplit'], s.tipSplit),
      change: _bool(g['change'], s.change),
      tipChips: _zahlenliste(g, 'tipChips', s.tipChips, fremd),
      exactCash: _bool(g['exactCash'], s.exactCash),
      checkoutMode: _wahl(g, 'checkoutMode', KasseKassierenModus.values, s.checkoutMode, fremd),
      receiptOutput: _wahl(g, 'receiptOutput', KasseBelegAusgabe.values, s.receiptOutput, fremd),
      doneScreenSeconds: _ausListe(g, 'doneScreenSeconds', kasseFertigSekunden, s.doneScreenSeconds, fremd),
      logoImage: _text(g['logoImage'], s.logoImage),
      watermarkSide: _wahl(g, 'watermarkSide', KasseWasserzeichenSeite.values, s.watermarkSide, fremd),
      watermarkX: _ganz(g, 'watermarkX', -25, 125, s.watermarkX, fremd),
      watermarkY: _ganz(g, 'watermarkY', -25, 125, s.watermarkY, fremd),
      watermarkStrength: _ausListe(g, 'watermarkStrength', kasseWasserzeichenStaerken, s.watermarkStrength, fremd),
      logoScale: _wahl(g, 'logoScale', KasseSkala.values, s.logoScale, fremd),
      watermarkScale: _wahl(g, 'watermarkScale', KasseSkala.values, s.watermarkScale, fremd),
      glass: _bool(g['glass'], s.glass),
      hints: _bool(g['hints'], s.hints),
      discountChips: _zahlenliste(g, 'discountChips', s.discountChips, fremd),
      fremdeWerte: Map.unmodifiable(fremd),
    );
  }

  Map<String, dynamic> toJson() => {
        'logoText': logoText,
        'logoEnabled': logoEnabled,
        'logoSize': logoSize.wert,
        'watermark': watermark.wert,
        'color': color,
        'theme': theme.wert,
        'fontSize': fontSize.wert,
        'settingsFontSize': settingsFontSize.wert,
        'tileStyle': tileStyle.wert,
        'clock': clock,
        'lockScreen': lockScreen,
        'staffPhotos': staffPhotos,
        'autoLogoutMinutes': autoLogoutMinutes,
        'logoutAfterSale': logoutAfterSale,
        'fastLogin': fastLogin,
        'showPrices': showPrices,
        'showVat': showVat,
        'emoji': emoji,
        'categoryColors': categoryColors,
        'customAmountAllowed': customAmountAllowed,
        'vatRates': {...vatRates},
        'quantity': quantity.wert,
        'note': note,
        'search': search,
        'discount': discount.wert,
        'payCash': payCash,
        'payCard': payCard,
        'paySplit': paySplit,
        'cardProvider': cardProvider.wert,
        'tip': tip,
        'tipMode': tipMode.wert,
        'tipSteps': {...tipSteps},
        'tipSplit': tipSplit,
        'change': change,
        'tipChips': [...tipChips],
        'exactCash': exactCash,
        'checkoutMode': checkoutMode.wert,
        'receiptOutput': receiptOutput.wert,
        'doneScreenSeconds': doneScreenSeconds,
        'logoImage': logoImage,
        'watermarkSide': watermarkSide.wert,
        'watermarkX': watermarkX,
        'watermarkY': watermarkY,
        'watermarkStrength': watermarkStrength,
        'logoScale': logoScale.wert,
        'watermarkScale': watermarkScale.wert,
        'glass': glass,
        'hints': hints,
        'discountChips': [...discountChips],
        ...fremdeWerte,
      };
}

// --------------------------------------------------------------- Geraeteteil

/// Was nur für dieses Gerät gilt (in der Kasse selbst eingestellt).
class KasseSettingsGeraet {
  const KasseSettingsGeraet({
    this.layout = KasseLayout.right,
    this.categoryPosition = KasseKatpos.top,
    this.extraColumns = 0,
    this.tileHeight = KasseHoehe.m,
    this.touch = false,
    this.shortcuts = kasseTastenStandard,
    this.printerEnabled = false,
    this.printerType = KasseDruckerArt.sdp,
    this.printerIp = '',
    this.printerPort = 9100,
    this.printerBluetoothId = '',
    this.printerName = '',
    this.printerId = '',
    this.printerDeviceId = 'local_printer',
    this.connectPrinterId = '',
    this.paperSize = KassePapier.mm80,
    this.codePage = KasseZeichensatz.cp1252,
    this.cut = KasseSchnitt.partial,
    this.qrMode = KasseQrModus.auto,
    this.drawerEnabled = false,
    this.drawerAutoOpen = KasseLadeAuto.cash,
    this.terminalIp = '',
    this.terminalPort = 8080,
    this.terminalTid = '',
    this.terminalVia = KasseTerminalVia.direct,
    this.terminalType = KasseTerminalArt.none,
    this.shortcutHints = true,
    this.fremdeWerte = const {},
  });

  final KasseLayout layout;
  final KasseKatpos categoryPosition;

  /// Zusätzliche Kachelspalten gegenüber der berechneten Breite (-2 bis 4).
  final int extraColumns;
  final KasseHoehe tileHeight;
  final bool touch;

  /// Tastenbelegung dieses Geräts. Aktionen, die dieses Paket nicht kennt
  /// (eine künftige des Servers), bleiben stehen.
  final Map<String, List<String>> shortcuts;
  final bool printerEnabled;
  final KasseDruckerArt printerType;
  final String printerIp;
  final int printerPort;
  final String printerBluetoothId;

  /// Wie sich der gemerkte Drucker nennt; ohne ihn stünde in den
  /// Einstellungen eine nackte Bluetooth-Adresse.
  final String printerName;

  /// Kennung des Netzwerk-Druckers (Server Direct Print, `listMyPrinters`);
  /// '' = keiner gewählt.
  final String printerId;

  /// ePOS Device-ID bei [KasseDruckerArt.network] (Epson direkt per IP).
  final String printerDeviceId;

  /// Kennung des Druckers im lokalen Kasseneck-Connect-Agenten, bei
  /// [KasseDruckerArt.connect].
  final String connectPrinterId;
  final KassePapier paperSize;
  final KasseZeichensatz codePage;
  final KasseSchnitt cut;

  /// Welcher Druckbefehl den Signatur-QR erzeugt; [KasseQrModus.auto] heißt
  /// unbestimmt.
  final KasseQrModus qrMode;
  final bool drawerEnabled;
  final KasseLadeAuto drawerAutoOpen;
  final String terminalIp;
  final int terminalPort;

  /// Terminal-ID aus dem Hobex-Vertrag (ohne führende Null).
  final String terminalTid;
  final KasseTerminalVia terminalVia;

  /// Art des Terminals ([KasseTerminalArt.none] = keine Anbindung).
  final KasseTerminalArt terminalType;

  /// Tastenmarken (die kleinen Kürzel an den Knöpfen) anzeigen.
  final bool shortcutHints;

  /// Siehe [KasseSettingsBetrieb.fremdeWerte].
  final Map<String, Object> fremdeWerte;

  /// Siehe [KasseSettingsBetrieb.mit]; `shortcuts` wird je Aktion gemischt.
  KasseSettingsGeraet mit(Map<String, dynamic> aenderung) {
    _pruefeAenderung('device', aenderung, _geraetSchluessel, altformGeraetSchluessel);
    return KasseSettingsGeraet.ausJson(_mische(toJson(), aenderung));
  }

  /// Aus der Drahtform (schon mit den Standardwerten gemischt oder nicht).
  factory KasseSettingsGeraet.ausJson(Map<String, dynamic> roh) {
    const s = KasseSettingsGeraet();
    final g = _mische(s.toJson(), roh);
    final fremd = <String, Object>{};
    return KasseSettingsGeraet(
      layout: _wahl(g, 'layout', KasseLayout.values, s.layout, fremd),
      categoryPosition: _wahl(g, 'categoryPosition', KasseKatpos.values, s.categoryPosition, fremd),
      extraColumns: _ganz(g, 'extraColumns', -2, 4, s.extraColumns, fremd),
      tileHeight: _wahl(g, 'tileHeight', KasseHoehe.values, s.tileHeight, fremd),
      touch: _bool(g['touch'], s.touch),
      shortcuts: _tastenkarte(g['shortcuts'], s.shortcuts),
      printerEnabled: _bool(g['printerEnabled'], s.printerEnabled),
      printerType: _wahl(g, 'printerType', KasseDruckerArt.values, s.printerType, fremd),
      printerIp: _text(g['printerIp'], s.printerIp),
      printerPort: _ganz(g, 'printerPort', 1, 65535, s.printerPort, fremd),
      printerBluetoothId: _text(g['printerBluetoothId'], s.printerBluetoothId),
      printerName: _text(g['printerName'], s.printerName),
      printerId: _text(g['printerId'], s.printerId),
      printerDeviceId: _text(g['printerDeviceId'], s.printerDeviceId),
      connectPrinterId: _text(g['connectPrinterId'], s.connectPrinterId),
      paperSize: _wahl(g, 'paperSize', KassePapier.values, s.paperSize, fremd),
      codePage: _wahl(g, 'codePage', KasseZeichensatz.values, s.codePage, fremd),
      cut: _wahl(g, 'cut', KasseSchnitt.values, s.cut, fremd),
      qrMode: _wahl(g, 'qrMode', KasseQrModus.values, s.qrMode, fremd),
      drawerEnabled: _bool(g['drawerEnabled'], s.drawerEnabled),
      drawerAutoOpen: _wahl(g, 'drawerAutoOpen', KasseLadeAuto.values, s.drawerAutoOpen, fremd),
      terminalIp: _text(g['terminalIp'], s.terminalIp),
      terminalPort: _ganz(g, 'terminalPort', 1, 65535, s.terminalPort, fremd),
      terminalTid: _text(g['terminalTid'], s.terminalTid),
      terminalVia: _wahl(g, 'terminalVia', KasseTerminalVia.values, s.terminalVia, fremd),
      terminalType: _wahl(g, 'terminalType', KasseTerminalArt.values, s.terminalType, fremd),
      shortcutHints: _bool(g['shortcutHints'], s.shortcutHints),
      fremdeWerte: Map.unmodifiable(fremd),
    );
  }

  Map<String, dynamic> toJson() => {
        'layout': layout.wert,
        'categoryPosition': categoryPosition.wert,
        'extraColumns': extraColumns,
        'tileHeight': tileHeight.wert,
        'touch': touch,
        'shortcuts': {for (final e in shortcuts.entries) e.key: [...e.value]},
        'printerEnabled': printerEnabled,
        'printerType': printerType.wert,
        'printerIp': printerIp,
        'printerPort': printerPort,
        'printerBluetoothId': printerBluetoothId,
        'printerName': printerName,
        'printerId': printerId,
        'printerDeviceId': printerDeviceId,
        'connectPrinterId': connectPrinterId,
        'paperSize': paperSize.wert,
        'codePage': codePage.wert,
        'cut': cut.wert,
        'qrMode': qrMode.wert,
        'drawerEnabled': drawerEnabled,
        'drawerAutoOpen': drawerAutoOpen.wert,
        'terminalIp': terminalIp,
        'terminalPort': terminalPort,
        'terminalTid': terminalTid,
        'terminalVia': terminalVia.wert,
        'terminalType': terminalType.wert,
        'shortcutHints': shortcutHints,
        ...fremdeWerte,
      };
}

// ------------------------------------------------------------------ Ganzes

class KasseSettings {
  const KasseSettings({required this.betrieb, required this.geraet});

  /// Die Standardwerte, deckungsgleich mit Backend und Browser-Kasse.
  const KasseSettings.standard()
      : betrieb = const KasseSettingsBetrieb(),
        geraet = const KasseSettingsGeraet();

  final KasseSettingsBetrieb betrieb;
  final KasseSettingsGeraet geraet;

  /// Standard + Gespeichertes in der Drahtform `{business, device}`. Was
  /// fehlt, bleibt beim Standard; ein Schlüssel, den der Standard nicht
  /// führt, bleibt draußen; ein Wert der inneren Form 0.x fällt auf den
  /// Standard; ein unbekannter englischer Wert bleibt wörtlich erhalten
  /// ([KasseSettingsBetrieb.fremdeWerte]).
  ///
  /// **Zwischenspeicher der Version 9.x:** trägt die Map statt `business` und
  /// `device` die alten Teile `betrieb`/`geraet` (deutsche Schlüssel und
  /// Werte, so schrieb `toJson` bis 9.x), wird sie Feld für Feld übersetzt
  /// (Tabelle `renames-1.0.json`). Ein alter Stand geht so beim Update nicht
  /// verloren. Die Tastenkarte wird dabei wie am Server entwirrt
  /// ([entwirreTasten]), damit die alten Vorgaben (`frei: Mod+F`) keine
  /// Doppelbelegung mit den neuen (`fullscreen: Mod+F`) ergeben. Übrige
  /// 9.x-Standardwerte im Stand (`terminalPort` 20008, `kassierenModus`
  /// `seite`) gelten als gesetzt, bis die erste Serverantwort
  /// (`getKasseSettings`, Benutzerliste) den Stand ersetzt.
  factory KasseSettings.aus(Map<String, dynamic>? gespeichert) {
    final roh = gespeichert ?? const <String, dynamic>{};
    final alt = !roh.containsKey('business') &&
        !roh.containsKey('device') &&
        (roh.containsKey('betrieb') || roh.containsKey('geraet'));
    Map<String, dynamic> teil(String neu, String altName, Map<String, String> schluessel) {
      final w = roh[alt ? altName : neu];
      if (w is! Map) return const {};
      final m = Map<String, dynamic>.from(w);
      if (!alt) return m;
      final uebersetzt = _ausAltform(m, schluessel);
      final tasten = uebersetzt['shortcuts'];
      // Der 9.x-Stand trägt die gemischte Tastenkarte samt der alten
      // Vorgaben (frei: Mod+F, belege: Mod+E). Wie der Server
      // (`entwirreTasten`): die gespeicherte Wahl gewinnt, eine beanspruchte
      // Vorgabe-Taste fällt bei der Aktion, die nicht gespeichert war (Mod+F
      // verliert das Vollbild, statt doppelt belegt zu sein).
      if (tasten is Map) {
        final gespeichert = <String, Object?>{
          for (final e in tasten.entries)
            if (!altformTastenAktionen.containsKey(e.key)) e.key.toString(): e.value,
        };
        uebersetzt['shortcuts'] = entwirreTasten({...kasseTastenStandard, ...gespeichert}, gespeichert);
      }
      return uebersetzt;
    }

    return KasseSettings(
      betrieb: KasseSettingsBetrieb.ausJson(teil('business', 'betrieb', altformBetriebSchluessel)),
      geraet: KasseSettingsGeraet.ausJson(teil('device', 'geraet', altformGeraetSchluessel)),
    );
  }

  Map<String, dynamic> toJson() => {'business': betrieb.toJson(), 'device': geraet.toJson()};
}

// ------------------------------------------- Wertemengen, Aenderungen, Pruefung

/// Die Wertemenge je Betriebsfeld, soweit das Feld eine hat (Zwilling von
/// `POS_BUSINESS_VALUES`); dagegen prüft der Schreibweg vor dem Senden.
final Map<String, List<Object>> posBusinessValues = Map.unmodifiable({
  'logoSize': _werte(KasseGroesse.values),
  'watermark': _werte(KasseWasserzeichen.values),
  'theme': _werte(KasseStil.values),
  'fontSize': _werte(KasseSchrift.values),
  'settingsFontSize': _werte(KasseEinstellSchrift.values),
  'tileStyle': _werte(KasseKachelstil.values),
  'autoLogoutMinutes': kasseAutoAbmeldenMinuten,
  'quantity': _werte(KasseMenge.values),
  'discount': _werte(KasseRabatt.values),
  'cardProvider': _werte(KasseKartenanbieter.values),
  'tipMode': _werte(KasseTgModus.values),
  'checkoutMode': _werte(KasseKassierenModus.values),
  'receiptOutput': _werte(KasseBelegAusgabe.values),
  'doneScreenSeconds': kasseFertigSekunden,
  'watermarkSide': _werte(KasseWasserzeichenSeite.values),
  'watermarkStrength': kasseWasserzeichenStaerken,
  'logoScale': _werte(KasseSkala.values),
  'watermarkScale': _werte(KasseSkala.values),
});

/// Wie [posBusinessValues] für die Geräte-Einstellungen (`POS_DEVICE_VALUES`).
final Map<String, List<Object>> posDeviceValues = Map.unmodifiable({
  'layout': _werte(KasseLayout.values),
  'categoryPosition': _werte(KasseKatpos.values),
  'tileHeight': _werte(KasseHoehe.values),
  'printerType': _werte(KasseDruckerArt.values),
  'paperSize': _werte(KassePapier.values),
  'codePage': _werte(KasseZeichensatz.values),
  'cut': _werte(KasseSchnitt.values),
  'qrMode': _werte(KasseQrModus.values),
  'drawerAutoOpen': _werte(KasseLadeAuto.values),
  'terminalVia': _werte(KasseTerminalVia.values),
  'terminalType': _werte(KasseTerminalArt.values),
});

List<Object> _werte(List<KasseWert> werte) => List.unmodifiable([for (final w in werte) w.wert]);

/// Die Felder, deren Wert dieses Paket nicht kennt, als Pfade
/// (`business.theme`, `device.shortcuts.<aktion>`). Die Oberfläche zeigt sie
/// als „vom Server, hier nicht einstellbar"; sie bleiben erhalten, solange nur
/// geänderte Felder geschrieben werden ([posSettingsChanges]). Zwilling von
/// `unknownPosSettingValues`.
List<String> unknownPosSettingValues(KasseSettings settings) {
  final raus = <String>[
    for (final k in settings.betrieb.fremdeWerte.keys) 'business.$k',
    for (final k in settings.geraet.fremdeWerte.keys) 'device.$k',
  ];
  for (final aktion in settings.geraet.shortcuts.keys) {
    if (!kasseTastenAktionen.contains(aktion)) raus.add('device.shortcuts.$aktion');
  }
  return raus;
}

/// Was sich zwischen zwei Ständen eines Teils (`toJson` von Betrieb oder
/// Gerät) geändert hat, als Nutzlast für `betriebSpeichern` bzw.
/// `geraetSpeichern`: **nur geänderte Felder** (der Server mischt; ein nicht
/// geänderter, hier unbekannter Wert geht so nie verloren). `vatRates` geht
/// bei einer Änderung als ganze Karte (Nachtrag §11.7.2), `shortcuts` ebenfalls
/// ganz, aber nur mit den Aktionen, die dieses Paket kennt: so sieht die
/// Doppelbelegungsprüfung die ganze Belegung, und eine unbekannte Aktion
/// bleibt am Server stehen. `tipSteps` geht nur mit den geänderten Einträgen.
/// Zwilling von `posSettingsChanges`.
Map<String, dynamic> posSettingsChanges(Map<String, dynamic> vorher, Map<String, dynamic> nachher) {
  final raus = <String, dynamic>{};
  for (final k in nachher.keys) {
    final neu = nachher[k];
    final alt = vorher[k];
    if (_gleich(alt, neu)) continue;
    if (k == 'shortcuts' && neu is Map) {
      raus[k] = <String, dynamic>{
        for (final e in neu.entries)
          if (kasseTastenAktionen.contains(e.key)) e.key.toString(): e.value,
      };
      continue;
    }
    if (k != 'vatRates' && neu is Map && alt is Map) {
      final teil = <String, dynamic>{
        for (final e in neu.entries)
          if (!_gleich(alt[e.key], e.value)) e.key.toString(): e.value,
      };
      if (teil.isNotEmpty) raus[k] = teil;
      continue;
    }
    raus[k] = neu;
  }
  return raus;
}

bool _gleich(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_gleich(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_gleich(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

// ------------------------------------------------------------ Altform 0.x/9.x

/// Schlüssel der inneren Form (0.x, Zwischenspeicher bis Dart 9.x) -> Draht,
/// Betriebsteil. Ein Test hält die Tabelle deckungsgleich mit
/// `renames-1.0.json` (`structure.pos-settings-defaults.json.business`).
const Map<String, String> altformBetriebSchluessel = {
  'logoText': 'logoText', 'logoAn': 'logoEnabled', 'logoGroesse': 'logoSize', 'wasserzeichen': 'watermark',
  'farbe': 'color', 'stil': 'theme', 'schrift': 'fontSize', 'schriftEinst': 'settingsFontSize',
  'kachelstil': 'tileStyle', 'uhr': 'clock', 'sperrbild': 'lockScreen', 'foto': 'staffPhotos',
  'autoAbMin': 'autoLogoutMinutes', 'abNachVerkauf': 'logoutAfterSale', 'schnellLogin': 'fastLogin',
  'preisAnzeigen': 'showPrices', 'ustAnzeigen': 'showVat', 'emoji': 'emoji', 'katFarben': 'categoryColors',
  'freiErlaubt': 'customAmountAllowed', 'saetze': 'vatRates', 'menge': 'quantity', 'notiz': 'note',
  'suche': 'search', 'rabatt': 'discount', 'zahlBar': 'payCash', 'zahlKarte': 'payCard',
  'zahlGetrennt': 'paySplit', 'kartenanbieter': 'cardProvider', 'trinkgeld': 'tip', 'tgModus': 'tipMode',
  'tgStufen': 'tipSteps', 'tgSplit': 'tipSplit', 'rueckgeld': 'change', 'tgChips': 'tipChips',
  'schnellbar': 'exactCash', 'kassierenModus': 'checkoutMode', 'belegAusgabe': 'receiptOutput',
  'fertigSekunden': 'doneScreenSeconds', 'logoBild': 'logoImage', 'wzSeite': 'watermarkSide',
  'wzPos': 'watermarkX', 'wzPosV': 'watermarkY', 'wzStaerke': 'watermarkStrength', 'logoSkala': 'logoScale',
  'wzSkala': 'watermarkScale', 'glas': 'glass', 'hinweise': 'hints', 'rabattChips': 'discountChips',
};

/// Wie [altformBetriebSchluessel] für den Geräteteil.
const Map<String, String> altformGeraetSchluessel = {
  'layout': 'layout', 'katpos': 'categoryPosition', 'spaltenExtra': 'extraColumns', 'hoehe': 'tileHeight',
  'touch': 'touch', 'tasten': 'shortcuts', 'druckerAn': 'printerEnabled', 'druckerArt': 'printerType',
  'druckerIp': 'printerIp', 'druckerPort': 'printerPort', 'druckerBt': 'printerBluetoothId',
  'druckerName': 'printerName', 'druckerId': 'printerId', 'druckerDevid': 'printerDeviceId',
  'connectDruckerId': 'connectPrinterId', 'papier': 'paperSize', 'zeichensatz': 'codePage', 'schnitt': 'cut',
  'qrModus': 'qrMode', 'ladeAn': 'drawerEnabled', 'ladeAuto': 'drawerAutoOpen', 'terminalIp': 'terminalIp',
  'terminalPort': 'terminalPort', 'terminalTid': 'terminalTid', 'terminalVia': 'terminalVia',
  'terminalArt': 'terminalType', 'tastenMarken': 'shortcutHints',
};

/// Tasten-Aktionen der inneren Form -> Draht.
const Map<String, String> altformTastenAktionen = {
  'kassieren': 'checkout', 'abschliessen': 'complete', 'abbrechen': 'cancel', 'frei': 'customAmount',
  'bar': 'cash', 'karte': 'card', 'passend': 'exactAmount', 'belege': 'receipts', 'letzteZurueck': 'undoLast',
  'einstellungen': 'settings', 'abmelden': 'logout', 'trinkgeld': 'tip', 'vollbild': 'fullscreen',
  'gegebenLeeren': 'clearTendered', 'korbLeeren': 'clearCart', 'getrennt': 'splitPayment',
};

/// Werte der inneren Form -> Draht, je Drahtfeld; gleichlautende Werte
/// (`gptom`, `S`) stehen nicht darin. Ein Test hält die Tabelle deckungsgleich
/// mit `renames-1.0.json` (`values.pos-settings-defaults.json`).
const Map<String, Map<String, String>> altformWerte = {
  'cardProvider': {'keiner': 'none', 'extern': 'external'},
  'checkoutMode': {'seite': 'page'},
  'discount': {'aus': 'off', 'an': 'on'},
  'quantity': {'aus': 'off'},
  'receiptOutput': {'druck': 'print', 'mail': 'email', 'fragen': 'ask'},
  'theme': {'klar': 'clear', 'nacht': 'night', 'kontrast': 'contrast'},
  'tileStyle': {'streifen': 'stripe', 'voll': 'full'},
  'tipMode': {'betrag': 'amount', 'gesamt': 'total', 'beides': 'both'},
  'watermark': {'aus': 'off', 'anmeldung': 'login', 'ueberall': 'everywhere'},
  'watermarkSide': {'links': 'left', 'mitte': 'center', 'rechts': 'right'},
  'categoryPosition': {'oben': 'top', 'links': 'left'},
  'drawerAutoOpen': {'bar': 'cash', 'immer': 'always', 'nie': 'never'},
  'layout': {'rechts': 'right', 'links': 'left', 'vollbild': 'fullscreen'},
  'printerType': {'netz': 'network', 'bt': 'bluetooth'},
  'terminalType': {'keins': 'none'},
  'terminalVia': {'direkt': 'direct'},
};

/// Ein Teil der inneren Form in die Drahtform übersetzen (lesend migrieren).
Map<String, dynamic> _ausAltform(Map<String, dynamic> alt, Map<String, String> schluessel) {
  final raus = <String, dynamic>{};
  for (final e in alt.entries) {
    final neu = schluessel[e.key];
    if (neu == null) continue;
    var wert = e.value;
    if (neu == 'shortcuts' && wert is Map) {
      wert = <String, dynamic>{
        for (final t in wert.entries) (altformTastenAktionen[t.key.toString()] ?? t.key.toString()): t.value,
      };
    } else if (wert is String) {
      wert = altformWerte[neu]?[wert] ?? wert;
    }
    raus[neu] = wert;
  }
  return raus;
}

/// Zwilling von `entwirreTasten` (Backend, npm `stored`): Aktionen aus
/// [gespeichert] behalten ihre Tasten; jede andere Aktion verliert eine Taste,
/// die eine gespeicherte Aktion beansprucht, außer die beiden dürfen sie
/// teilen ([posShortcutSharedPairs]).
Map<String, Object?> entwirreTasten(Map<String, Object?> gemischt, Map<String, Object?> gespeichert) {
  final beansprucht = <Object?, String>{};
  for (final e in gespeichert.entries) {
    final tasten = e.value;
    if (tasten is! List) continue;
    for (final t in tasten) {
      beansprucht[t] = e.key;
    }
  }
  return {
    for (final e in gemischt.entries)
      e.key: e.value is! List || gespeichert.containsKey(e.key)
          ? e.value
          : [
              for (final t in e.value as List)
                if (beansprucht[t] == null || beansprucht[t] == e.key || _darfTeilen(beansprucht[t]!, e.key)) t,
            ],
  };
}

final Set<String> _betriebSchluessel = const KasseSettingsBetrieb().toJson().keys.toSet();
final Set<String> _geraetSchluessel = const KasseSettingsGeraet().toJson().keys.toSet();

void _pruefeAenderung(String teil, Map<String, dynamic> aenderung, Set<String> bekannt, Map<String, String> altform) {
  for (final e in aenderung.entries) {
    if (!bekannt.contains(e.key)) {
      final neu = altform[e.key];
      throw ArgumentError('$teil.${e.key}: unbekanntes Feld'
          '${neu != null && neu != e.key ? ' (Schluessel aus 9.x, heute $neu)' : ''}');
    }
    if (istAltwert0x(e.key, e.value)) {
      throw ArgumentError('$teil.${e.key}: Wert der inneren Form 0.x (${e.value}), '
          'heute ${altformWerte[e.key]![e.value]}');
    }
    final wert = e.value;
    if (e.key == 'shortcuts' && wert is Map) {
      for (final aktion in wert.keys) {
        final neu = altformTastenAktionen[aktion];
        if (neu != null) throw ArgumentError('$teil.shortcuts.$aktion: Tasten-Aktion aus 9.x, heute $neu');
      }
    }
  }
}

/// Ist [wert] ein Wert der inneren Form 0.x für dieses Drahtfeld?
bool istAltwert0x(String feld, Object? wert) => altformWerte[feld]?.containsKey(wert) ?? false;

// ------------------------------------------------------------------ Helfer

/// Standard + Gespeichertes, Zwilling von `mergePosSettings`: nur Schlüssel,
/// die der Standard führt; Karten (`vatRates`, `tipSteps`, `shortcuts`) je
/// Eintrag; ein Wert der inneren Form 0.x und eine deutsche Tasten-Aktion
/// bleiben draußen; `null` zählt als nicht gesetzt.
Map<String, dynamic> _mische(Map<String, dynamic> standard, Map<String, dynamic> gespeichert) {
  final out = <String, dynamic>{...standard};
  for (final e in gespeichert.entries) {
    final key = e.key;
    if (!standard.containsKey(key)) continue;
    final wert = e.value;
    final alt = out[key];
    if (alt is Map && wert is Map) {
      out[key] = <String, dynamic>{
        ...Map<String, dynamic>.from(alt),
        for (final k in wert.entries)
          if (!(key == 'shortcuts' && altformTastenAktionen.containsKey(k.key))) k.key.toString(): k.value,
      };
    } else if (wert != null) {
      if (istAltwert0x(key, wert)) continue;
      out[key] = wert;
    }
  }
  return out;
}

/// Steuersatz als Schlüssel, wie ihn das Backend schreibt: ganze Sätze ohne
/// Nachkomma („20"), gebrochene mit („4.9").
String _satzSchluessel(double satz) =>
    satz == satz.roundToDouble() ? satz.toInt().toString() : satz.toString();

bool _bool(Object? wert, bool standard) => wert is bool ? wert : standard;

String _text(Object? wert, String standard) => wert is String ? wert : standard;

/// Ganze Zahl im Bereich; ein Wert außerhalb (etwa ein weiterer Bereich eines
/// neueren Servers) wird wie ein unbekannter Aufzählungswert in [fremd]
/// festgehalten, nie still ersetzt.
int _ganz(Map<String, dynamic> g, String feld, int min, int max, int standard, Map<String, Object> fremd) {
  final wert = g[feld];
  if (wert is num && wert == wert.roundToDouble() && wert >= min && wert <= max) return wert.toInt();
  if (wert is String || wert is num) fremd[feld] = wert as Object;
  return standard;
}

/// Wert aus einer Wertemenge; ein unbekannter Wert (Text oder Zahl) wird
/// wörtlich in [fremd] festgehalten, das Feld bekommt den Standard.
T _wahl<T extends KasseWert>(Map<String, dynamic> g, String feld, List<T> werte, T standard, Map<String, Object> fremd) {
  final wert = g[feld];
  for (final e in werte) {
    if (e.wert == wert) return e;
  }
  if (wert is String || wert is num) fremd[feld] = wert as Object;
  return standard;
}

int _ausListe(Map<String, dynamic> g, String feld, List<int> erlaubt, int standard, Map<String, Object> fremd) {
  final wert = g[feld];
  if (wert is num && wert == wert.roundToDouble() && erlaubt.contains(wert.toInt())) return wert.toInt();
  if (wert is String || wert is num) fremd[feld] = wert as Object;
  return standard;
}

/// Landkarte je Schlüssel mischen: neue Sätze/Stufen kommen beim Altbestand
/// an; Einträge, die der Standard nicht kennt, bleiben stehen (ein neuer Satz
/// des Servers).
Map<String, bool> _karte(Object? wert, Map<String, bool> standard) {
  if (wert is! Map) return standard;
  final out = <String, bool>{...standard};
  for (final e in wert.entries) {
    if (e.value is bool) out[e.key.toString()] = e.value as bool;
  }
  return out;
}

/// Tastenbelegung je Aktion mischen; eine Aktion, die dieses Paket nicht
/// kennt, bleibt stehen (siehe [unknownPosSettingValues]).
Map<String, List<String>> _tastenkarte(Object? wert, Map<String, List<String>> standard) {
  final out = <String, List<String>>{for (final e in standard.entries) e.key: [...e.value]};
  if (wert is! Map) return out;
  for (final e in wert.entries) {
    final tasten = e.value;
    if (tasten is List) out[e.key.toString()] = tasten.whereType<String>().toList();
  }
  return out;
}

/// Zahlenliste (Chips): höchstens fünf, eindeutig, in der Reihenfolge des
/// Chefs. Eine Liste, die davon abweicht (mehr Einträge, Doppel, keine Zahl),
/// bleibt wörtlich in [fremd], die Kasse arbeitet mit dem bereinigten Teil.
List<double> _zahlenliste(Map<String, dynamic> g, String feld, List<double> standard, Map<String, Object> fremd) {
  final wert = g[feld];
  if (wert is! List) {
    if (wert is String || wert is num) fremd[feld] = wert as Object;
    return standard;
  }
  final out = <double>[];
  for (final e in wert) {
    final zahl = e is num ? e.toDouble() : null;
    if (zahl == null || out.contains(zahl)) continue;
    out.add(zahl);
    if (out.length == 5) break;
  }
  if (out.length != wert.length) fremd[feld] = List<Object?>.unmodifiable(wert);
  return out;
}
