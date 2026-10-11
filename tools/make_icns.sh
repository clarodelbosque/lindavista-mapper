#!/bin/sh
# Regenerates resources/LindaVistaMapper.icns from resources/LindaVistaMapper-icon.png
# (a square PNG, 1024x1024 recommended). Run from the repo root: sh tools/make_icns.sh
set -e
SRC=resources/LindaVistaMapper-icon.png
OUT=resources/LindaVistaMapper.icns
SET=$(mktemp -d)/LindaVistaMapper.iconset
mkdir -p "$SET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$SRC" --out "$SET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$SRC" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$OUT"
rm -rf "$(dirname "$SET")"
echo "Wrote $OUT"
