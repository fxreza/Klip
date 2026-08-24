#!/bin/bash
set -e

echo "📦 Loading environment..."
set -a # automatically export all variables
[ -f .env ] && source .env
set +a

APP_NAME=${APP_NAME:-Klip}
DEPLOY_TARGET=${DEPLOY_TARGET:-13.0}
BUNDLE_ID=${BUNDLE_ID:-com.fxreza.klip}

# Ends in `.noindex` deliberately: macOS Spotlight never indexes a directory
# with that suffix, so the Klip.app built here does not show up in Spotlight
# and Raycast alongside the real /Applications/Klip.app. Same rule as
# scripts/build_local.sh's output — see AGENTS.md. Do not rename this back to
# plain `build`.
BUILD_DIR="build.noindex"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Info.plist)
echo "🔖 Version: ${VERSION} (Build: ${BUILD})"


echo "🧹 Cleaning..."
rm -rf build dmg_* ${APP_NAME}_*.dmg ${APP_NAME}_*.zip

mkdir -p ${BUILD_DIR}

# Source list (review 5A-26): null-delimited, so a file name with a space
# cannot split into two arguments.
SOURCES=(*.swift)
while IFS= read -r -d '' f; do
    SOURCES+=("$f")
done < <(find Models Services Views -name '*.swift' -print0 | sort -z)

echo "🔨 Compiling Swift for arm64 (Apple Silicon)..."
swiftc \
-sdk $(xcrun --show-sdk-path --sdk macosx) \
-target arm64-apple-macosx${DEPLOY_TARGET} \
-parse-as-library \
-framework Cocoa \
-framework SwiftUI \
-framework Carbon \
-framework Quartz \
-framework QuickLookThumbnailing \
-default-isolation MainActor \
"${SOURCES[@]}" \
-o ${BUILD_DIR}/${APP_NAME}_arm64

echo "🔨 Compiling Swift for x86_64 (Intel)..."
swiftc \
-sdk $(xcrun --show-sdk-path --sdk macosx) \
-target x86_64-apple-macosx${DEPLOY_TARGET} \
-parse-as-library \
-framework Cocoa \
-framework SwiftUI \
-framework Carbon \
-framework Quartz \
-framework QuickLookThumbnailing \
-default-isolation MainActor \
"${SOURCES[@]}" \
-o ${BUILD_DIR}/${APP_NAME}_x86_64

