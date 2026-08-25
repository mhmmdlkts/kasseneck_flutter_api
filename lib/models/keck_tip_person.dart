import 'keck_tip.dart';

/// Eine Person, der sich Trinkgeld zuweisen lässt.
///
/// Bewusst drei Felder — Kennung, Anzeigename, [owner]. Wer die Liste
/// abruft, braucht nicht die Rechtestruktur des Betriebs zu sehen.
///
/// [owner] ist keine Anzeigefrage: Davon hängt ab, ob die Position am Beleg
/// „Trinkgeld" heißt (Inhaber — Entgelt des Betriebs) oder „Trinkgeld Personal"
/// (durchlaufender Posten). Entschieden wird das im Backend; hier reist es mit,
/// damit eine Oberfläche es zeigen kann.
class KeckTipPerson {
  const KeckTipPerson({required this.registerUserId, required this.name, required this.owner});

  factory KeckTipPerson.aus(Map<String, dynamic> roh) => KeckTipPerson(
        registerUserId: roh['registerUserId'] is String ? roh['registerUserId'] as String : '',
        name: roh['name'] is String ? roh['name'] as String : '',
        owner: roh['owner'] == true,
      );

  final String registerUserId;
  final String name;

  /// true: Inhaber — das Trinkgeld ist Entgelt des Betriebs. Dieselben
  /// Feldnamen wie der Empfänger am Beleg-Item (`tipRecipientId`,
  /// `tipRecipientName`, `isOwnerTip` lesen genau diese Schlüssel).
  ///
  /// Nicht nullbar, und ein fehlendes oder nicht-`true`-Feld wird zu `false`:
  /// Von diesem Flag hängt die steuerliche Behandlung ab (Entgelt des Betriebs
  /// gegen durchlaufender Posten). Ein `bool?` zwänge jeden Aufrufer, sich bei
  /// genau dieser Frage etwas für „unbekannt" auszudenken — und der Aufruf
  /// liefert immer ein echtes Boolean.
  final bool owner;

  /// Anteil für diese Person. Der wahrscheinlichste Fehler eines Aufrufers ist,
  /// eine Kennung von Hand zu übertragen und dabei eine zu erwischen, die der
  /// Server ablehnt — wer die Liste benutzt, kann nicht danebengreifen.
  KeckTipRecipient mit({required int cents}) {
    if (cents <= 0) throw ArgumentError.value(cents, 'cents', 'Anteil muss > 0 sein');
    return KeckTipRecipient(registerUserId: registerUserId, cents: cents);
  }
}
