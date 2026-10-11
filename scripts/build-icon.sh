#!/bin/bash
# iHearYou | Signature: i729
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/iHearYou.iconset
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" icon.png --out "build/iHearYou.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" icon.png --out "build/iHearYou.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/iHearYou.iconset -o build/iHearYou.icns
