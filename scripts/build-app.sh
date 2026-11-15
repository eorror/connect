#!/usr/bin/env bash
# Builds build/Connect.app (universal: Apple Silicon + Intel).
set -euo pipefail
cd "$(dirname "$0")/.."
source version.env

FEED_URL="https://github.com/${GITHUB_REPO}/releases/latest/download/appcast.xml"
APP=build/Connect.app

swift build -c release --arch arm64 --arch x86_64
PRODUCTS=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$PRODUCTS/Connect" "$APP/Contents/MacOS/Connect"
ditto "$PRODUCTS/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

sed -e "s|__VERSION__|${MARKETING_VERSION}|" \
    -e "s|__BUILD__|${BUILD_NUMBER}|" \
    -e "s|__FEED_URL__|${FEED_URL}|" \
    -e "s|__SUPABASE_URL__|${SUPABASE_URL:-}|" \
    -e "s|__SUPABASE_KEY__|${SUPABASE_KEY:-}|" \
    Resources/Info.plist > "$APP/Contents/Info.plist"

# Let the executable find Sparkle inside the bundle.
if ! otool -l "$APP/Contents/MacOS/Connect" | grep -q "@executable_path/../Frameworks"; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Connect"
fi

# Ad-hoc sign (updates are verified by Sparkle's EdDSA signature).
codesign --force --deep --sign - "$APP"
echo "Built $APP  (v${MARKETING_VERSION}, build ${BUILD_NUMBER})"
