#!/usr/bin/env bash
# Holt die Vertragsdateien aus dem veröffentlichten npm-Paket.
#
#   ziehen   — Kopie unter test/fixtures/vertrag/ neu schreiben
#   pruefen  — Kopie byteweise gegen den Tarball vergleichen (CI)
#
# Das Holen macht bewusst dieses Skript und nicht Dart-Code: so braucht das
# veröffentlichte Paket keine HTTP- und Archiv-Abhängigkeit, nur um sich selbst
# zu prüfen.
#
# Quelle ist die Registry. Für den Übergang, solange eine Version im JS-Repo
# gepackt, aber noch nicht veröffentlicht ist, darf ZWILLINGE_TARBALL auf den
# Tarball zeigen (`npm pack` dort):
#
#   ZWILLINGE_TARBALL=/pfad/kreiseck-kasseneck-api-1.0.0-rc.1.tgz tool/zwillinge.sh ziehen
#
# Das ist ein Zwischenstand, kein Beweis: echt ist die Kopie erst, wenn
# `tool/zwillinge.sh pruefen` OHNE die Variable grün ist, also gegen die
# veröffentlichte Version. Die CI nimmt die Variable deshalb nicht an — sie
# bleibt rot, bis die angeheftete Version auf npm steht.
set -euo pipefail

wurzel="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$wurzel"

ziel="test/fixtures/vertrag"
neu="${ziel}.neu"

# Der Unterbefehl wird geprüft, bevor irgendetwas geladen wird: ein Tippfehler
# soll die Aufruf-Hilfe zeigen und nicht erst ein Paket herunterladen.
befehl="${1:-}"
case "$befehl" in
  ziehen|pruefen) ;;
  *)
    echo "Aufruf: tool/zwillinge.sh {ziehen|pruefen}" >&2
    exit 2
    ;;
esac

version="$(sed -n 's/^npm_version:[[:space:]]*//p' zwillinge.yaml | tr -d '"' | head -1)"
[ -n "$version" ] || { echo "npm_version fehlt in zwillinge.yaml" >&2; exit 1; }

tmp="$(mktemp -d)"
# Aufgeräumt wird am EXIT. Strg-C und kill lösen bewusst ein `exit` aus, statt
# selbst aufzuräumen: sonst liefe das Skript nach dem Handler einfach weiter —
# dann mit gelöschtem Arbeitsverzeichnis.
trap 'rm -rf "$tmp" "$neu"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

tarball="${ZWILLINGE_TARBALL:-}"
if [ -n "$tarball" ]; then
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    echo "ZWILLINGE_TARBALL gilt nicht in der CI — dort zählt nur die Registry." >&2
    exit 1
  fi
  [ -f "$tarball" ] || { echo "ZWILLINGE_TARBALL zeigt auf keine Datei: ${tarball}" >&2; exit 1; }
  tar -xzf "$tarball" -C "$tmp"
  echo "Achtung: Vertrag aus dem lokalen Tarball ${tarball}, nicht aus der Registry." >&2
  echo "Nach der Veröffentlichung 'tool/zwillinge.sh pruefen' ohne ZWILLINGE_TARBALL laufen lassen." >&2
else
  npm pack "@kreiseck/kasseneck-api@${version}" --pack-destination "$tmp" --silent >/dev/null
  tar -xzf "$tmp"/kreiseck-kasseneck-api-*.tgz -C "$tmp"
fi

# Die Version im Paket muss die angeheftete sein. Aus der Registry ist das
# selbstverständlich; ein lokaler Tarball kann aber ein anderer Stand sein, und
# dann stünde unter npm_version still ein fremder Vertrag.
paketversion="$(node -p 'require(process.argv[1]).version' "$tmp/package/package.json" 2>/dev/null || true)"
if [ "$paketversion" != "$version" ]; then
  echo "Das Paket trägt die Version '${paketversion}', angeheftet ist ${version}." >&2
  echo "Die Kopie unter ${ziel} bleibt unangetastet." >&2
  exit 1
fi

quelle="$tmp/package/fixtures"
if [ ! -d "$quelle" ]; then
  echo "Das Paket ${version} enthält kein fixtures/ — es taugt nicht als Vertrag." >&2
  echo "Die Kopie unter ${ziel} bleibt unangetastet." >&2
  exit 1
fi

