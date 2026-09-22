#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
DERIVED="$(mktemp -d /tmp/MemLite-release.XXXXXX)"
STAGING="$(mktemp -d /tmp/MemLite-dmg.XXXXXX)"
RW_IMAGE="$STAGING/MemLite-rw.dmg"
VOLUME_NAME="MemLite"
MOUNT="/Volumes/$VOLUME_NAME"

cleanup() {
    if mount | grep -q " on $MOUNT "; then
        hdiutil detach "$MOUNT" -quiet || hdiutil detach "$MOUNT" -force || true
    fi
    rm -rf "$DERIVED" "$STAGING"
}
trap cleanup EXIT

xcodebuild \
    -project "$ROOT/MemLite.xcodeproj" \
    -scheme MemLite \
    -configuration Release \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED" \
    build

APP="$DERIVED/Build/Products/Release/MemLite.app"
if [[ ! -d "$APP" ]]; then
    echo "Release 앱을 찾지 못했습니다: $APP" >&2
    exit 1
fi

if mount | grep -q " on $MOUNT "; then
    hdiutil detach "$MOUNT" -quiet || hdiutil detach "$MOUNT" -force
fi

mkdir -p "$DIST"
rm -f "$DIST/MemLite.dmg"

hdiutil create \
    -size 64m \
    -fs HFS+ \
    -volname "$VOLUME_NAME" \
    "$RW_IMAGE" >/dev/null

hdiutil attach \
    -readwrite \
    -noverify \
    -noautoopen \
    "$RW_IMAGE" >/dev/null

cp -R "$APP" "$MOUNT/MemLite.app"
ln -s /Applications "$MOUNT/Applications"

osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 780, 440}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set position of item "MemLite.app" of container window to {160, 180}
        set position of item "Applications" of container window to {420, 180}
        update without registering applications
        delay 3
        close
        delay 2
    end tell
end tell
APPLESCRIPT

sync
detached=0
for _ in 1 2 3 4 5 6; do
    if hdiutil detach "$MOUNT" -quiet; then
        detached=1
        break
    fi
    sleep 1
done
if [[ "$detached" -ne 1 ]]; then
    echo "설치 디스크를 분리하지 못했습니다." >&2
    exit 1
fi

hdiutil convert \
    "$RW_IMAGE" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DIST/MemLite.dmg" >/dev/null

echo "생성됨: $DIST/MemLite.dmg"
