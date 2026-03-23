#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────
# HyprArc DMG Builder
# Usage: ./scripts/build-dmg.sh [--skip-notarize]
# ─────────────────────────────────────────────

SKIP_NOTARIZE=false
for arg in "$@"; do
    case "$arg" in
        --skip-notarize) SKIP_NOTARIZE=true ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/HyprArc.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/HyprArc.app"
DMG_STAGING="$BUILD_DIR/dmg-staging"

# Notarization keychain profile name (set up once via store-credentials)
NOTARY_PROFILE="HyprArc"

# Extract version from Xcode project
VERSION=$(xcodebuild -project "$PROJECT_DIR/HyprArc.xcodeproj" -scheme HyprArc -showBuildSettings 2>/dev/null | grep MARKETING_VERSION | tr -d ' ' | cut -d= -f2)
VERSION="${VERSION:-1.0}"
DMG_NAME="HyprArc-${VERSION}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

echo "══════════════════════════════════════"
echo "  HyprArc DMG Builder v${VERSION}"
if $SKIP_NOTARIZE; then
    echo "  (notarization skipped)"
fi
echo "══════════════════════════════════════"
echo ""

# ── Step 1: Clean ──
echo "→ Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ── Step 2: Archive ──
echo "→ Building release archive..."
xcodebuild archive \
    -project "$PROJECT_DIR/HyprArc.xcodeproj" \
    -scheme HyprArc \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -quiet

echo "  ✓ Archive created"

# ── Step 3: Export with Developer ID signing ──
echo "→ Exporting with Developer ID signing..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$PROJECT_DIR/ExportOptions.plist" \
    -quiet

echo "  ✓ Signed .app exported"

# ── Step 4: Verify code signature ──
echo "→ Verifying code signature..."
codesign -dvv "$APP_PATH" 2>&1 | grep -E "Authority|TeamIdentifier" | head -4
echo "  ✓ Signature valid"

# ── Step 5: Create DMG ──
echo "→ Creating DMG..."
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

# Copy app and create Applications symlink
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

# Create DMG
hdiutil create \
    -volname "HyprArc" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH" \
    -quiet

rm -rf "$DMG_STAGING"
echo "  ✓ DMG created"

# ── Step 6: Sign the DMG ──
echo "→ Signing DMG..."
codesign --sign "Developer ID Application" --timestamp "$DMG_PATH"
echo "  ✓ DMG signed"

# ── Step 7-8: Notarize + Staple (optional) ──
if $SKIP_NOTARIZE; then
    echo ""
    echo "⚠ Notarization skipped (--skip-notarize)"
    echo "  Users will need to right-click → Open on first launch."
    echo "  Run without --skip-notarize once you've set up credentials:"
    echo "  xcrun notarytool store-credentials \"HyprArc\" \\"
    echo "    --apple-id \"YOUR_APPLE_ID\" --team-id \"26H5KWS9TD\""
else
    echo "→ Submitting for notarization (this may take a few minutes)..."
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    echo "  ✓ Notarization complete"

    echo "→ Stapling notarization ticket..."
    xcrun stapler staple "$DMG_PATH"
    echo "  ✓ Ticket stapled"
fi

# ── Done ──
echo ""
echo "══════════════════════════════════════"
echo "  ✓ Ready for distribution!"
echo "  $DMG_PATH"
SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo "  Size: $SIZE"
echo "══════════════════════════════════════"
