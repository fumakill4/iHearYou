#!/bin/bash
# iHearYou | Signature: i729
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
# Use the user's native macOS icon directly, preserving all supplied sizes.
icon_path="${IHEARYOU_ICON_PATH:-Real app logo.icns}"
if [[ ! -f "$icon_path" && -z "${IHEARYOU_ICON_PATH:-}" ]]; then icon_path="icon.png"; fi
test -f "$icon_path"
if [[ "$icon_path" == *.png ]]; then
    mkdir -p build/iHearYou.iconset
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$icon_path" --out "build/iHearYou.iconset/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z "$double" "$double" "$icon_path" --out "build/iHearYou.iconset/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns build/iHearYou.iconset -o build/iHearYou.icns
else
    cp "$icon_path" build/iHearYou.icns
fi
