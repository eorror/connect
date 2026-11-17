#!/usr/bin/env bash
# Ships an over-the-air update: bumps the version, builds, signs, and publishes a
# GitHub release with an appcast.xml. Running copies of Connect pick it up within the hour.
#
#   scripts/release.sh "What changed"        # bumps patch version (1.0.3 -> 1.0.4)
#   NO_BUMP=1 scripts/release.sh "First"     # publish the current version as-is
set -euo pipefail
cd "$(dirname "$0")/.."
source version.env
NOTES="${1:-Small improvements}"
SPARKLE_BIN=.build/artifacts/sparkle/Sparkle/bin

if [ -z "${NO_BUMP:-}" ]; then
  IFS=. read -r MA MI PA <<<"$MARKETING_VERSION"
  MARKETING_VERSION="$MA.$MI.$((PA + 1))"
  BUILD_NUMBER=$((BUILD_NUMBER + 1))
  sed -i '' -e "s/^MARKETING_VERSION=.*/MARKETING_VERSION=$MARKETING_VERSION/" \
            -e "s/^BUILD_NUMBER=.*/BUILD_NUMBER=$BUILD_NUMBER/" version.env
fi

scripts/build-app.sh

mkdir -p dist
ZIP="dist/Connect-$MARKETING_VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent build/Connect.app "$ZIP"

SIGNATURE_ATTRS=$("$SPARKLE_BIN/sign_update" --account connect "$ZIP")
TAG="v$MARKETING_VERSION"
URL="https://github.com/$GITHUB_REPO/releases/download/$TAG/Connect-$MARKETING_VERSION.zip"
PUBDATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")

cat > dist/appcast.xml <<EOX
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Connect</title>
    <item>
      <title>Version $MARKETING_VERSION</title>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$MARKETING_VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[$NOTES]]></description>
      <enclosure url="$URL" type="application/octet-stream" $SIGNATURE_ATTRS />
    </item>
  </channel>
</rss>
EOX

gh release create "$TAG" "$ZIP" dist/appcast.xml --repo "$GITHUB_REPO" --title "Connect $MARKETING_VERSION" --notes "$NOTES"
echo "Released $TAG. Installed copies will update automatically."
