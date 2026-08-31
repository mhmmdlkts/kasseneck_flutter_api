/// Was ein Betrieb ueber die Schnittstelle mitbringen darf -- Feld fuer Feld.
///
/// **Unbekannte Felder werden abgewiesen, nicht stillschweigend verworfen.**
/// Vorher verschwand ein `iban` oder ein vertippter Feldname spurlos: der
/// Partner glaubte, er habe die Steuernummer geschickt, und Kasseneck hatte
/// nichts. Ein Feld, das man schickt und das nichts bewirkt, ist der teuerste
/// Fehler in einer Schnittstelle, weil ihn niemand bemerkt.
///
/// Seitdem antwortet `createPartnerCustomer` mit `validation` und dem genauen
/// Feldpfad -- verschachtelt und je Kontakt: `address.land`,
/// `tax_details.ustid`, `contacts.1.abteilung`.
///
/// Der Betrieb geht hier als `Map<String, dynamic>` hinaus (siehe
/// `PartnerApi.createPartnerCustomer`), es gibt also keine Typpruefung, die
/// ein ueberzaehliges Feld beim Uebersetzen faende. Genau dafuer ist
/// [unbekannteBetriebsfelder] da: dieselbe Ableitung wie im Backend, also
/// dieselben Pfade wie in `data.errors[].field` -- vor dem Senden statt danach.
///
/// **Die Wahrheit bleibt der Server.** Dieser Client weist nichts von sich aus
/// ab: eine spaetere Backend-Fassung darf ein Feld ergaenzen, ohne dass ein
/// aelterer Client es blockiert. [unbekannteBetriebsfelder] ist die Vorschau,
/// nicht das Tor.
///
/// Quelle der Liste: `partner-core.BETRIEB_FELDER` im Backend; der Zwilling in
/// JavaScript ist `src/partner/betrieb.ts`.
library;

/// Jedes erlaubte Feld als Pfad. `[]` markiert eine Liste -- im Fehlerpfad des
/// Servers steht dort der Index (`contacts.0.name`).
///
/// Bewusst flach und nicht verschachtelt: so ist es EINE Liste, die der
/// Zwilling Zeile fuer Zeile nachhalten kann. Das Schema fuer die Pruefung
/// entsteht daraus und nicht daneben.
const List<String> kBetriebFelder = <String>[
  'companyName',
  'legalForm',
  'state',
  'industry',
  'companyRegister',
  'court',
  'web',
  'phone',
  'email',
  'billingEmail',
  'address.street',
  'address.number',
  'address.zip',
  'address.city',
  'taxDetails.taxNumber',
  'taxDetails.vatId',
  'taxDetails.gln',
  'taxDetails.smallBusiness',
  'contacts[].name',
  'contacts[].email',
  'contacts[].phone',
  'contacts[].roles',
  'taxAdvisor.name',
  'taxAdvisor.email',
  'taxAdvisor.phone',
  'taxAdvisor.mayContact',
];

/// Ein Knoten des abgeleiteten Schemas: entweder ein einfacher Wert, ein
/// Objekt mit Unterfeldern oder eine Liste solcher Objekte.
class _Knoten {
  _Knoten({this.liste = false});

  final bool liste;
  final Map<String, _Knoten> felder = <String, _Knoten>{};

  bool get einfach => felder.isEmpty && !liste;
}

/// Das Schema entsteht aus [kBetriebFelder] -- eine Quelle, keine zweite Liste.
final Map<String, _Knoten> _schema = () {
  final wurzel = <String, _Knoten>{};
  for (final pfad in kBetriebFelder) {
    final teile = pfad.split('.');
    var stand = wurzel;
    for (var i = 0; i < teile.length; i++) {
      final roh = teile[i];
      final liste = roh.endsWith('[]');
      final name = liste ? roh.substring(0, roh.length - 2) : roh;
      final knoten = stand.putIfAbsent(name, () => _Knoten(liste: liste));
      if (i == teile.length - 1) break;
      stand = knoten.felder;
    }
  }
  return wurzel;
}();

void _sammle(Object? eingabe, Map<String, _Knoten> schema, String pfad, List<String> raus) {
  if (eingabe is! Map) return;
  for (final eintrag in eingabe.entries) {
    final name = '${eintrag.key}';
    final voll = pfad.isEmpty ? name : '$pfad.$name';
    final erlaubt = schema[name];
    if (erlaubt == null) {
      raus.add(voll);
      continue;
    }
    if (erlaubt.einfach) continue;
    if (erlaubt.liste) {
      // Ein falscher Typ ist kein unbekanntes Feld -- den meldet der Server
      // als eigenen Formfehler auf demselben Pfad.
      final wert = eintrag.value;
      if (wert is! List) continue;
      for (var i = 0; i < wert.length; i++) {
        _sammle(wert[i], erlaubt.felder, '$voll.$i', raus);
      }
      continue;
    }
    _sammle(eintrag.value, erlaubt.felder, voll, raus);
  }
}

/// Die Feldpfade eines Betriebs, die [kBetriebFelder] nicht kennt -- dieselben
/// Pfade, die der Server in `data.errors[].field` nennen wuerde. Leer heisst:
/// aus dieser Sicht ist nichts ueberzaehlig.
///
/// Sagt **nichts** ueber die Werte: Steuernummer, UID, PLZ und Gericht prueft
/// das Backend mit `kreiseck_validator`. Diese Funktion beantwortet nur die
/// Frage "schicke ich etwas, das dort niemand erwartet?".
List<String> unbekannteBetriebsfelder(Object? betrieb) {
  final raus = <String>[];
  _sammle(betrieb, _schema, '', raus);
  return raus;
}
