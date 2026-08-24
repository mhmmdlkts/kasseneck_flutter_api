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

version="$(sed -n 's/^npm_version:[[:space:]]*//p' zwillinge.yaml | tr -d '"' | head -1)"
[ -n "$version" ] || { echo "npm_version fehlt in zwillinge.yaml" >&2; exit 1; }

ziel="test/fixtures/vertrag"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

npm pack "@kreiseck/kasseneck-api@${version}" --pack-destination "$tmp" >/dev/null
tar -xzf "$tmp"/kreiseck-kasseneck-api-*.tgz -C "$tmp"

case "${1:-}" in
  ziehen)
    rm -rf "$ziel"
    mkdir -p "$ziel"
    cp -R "$tmp"/package/fixtures/. "$ziel"/
    echo "Vertrag ${version} gezogen nach ${ziel}"
    ;;
  pruefen)
    if diff -r "$tmp/package/fixtures" "$ziel"; then
      echo "Vertrag ${version}: Kopie ist echt"
    else
      echo "" >&2
      echo "Die Kopie unter ${ziel} weicht vom Paket ${version} ab." >&2
      echo "Sie wird NUR von 'tool/zwillinge.sh ziehen' geschrieben — von Hand nie." >&2
      exit 1
    fi
    ;;
  *)
    echo "Aufruf: tool/zwillinge.sh {ziehen|pruefen}" >&2
    exit 2
    ;;
esac
