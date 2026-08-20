/// Ob ein Beleg aus einer Test-Umgebung stammt.
///
/// **Ein solcher Beleg muss sich zu erkennen geben.** Sonst ist er von einem
/// echten nicht zu unterscheiden und landet womöglich in einer Buchhaltung.
///
/// Zwei Quellen, und die zweite ist die verlässlichere:
///
/// 1. `testKasse` aus der Antwort des Backends.
/// 2. Der Signatur-QR selbst. `_R1-AT100_` ist das ZDA-Kennzeichen des
///    Testpfads — es steht **im Beleg**, nicht in einer Antwort, die jemand
///    vergessen kann mitzuschicken. Ältere Backends senden das Feld gar nicht.
library;

/// Trägt der Beleg eine Test-Signatur? Erkannt am ZDA-Kennzeichen `AT100`.
///
/// Der Unterstrich am Ende ist Absicht: ohne ihn träfe die Prüfung auch auf
/// ein künftiges `AT1000` zu.
bool signaturIstTest(String? qr) => (qr ?? '').startsWith('_R1-AT100_');

/// Beides zusammen — so entscheidet die Anzeige.
bool belegIstTest({required bool testKasse, String? qr}) =>
    testKasse || signaturIstTest(qr);
