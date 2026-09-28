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
/// wörtlich fest: [PosBusinessSettings.unknownValues] bzw.
/// [PosDeviceSettings.unknownValues], `toJson` gibt ihn unverändert aus, und
/// [unknownPosSettingValues] nennt die Felder. Geschrieben wird nur, was sich
/// geändert hat ([posSettingsChanges]); so bleibt der Wert am Server stehen.
///
/// **Werte der inneren Form 0.x** (`theme: 'nacht'`, `layout: 'rechts'`) fallen
/// auf den Standard zurück, nie in das englische Modell. Ein zwischengespeicherter
/// Stand der Version 9.x (`{betrieb, geraet}`, deutsche Schlüssel und Werte)
/// wird beim Lesen übersetzt ([PosSettings.fromJson]): nach dem Update geht keine
/// Einstellung verloren.
library;

// ------------------------------------------------------------------ Enums

/// Gemeinsame Sicht auf die Aufzählungen der Einstellungen: [value] ist der
/// Wert am Draht.
abstract interface class PosSettingValue {
  Object get value;
}

enum PosTheme implements PosSettingValue {
  clear,
  warm,
  night,
  contrast;

  @override
  String get value => name;
}

enum PosFontSize implements PosSettingValue {
  s('S'),
  m('M'),
  l('L'),
  xl('XL');

  const PosFontSize(this.value);
  @override
  final String value;
}

enum PosSettingsFontSize implements PosSettingValue {
  s('S'),
  m('M'),
  l('L');

  const PosSettingsFontSize(this.value);
  @override
  final String value;
}

/// Größe des Kürzel-Logos in der Kopfzeile der Kasse (`logoSize`).
enum PosLogoSize implements PosSettingValue {
  s('S'),
  m('M'),
  l('L');

  const PosLogoSize(this.value);
  @override
  final String value;
}

/// Größe des Bild-Logos am Beleg (`logoScale`) bzw. des Wasserzeichens
/// (`watermarkScale`).
enum PosScale implements PosSettingValue {
  s('S'),
  m('M'),
  l('L'),
  xl('XL');

  const PosScale(this.value);
  @override
  final String value;
}

enum PosWatermark implements PosSettingValue {
  off,
  login,
  everywhere;

  @override
  String get value => name;
}

/// Seite des Wasserzeichens; alt, abgelöst von `watermarkX`, bleibt fürs
/// Mischen alter Stände.
enum PosWatermarkSide implements PosSettingValue {
  left,
  center,
  right;

  @override
  String get value => name;
}

enum PosTileStyle implements PosSettingValue {
  stripe,
  full;

  @override
  String get value => name;
}

enum PosQuantity implements PosSettingValue {
  off,
  x,
  kg;

  @override
  String get value => name;
}

enum PosDiscount implements PosSettingValue {
  off,
  on;

  @override
  String get value => name;
}

/// Karte gibt es erst mit eingerichtetem Anbieter.
///
/// - `external`: ein Terminal, das die Kasse nicht anspricht. Der Kassier
///   tippt den Betrag dort selbst ein und bestätigt in der Kasse; das ist ein
///   gültiger Weg, kein Notbehelf.
/// - `gptom`: GP Tom, angesprochen über die Terminal-App auf demselben Gerät.
/// - `hobex`: Hobex HPS über die Terminal-Adresse im Kassennetz
///   ([PosDeviceSettings.terminalIp] / `terminalPort`).
enum PosCardProvider implements PosSettingValue {
  none,
  external,
  gptom,
  hobex,
  mypos,
  stripe;

  @override
  String get value => name;
}

enum PosTipMode implements PosSettingValue {
  amount,
  total,
  both;

  @override
  String get value => name;
}

enum PosCheckoutMode implements PosSettingValue {
  page,
  panel;

  @override
  String get value => name;
}

enum PosReceiptOutput implements PosSettingValue {
  qr,
  print,
  email,
  sms,
  ask;

  @override
  String get value => name;
}

enum PosLayout implements PosSettingValue {
  right,
  left,
  fullscreen;

  @override
  String get value => name;
}

enum PosCategoryPosition implements PosSettingValue {
  top,
  left;

  @override
  String get value => name;
}

enum PosTileHeight implements PosSettingValue {
  s('S'),
  m('M'),
  l('L');

  const PosTileHeight(this.value);
  @override
  final String value;
}

/// `sdp` = Netzwerk über Epson Server Direct Print (der Drucker holt die Jobs
/// vom Backend), `network` = direkt per IP (ePOS), `bluetooth`, `usb` = Kabel,
/// `connect` = Kasseneck Connect (lokaler Agent auf dem Kassen-Rechner).
enum PosPrinterType implements PosSettingValue {
  sdp,
  network,
  bluetooth,
  usb,
  connect;