# Die Markendaten (Raster + Pfade fuer den Kasseneck-Schriftzug am
# Belegende) reisen NICHT unter fixtures/ -- sie sind erzeugte TS-Quelle und
# landen wie jeder Code kompiliert in dist/. Trotzdem sind sie Vertrag (siehe
# docs/specs/2026-09-21-marke-einheitlich-design.md, § 3.4): hier aus dem
# ESM-Modul gezogen und als gewoehnliche Fixture ins Staging gelegt, damit
# ziehen/pruefen sie ohne Sonderweg mitnehmen. Damit deckt der bestehende
# Zwillings-Nachweis erstmals auch Bilddaten ab, nicht nur Beschreibungsdateien.
markeModul="$tmp/package/dist/esm/receipt/marke-daten.js"
if [ ! -f "$markeModul" ]; then
  echo "Das Paket ${version} enthält kein dist/esm/receipt/marke-daten.js — die Markendaten fehlen." >&2
  echo "Die Kopie unter ${ziel} bleibt unangetastet." >&2
  exit 1
fi
# Seit 1.0 heissen die Exporte englisch (BRAND_MARK_RASTERS, BRAND_MARK_PATHS),
# die Schluessel darin ebenso (width, height, bits, paths). Fehlt ein Export,
# bricht das Skript ab: JSON.stringify liesse `undefined` still weg, und aus
# der Markendatei wuerde ein leeres `{}`, das erst ein Test bemerkt.
node --input-type=module -e '
  import { writeFileSync } from "node:fs";
  const [modulPfad, zielPfad] = process.argv.slice(1);
  const mod = await import(modulPfad);
  for (const name of ["BRAND_MARK_RASTERS", "BRAND_MARK_PATHS"]) {
    if (mod[name] === undefined) {
      console.error(`marke-daten.js exportiert ${name} nicht.`);
      process.exit(1);
    }
  }
  writeFileSync(zielPfad, JSON.stringify({ rasters: mod.BRAND_MARK_RASTERS, paths: mod.BRAND_MARK_PATHS }, null, 2) + "\n");
' "$markeModul" "$quelle/marke.json"

# Was die Zwillingstests lesen, muss im Paket stehen. `diff -r` allein merkt
# ein fehlendes Verzeichnis nur als Abweichung zur alten Kopie; beim Ziehen
# kaeme es gar nicht auf. Die Liste nennt die Wurzeln, die 1.0 neu einfuehrt
# oder umbenennt, dazu die Dateien, auf die die Tests direkt zugreifen.
pflicht=(
  manifest.json
  surface.json
  pos-settings-defaults.json
  pos-texts.json
  pos-message-cases.json
  hobex-hps-codes.json
  item-from-euro.json
  invoice-api.schema.json
  invoice-api-examples
  invoice-calc.json
  invoice-calc-random.json
  invoice-totals.json
  invoice-texts.json
  receipt-due-generated.json
  renames-1.0.json
  receipts
  expected
  stored
  v3
  v3/v3-vokabular.json
  v3/zahlbetrag-faelle.json
  v3/antworten
  v3/stored
)
for eintrag in "${pflicht[@]}"; do
  if [ ! -e "$quelle/$eintrag" ]; then
    echo "Das Paket ${version} enthält fixtures/${eintrag} nicht." >&2
    echo "Die Kopie unter ${ziel} bleibt unangetastet." >&2
    exit 1
  fi
done

case "$befehl" in
  ziehen)
    # Erst vollständig danebenbauen, dann austauschen: schlägt das Kopieren
    # fehl, bleibt die vorhandene Kopie stehen statt gelöscht zu sein.
    rm -rf "$neu"
    mkdir -p "$neu"
    cp -R "$quelle"/. "$neu"/
    rm -rf "$ziel"
    mv "$neu" "$ziel"
    echo "Vertrag ${version} gezogen nach ${ziel}"
    ;;
  pruefen)
    rueck=0
    diff -r "$quelle" "$ziel" || rueck=$?
    case "$rueck" in
      0)
        echo "Vertrag ${version}: Kopie ist echt"
        ;;
      1)
        echo "" >&2
        echo "Die Kopie unter ${ziel} weicht vom Paket ${version} ab." >&2
        echo "Sie wird NUR von 'tool/zwillinge.sh ziehen' geschrieben — von Hand nie." >&2
        exit 1
        ;;
      *)
        # diff selbst kam nicht durch (Code 2), etwa weil ${ziel} fehlt. Das ist
        # kein Befund über den Inhalt und darf nicht als solcher gemeldet werden.
        echo "" >&2
        echo "Der Vergleich mit dem Paket ${version} konnte nicht durchgeführt werden" >&2
        echo "(diff endete mit ${rueck}). Fehlt ${ziel}? Dann 'tool/zwillinge.sh ziehen'." >&2
        exit 1
        ;;
    esac
    ;;
esac
