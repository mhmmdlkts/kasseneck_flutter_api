import 'package:kasseneck_api/enums/keck_payment_method.dart';

/// Ein Trinkgeld-Empfänger: ein Kassen-Benutzer und sein Anteil.
///
/// [registerUserId] ist die ID unter `users/{uid}/register_users`. Ob der
/// Anteil am Ende Umsatz ist (Inhaber) oder durchlaufender Posten
/// (Mitarbeiter), entscheidet das Backend anhand des `inhaber`-Flags dieses
/// Benutzers — nicht der Aufrufer. Deshalb gibt es hier keinen Schalter dafür.
class KeckTipRecipient {
  final String registerUserId;

  /// Anteil in **Cent** (> 0).
  final int cents;

  const KeckTipRecipient({required this.registerUserId, required this.cents});

  /// Komfort-Konstruktor mit Anteil in **Euro** (einmalige Rundung auf Cent).
  factory KeckTipRecipient.euro({
    required String registerUserId,
    required double amount,
  }) {
    return KeckTipRecipient(
      registerUserId: registerUserId,
      cents: (amount * 100).round(),
    );
  }

  Map<String, dynamic> toJson() => {
        'registerUserId': registerUserId,
        'cents': cents,
      };
}

/// Trinkgeld auf einem Beleg.
///
/// Der Aufrufer schickt nur den Betrag (und wer ihn bekommt); die
/// Belegpositionen erzeugt das Backend. Das ist Absicht: Trinkgeld ist
/// steuerlich zweierlei — an Mitarbeiter ein durchlaufender Posten mit 0 %
/// (Erlass 2.4.6 / 2.4.2.1), an den Inhaber Entgelt nach § 4 UStG, das
/// anteilig auf die Steuersätze der Warenpositionen fällt. Diese Rechnung
/// gehört an eine Stelle, und die steht im Backend.
///
/// Ohne [recipients] bekommt der angemeldete Kassen-Benutzer das Trinkgeld;
/// gibt es keinen (Anmeldung über API-Schlüssel), bleibt es „nicht
/// zugeordnet" — der Beleg stimmt dann, der Bericht je Person aber nicht.
/// Wer auswerten will, wem was zusteht, gibt [recipients] an.
///
/// ```dart
/// await api.sellReceipt(
///   paymentMethod: KeckPaymentMethod.creditCard,
///   items: [...],
///   tip: KeckTip.fuer('ru_7', cents: 200),
/// );
/// ```
class KeckTip {
  /// Gesamtbetrag in **Cent** (> 0).
  final int cents;

  /// Zahlart des Trinkgelds. Ohne Angabe gilt die des Belegs — bar bezahlen
  /// und am Terminal Trinkgeld geben ist damit möglich.
  final KeckPaymentMethod? paymentMethod;

  /// Aufteilung auf Kassen-Benutzer. Ohne Angabe: angemeldeter Benutzer.
  final List<KeckTipRecipient>? recipients;

  /// Hat der Empfänger das Geld schon? `true` = ja (Bargeld mitgenommen,
  /// Kartentrinkgeld sofort aus der Lade ausgezahlt), `false` = der Betrieb
  /// behält es und schuldet es.
  ///
  /// Entscheidend ist **nicht die Zahlart**, sondern der Besitz — § 2j Abs 2
  /// AVRAG kennt beide Fälle. Ohne Angabe gilt die Voreinstellung des Betriebs
  /// (bar: schon erhalten, bargeldlos: einbehalten); das ist der Normalfall,
  /// und diese Angabe braucht es nur für die Ausnahme.
  ///
  /// **Nur mit dem Recht `tipAssign`** bei persönlicher Anmeldung: das Merkmal
  /// entscheidet, ob der Betrieb Geld schuldet, und gewöhnliches Personal soll
  /// das nicht am Gerät umstellen können. Über einen Geräte-API-Schlüssel
  /// (ohne angemeldeten Kassen-Benutzer) gilt die Einschränkung nicht.
  final bool? sofortErhalten;

  const KeckTip({
    required this.cents,
    this.paymentMethod,
    this.recipients,
    this.sofortErhalten,
  });

  /// Komfort-Konstruktor mit Betrag in **Euro** (einmalige Rundung auf Cent).
  factory KeckTip.euro({
    required double amount,
    KeckPaymentMethod? paymentMethod,
    List<KeckTipRecipient>? recipients,
    bool? sofortErhalten,
  }) {
    return KeckTip(
      cents: (amount * 100).round(),
      paymentMethod: paymentMethod,
      recipients: recipients,
      sofortErhalten: sofortErhalten,
    );
  }

  /// Der 90-%-Fall: alles an eine Person.
  factory KeckTip.fuer(
    String registerUserId, {
    required int cents,
    KeckPaymentMethod? paymentMethod,
    bool? sofortErhalten,
  }) {
    return KeckTip(
      cents: cents,
      paymentMethod: paymentMethod,
      sofortErhalten: sofortErhalten,
      recipients: [
        KeckTipRecipient(registerUserId: registerUserId, cents: cents),
      ],
    );
  }

  /// Betrag in Euro (Anzeige/Format — für Arithmetik [cents] nutzen).
  double get amount => cents / 100;

  /// Was am Trinkgeld nicht stimmt — `null`, wenn alles passt.
  ///
  /// Zwilling der Prüfungen in `tip-core.normalizeTip` des Backends, Wortlaut
  /// inklusive: Wer den Fehler hier sieht, sieht denselben Satz wie der, der
  /// ihn vom Server bekommt. Geprüft wird hier trotzdem, damit ein Tippfehler
  /// nicht erst nach einem Netzweg auffällt.
  String? get fehler {
    if (cents <= 0) {
      return 'Trinkgeld: Betrag muss eine ganze Zahl in Cent > 0 sein';
    }
    final e = recipients;
    if (e == null) return null;
    if (e.isEmpty) {
      return 'Trinkgeld: Empfängerliste darf nicht leer sein';
    }
    final ids = <String>{};
    var summe = 0;
    for (final r in e) {
      if (r.registerUserId.trim().isEmpty) {
        return 'Trinkgeld: Kassen-Benutzer fehlt';
      }
      if (!ids.add(r.registerUserId)) {
        return 'Trinkgeld: Kassen-Benutzer ${r.registerUserId} doppelt';
      }
      if (r.cents <= 0) {
        return 'Trinkgeld: Betrag muss eine ganze Zahl in Cent > 0 sein';
      }
      summe += r.cents;
    }
    if (summe != cents) {
      return 'Trinkgeld: Summe der Empfänger ($summe) entspricht nicht dem '
          'Betrag ($cents)';
    }
    return null;
  }

  bool get isValid => fehler == null;

  /// Langform, immer.
  ///
  /// Das Backend nimmt auch die Kurzform (`"tip": 200`), aber eine Gestalt ist
  /// im Protokoll leichter zu lesen als zwei, und der Unterschied ist rein
  /// äußerlich: `{cents: 200}` ohne Empfänger tut genau dasselbe.
  Map<String, dynamic> toJson() => {
        'cents': cents,
        if (paymentMethod != null) 'paymentMethod': paymentMethod!.name,
        if (recipients != null)
          'recipients': recipients!.map((r) => r.toJson()).toList(),
        // Nur mitschicken, wenn gesetzt: fehlt das Feld, entscheidet die
        // Voreinstellung des Betriebs. Ein `false` wäre dort eine Aussage,
        // kein Weglassen.
        if (sofortErhalten != null) 'sofortErhalten': sofortErhalten,
      };
}