  @override
  String get value => name;
}

/// Terminal-Ansprache: direkt per IP oder über Kasseneck Connect.
enum PosTerminalVia implements PosSettingValue {
  direct,
  connect;

  @override
  String get value => name;
}

/// Art des Kartenterminals an dieser Kasse: keines oder Hobex HPS.
enum PosTerminalType implements PosSettingValue {
  none,
  hps;

  @override
  String get value => name;
}

enum PosPaperSize implements PosSettingValue {
  mm58,
  mm80;

  @override
  String get value => name;
}

enum PosCodePage implements PosSettingValue {
  cp1252('CP1252'),
  cp437('CP437');

  const PosCodePage(this.value);
  @override
  final String value;
}

enum PosCut implements PosSettingValue {
  partial,
  full,
  none;

  @override
  String get value => name;
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
enum PosQrMode implements PosSettingValue {
  auto,
  raster,
  escpos;

  @override
  String get value => name;
}

enum PosDrawerAutoOpen implements PosSettingValue {
  cash,
  always,
  never;

  @override
  String get value => name;
}

/// Automatisches Abmelden nach Minuten Ruhe; 0 = nie.
const List<int> posAutoLogoutMinutes = [0, 1, 5, 15, 30];

/// Wie lange die Fertig-Seite stehen bleibt, in Sekunden; 0 = bis zum Tippen.
const List<int> posDoneScreenSeconds = [0, 3, 5, 10, 15, 30, 60];

/// Deckkraft des Wasserzeichens in Prozent, bewusst Stufen.
const List<int> posWatermarkStrengths = [3, 6, 10, 16];

/// Aktionen der Kasse, die eine Taste bekommen können (Schlüssel von
/// `device.shortcuts`), Zwilling von `POS_SHORTCUT_ACTIONS`.
const List<String> posShortcutActions = [
  'checkout', 'complete', 'cancel', 'customAmount', 'cash', 'card', 'exactAmount', 'receipts', 'undoLast',
  'settings', 'logout', 'tip', 'fullscreen', 'clearTendered', 'clearCart', 'splitPayment',
];

/// Tastenbelegung: Aktion -> Tasten (`Mod+F`, `Enter`, `Escape`, `F5` ...;
/// `Mod` = Cmd auf dem Mac, Strg sonst). Zwilling von `POS_SHORTCUT_DEFAULTS`.
const Map<String, List<String>> posShortcutDefaults = {
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
const List<double> posVatRateOrder = [20, 19, 13, 10, 4.9, 0];

const Map<String, bool> _saetzeStandard = {'20': true, '19': false, '13': true, '10': true, '4.9': true, '0': true};
const Map<String, bool> _tgStufenStandard = {'5': true, '10': true, '15': false, '20': false};

// ------------------------------------------------------------- Betriebsteil

/// Was für den ganzen Betrieb gilt (im Panel eingestellt).
class PosBusinessSettings {
  const PosBusinessSettings({
    this.logoText = 'K',
    this.logoEnabled = true,
    this.logoSize = PosLogoSize.m,
    this.watermark = PosWatermark.login,
    // Die Farbe der Marke Kasseneck (Rolle `brand` des Design-Systems), wie
    // im Vertrag ab npm 0.14.0.
    this.color = '#136B6B',
    this.theme = PosTheme.clear,
    this.fontSize = PosFontSize.m,
    this.settingsFontSize = PosSettingsFontSize.s,
    this.tileStyle = PosTileStyle.stripe,
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
    this.quantity = PosQuantity.x,
    this.note = false,
    this.search = false,
    this.discount = PosDiscount.off,
    this.payCash = true,
    this.payCard = false,
    this.paySplit = false,
    this.cardProvider = PosCardProvider.none,
    this.tip = false,
    this.tipMode = PosTipMode.both,
    this.tipSteps = _tgStufenStandard,
    this.tipSplit = true,
    this.change = true,
    this.tipChips = const [5, 10],
    this.exactCash = false,
    this.checkoutMode = PosCheckoutMode.panel,
    // Die Fertig-Seite fragt: QR oder Bon. Ein Betrieb ohne eigene
    // Einstellung soll am Tresen nicht ungefragt auf den QR festgelegt sein.
    this.receiptOutput = PosReceiptOutput.ask,
    this.doneScreenSeconds = 0,
    this.logoImage = '',
    this.watermarkSide = PosWatermarkSide.center,
    this.watermarkX = 50,
    this.watermarkY = 50,
    this.watermarkStrength = 6,
    this.logoScale = PosScale.m,
    this.watermarkScale = PosScale.m,
    this.glass = true,
    this.hints = true,
    this.discountChips = const [5, 10, 15, 20],
    this.unknownValues = const {},
  });

  final String logoText;
  final bool logoEnabled;
  final PosLogoSize logoSize;
  final PosWatermark watermark;
  final String color;
  final PosTheme theme;
  final PosFontSize fontSize;

  /// Schriftgröße im Einstellungsbereich (dort darf es kleiner sein).
  final PosSettingsFontSize settingsFontSize;
  final PosTileStyle tileStyle;
  final bool clock;
  final bool lockScreen;

  /// Fotos der Mitarbeiter am Anmeldebildschirm.
  final bool staffPhotos;

  /// Nach so vielen Minuten ohne Bedienung abmelden; 0 = nie
  /// ([posAutoLogoutMinutes]).
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
  final PosQuantity quantity;
  final bool note;
  final bool search;
  final PosDiscount discount;
  final bool payCash;
  final bool payCard;

  /// Getrennt zahlen: dritter Knopf neben Bar und Karte, ein Beleg mit
  /// mehreren Zahlungen.
  final bool paySplit;
  final PosCardProvider cardProvider;
  final bool tip;
  final PosTipMode tipMode;
  final Map<String, bool> tipSteps;
  final bool tipSplit;

  /// Rückgeld-Rechner.
  final bool change;

  /// Trinkgeld-Chips in Prozent (eine Nachkommastelle, höchstens 5).
  final List<double> tipChips;

  /// „Bar passend": schließt den Betrag ohne Eintippen bar ab.
  final bool exactCash;
  final PosCheckoutMode checkoutMode;
  final PosReceiptOutput receiptOutput;

  /// Wie lange der Fertig-Bildschirm stehen bleibt; 0 = bis zum Tippen
  /// ([posDoneScreenSeconds]).
  final int doneScreenSeconds;

  /// Bild-Logo (Adresse aus `setMyKasseLogo`); '' = Kürzel verwenden.
  final String logoImage;
  final PosWatermarkSide watermarkSide;

  /// Lage der Wasserzeichen-Mitte in Prozent (-25 bis 125).
  final int watermarkX;
  final int watermarkY;

  /// Deckkraft in Prozent ([posWatermarkStrengths]).
  final int watermarkStrength;

  /// Größe des Bild-Logos am Beleg.
  final PosScale logoScale;
  final PosScale watermarkScale;

  /// Glas-Optik: Kacheln und Korb leicht durchscheinend.
  final bool glass;

  /// Hilfetexte in den Chef-Einstellungen.
  final bool hints;

  /// Rabatt-Chips in Prozent, dieselben Regeln wie [tipChips].
  final List<double> discountChips;

  /// Werte des Servers, die dieses Paket nicht kennt, wörtlich (Feld ->
  /// Wert). Die Kasse arbeitet für diese Felder mit dem Standard; `toJson`
  /// gibt den Wert unverändert aus.
  final Map<String, Object> unknownValues;

  /// Kartenzahlung ist möglich: eingeschaltet **und** ein Anbieter eingerichtet.
  bool get cardPaymentEnabled => payCard && cardProvider != PosCardProvider.none;

  /// Die eingeschalteten Steuersätze in der Reihenfolge des Bildschirms.
  List<double> get activeVatRates =>
      posVatRateOrder.where((s) => vatRates[_satzSchluessel(s)] == true).toList();

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
  PosBusinessSettings merge(Map<String, dynamic> aenderung) {
    _pruefeAenderung('business', aenderung, _betriebSchluessel, legacyBusinessKeys);
    return PosBusinessSettings.fromJson(_mische(toJson(), aenderung));
  }

  /// Aus der Drahtform (schon mit den Standardwerten gemischt oder nicht).
  factory PosBusinessSettings.fromJson(Map<String, dynamic> roh) {
    const s = PosBusinessSettings();
    final g = _mische(s.toJson(), roh);
    final fremd = <String, Object>{};
    return PosBusinessSettings(
      logoText: _text(g['logoText'], s.logoText),
      logoEnabled: _bool(g['logoEnabled'], s.logoEnabled),
      logoSize: _wahl(g, 'logoSize', PosLogoSize.values, s.logoSize, fremd),
      watermark: _wahl(g, 'watermark', PosWatermark.values, s.watermark, fremd),
      color: _text(g['color'], s.color),
      theme: _wahl(g, 'theme', PosTheme.values, s.theme, fremd),
      fontSize: _wahl(g, 'fontSize', PosFontSize.values, s.fontSize, fremd),
      settingsFontSize: _wahl(g, 'settingsFontSize', PosSettingsFontSize.values, s.settingsFontSize, fremd),
      tileStyle: _wahl(g, 'tileStyle', PosTileStyle.values, s.tileStyle, fremd),
      clock: _bool(g['clock'], s.clock),
      lockScreen: _bool(g['lockScreen'], s.lockScreen),
      staffPhotos: _bool(g['staffPhotos'], s.staffPhotos),
      autoLogoutMinutes: _ausListe(g, 'autoLogoutMinutes', posAutoLogoutMinutes, s.autoLogoutMinutes, fremd),
      logoutAfterSale: _bool(g['logoutAfterSale'], s.logoutAfterSale),
      fastLogin: _bool(g['fastLogin'], s.fastLogin),
      showPrices: _bool(g['showPrices'], s.showPrices),
      showVat: _bool(g['showVat'], s.showVat),
      emoji: _bool(g['emoji'], s.emoji),
      categoryColors: _bool(g['categoryColors'], s.categoryColors),
      customAmountAllowed: _bool(g['customAmountAllowed'], s.customAmountAllowed),
      vatRates: _karte(g['vatRates'], s.vatRates),
      quantity: _wahl(g, 'quantity', PosQuantity.values, s.quantity, fremd),
      note: _bool(g['note'], s.note),
      search: _bool(g['search'], s.search),
      discount: _wahl(g, 'discount', PosDiscount.values, s.discount, fremd),
      payCash: _bool(g['payCash'], s.payCash),
      payCard: _bool(g['payCard'], s.payCard),
      paySplit: _bool(g['paySplit'], s.paySplit),
      cardProvider: _wahl(g, 'cardProvider', PosCardProvider.values, s.cardProvider, fremd),
      tip: _bool(g['tip'], s.tip),
      tipMode: _wahl(g, 'tipMode', PosTipMode.values, s.tipMode, fremd),
      tipSteps: _karte(g['tipSteps'], s.tipSteps),
      tipSplit: _bool(g['tipSplit'], s.tipSplit),
      change: _bool(g['change'], s.change),
      tipChips: _zahlenliste(g, 'tipChips', s.tipChips, fremd),
      exactCash: _bool(g['exactCash'], s.exactCash),
      checkoutMode: _wahl(g, 'checkoutMode', PosCheckoutMode.values, s.checkoutMode, fremd),
      receiptOutput: _wahl(g, 'receiptOutput', PosReceiptOutput.values, s.receiptOutput, fremd),
      doneScreenSeconds: _ausListe(g, 'doneScreenSeconds', posDoneScreenSeconds, s.doneScreenSeconds, fremd),
      logoImage: _text(g['logoImage'], s.logoImage),
      watermarkSide: _wahl(g, 'watermarkSide', PosWatermarkSide.values, s.watermarkSide, fremd),
      watermarkX: _ganz(g, 'watermarkX', -25, 125, s.watermarkX, fremd),
      watermarkY: _ganz(g, 'watermarkY', -25, 125, s.watermarkY, fremd),
      watermarkStrength: _ausListe(g, 'watermarkStrength', posWatermarkStrengths, s.watermarkStrength, fremd),
      logoScale: _wahl(g, 'logoScale', PosScale.values, s.logoScale, fremd),
      watermarkScale: _wahl(g, 'watermarkScale', PosScale.values, s.watermarkScale, fremd),
      glass: _bool(g['glass'], s.glass),
      hints: _bool(g['hints'], s.hints),
      discountChips: _zahlenliste(g, 'discountChips', s.discountChips, fremd),
      unknownValues: Map.unmodifiable(fremd),
    );
  }

  Map<String, dynamic> toJson() => {
        'logoText': logoText,
        'logoEnabled': logoEnabled,
        'logoSize': logoSize.value,
        'watermark': watermark.value,
        'color': color,
        'theme': theme.value,
        'fontSize': fontSize.value,
        'settingsFontSize': settingsFontSize.value,
        'tileStyle': tileStyle.value,
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
        'quantity': quantity.value,
        'note': note,
        'search': search,
        'discount': discount.value,
        'payCash': payCash,
        'payCard': payCard,
        'paySplit': paySplit,
        'cardProvider': cardProvider.value,
        'tip': tip,
        'tipMode': tipMode.value,
        'tipSteps': {...tipSteps},
        'tipSplit': tipSplit,
        'change': change,
        'tipChips': [...tipChips],
        'exactCash': exactCash,
        'checkoutMode': checkoutMode.value,
        'receiptOutput': receiptOutput.value,
        'doneScreenSeconds': doneScreenSeconds,
        'logoImage': logoImage,
        'watermarkSide': watermarkSide.value,
        'watermarkX': watermarkX,
        'watermarkY': watermarkY,
        'watermarkStrength': watermarkStrength,
        'logoScale': logoScale.value,
        'watermarkScale': watermarkScale.value,
        'glass': glass,
        'hints': hints,
        'discountChips': [...discountChips],
        ...unknownValues,
      };
}

// --------------------------------------------------------------- Geraeteteil

/// Was nur für dieses Gerät gilt (in der Kasse selbst eingestellt).
class PosDeviceSettings {
  const PosDeviceSettings({
    this.layout = PosLayout.right,
    this.categoryPosition = PosCategoryPosition.top,
    this.extraColumns = 0,
    this.tileHeight = PosTileHeight.m,
    this.touch = false,
    this.shortcuts = posShortcutDefaults,
    this.printerEnabled = false,
    this.printerType = PosPrinterType.sdp,
    this.printerIp = '',
    this.printerPort = 9100,
    this.printerBluetoothId = '',
    this.printerName = '',
    this.printerId = '',
    this.printerDeviceId = 'local_printer',
    this.connectPrinterId = '',
    this.paperSize = PosPaperSize.mm80,
    this.codePage = PosCodePage.cp1252,
    this.cut = PosCut.partial,
    this.qrMode = PosQrMode.auto,
    this.drawerEnabled = false,
    this.drawerAutoOpen = PosDrawerAutoOpen.cash,
    this.terminalIp = '',
    this.terminalPort = 8080,
    this.terminalTid = '',
    this.terminalVia = PosTerminalVia.direct,
    this.terminalType = PosTerminalType.none,
    this.shortcutHints = true,
    this.unknownValues = const {},
  });

  final PosLayout layout;
  final PosCategoryPosition categoryPosition;

  /// Zusätzliche Kachelspalten gegenüber der berechneten Breite (-2 bis 4).
  final int extraColumns;
  final PosTileHeight tileHeight;
  final bool touch;

  /// Tastenbelegung dieses Geräts. Aktionen, die dieses Paket nicht kennt
  /// (eine künftige des Servers), bleiben stehen.
  final Map<String, List<String>> shortcuts;
  final bool printerEnabled;
  final PosPrinterType printerType;
  final String printerIp;
  final int printerPort;
  final String printerBluetoothId;

  /// Wie sich der gemerkte Drucker nennt; ohne ihn stünde in den
  /// Einstellungen eine nackte Bluetooth-Adresse.
  final String printerName;

  /// Kennung des Netzwerk-Druckers (Server Direct Print, `listMyPrinters`);
  /// '' = keiner gewählt.
  final String printerId;

  /// ePOS Device-ID bei [PosPrinterType.network] (Epson direkt per IP).
  final String printerDeviceId;

  /// Kennung des Druckers im lokalen Kasseneck-Connect-Agenten, bei
  /// [PosPrinterType.connect].
  final String connectPrinterId;
  final PosPaperSize paperSize;
  final PosCodePage codePage;
  final PosCut cut;

  /// Welcher Druckbefehl den Signatur-QR erzeugt; [PosQrMode.auto] heißt
  /// unbestimmt.
  final PosQrMode qrMode;
  final bool drawerEnabled;
  final PosDrawerAutoOpen drawerAutoOpen;
  final String terminalIp;
  final int terminalPort;

  /// Terminal-ID aus dem Hobex-Vertrag (ohne führende Null).
  final String terminalTid;
  final PosTerminalVia terminalVia;

  /// Art des Terminals ([PosTerminalType.none] = keine Anbindung).
  final PosTerminalType terminalType;

  /// Tastenmarken (die kleinen Kürzel an den Knöpfen) anzeigen.
  final bool shortcutHints;

  /// Siehe [PosBusinessSettings.unknownValues].
  final Map<String, Object> unknownValues;

  /// Siehe [PosBusinessSettings.merge]; `shortcuts` wird je Aktion gemischt.
  PosDeviceSettings merge(Map<String, dynamic> aenderung) {
    _pruefeAenderung('device', aenderung, _geraetSchluessel, legacyDeviceKeys);
    return PosDeviceSettings.fromJson(_mische(toJson(), aenderung));
  }

  /// Aus der Drahtform (schon mit den Standardwerten gemischt oder nicht).
  factory PosDeviceSettings.fromJson(Map<String, dynamic> roh) {
    const s = PosDeviceSettings();
    final g = _mische(s.toJson(), roh);
    final fremd = <String, Object>{};
    return PosDeviceSettings(
      layout: _wahl(g, 'layout', PosLayout.values, s.layout, fremd),
      categoryPosition: _wahl(g, 'categoryPosition', PosCategoryPosition.values, s.categoryPosition, fremd),
      extraColumns: _ganz(g, 'extraColumns', -2, 4, s.extraColumns, fremd),
      tileHeight: _wahl(g, 'tileHeight', PosTileHeight.values, s.tileHeight, fremd),
      touch: _bool(g['touch'], s.touch),
      shortcuts: _tastenkarte(g['shortcuts'], s.shortcuts),
      printerEnabled: _bool(g['printerEnabled'], s.printerEnabled),
      printerType: _wahl(g, 'printerType', PosPrinterType.values, s.printerType, fremd),
      printerIp: _text(g['printerIp'], s.printerIp),
      printerPort: _ganz(g, 'printerPort', 1, 65535, s.printerPort, fremd),
      printerBluetoothId: _text(g['printerBluetoothId'], s.printerBluetoothId),
      printerName: _text(g['printerName'], s.printerName),
      printerId: _text(g['printerId'], s.printerId),
      printerDeviceId: _text(g['printerDeviceId'], s.printerDeviceId),
      connectPrinterId: _text(g['connectPrinterId'], s.connectPrinterId),
      paperSize: _wahl(g, 'paperSize', PosPaperSize.values, s.paperSize, fremd),
      codePage: _wahl(g, 'codePage', PosCodePage.values, s.codePage, fremd),
      cut: _wahl(g, 'cut', PosCut.values, s.cut, fremd),
      qrMode: _wahl(g, 'qrMode', PosQrMode.values, s.qrMode, fremd),
      drawerEnabled: _bool(g['drawerEnabled'], s.drawerEnabled),
      drawerAutoOpen: _wahl(g, 'drawerAutoOpen', PosDrawerAutoOpen.values, s.drawerAutoOpen, fremd),
      terminalIp: _text(g['terminalIp'], s.terminalIp),
      terminalPort: _ganz(g, 'terminalPort', 1, 65535, s.terminalPort, fremd),
      terminalTid: _text(g['terminalTid'], s.terminalTid),
      terminalVia: _wahl(g, 'terminalVia', PosTerminalVia.values, s.terminalVia, fremd),
      terminalType: _wahl(g, 'terminalType', PosTerminalType.values, s.terminalType, fremd),
      shortcutHints: _bool(g['shortcutHints'], s.shortcutHints),
      unknownValues: Map.unmodifiable(fremd),
    );
  }

  Map<String, dynamic> toJson() => {
        'layout': layout.value,
        'categoryPosition': categoryPosition.value,
        'extraColumns': extraColumns,
        'tileHeight': tileHeight.value,
        'touch': touch,
        'shortcuts': {for (final e in shortcuts.entries) e.key: [...e.value]},
        'printerEnabled': printerEnabled,
        'printerType': printerType.value,
        'printerIp': printerIp,
        'printerPort': printerPort,
        'printerBluetoothId': printerBluetoothId,
        'printerName': printerName,
        'printerId': printerId,
        'printerDeviceId': printerDeviceId,
        'connectPrinterId': connectPrinterId,
        'paperSize': paperSize.value,
        'codePage': codePage.value,
        'cut': cut.value,
        'qrMode': qrMode.value,
        'drawerEnabled': drawerEnabled,
        'drawerAutoOpen': drawerAutoOpen.value,
        'terminalIp': terminalIp,
        'terminalPort': terminalPort,
        'terminalTid': terminalTid,
        'terminalVia': terminalVia.value,
        'terminalType': terminalType.value,
        'shortcutHints': shortcutHints,
        ...unknownValues,
      };
}

// ------------------------------------------------------------------ Ganzes

class PosSettings {
  const PosSettings({required this.business, required this.device});

  /// Die Standardwerte, deckungsgleich mit Backend und Browser-Kasse.
  const PosSettings.standard()
      : business = const PosBusinessSettings(),
        device = const PosDeviceSettings();

  final PosBusinessSettings business;
  final PosDeviceSettings device;

  /// Standard + Gespeichertes in der Drahtform `{business, device}`. Was
  /// fehlt, bleibt beim Standard; ein Schlüssel, den der Standard nicht
  /// führt, bleibt draußen; ein Wert der inneren Form 0.x fällt auf den
  /// Standard; ein unbekannter englischer Wert bleibt wörtlich erhalten
  /// ([PosBusinessSettings.unknownValues]).
  ///
  /// **Zwischenspeicher der Version 9.x:** trägt die Map statt `business` und
  /// `device` die alten Teile `betrieb`/`geraet` (deutsche Schlüssel und
  /// Werte, so schrieb `toJson` bis 9.x), wird sie Feld für Feld übersetzt
  /// (Tabelle `renames-1.0.json`). Ein alter Stand geht so beim Update nicht
  /// verloren. Die Tastenkarte wird dabei wie am Server entwirrt
  /// ([untangleShortcuts]), damit die alten Vorgaben (`frei: Mod+F`) keine
  /// Doppelbelegung mit den neuen (`fullscreen: Mod+F`) ergeben. Übrige
  /// 9.x-Standardwerte im Stand (`terminalPort` 20008, `kassierenModus`
  /// `seite`) gelten als gesetzt, bis die erste Serverantwort
  /// (`getKasseSettings`, Benutzerliste) den Stand ersetzt.
  factory PosSettings.fromJson(Map<String, dynamic>? gespeichert) {
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
      // (`untangleShortcuts`): die gespeicherte Wahl gewinnt, eine beanspruchte
      // Vorgabe-Taste fällt bei der Aktion, die nicht gespeichert war (Mod+F
      // verliert das Vollbild, statt doppelt belegt zu sein).
      if (tasten is Map) {
        final gespeichert = <String, Object?>{
          for (final e in tasten.entries)
            if (!legacyShortcutActions.containsKey(e.key)) e.key.toString(): e.value,
        };
        uebersetzt['shortcuts'] = untangleShortcuts({...posShortcutDefaults, ...gespeichert}, gespeichert);
      }
      return uebersetzt;
    }

    return PosSettings(
      business: PosBusinessSettings.fromJson(teil('business', 'betrieb', legacyBusinessKeys)),
      device: PosDeviceSettings.fromJson(teil('device', 'geraet', legacyDeviceKeys)),
    );
  }

  Map<String, dynamic> toJson() => {'business': business.toJson(), 'device': device.toJson()};
}

// ------------------------------------------- Wertemengen, Aenderungen, Pruefung

/// Die Wertemenge je Betriebsfeld, soweit das Feld eine hat (Zwilling von
/// `POS_BUSINESS_VALUES`); dagegen prüft der Schreibweg vor dem Senden.
final Map<String, List<Object>> posBusinessValues = Map.unmodifiable({
  'logoSize': _werte(PosLogoSize.values),
  'watermark': _werte(PosWatermark.values),
  'theme': _werte(PosTheme.values),
  'fontSize': _werte(PosFontSize.values),
  'settingsFontSize': _werte(PosSettingsFontSize.values),
  'tileStyle': _werte(PosTileStyle.values),
  'autoLogoutMinutes': posAutoLogoutMinutes,
  'quantity': _werte(PosQuantity.values),
  'discount': _werte(PosDiscount.values),
  'cardProvider': _werte(PosCardProvider.values),
  'tipMode': _werte(PosTipMode.values),
  'checkoutMode': _werte(PosCheckoutMode.values),
  'receiptOutput': _werte(PosReceiptOutput.values),
  'doneScreenSeconds': posDoneScreenSeconds,
  'watermarkSide': _werte(PosWatermarkSide.values),
  'watermarkStrength': posWatermarkStrengths,
  'logoScale': _werte(PosScale.values),
  'watermarkScale': _werte(PosScale.values),
});

/// Wie [posBusinessValues] für die Geräte-Einstellungen (`POS_DEVICE_VALUES`).
final Map<String, List<Object>> posDeviceValues = Map.unmodifiable({
  'layout': _werte(PosLayout.values),
  'categoryPosition': _werte(PosCategoryPosition.values),
  'tileHeight': _werte(PosTileHeight.values),
  'printerType': _werte(PosPrinterType.values),
  'paperSize': _werte(PosPaperSize.values),
  'codePage': _werte(PosCodePage.values),
  'cut': _werte(PosCut.values),
  'qrMode': _werte(PosQrMode.values),
  'drawerAutoOpen': _werte(PosDrawerAutoOpen.values),
  'terminalVia': _werte(PosTerminalVia.values),
  'terminalType': _werte(PosTerminalType.values),
});

List<Object> _werte(List<PosSettingValue> werte) => List.unmodifiable([for (final w in werte) w.value]);

/// Die Felder, deren Wert dieses Paket nicht kennt, als Pfade
/// (`business.theme`, `device.shortcuts.<aktion>`). Die Oberfläche zeigt sie
/// als „vom Server, hier nicht einstellbar"; sie bleiben erhalten, solange nur
/// geänderte Felder geschrieben werden ([posSettingsChanges]). Zwilling von
/// `unknownPosSettingValues`.
List<String> unknownPosSettingValues(PosSettings settings) {
  final raus = <String>[
    for (final k in settings.business.unknownValues.keys) 'business.$k',
    for (final k in settings.device.unknownValues.keys) 'device.$k',
  ];
  for (final aktion in settings.device.shortcuts.keys) {
    if (!posShortcutActions.contains(aktion)) raus.add('device.shortcuts.$aktion');
  }
  return raus;
}

/// Was sich zwischen zwei Ständen eines Teils (`toJson` von Betrieb oder
/// Gerät) geändert hat, als Nutzlast für `saveBusiness` bzw.
/// `saveDevice`: **nur geänderte Felder** (der Server mischt; ein nicht
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
          if (posShortcutActions.contains(e.key)) e.key.toString(): e.value,
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
const Map<String, String> legacyBusinessKeys = {
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

/// Wie [legacyBusinessKeys] für den Geräteteil.
const Map<String, String> legacyDeviceKeys = {
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
const Map<String, String> legacyShortcutActions = {
  'kassieren': 'checkout', 'abschliessen': 'complete', 'abbrechen': 'cancel', 'frei': 'customAmount',
  'bar': 'cash', 'karte': 'card', 'passend': 'exactAmount', 'belege': 'receipts', 'letzteZurueck': 'undoLast',
  'einstellungen': 'settings', 'abmelden': 'logout', 'trinkgeld': 'tip', 'vollbild': 'fullscreen',
  'gegebenLeeren': 'clearTendered', 'korbLeeren': 'clearCart', 'getrennt': 'splitPayment',
};

/// Werte der inneren Form -> Draht, je Drahtfeld; gleichlautende Werte
/// (`gptom`, `S`) stehen nicht darin. Ein Test hält die Tabelle deckungsgleich
/// mit `renames-1.0.json` (`values.pos-settings-defaults.json`).
const Map<String, Map<String, String>> legacyValues = {
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
        for (final t in wert.entries) (legacyShortcutActions[t.key.toString()] ?? t.key.toString()): t.value,
      };
    } else if (wert is String) {
      wert = legacyValues[neu]?[wert] ?? wert;
    }
    raus[neu] = wert;
  }
  return raus;
}

