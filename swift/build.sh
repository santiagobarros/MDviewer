#!/bin/bash
# Builds the Swift port and swaps its binaries into the app bundle produced by
# the root build.sh, which continues to own resources, vendored libraries,
# plists, entitlements, and bundle layout.

set -euo pipefail

SWIFT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SWIFT_DIR/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/Markdown Viewer.app"
APPEX_DIR="$APP_DIR/Contents/PlugIns/MarkdownViewerQuickLook.appex"

echo "Building ObjC bundle scaffold..."
"$ROOT_DIR/build.sh" build

echo "Building Swift targets..."
cd "$SWIFT_DIR"
swift build -c release

BIN="$SWIFT_DIR/.build/release"

echo "Swapping in Swift binaries..."
cp "$BIN/MarkdownViewerApp" "$APP_DIR/Contents/MacOS/MarkdownViewer"
cp "$BIN/QuickLookPreview" "$APPEX_DIR/Contents/MacOS/MarkdownViewerQuickLook"
cp "$BIN/RenderHelper" "$APP_DIR/Contents/MacOS/MarkdownViewerRenderHelper"

# Same identity selection as the root build.sh: CODESIGN_IDENTITY override,
# then Developer ID Application (hardened runtime + timestamp, the
# notarization prerequisites), then Apple Development, then ad-hoc.
resolve_signing_identity() {
    if [ -n "${CODESIGN_IDENTITY:-}" ]; then
        printf '%s' "$CODESIGN_IDENTITY"
        return
    fi

    local identity
    identity="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
    if [ -n "$identity" ]; then
        printf '%s' "$identity"
        return
    fi

    identity="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')"
    if [ -n "$identity" ]; then
        printf '%s' "$identity"
        return
    fi

    printf '%s' "-"
}

if command -v codesign >/dev/null 2>&1; then
    identity="$(resolve_signing_identity)"
    sign_flags=()
    case "$identity" in
        "Developer ID Application"*)
            sign_flags=(--options runtime --timestamp)
            ;;
    esac

    codesign --force --sign "$identity" "${sign_flags[@]+"${sign_flags[@]}"}" --entitlements "$ROOT_DIR/src/quicklook.entitlements" "$APPEX_DIR"
    codesign --force --sign "$identity" "${sign_flags[@]+"${sign_flags[@]}"}" "$APP_DIR/Contents/MacOS/MarkdownViewerRenderHelper"
    codesign --force --sign "$identity" "${sign_flags[@]+"${sign_flags[@]}"}" "$APP_DIR"
    echo "Signed with: $identity"
fi

echo "Done! Swift-powered bundle -> $APP_DIR"

# "installer" also wraps the Swift bundle in the .pkg wizard.
if [ "${1:-build}" = "installer" ]; then
    echo "Building installer around the Swift bundle..."
    MDV_SKIP_BUILD=1 "$ROOT_DIR/build.sh" installer
fi
