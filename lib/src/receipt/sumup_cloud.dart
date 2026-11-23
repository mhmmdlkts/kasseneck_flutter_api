/// Der SumUp-Block einer Kartenzahlung ueber die Cloud-API (SumUp Solo,
/// `providerData.channel == 'cloud'`), gemeinsam fuer den Bon ohne
/// Server-Layout (`PrintPaper`), die Anzeige (`KeckReceiptWidget`) und die
/// Frage, ob ein geliefertes Layout den Block zeigen muss
/// (`KasseneckReceipt.cardPayments`). Zwilling des Cloud-Zweigs von
/// `sumupBlock` in `receipt/layout.ts` (npm 1.43.0).
///
/// Der Cloud-Weg kennt nicht jeden Wert, den das SDK liefert (etwa keinen
/// Zahlungstyp): was fehlt, entfaellt als Zeile, ein „n/a“ waere eine
/// Behauptung ueber eine Zahlung, die der Beleg nicht kennt. Ohne
/// Transaktionscode und ohne Endziffern (Handbeleg einer ungeklaerten
/// Zahlung, Rueckbuchungszeile am Storno) gibt es nichts, was ein Kartenbeleg
/// zeigen koennte: dann steht gar kein Block da. Der Autorisierungscode steht
/// in den Anbieterdaten, aber nie auf dem Bon. Zahlungen ueber das SDK
/// betrifft das nicht; ihr Block bleibt, wie er war.
library;

/// Die Zeilen des Blocks unter der Ueberschrift, in Druckreihenfolge.
/// `null`: keine Cloud-Zahlung (der SDK-Block gilt). Leer: kein Block.
List<({String label, String value})>? sumupCloudLines(Map<String, dynamic> data) {
  if (data['channel'] != 'cloud') return null;
  String feld(String schluessel) {
    final wert = data[schluessel];
    return wert == null ? '' : '$wert';
  }

  final code = feld('transactionCode');
  final ziffern = feld('cardLastDigits');
  if (code.isEmpty && ziffern.isEmpty) return const [];
  final betrag = _sumupBetrag(data['amount']);
  return [
    if (feld('cardType').isNotEmpty) (label: 'Kartentyp:', value: feld('cardType')),
    if (ziffern.isNotEmpty) (label: 'Kartennummer:', value: '**** **** **** $ziffern'),
    if (feld('paymentType').isNotEmpty) (label: 'Zahlungstyp:', value: feld('paymentType')),
    if (betrag != null) (label: 'Gesamtbetrag:', value: '$betrag ${feld('currency')}'.trim()),
    if (code.isNotEmpty) (label: 'Transaktionscode:', value: code),
    if (feld('entryMode').isNotEmpty) (label: 'Modus:', value: feld('entryMode').toUpperCase()),
  ];
}

/// Hat die Zahlung keinen Block? Nur eine Cloud-Zahlung ohne Transaktionscode
/// und ohne Endziffern; ein geliefertes Layout muss sie nicht zeigen.
bool isSumupCloudWithoutBlock(Map<String, dynamic> data) => sumupCloudLines(data)?.isEmpty ?? false;

final RegExp _dezimal = RegExp(r'^-?\d+(\.\d+)?$');

/// SumUp liefert `amount` in Euro (auch eine ganze Zahl ist Euro, nie Cent);
/// ein Text mit Punkt wird gelesen. Alles andere: `null`, die Zeile entfaellt.
String? _sumupBetrag(Object? roh) {
  final num? zahl = switch (roh) {
    num n => n,
    String s when _dezimal.hasMatch(s.trim()) => double.parse(s.trim()),
    _ => null,
  };
  if (zahl == null || !zahl.isFinite) return null;
  return zahl.toStringAsFixed(2).replaceAll('.', ',');
}
