/// Rabatt-Vorlagen der Kasse (benannte Rabatt-Chips): wirksame Liste,
/// Chip-Text, Spiegelung nach `discountChips`, Pruefung und Bon-Block.
/// Zwilling von `pos/rabatt-vorlagen.ts` im npm-Paket (1.31.0); der Vertrag sind
/// die Pruefaelle `discount-preset-cases.json`, byte-gleich mit dem Backend.
library;

import 'einstellungen.dart';
import 'schicht.dart' show ShiftDiscount;
import 'texte.dart';

/// Fehlercode, den der Server bei einer ungueltigen Vorlage sendet.
const String invalidDiscountPreset = 'invalid_discount_preset';

/// Hoechstzahl der Vorlagen.
const int discountPresetsMax = 5;

/// Laenge des Namens in Zeichen (nach dem Trimmen).
const int discountPresetNameMax = 24;

/// Prozent in Basispunkten: 0,1 % bis 100 % in Schritten von 0,1 %.
const ({int min, int max, int step}) discountPresetPercentBp = (min: 10, max: 10000, step: 10);

/// Betrag in Cent: 0,01 € bis 1.000.000,00 €.
const ({int min, int max}) discountPresetAmountCents = (min: 1, max: 100000000);

/// Wirksame Vorlagen: die gespeicherten (auch leer), sonst die Prozent-Chips
/// als namenlose Prozent-Vorlagen. Zwilling von `posDiscountPresets`.
List<PosDiscountPreset> posDiscountPresets(PosBusinessSettings? business) {
  final vorlagen = business?.discountPresets;
  if (vorlagen != null) return [...vorlagen];
  final raus = <PosDiscountPreset>[];
  for (final p in business?.discountChips ?? const <double>[]) {
    if (!p.isFinite) continue;
    // Math.round rundet .5 nach oben; fuer positive Werte wie round().
    final bp = (p * 100).round();
    if (bp >= discountPresetPercentBp.min && bp <= discountPresetPercentBp.max) {
      raus.add(PosDiscountPreset(name: '', kind: PosDiscountPresetKind.percent, percentBp: bp));
    }
  }
  return raus;
}

/// Die Prozent-Chips, die der Server aus den Vorlagen nach `discountChips`
/// spiegelt (fuer aeltere Kassen): Prozent-Vorlagen in ihrer Reihenfolge,
/// gleiche Werte nur einmal, Betrag-Vorlagen fallen weg. Zwilling von
/// `discountChipsFromPresets`.
List<double> discountChipsFromPresets(Iterable<PosDiscountPreset>? presets) {
  final raus = <double>[];
  for (final v in presets ?? const <PosDiscountPreset>[]) {
    final bp = v.percentBp;
    if (v.kind != PosDiscountPresetKind.percent || bp == null) continue;
    final p = bp / 100;
    if (!raus.contains(p)) raus.add(p);
  }
  return raus;
}

/// Prozent aus Basispunkten als Text mit Komma, ohne ueberfluessige Stellen:
/// `1000` -> `10`, `1050` -> `10,5`.
String _prozentText(int bp) {
  final ganz = bp ~/ 100;
  final rest = (bp % 100).toString().padLeft(2, '0').replaceFirst(RegExp(r'0+$'), '');
  return rest.isEmpty ? '$ganz' : '$ganz,$rest';
}

/// Euro aus Cent mit Tausenderpunkt: `123456` -> `1.234,56 €`.
String _euroText(int cents) {
  final ganz = (cents ~/ 100).toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '$ganz,${(cents % 100).toString().padLeft(2, '0')} €';
}

/// Text auf dem Chip: `Mitarbeiter-Rabatt 20 %`, `Stammkunde 5,00 €`; ohne
/// Namen nur der Wert (`10 %`). Zwilling von `discountPresetChipText`.
String discountPresetChipText(PosDiscountPreset preset) {
  final wert = preset.kind == PosDiscountPresetKind.amount
      ? _euroText(preset.amountCents ?? 0)
      : '${_prozentText(preset.percentBp ?? 0)} %';
  return preset.name.isNotEmpty ? '${preset.name} $wert' : wert;
}