/// Zwilling von `untangleShortcuts` (Backend, npm `stored`): Aktionen aus
/// [gespeichert] behalten ihre Tasten; jede andere Aktion verliert eine Taste,
/// die eine gespeicherte Aktion beansprucht, außer die beiden dürfen sie
/// teilen ([posShortcutSharedPairs]).
Map<String, Object?> untangleShortcuts(Map<String, Object?> gemischt, Map<String, Object?> gespeichert) {
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

final Set<String> _betriebSchluessel = const PosBusinessSettings().toJson().keys.toSet();
final Set<String> _geraetSchluessel = const PosDeviceSettings().toJson().keys.toSet();

void _pruefeAenderung(String teil, Map<String, dynamic> aenderung, Set<String> bekannt, Map<String, String> altform) {
  for (final e in aenderung.entries) {
    if (!bekannt.contains(e.key)) {
      final neu = altform[e.key];
      throw ArgumentError('$teil.${e.key}: unbekanntes Feld'
          '${neu != null && neu != e.key ? ' (Schluessel aus 9.x, heute $neu)' : ''}');
    }
    if (isLegacyValue0x(e.key, e.value)) {
      throw ArgumentError('$teil.${e.key}: Wert der inneren Form 0.x (${e.value}), '
          'heute ${legacyValues[e.key]![e.value]}');
    }
    final wert = e.value;
    if (e.key == 'shortcuts' && wert is Map) {
      for (final aktion in wert.keys) {
        final neu = legacyShortcutActions[aktion];
        if (neu != null) throw ArgumentError('$teil.shortcuts.$aktion: Tasten-Aktion aus 9.x, heute $neu');
      }
    }
  }
}

/// Ist [value] ein Wert der inneren Form 0.x für dieses Drahtfeld?
bool isLegacyValue0x(String feld, Object? wert) => legacyValues[feld]?.containsKey(wert) ?? false;

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
          if (!(key == 'shortcuts' && legacyShortcutActions.containsKey(k.key))) k.key.toString(): k.value,
      };
    } else if (wert != null) {
      if (isLegacyValue0x(key, wert)) continue;
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
T _wahl<T extends PosSettingValue>(Map<String, dynamic> g, String feld, List<T> werte, T standard, Map<String, Object> fremd) {
  final wert = g[feld];
  for (final e in werte) {
    if (e.value == wert) return e;
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
