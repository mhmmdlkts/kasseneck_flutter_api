/// Rueckgabe-Wahl beim Storno (Lager-Kern Stufe 2) – Zwilling von
/// `RETURN_DISPOSITIONS` in `models/cancellation.ts` des JS-Pakets (Katalog
/// `RUECKGABE` des Backends).
///
/// Wohin die Ware einer stornierten Artikelzeile geht: `restock` zurueck ins
/// Lager (Vorgabe des Servers), `defective` als defekt ins Lager, `disposed`
/// entsorgt. Sie wirkt nur an Positionen mit `articleId`; alle anderen bucht
/// der Server nie und meldet dafuer auch keinen Fehler. Dieselbe Liste gilt
/// fuer Gutschrift und Rechnungsstorno der Rechnungs-API.
library;

/// Die Werte der Rueckgabe-Wahl, englisch wie am Draht, in der Reihenfolge
/// des Vertrags.
const List<String> returnDispositions = ['restock', 'defective', 'disposed'];

/// Rueckgabe-Wahl als Typ; der Name ist der Wert am Draht
/// (`ReturnDisposition.defective.name` = `'defective'`).
enum ReturnDisposition { restock, defective, disposed }

/// Ist [value] eine Rueckgabe-Wahl aus [returnDispositions]? Der innere
/// deutsche Wert (`lager`, `defekt`, `entsorgt`) ist keine.
bool isReturnDisposition(Object? value) => value is String && returnDispositions.contains(value);
