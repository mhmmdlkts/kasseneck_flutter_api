/// Die Vorschau im Drucker-Wizard: nach der Wahl einer Zeile zeigt der
/// Bildschirm ein Beispiel so, wie es mit dieser Tabelle am Bon steht. Wer
/// Zeile 4 (PC437) waehlt, sieht „3,50 EUR“ statt „3,50 €“, bevor er
/// uebernimmt. (Zwilling von `code-table-preview.ts` im npm-Paket ab 1.1.1.)
///
/// Gemeinsamer Prueffall mit dem npm-Paket: `code-table-preview.json`.
library;

import 'code_tables.dart';
import 'printable.dart';

/// Das Beispiel: Umlaut, €, °.
const List<String> _beispiel = ['Käsekrainer 3,50 €', 'Tee 80°'];

/// Das Beispiel mit den Ersetzungen der Tabelle, Zeilen durch `\n` getrennt:
/// fehlt der Tabelle ein Zeichen, stehen seine Ersatzbuchstaben da
/// (`pc437` -> „Käsekrainer 3,50 EUR“, `replacement` -> „Kaesekrainer 3,50 EUR“).
String codeTablePreviewText(CodeTableId table) =>
    [for (final zeile in _beispiel) printableText(zeile, codeTable: table)].join('\n');
