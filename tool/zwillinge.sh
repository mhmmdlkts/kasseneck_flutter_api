#!/usr/bin/env bash
# Holt die Vertragsdateien aus dem veröffentlichten npm-Paket.
#
#   ziehen   — Kopie unter test/fixtures/vertrag/ neu schreiben
#   pruefen  — Kopie byteweise gegen den Tarball vergleichen (CI)
#
# Das Holen macht bewusst dieses Skript und nicht Dart-Code: so braucht das
# veröffentlichte Paket keine HTTP- und Archiv-Abhängigkeit, nur um sich selbst
# zu prüfen.
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

npm pack "@kreiseck/kasseneck-api@${version}" --pack-destination "$tmp" >/dev/null
tar -xzf "$tmp"/kreiseck-kasseneck-api-*.tgz -C "$tmp"

quelle="$tmp/package/fixtures"
if [ ! -d "$quelle" ]; then
  echo "Das Paket ${version} enthält kein fixtures/ — es taugt nicht als Vertrag." >&2
  echo "Die Kopie unter ${ziel} bleibt unangetastet." >&2
  exit 1
fi

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
