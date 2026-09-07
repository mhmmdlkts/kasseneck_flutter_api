enum CreditCardProvider {
  gpTomAndroid,
  gpTomIos,
  hobexCloudApi,
  hobexHps,
  sumup,
  myposPro,
  stripe,
  custom
}

/// Die Überschrift des Kartenzahlungsblocks je Anbieter.
///
/// Eine Quelle für zwei Leser: den Bon-Bauer (`PrintPaper`) und die Frage, ob
/// ein geliefertes Zeilenmodell die Zahlung überhaupt zeigt
/// (`KasseneckReceipt.layoutIstVollstaendig`). Stünden die Wörter zweimal
/// getippt da, könnte die Prüfung ins Leere greifen, sobald jemand eine
/// Überschrift ändert — und ein stillschweigend falsches „vollständig" ist
/// genau der Fehler, den sie verhindern soll.
///
/// `custom` fehlt bewusst: ein eigener Anbieter bringt keine Terminaldaten mit
/// und bekommt deshalb keinen Block.
const Map<CreditCardProvider, String> kartenblockUeberschrift = {
  CreditCardProvider.hobexHps: 'Hobex Beleg',
  CreditCardProvider.hobexCloudApi: 'Hobex Beleg',
  CreditCardProvider.sumup: 'Sumup Beleg',
  CreditCardProvider.myposPro: 'MyPos Beleg',
  CreditCardProvider.gpTomAndroid: 'GP Tom Beleg',
  CreditCardProvider.gpTomIos: 'GP Tom Beleg',
  CreditCardProvider.stripe: 'Online-Zahlung (Stripe)',
};
