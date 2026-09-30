#!/usr/bin/env bash
# Erzeugt test/fixtures/zeichensatz/special-characters.lines.json neu.
#
# Der Vertrag fuehrt den Fall `special-characters` (code-table-receipts.json)
# nur als Eingabe (Firma, Beleg, Optionen). Das Layout daraus baut das
# npm-Paket (`fromReceiptPayload` + `buildReceiptLayout`, wie dort
# scripts/zeichensatz-fixtures.mjs); dieses Paket bekommt Layouts fertig vom
# Server und hat keinen Layout-Bauer. Darum wird das Layout einmal mit dem
# angehefteten npm-Paket gebaut und hier abgelegt, dazu die Herkunft in
# special-characters.source.json (Version, shasum des Tarballs, sha256 der
# Datei). test/code_table_receipt_test.dart prueft den Hash und die Version.
#
#   tool/zeichensatz_layout.sh                  # Tarball aus der Registry (npm_version)
#   ZWILLINGE_TARBALL=/pfad/x.tgz tool/zeichensatz_layout.sh
set -euo pipefail

wurzel="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$wurzel"

version="$(sed -n 's/^npm_version:[[:space:]]*//p' zwillinge.yaml | tr -d '"' | head -1)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

tarball="${ZWILLINGE_TARBALL:-}"
if [ -z "$tarball" ]; then
  npm pack "@kreiseck/kasseneck-api@${version}" --pack-destination "$tmp" --silent >/dev/null
  tarball="$(ls "$tmp"/kreiseck-kasseneck-api-*.tgz)"
fi
tar -xzf "$tarball" -C "$tmp"
paket="$tmp/package"
paketversion="$(node -p 'require(process.argv[1]).version' "$paket/package.json")"
if [ "$paketversion" != "$version" ]; then
  echo "Das Paket traegt die Version '${paketversion}', angeheftet ist ${version}." >&2
  exit 1
fi
ziel="test/fixtures/zeichensatz"
mkdir -p "$ziel"
node --input-type=module - "$paket" > "$ziel/special-characters.lines.json" <<'JS'
import { readFileSync } from 'node:fs';
const p = process.argv[2];
const { fromReceiptPayload } = await import(p + '/dist/esm/models/index.js');
const { buildReceiptLayout } = await import(p + '/dist/esm/receipt/index.js');
const bons = JSON.parse(readFileSync(p + '/fixtures/code-table-receipts.json', 'utf8'));
const f = bons.cases.find((c) => c.name === 'special-characters').input;
const receipt = fromReceiptPayload({ ...f.receipt, customerDetails: f.receipt.customerDetails.join('\n'), legalMessage: f.receipt.legalMessage.join('\n') });
process.stdout.write(JSON.stringify(buildReceiptLayout(receipt, f.company, f.options ?? {}), null, 2) + '\n');
JS
tarsha="$(shasum -a 1 "$tarball" | cut -d' ' -f1)"
dateisha="$(shasum -a 256 "$ziel/special-characters.lines.json" | cut -d' ' -f1)"
printf '{\n  "npmVersion": "%s",\n  "tarballShasum": "%s",\n  "sha256": "%s"\n}\n' "$version" "$tarsha" "$dateisha" > "$ziel/special-characters.source.json"
echo "special-characters.lines.json aus @kreiseck/kasseneck-api ${version} (shasum ${tarsha}) erzeugt."
