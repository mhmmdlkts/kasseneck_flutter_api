import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/kasse.dart';

/// Ein Beleg aus einer Test-Umgebung muss sich zu erkennen geben.
///
/// **Sonst ist er von einem echten nicht zu unterscheiden** — und landet
/// womöglich in einer Buchhaltung. Erkannt wird an zwei Dingen: am Feld des
/// Backends und, unabhängig davon, am Signatur-QR. Die zweite Quelle ist die
/// verlässlichere: `_R1-AT100_` ist das ZDA-Kennzeichen des Testpfads und
/// steht im Beleg selbst, nicht in einer Antwort, die jemand vergessen kann
/// mitzuschicken.

void main() {
  test('der Testpfad wird am QR erkannt', () {
    expect(signaturIstTest('_R1-AT100_KASSE1_...'), isTrue);
  });

  test('eine echte Signatur nicht', () {
    for (final qr in ['_R1-AT1_KASSE1_...', '_R1-AT0_x', '', '_R1-AT1000_x']) {
      expect(signaturIstTest(qr), isFalse, reason: qr);
    }
  });

  test('das Kennzeichen greift auch ohne Feld vom Backend', () {
    // Ältere Backends senden `testKasse` nicht. Der QR ist trotzdem da.
    expect(belegIstTest(testKasse: false, qr: '_R1-AT100_x'), isTrue);
  });

  test('und auch ohne QR, wenn das Backend es sagt', () {
    expect(belegIstTest(testKasse: true, qr: null), isTrue);
  });

  test('ein gewöhnlicher Beleg bleibt ungekennzeichnet', () {
    expect(belegIstTest(testKasse: false, qr: '_R1-AT1_x'), isFalse);
  });
}
