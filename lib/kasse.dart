/// Die Kasse am Tresen: Einstellungen, Warenkorb, Kassieren und Belege —
/// gemeinsam von Browser-Kasse und App.
///
/// Zwilling von `kasse/settings.ts` bzw. `client/receipts.ts` im JS-Paket und
/// von `functions/kasse-settings-core.js` im Backend. Die Golden-Datei
/// `fixtures/kasse-settings-standard.json` hält die Standardwerte deckungsgleich.
library;

// Die Typen, die in dieser Schnittstelle vorkommen, gehoeren mit dazu: wer den
// Warenkorb benutzt, braucht Steuersatz, Belegposition und Zahlungsart.
export 'enums/keck_payment_method.dart';
export 'enums/vat_rate.dart';
export 'models/kasseneck_item.dart';
export 'models/kasseneck_receipt.dart';
// Wer einen Beleg einliest, muss den Lesefehler fangen koennen: er traegt die
// receiptId eines bereits signierten Belegs.
export 'src/register/fehler.dart' show KasseneckReceiptFormatError;
// Wer Trinkgeld zuweist, braucht die Personenliste und den Anteil, der daraus
// entsteht.
export 'models/keck_tip.dart';
export 'models/keck_tip_person.dart';
// Die Storno-Regeln fragen nach der Reichweite eines Rechts; wer sie benutzt,
// braucht den Typ.
export 'src/register/pairing.dart' show RegisterScope;
export 'src/kasse/artikel.dart';
export 'src/kasse/testkennzeichen.dart';
export 'src/kasse/belege.dart';
export 'src/kasse/belegliste.dart';
export 'src/kasse/einstellungen.dart';
export 'src/kasse/farbe.dart';
export 'src/kasse/thema.dart';
export 'src/kasse/einstellungen_client.dart';
export 'src/kasse/kacheln.dart';
export 'src/kasse/kassieren.dart';
export 'src/kasse/storno.dart';
export 'src/kasse/warenkorb.dart';
