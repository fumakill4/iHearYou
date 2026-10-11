#!/bin/bash
# iHearYou | Signature: i729
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
# Use the user's native macOS icon directly, preserving all supplied sizes.
test -f 'Real app logo.icns'
cp 'Real app logo.icns' build/iHearYou.icns
