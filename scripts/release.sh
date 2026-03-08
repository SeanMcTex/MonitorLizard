#!/bin/bash
set -euo pipefail

# MonitorLizard Release Script
# Builds, signs, creates a GitHub release, and updates the appcast.

# --- Configuration ---
APP_NAME="MonitorLizard"
SCHEME="MonitorLizard"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$PROJECT_DIR/MonitorLizard/MonitorLizard.xcodeproj"
APPCAST_FILE="$PROJECT_DIR/docs/appcast.xml"
BUILD_DIR="$PROJECT_DIR/build/release"
SPARKLE_BIN="$(find ~/Library/Developer/Xcode/DerivedData/MonitorLizard-*/SourcePackages/artifacts/sparkle/Sparkle/bin -maxdepth 0 2>/dev/null | head -1)"

# --- Preflight checks ---
if [ -z "$SPARKLE_BIN" ]; then
    echo "Error: Sparkle bin directory not found in DerivedData."
    echo "Build the project in Xcode first so SPM resolves the Sparkle package."
    exit 1
fi

if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed. Install with: brew install gh"
    exit 1
fi

if ! gh auth status &> /dev/null; then
    echo "Error: GitHub CLI is not authenticated. Run: gh auth login"
    exit 1
fi

# --- Get version info ---
INFO_PLIST="$PROJECT_DIR/MonitorLizard/Info.plist"
CURRENT_SHORT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")

echo "=== $APP_NAME Release Script ==="
echo ""
echo "Current version: $CURRENT_SHORT_VERSION (build $CURRENT_BUILD)"
echo ""

# --- Prompt for new version ---
read -p "New version string (e.g. 1.1.0): " NEW_VERSION
read -p "New build number (e.g. 2): " NEW_BUILD

if [ -z "$NEW_VERSION" ] || [ -z "$NEW_BUILD" ]; then
    echo "Error: Version and build number are required."
    exit 1
fi

echo ""
echo "Release notes (enter a blank line to finish):"
RELEASE_NOTES=""
while IFS= read -r line; do
    [ -z "$line" ] && break
    RELEASE_NOTES+="$line"$'\n'
done
RELEASE_NOTES="${RELEASE_NOTES%$'\n'}"  # trim trailing newline

if [ -z "$RELEASE_NOTES" ]; then
    echo "Error: Release notes are required."
    exit 1
fi

TAG="v$NEW_VERSION"

echo ""
echo "--- Summary ---"
echo "Version:       $NEW_VERSION (build $NEW_BUILD)"
echo "Tag:           $TAG"
echo "Release notes:"
echo "$RELEASE_NOTES"
echo "---------------"
echo ""
read -p "Proceed? (y/N): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Aborted."
    exit 0
fi

# --- Step 1: Update version numbers in Info.plist ---
echo ""
echo "[1/7] Updating version to $NEW_VERSION (build $NEW_BUILD)..."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$INFO_PLIST"

# --- Step 2: Build Release archive ---
echo "[2/7] Building Release archive..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
    archive \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    2>&1 | tail -5

# --- Step 3: Export the .app from the archive ---
echo "[3/7] Exporting app from archive..."
APP_PATH="$BUILD_DIR/$APP_NAME.xcarchive/Products/Applications/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: $APP_NAME.app not found in archive at $APP_PATH"
    exit 1
fi

# --- Step 4: Create zip for distribution ---
echo "[4/7] Creating distribution zip..."
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
cd "$BUILD_DIR/$APP_NAME.xcarchive/Products/Applications"
zip -r -y "$ZIP_PATH" "$APP_NAME.app"
cd "$PROJECT_DIR"

ZIP_SIZE=$(stat -f%z "$ZIP_PATH")
echo "    Zip created: $ZIP_PATH ($ZIP_SIZE bytes)"

# --- Step 5: Sign the zip with Sparkle ---
echo "[5/7] Signing with Sparkle EdDSA key..."
SIGNATURE=$("$SPARKLE_BIN/sign_update" "$ZIP_PATH" 2>&1)
# sign_update outputs: sparkle:edSignature="..." length="..."
ED_SIGNATURE=$(echo "$SIGNATURE" | grep -o 'sparkle:edSignature="[^"]*"' | sed 's/sparkle:edSignature="//;s/"//')

if [ -z "$ED_SIGNATURE" ]; then
    echo "Error: Failed to get EdDSA signature."
    echo "sign_update output: $SIGNATURE"
    exit 1
fi
echo "    Signature: ${ED_SIGNATURE:0:20}..."

# --- Step 6: Create GitHub release ---
echo "[6/7] Creating GitHub release $TAG..."

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/$APP_NAME.zip"

gh release create "$TAG" "$ZIP_PATH" \
    --title "$APP_NAME $NEW_VERSION" \
    --notes "$RELEASE_NOTES"

echo "    Release created: https://github.com/$REPO/releases/tag/$TAG"

# --- Step 7: Update appcast.xml ---
echo "[7/7] Updating appcast.xml..."

# Format release notes as HTML list items
HTML_NOTES=""
while IFS= read -r line; do
    HTML_NOTES+="                    <li>$line</li>"$'\n'
done <<< "$RELEASE_NOTES"
HTML_NOTES="${HTML_NOTES%$'\n'}"  # trim trailing newline

PUB_DATE=$(date -R)

NEW_ITEM="        <item>
            <title>Version $NEW_VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$NEW_BUILD</sparkle:version>
            <sparkle:shortVersionString>$NEW_VERSION</sparkle:shortVersionString>
            <description><![CDATA[
                <h2>What's New</h2>
                <ul>
$HTML_NOTES
                </ul>
            ]]></description>
            <enclosure
                url=\"$DOWNLOAD_URL\"
                length=\"$ZIP_SIZE\"
                type=\"application/octet-stream\"
                sparkle:edSignature=\"$ED_SIGNATURE\"
            />
        </item>"

# Insert new item at the top of the channel (after <language> line)
sed -i '' "/<language>en<\/language>/a\\
$NEW_ITEM
" "$APPCAST_FILE"

echo ""
echo "=== Release $NEW_VERSION complete! ==="
echo ""
echo "Remaining steps:"
echo "  1. Commit the updated Info.plist and appcast.xml"
echo "  2. Push to main so GitHub Pages serves the new appcast"
echo "     git add MonitorLizard/Info.plist docs/appcast.xml"
echo "     git commit -m 'Release $NEW_VERSION'"
echo "     git push"
