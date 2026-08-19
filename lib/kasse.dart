/// Kassen-Einstellungen der Browser- und der App-Kasse.
///
/// Zwilling von `kasse/settings.ts` im JS-Paket und von
/// `functions/kasse-settings-core.js` im Backend. Die Golden-Datei
/// `fixtures/kasse-settings-standard.json` hält die Standardwerte deckungsgleich.
library;

// Die Typen, die in dieser Schnittstelle vorkommen, gehoeren mit dazu: wer den
// Warenkorb benutzt, braucht Steuersatz, Belegposition und Zahlungsart.
export 'enums/keck_payment_method.dart';
export 'enums/vat_rate.dart';
export 'models/kasseneck_item.dart';
export 'src/kasse/einstellungen.dart';
export 'src/kasse/kassieren.dart';
export 'src/kasse/warenkorb.dart';
