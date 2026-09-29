/// Die Kasse am Tresen: Einstellungen, Warenkorb, Kassieren und Belege —
/// gemeinsam von Browser-Kasse und App.
///
/// Zwilling von `kasse/settings.ts` bzw. `client/receipts.ts` im JS-Paket und
/// von `functions/kasse-settings-core.js` im Backend. Die Golden-Datei
/// `fixtures/pos-settings-defaults.json` hält die Standardwerte deckungsgleich.
library;

// Die Typen, die in dieser Schnittstelle vorkommen, gehoeren mit dazu: wer den
// Warenkorb benutzt, braucht Steuersatz, Belegposition und Zahlungsart.
export 'enums/keck_payment_method.dart';
export 'enums/vat_rate.dart';
// Wer mit Karte kassiert, benennt den Anbieter am Verkauf — ohne diesen Export
// braeuchte die Kasse einen zweiten Import fuer ein einziges Argument.
export 'enums/credit_card_provider.dart';
export 'models/kasseneck_item.dart';
export 'models/kasseneck_receipt.dart';
export 'models/registration_info.dart';
export 'src/receipt/codes.dart'
    show
        cancellationErrorCodes,
        cancellationStatuses,
        isReceiptErrorCode,
        paymentErrorCodes,
        receiptEmailErrorCodes,
        receiptEmailSendErrorCodes,
        receiptEmailVias,
        receiptErrorCodes;
// Wer einen Beleg einliest, muss den Lesefehler fangen koennen: er traegt die
// receiptId eines bereits signierten Belegs.
export 'src/register/fehler.dart' show KasseneckReceiptFormatError;
// Welcher Fehler welchen Satz bekommt, entscheidet der Ausgang: ohne diese
// beiden Namen liesse sich [messageOutcome] aus diesem Barrel nicht lesen.
export 'src/register/fehler.dart' show ErrorOutcome, isOutcomeUnknown;
// Wer Trinkgeld zuweist, braucht die Personenliste und den Anteil, der daraus
// entsteht.
export 'models/keck_tip.dart';
export 'models/keck_tip_person.dart';
// Mehrere Zahlungen je Beleg: Eingabe am Verkauf/Storno, Zahlung am Beleg.
export 'models/keck_payment.dart' show KeckPayment, KeckPaymentInput, paymentsError, maxPayments;
// Die Storno-Regeln fragen nach der Reichweite eines Rechts; wer sie benutzt,
// braucht den Typ.
export 'src/register/pairing.dart' show RegisterScope;
export 'src/kasse/artikel.dart';
export 'src/kasse/testkennzeichen.dart';
export 'src/kasse/belege.dart';
export 'src/kasse/belegliste.dart';
export 'src/kasse/belegmail.dart';
export 'src/kasse/codes.dart';
export 'src/kasse/drucker.dart';
export 'src/kasse/einstellungen.dart';
export 'src/kasse/farbe.dart';
export 'src/kasse/thema.dart';
export 'src/kasse/einstellungen_client.dart';
export 'src/kasse/kacheln.dart';
export 'src/kasse/kassieren.dart';
export 'src/kasse/storno.dart';
export 'src/kasse/texte.dart';
export 'src/kasse/warenkorb.dart';
export 'src/kasse/zahlungen.dart';