package_app() {
    local ARCH_BIN=$1
    local SUFFIX=$2
    
    echo ""
    echo "======================================"
    echo "🚀 Packaging ${APP_NAME} for ${SUFFIX}..."
    echo "======================================"
    
    local ARCH_BUILD_DIR="${BUILD_DIR}/${SUFFIX}"
    local APP_DIR="${ARCH_BUILD_DIR}/${APP_NAME}.app"
    local DMG_DIR="dmg_${SUFFIX}"
    local DMG_NAME="${APP_NAME}_${SUFFIX}.dmg"
    
    mkdir -p ${ARCH_BUILD_DIR}
    mkdir -p ${APP_DIR}/Contents/MacOS
    mkdir -p ${APP_DIR}/Contents/Resources
    
    cp ${ARCH_BIN} ${APP_DIR}/Contents/MacOS/${APP_NAME}
    
    echo "📋 Creating Info.plist..."
    cat > ${APP_DIR}/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN">
<plist version="1.0">
<dict>
<key>CFBundleExecutable</key>
<string>${APP_NAME}</string>
<key>CFBundleIconFile</key>
<string>AppIcon</string>
<key>CFBundleIconName</key>
<string>AppIcon</string>
<key>CFBundleIdentifier</key>
<string>${BUNDLE_ID}</string>
<key>CFBundleName</key>
<string>${APP_NAME}</string>
<key>CFBundleDisplayName</key>
<string>${APP_NAME}</string>
<key>CFBundlePackageType</key>
<string>APPL</string>
<key>CFBundleShortVersionString</key>
<string>${VERSION}</string>
<key>CFBundleVersion</key>
<string>${BUILD}</string>
<key>LSMinimumSystemVersion</key>
<string>${DEPLOY_TARGET}</string>
<key>LSUIElement</key>
<true/>
<key>NSPrincipalClass</key>
<string>NSApplication</string>
</dict>
</plist>
EOF

    echo "🎨 Building assets..."
    xcrun actool Assets.xcassets \
    --compile ${APP_DIR}/Contents/Resources \
    --platform macosx \
    --minimum-deployment-target ${DEPLOY_TARGET} \
    --app-icon AppIcon \
    --output-partial-info-plist ${BUILD_DIR}/partial_${SUFFIX}.plist 2>/dev/null || true
    # iconutil fallback (no Xcode/actool on this Mac): build AppIcon.icns from the appiconset PNGs
    if [[ ! -f "${APP_DIR}/Contents/Resources/AppIcon.icns" ]] && [[ -d "Assets.xcassets/AppIcon.appiconset" ]]; then
        ICONSET="${BUILD_DIR}/AppIcon.iconset"; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
        cp Assets.xcassets/AppIcon.appiconset/icon_*.png "$ICONSET"/
        [[ -f "$ICONSET/icon_512x512.png" ]] || sips -z 512 512 Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png --out "$ICONSET/icon_512x512.png" >/dev/null
        [[ -f "$ICONSET/icon_512x512@2x.png" ]] || sips -z 1024 1024 Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png --out "$ICONSET/icon_512x512@2x.png" >/dev/null
        iconutil -c icns "$ICONSET" -o "${APP_DIR}/Contents/Resources/AppIcon.icns" && echo "🎨 AppIcon.icns built with iconutil"
        rm -rf "$ICONSET"
    fi

    # Same bundled resources as scripts/build_local.sh — this script assembles
    # its own bundle rather than calling that one, so the copies have to exist
    # in both places or the notarized/DMG build would ship without them.
    # CHANGELOG.md is read at runtime by the in-app "What's New" window; the
    # license files carry the MIT notices that used to be in the Settings
    # footer. Guarded, because reference/ is an optional local checkout.
    for pair in \
        "CHANGELOG.md:CHANGELOG.md" \
        "LICENSE:LICENSE.txt" \
        "ATTRIBUTION.md:ATTRIBUTION.md" \
        "reference/clipfield/LICENSE:Licenses/Clipfield-LICENSE.txt" \
        "reference/pesty/LICENSE:Licenses/Pesty-LICENSE.txt"
    do
        SRC="${pair%%:*}"
        DEST="${APP_DIR}/Contents/Resources/${pair#*:}"
        if [[ -f "$SRC" ]]; then
            mkdir -p "$(dirname "$DEST")"
            cp "$SRC" "$DEST"
            echo "📄 Bundled ${SRC} → Contents/Resources/${pair#*:}"
        fi
    done

    echo "📦 Creating PkgInfo..."
    echo "APPL????" > ${APP_DIR}/Contents/PkgInfo

    echo "🔏 Signing..."
    if [ -z "${SIGN_IDENTITY:-}" ]; then
        echo "⚠️  SIGN_IDENTITY not set — skipping real signing, ad-hoc signing instead."
        codesign --force --deep --sign - ${APP_DIR}
    else
        SIGN_OK=false
        for attempt in 1 2 3; do
            if codesign \
                --force \
                --deep \
                --timestamp \
                --options runtime \
                --sign "${SIGN_IDENTITY}" \
                --entitlements Klip.entitlements \
                ${APP_DIR}; then
                SIGN_OK=true
                break
            fi
            echo "⚠️  Signing attempt ${attempt} failed (timestamp server unreachable?), retrying in 3s..."
            sleep 3
        done
        if [ "$SIGN_OK" = false ]; then
            echo "❌ Signing failed after 3 attempts. Check internet connectivity to timestamp.apple.com"
            exit 1
        fi
    fi

    echo "🔍 Verifying..."
    codesign --verify --deep --strict ${APP_DIR}

    echo "🗜️ Creating ZIP..."
    local ZIP_NAME="${APP_NAME}_${SUFFIX}.zip"
    ditto -ck --rsrc --sequesterRsrc --keepParent ${APP_DIR} ${ZIP_NAME}
    echo "✅ ZIP: ${ZIP_NAME}"

    echo "📂 Preparing DMG..."
    mkdir -p ${DMG_DIR}
    cp -R ${APP_DIR} ${DMG_DIR}/
    ln -s /Applications ${DMG_DIR}/Applications

    echo "💿 Creating DMG..."
    hdiutil create \
    -volname "${APP_NAME} ${SUFFIX}" \
    -srcfolder ${DMG_DIR} \
    -ov \
    -format UDZO \
    ${DMG_NAME}

    echo "🔏 Signing DMG..."
    if [ -z "${SIGN_IDENTITY:-}" ]; then
        echo "⚠️  SIGN_IDENTITY not set — skipping DMG signing."
    else
        codesign \
        --force \
        --sign "${SIGN_IDENTITY}" \
        ${DMG_NAME}
    fi

    echo "📤 Notarizing DMG..."
    if [ -z "${NOTARY_PROFILE:-}" ]; then
        echo "⚠️  NOTARY_PROFILE not set — skipping notarization."
    elif xcrun notarytool submit ${DMG_NAME} --keychain-profile "${NOTARY_PROFILE}" --wait; then
        echo "📎 Stapling DMG..."
        xcrun stapler staple ${DMG_NAME}
    else
        echo "⚠️  Notarization failed or skipped. Continuing with unnotarized DMG..."
    fi

    echo "🧼 Cleanup..."
    rm -rf ${DMG_DIR}
    
    echo "✅ Finished ${SUFFIX}: ${DMG_NAME}"
}

package_app "${BUILD_DIR}/${APP_NAME}_arm64" "Silicon"
package_app "${BUILD_DIR}/${APP_NAME}_x86_64" "Intel"

echo ""
echo "🎉 ALL BUILDS COMPLETE"