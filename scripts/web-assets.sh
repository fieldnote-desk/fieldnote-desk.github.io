#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
font="app/assets/FieldnoteSans.ttf"
url='https://raw.githubusercontent.com/google/fonts/2894aab31764f10f29c421bdfd2340d3b382d384/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf'
sha='a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da'
if ! printf '%s  %s\n' "$sha" "$font" | sha256sum --check --status; then
  curl --fail --silent --show-error --location --retry 2 --max-time 90 "$url" --output "$font"
  printf '%s  %s\n' "$sha" "$font" | sha256sum --check
fi
