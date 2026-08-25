import 'package:flutter_test/flutter_test.dart';
import 'package:kasseneck_api/kasse.dart';

void main() {
  group('KeckTipPerson', () {
    test('liest die drei Felder', () {
      final p = KeckTipPerson.aus({'registerUserId': 'a', 'name': 'Anna', 'owner': true});
      expect(p.registerUserId, 'a');
      expect(p.name, 'Anna');
      expect(p.owner, isTrue);
    });

    test('owner ist nur bei echtem true wahr', () {
      expect(KeckTipPerson.aus({'registerUserId': 'a', 'name': 'A', 'owner': 'ja'}).owner, isFalse);
      expect(KeckTipPerson.aus({'registerUserId': 'a', 'name': 'A'}).owner, isFalse);
    });

    test('mit(cents:) macht daraus einen Empfaenger-Anteil', () {
      final p = KeckTipPerson.aus({'registerUserId': 'a', 'name': 'Anna', 'owner': false});
      final anteil = p.mit(cents: 500);
      expect(anteil.registerUserId, 'a');
      expect(anteil.cents, 500);
    });

    test('ein Anteil <= 0 faellt hier, nicht erst am Server', () {
      final p = KeckTipPerson.aus({'registerUserId': 'a', 'name': 'Anna'});
      expect(() => p.mit(cents: 0), throwsA(isA<ArgumentError>()));
    });
  });
}