/// Warum eine Vorlage abgelehnt wird; je Grund ein Satz im Katalog
/// ([discountPresetMessages]). `value` ist der Drahtname (`unknown_field`).
enum DiscountPresetReason {
  list('list'),
  entry('entry'),
  name('name'),
  duplicate('duplicate'),
  kind('kind'),
  percent('percent'),
  amount('amount'),
  unknownField('unknown_field');

  const DiscountPresetReason(this.value);
  final String value;
}

/// Grund -> Satz (Katalog `discount_preset.*`).
const Map<DiscountPresetReason, String> discountPresetMessages = {
  DiscountPresetReason.list: 'discount_preset.list',
  DiscountPresetReason.entry: 'discount_preset.entry',
  DiscountPresetReason.name: 'discount_preset.name',
  DiscountPresetReason.duplicate: 'discount_preset.duplicate',
  DiscountPresetReason.kind: 'discount_preset.kind',
  DiscountPresetReason.percent: 'discount_preset.percent',
  DiscountPresetReason.amount: 'discount_preset.amount',
  DiscountPresetReason.unknownField: 'discount_preset.unknown_field',
};

/// Ein Fehler der Pruefung: [index] die Vorlage (`null` = die Liste), [field]
/// das Feld (`null` = die ganze Vorlage).
class DiscountPresetError {
  const DiscountPresetError({required this.index, required this.field, required this.reason, required this.message});

  final int? index;
  final String? field;
  final DiscountPresetReason reason;
  final String message;
}

/// Ergebnis von [checkDiscountPresets]: bei [ok] die normalisierte Liste
/// ([value], Name getrimmt), sonst [code] ([invalidDiscountPreset]) und [errors].
class DiscountPresetsCheck {
  const DiscountPresetsCheck._(this.ok, this.value, this.errors);
  const DiscountPresetsCheck.valid(List<PosDiscountPreset> value) : this._(true, value, const []);
  const DiscountPresetsCheck.invalid(List<DiscountPresetError> errors) : this._(false, const [], errors);

  final bool ok;
  final List<PosDiscountPreset> value;
  final List<DiscountPresetError> errors;

  /// Der Fehlercode des Servers; nur bei `!ok`.
  String? get code => ok ? null : invalidDiscountPreset;
}

// Steuer- und Formatzeichen (Zeilenumbruch, Null, Zero-Width, Richtungswechsel):
// nie in einem Bon-Text.
final RegExp _steuerzeichen = RegExp(r'[\p{Cc}\p{Cf}  ]', unicode: true);

DiscountPresetError _fehler(int? index, String? field, DiscountPresetReason reason) => DiscountPresetError(
    index: index, field: field, reason: reason, message: messageText(discountPresetMessages[reason]!));

bool _ganzzahl(Object? w) => w is num && w.isFinite && w == w.truncateToDouble();

