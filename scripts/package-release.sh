#!/bin/bash
# iHearYou | Signature: i729
set -euo pipefail
cd "$(dirname "$0")/.."
app=dist/iHearYou.app
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
payload=build/release-root
# Recreate only generated staging files. The driver-only installer remains useful
# when the application is already installed.
rm -rf "$payload"
mkdir -p "$payload/Applications" "$payload/Library/Audio/Plug-Ins/HAL"
ditto --norsrc "$app" "$payload/Applications/iHearYou.app"
ditto --norsrc build/driver-root/Library/Audio/Plug-Ins/HAL/iHearYouMic.driver "$payload/Library/Audio/Plug-Ins/HAL/iHearYouMic.driver"
pkgbuild --analyze --root "$payload" build/release-components.plist
python3 - <<'PY'
import plistlib
from pathlib import Path
p = Path('build/release-components.plist')
components = plistlib.loads(p.read_bytes())
for component in components:
    component['BundleIsRelocatable'] = False
    component['BundleOverwriteAction'] = 'upgrade'
p.write_bytes(plistlib.dumps(components))
PY
pkgbuild --root "$payload" --component-plist build/release-components.plist \
    --identifier com.i729.iHearYou.installer --version "$version" \
    --scripts scripts/installer --ownership recommended --install-location / \
    "dist/iHearYou-$version.pkg"
ditto -c -k --norsrc --keepParent "$app" "dist/iHearYou-$version-macOS-arm64.zip"
python3 - "$version" <<'PY'
import hashlib
import sys
from pathlib import Path
version = sys.argv[1]
files = [Path(f'dist/iHearYou-{version}.pkg'),
         Path(f'dist/iHearYou-{version}-macOS-arm64.zip'),
         Path('dist/iHearYouMicrophone.pkg')]
Path('dist/SHA256SUMS.txt').write_text(''.join(
    f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in files))
PY
printf 'Installer: dist/iHearYou-%s.pkg\n' "$version"
