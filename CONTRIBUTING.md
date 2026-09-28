# Mitarbeit an der Linie 9.x

Dieser Zweig (`release/9.x`) ist eingefroren. Er zweigt bei 9.1.0 ab
(Commit 53a8d65) und bleibt stehen, solange Apps im Feld an `^9.0.0` hängen.
Die Weiterentwicklung (10.x, nur `/v3` und englisch, Zwilling von
`@kreiseck/kasseneck-api` 1.x) liegt auf `main`.

## Nur Fehlerbehebungen

- Hier landen ausschließlich Fehlerbehebungen, als Patch-Version
  (9.x.y). Keine neuen Funktionen, keine neuen Felder, keine Umbenennungen,
  keine Abhängigkeits-Sprünge über das Nötige hinaus.
- Jede Behebung braucht einen Test, der ohne sie rot ist.
- Betrifft der Fehler auch `main`, wird er dort zuerst oder im selben Zug
  behoben. Ein Fix, der nur hier steht, fehlt in 10.x.
- Der Vertrag mit dem npm-Zwilling bleibt auf `npm_version: 0.30.0`
  (`zwillinge.yaml`). Die npm-Linie 0.x ist ebenfalls eingefroren; ein
  0.x-Patch dort geht nur mit `--tag v0` hinaus. Ein Nachziehen auf npm 1.x
  gehört nicht auf diesen Zweig.
- Die Regeln aus `AGENTS.md` gelten unverändert, allen voran die zum Zahlweg.

## Veröffentlichen nur aus einer sauberen Kopie

`.pubignore` ersetzt beim Veröffentlichen die `.gitignore`: was lokal
herumliegt (Zugangsdaten, `.env`, Build-Reste), reist sonst mit. Deshalb:

1. Frische Kopie des Zweigs anlegen, nie aus einem Arbeitsverzeichnis:
   `git worktree add ../kasseneck_api-publish-9x release/9.x` (oder `git clone`).
2. Dort `flutter pub get`, `flutter analyze`, `flutter test`,
   `tool/zwillinge.sh pruefen`.
3. Version in `pubspec.yaml` und Eintrag in `CHANGELOG.md` (Änderung und Grund).
4. `dart pub publish --dry-run` und die Dateiliste lesen, erst dann
   `dart pub publish`.
5. Die Kopie danach entfernen (`git worktree remove`).

Eine niedrigere Version ändert auf pub.dev nichts an `latest`: wer
`^9.0.0` verlangt, bekommt den Patch, wer 10.x nutzt, bleibt dort.