/// Prueft die Liste der Vorlagen vor dem Schreiben, mit denselben Regeln wie der
/// Server: hoechstens 5, Name 1 bis 24 Zeichen nach dem Trimmen ohne
/// Steuerzeichen, eindeutig ohne Ruecksicht auf Gross und Klein, Art
/// `percent`/`amount` mit genau dem passenden Wertfeld (Prozent 0,1 bis 100 in
/// Schritten von 0,1, Betrag 0,01 bis 1.000.000 €). Der Server antwortet bei
/// einem Fehler mit [invalidDiscountPreset]. Zwilling von `checkDiscountPresets`.
DiscountPresetsCheck checkDiscountPresets(Object? list) {
  if (list is! List || list.length > discountPresetsMax) {
    return DiscountPresetsCheck.invalid([_fehler(null, null, DiscountPresetReason.list)]);
  }
  final errors = <DiscountPresetError>[];
  final value = <PosDiscountPreset>[];
  final namen = <String>{};
  for (var index = 0; index < list.length; index++) {
    final v = list[index];
    if (v is! Map) {
      errors.add(_fehler(index, null, DiscountPresetReason.entry));
      continue;
    }
    final vorher = errors.length;
    final name = v['name'] is String ? (v['name'] as String).trim() : null;
    if (name == null || name.isEmpty || name.runes.length > discountPresetNameMax || _steuerzeichen.hasMatch(name)) {
      errors.add(_fehler(index, 'name', DiscountPresetReason.name));
    } else if (namen.contains(name.toLowerCase())) {
      errors.add(_fehler(index, 'name', DiscountPresetReason.duplicate));
    } else {
      namen.add(name.toLowerCase());
    }
    final kind = switch (v['kind']) {
      'percent' => PosDiscountPresetKind.percent,
      'amount' => PosDiscountPresetKind.amount,
      _ => null,
    };
    if (kind == null) errors.add(_fehler(index, 'kind', DiscountPresetReason.kind));
    final wertfeld = kind == PosDiscountPresetKind.percent ? 'percentBp' : 'amountCents';
    for (final k in v.keys) {
      if (k == 'name' || k == 'kind') continue;
      if (k != 'percentBp' && k != 'amountCents') {
        errors.add(_fehler(index, '$k', DiscountPresetReason.unknownField));
      } else if (kind != null && wertfeld != k) {
        errors.add(_fehler(index, '$k', DiscountPresetReason.unknownField));
      }
    }
    if (kind == PosDiscountPresetKind.percent) {
      final p = v['percentBp'];
      const g = discountPresetPercentBp;
      if (!_ganzzahl(p) || (p as num) < g.min || p > g.max || p % g.step != 0) {
        errors.add(_fehler(index, 'percentBp', DiscountPresetReason.percent));
      }
    }
    if (kind == PosDiscountPresetKind.amount) {
      final c = v['amountCents'];
      const g = discountPresetAmountCents;
      if (!_ganzzahl(c) || (c as num) < g.min || c > g.max) {
        errors.add(_fehler(index, 'amountCents', DiscountPresetReason.amount));
      }
    }
    if (errors.length == vorher && kind != null) {
      final zahl = (v[wertfeld] as num).toInt();
      value.add(PosDiscountPreset(
        name: name!,
        kind: kind,
        percentBp: kind == PosDiscountPresetKind.percent ? zahl : null,
        amountCents: kind == PosDiscountPresetKind.amount ? zahl : null,
      ));
    }
  }
  return errors.isNotEmpty ? DiscountPresetsCheck.invalid(errors) : DiscountPresetsCheck.valid(value);
}

/// Eine Zeile des Rabatte-Blocks auf Z- und X-Bon: [label] und der Betrag als
/// Abzug (negativ).
class DiscountBlockLine {
  const DiscountBlockLine({required this.label, required this.cents});

  final String label;
  final int cents;

  @override
  bool operator ==(Object other) => other is DiscountBlockLine && other.label == label && other.cents == cents;

  @override
  int get hashCode => Object.hash(label, cents);

  @override
  String toString() => 'DiscountBlockLine($label, $cents)';
}

/// Zeilen des Rabatte-Blocks auf Z-Bon und Zwischenbericht: je Name
/// `<Name> (n×)` mit dem Abzug, ab zwei Eintraegen zusaetzlich `Rabatte gesamt`.
/// Ein leerer Name heisst „Rabatt“. Ein voll stornierter Name (Betrag 0) entfaellt
/// wie in der Liste des Servers. Ohne Rabatte leer (kein Block). Zwilling von
/// `discountBlockLines`.
List<DiscountBlockLine> discountBlockLines(Iterable<ShiftDiscount>? discounts) {
  final liste = [for (final r in discounts ?? const <ShiftDiscount>[]) if (r.cents != 0) r];
  final zeilen = [
    for (final r in liste)
      DiscountBlockLine(
        label: labelText('shift_receipt.discount_line', {
          'name': r.name.isEmpty ? labelText('shift_receipt.discount_unnamed') : r.name,
          'count': r.count,
        }),
        cents: -r.cents,
      ),
  ];
  if (zeilen.length > 1) {
    zeilen.add(DiscountBlockLine(label: labelText('shift_receipt.discounts_total'), cents: -liste.fold<int>(0, (x, r) => x + r.cents)));
  }
  return zeilen;
}
