#!/bin/bash
set -euo pipefail

# =============================================================================
# Local build script for macOS app
# Usage: scripts/build_local.sh [--arch arm64|x86_64|both] [--dist] [--sign <identity>|adhoc] [--out <dir>]
# =============================================================================

# Environment-overridable constants
APP_NAME=${APP_NAME:-Klip}
BUNDLE_ID=${BUNDLE_ID:-com.fxreza.klip}
DEPLOY_TARGET=${DEPLOY_TARGET:-13.0}

if [[ -z "${ENTITLEMENTS:-}" ]]; then
    if [[ -f "Klip.entitlements" ]]; then
        ENTITLEMENTS="Klip.entitlements"
    elif [[ -f "Buffer.entitlements" ]]; then
        ENTITLEMENTS="Buffer.entitlements"
    else
        ENTITLEMENTS=""
    fi
fi

# Parse arguments
ARCH="arm64"
DIST_FLAG=false
SIGN_IDENTITY=""
OUTPUT_DIR="build"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --dist)
            DIST_FLAG=true
            shift
            ;;
        --sign)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        --out)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Validate arch argument
if [[ ! "$ARCH" =~ ^(arm64|x86_64|both)$ ]]; then
    echo "Invalid --arch: must be arm64, x86_64, or both" >&2
    exit 1
fi

# Change to repo root
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Start timer
START_TIME=$(date +%s)

# Read version/build from Info.plist
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Info.plist)

echo "🔖 Building ${APP_NAME} v${VERSION} (build ${BUILD})"
echo "📋 Bundle ID: ${BUNDLE_ID}"
echo "🎯 Deployment Target: ${DEPLOY_TARGET}"
echo "🏗️  Output: ${OUTPUT_DIR}"

# Determine architectures to build
if [[ "$ARCH" == "both" ]]; then
    ARCHS=("arm64" "x86_64")
else
    ARCHS=("$ARCH")
fi

# Create output directory
mkdir -p "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}/compile-logs"

# Compile for each architecture
declare -a BIN_ARM64=""
declare -a BIN_X86_64=""

# Source list (review 5A-26). The old `*.swift $(find … | sort)` relied on
# word splitting, so a source file with a space in its name would silently
# break the build or compile the wrong set. Null-delimited, exactly like
# scripts/run_tests.sh.
SOURCES=(*.swift)
while IFS= read -r -d '' f; do
    SOURCES+=("$f")
done < <(find Models Services Views -name '*.swift' -print0 | sort -z)

for CURRENT_ARCH in "${ARCHS[@]}"; do
    OUTPUT_BIN="${OUTPUT_DIR}/${CURRENT_ARCH}/${APP_NAME}"
    mkdir -p "${OUTPUT_DIR}/${CURRENT_ARCH}"

    echo ""
    echo "🔨 Compiling for ${CURRENT_ARCH}..."

    COMPILE_LOG="${OUTPUT_DIR}/compile-logs/${CURRENT_ARCH}.log"

    swiftc \
        -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
        -target "${CURRENT_ARCH}-apple-macosx${DEPLOY_TARGET}" \
        -parse-as-library \
        -default-isolation MainActor \
        -framework Cocoa \
        -framework SwiftUI \
        -framework Carbon \
        -framework Quartz \
        -framework QuickLookThumbnailing \
        "${SOURCES[@]}" \
        -o "${OUTPUT_BIN}" \
        2>&1 | tee "${COMPILE_LOG}"

    if [[ "$CURRENT_ARCH" == "arm64" ]]; then
        BIN_ARM64="${OUTPUT_BIN}"
    else
        BIN_X86_64="${OUTPUT_BIN}"
    fi
done

# Count compiler warnings
WARN_COUNT=$(cat "${OUTPUT_DIR}/compile-logs"/*.log 2>/dev/null | grep -c "warning:" || true); WARN_COUNT=${WARN_COUNT:-0}
if [[ $WARN_COUNT -gt 0 ]]; then
    echo "⚠️  Compiler warnings: $WARN_COUNT"
fi

# For 'both' arch, create universal binary
if [[ "$ARCH" == "both" ]]; then
    echo ""
    echo "🔗 Creating universal binary..."
    mkdir -p "${OUTPUT_DIR}"
    lipo -create "$BIN_ARM64" "$BIN_X86_64" \
        -output "${OUTPUT_DIR}/${APP_NAME}"
    FINAL_BIN="${OUTPUT_DIR}/${APP_NAME}"
else
    if [[ "$ARCH" == "arm64" ]]; then
        FINAL_BIN="$BIN_ARM64"
    else
        FINAL_BIN="$BIN_X86_64"
    fi
fi

# Determine codesign identity
if [[ -z "$SIGN_IDENTITY" ]]; then
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "QTranslate Dev"; then
        SIGN_IDENTITY="QTranslate Dev"
    else
        SIGN_IDENTITY="-"
    fi
fi

# If no entitlements file found, use ad-hoc signing without entitlements
if [[ -z "$ENTITLEMENTS" ]] || [[ ! -f "$ENTITLEMENTS" ]]; then
    ENTITLEMENTS=""
    echo "⚠️  No entitlements file found; signing without entitlements"
fi

# Create .app bundle structure
echo ""
echo "📦 Creating .app bundle..."
APP_DIR="${OUTPUT_DIR}/${APP_NAME}.app"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Copy binary
cp "${FINAL_BIN}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# Generate Info.plist with APP_NAME/BUNDLE_ID/DEPLOY_TARGET from variables
cat > "${APP_DIR}/Contents/Info.plist" <<EOF
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

# Create PkgInfo
echo "APPL????" > "${APP_DIR}/Contents/PkgInfo"

# Handle icon asset
if [[ -d "Assets.xcassets" ]]; then
    echo "🎨 Processing assets..."
    xcrun actool Assets.xcassets \
        --compile "${APP_DIR}/Contents/Resources" \
        --platform macosx \
        --minimum-deployment-target "${DEPLOY_TARGET}" \
        --app-icon AppIcon \
        --output-partial-info-plist "${OUTPUT_DIR}/partial.plist" 2>/dev/null || true
fi

# Code sign
echo ""
echo "🔏 Signing with identity: ${SIGN_IDENTITY}"

if [[ -n "$ENTITLEMENTS" ]] && [[ -f "$ENTITLEMENTS" ]]; then
    codesign \
        --force \
        --deep \
        --sign "${SIGN_IDENTITY}" \
        --entitlements "${ENTITLEMENTS}" \
        "${APP_DIR}"
else
    codesign \
        --force \
        --deep \
        --sign "${SIGN_IDENTITY}" \
        "${APP_DIR}"
fi

# Print authority line
echo ""
echo "✅ Codesign verification:"
codesign -dvv "${APP_DIR}" 2>&1 | grep "Authority" || echo "  (ad-hoc signature)"

# Copy to dist if requested
if [[ "$DIST_FLAG" == true ]]; then
    echo ""
    echo "📤 Copying to dist/"
    rm -rf "dist/${APP_NAME}.app"
    mkdir -p "dist"
    cp -R "${APP_DIR}" "dist/"
    echo "✅ Copied to dist/${APP_NAME}.app"
fi

# Calculate elapsed time
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECONDS=$((ELAPSED % 60))

echo ""
echo "🎉 Build complete in ${MINUTES}m${SECONDS}s"
echo "📍 App location: ${APP_DIR}"
