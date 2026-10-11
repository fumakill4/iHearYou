#!/bin/bash
# iHearYou | Signature: i729
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/prepare-runtime.py
./scripts/build-icon.sh
swift build -c release 2>build-warnings.log
# Recreate the generated bundle so obsolete engines and notices cannot survive rebuilds.
rm -rf dist/iHearYou.app
mkdir -p dist/iHearYou.app/Contents/{MacOS,Resources,Frameworks} build/driver-root/Library/Audio/Plug-Ins/HAL/iHearYouMic.driver/Contents/{MacOS,Resources}
binary_dir="$(swift build -c release --show-bin-path)"
cp "$binary_dir/iHearYou" dist/iHearYou.app/Contents/MacOS/iHearYou
# Public artifacts carry no compiler debug records or absolute source paths.
strip -S dist/iHearYou.app/Contents/MacOS/iHearYou
cp Resources/Info.plist dist/iHearYou.app/Contents/Info.plist
cp Resources/BrowserRecorder.html dist/iHearYou.app/Contents/Resources/
cp Resources/PhoneSpeaker.html dist/iHearYou.app/Contents/Resources/
cp build/iHearYou.icns dist/iHearYou.app/Contents/Resources/
cp Vendor/DPDFNet/dpdfnet2_48khz_hr.onnx dist/iHearYou.app/Contents/Resources/
cp Vendor/DPDFNet/LICENSE dist/iHearYou.app/Contents/Resources/DPDFNet-LICENSE.txt
cp Vendor/Sherpa/LICENSE dist/iHearYou.app/Contents/Resources/Sherpa-LICENSE.txt
cp Vendor/Sherpa/ONNXRuntime-LICENSE dist/iHearYou.app/Contents/Resources/ONNXRuntime-LICENSE.txt
cp Vendor/Sherpa/lib/{libsherpa-onnx-c-api.dylib,libonnxruntime.dylib} dist/iHearYou.app/Contents/Frameworks/
# Bundle lookup precedes development fallback; installed builds must not rely on workspace paths.
install_name_tool -delete_rpath "$PWD/Vendor/Sherpa/lib" dist/iHearYou.app/Contents/MacOS/iHearYou
for library in dist/iHearYou.app/Contents/Frameworks/*.dylib; do codesign --force --sign - "$library"; done
cp Vendor/BlackHole/LICENSE dist/iHearYou.app/Contents/Resources/BlackHole-LICENSE.txt
cp LICENSE dist/iHearYou.app/Contents/Resources/iHearYou-LICENSE.txt
cp THIRD_PARTY_NOTICES.md dist/iHearYou.app/Contents/Resources/
driver=build/driver-root/Library/Audio/Plug-Ins/HAL/iHearYouMic.driver
clang -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 -O2 -fblocks -bundle \
    -framework CoreAudio -framework CoreFoundation -framework Accelerate \
    '-DkDriver_Name="iHearYouMic"' '-DkDevice_Name="iHearYou Microphone"' \
    '-DkDevice2_Name="iHearYou Monitor"' '-DkPlugIn_BundleID="com.i729.iHearYou.driver"' \
    '-DkPlugIn_Icon=""' '-DkManufacturer_Name="i729 (driver based on BlackHole)"' \
    -DkHas_Driver_Name_Format=false -DkNumber_Of_Channels=2 -DkCanBeDefaultSystemDevice=false \
    -DkDevice2_IsHidden=true -DkEnableVolumeControl=false -DBlackHole_Create=IHDriver_Create \
    Vendor/BlackHole/BlackHole/BlackHole.c -o "$driver/Contents/MacOS/iHearYouMic"
cp Resources/DriverInfo.plist "$driver/Contents/Info.plist"
cp Vendor/BlackHole/LICENSE "$driver/Contents/Resources/LICENSE.txt"
codesign --force --sign - "$driver"
pkgbuild --root build/driver-root --identifier com.i729.iHearYou.driver \
    --version 1.0.0 --scripts scripts/installer --ownership recommended --install-location / \
    dist/iHearYouMicrophone.pkg
cp dist/iHearYouMicrophone.pkg dist/iHearYou.app/Contents/Resources/
codesign --force --sign - --identifier com.i729.iHearYou dist/iHearYou.app
codesign --verify --deep --strict dist/iHearYou.app
./scripts/package-release.sh
printf 'Ready: %s/dist/iHearYou.app\n' "$PWD"
