#!/bin/bash
# macOS FFmpeg Preparation Script
# Called by Xcode Build Phase before copying FFmpeg to app bundle
#
# This script:
# 1. Checks if FFmpeg exists locally
# 2. Downloads it automatically if missing
# 3. Copies and signs it for the app bundle

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$MACOS_DIR")"

FFMPEG_SRC="${MACOS_DIR}/Runner/Resources/ffmpeg/ffmpeg"
FFMPEG_DST="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/MacOS/ffmpeg"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo "${GREEN}[FFmpeg]${NC} $1"; }
log_warn() { echo "${YELLOW}[FFmpeg]${NC} $1"; }
log_error() { echo "${RED}[FFmpeg]${NC} $1" >&2; }

# Download FFmpeg if not exists
download_ffmpeg() {
    log_info "FFmpeg not found, downloading..."

    local tmp_dir=$(mktemp -d)
    local martin_riedl="https://ffmpeg.martin-riedl.de/redirect/latest"

    # Download arm64
    log_info "  Downloading arm64..."
    curl -sL "$martin_riedl/macos/arm64/release/ffmpeg.zip" -o "$tmp_dir/arm64.zip"
    unzip -q "$tmp_dir/arm64.zip" -d "$tmp_dir/arm64"

    # Download x86_64
    log_info "  Downloading x86_64..."
    curl -sL "$martin_riedl/macos/amd64/release/ffmpeg.zip" -o "$tmp_dir/x64.zip"
    unzip -q "$tmp_dir/x64.zip" -d "$tmp_dir/x64"

    # Create Universal binary
    log_info "  Creating Universal binary..."
    mkdir -p "$(dirname "$FFMPEG_SRC")"
    lipo -create "$tmp_dir/arm64/ffmpeg" "$tmp_dir/x64/ffmpeg" -output "$FFMPEG_SRC"
    chmod +x "$FFMPEG_SRC"

    # Cleanup
    rm -rf "$tmp_dir"

    log_info "FFmpeg downloaded successfully"
}

# Check if FFmpeg exists and is Universal
check_ffmpeg() {
    if [ ! -f "$FFMPEG_SRC" ]; then
        return 1
    fi

    # Check if it's a Universal binary
    if ! file "$FFMPEG_SRC" | grep -q "universal"; then
        log_warn "Existing FFmpeg is not Universal, re-downloading..."
        return 1
    fi

    return 0
}

# Main
log_info "Preparing FFmpeg for macOS build..."

# Download if needed
if ! check_ffmpeg; then
    download_ffmpeg
fi

# Copy to app bundle
if [ -f "$FFMPEG_SRC" ]; then
    mkdir -p "$(dirname "$FFMPEG_DST")"
    cp -f "$FFMPEG_SRC" "$FFMPEG_DST"
    chmod +x "$FFMPEG_DST"

    # Sign with ad-hoc signature for local development
    # For release builds, use proper code signing with sandbox entitlements
    FFMPEG_ENTITLEMENTS="${MACOS_DIR}/Runner/Resources/ffmpeg/ffmpeg.entitlements"
    if [ "$CONFIGURATION" = "Debug" ]; then
        codesign --force --sign - "$FFMPEG_DST" 2>/dev/null || true
        log_info "FFmpeg copied and signed (ad-hoc)"
    else
        # For Release/Profile, sign with the same identity as the app
        # and include sandbox entitlements
        if [ -f "$FFMPEG_ENTITLEMENTS" ]; then
            # Unsigned CI builds disable Xcode code signing. Xcode can still
            # expose the project's Apple Development identity in
            # EXPANDED_CODE_SIGN_IDENTITY, so do not attempt to use it when
            # CODE_SIGNING_ALLOWED=NO; use an ad-hoc signature for the copied
            # executable instead.
            if [ "${CODE_SIGNING_ALLOWED:-YES}" = "NO" ]; then
                SIGN_IDENTITY="-"
            else
                SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY}"
                if [ -z "$SIGN_IDENTITY" ]; then
                    SIGN_IDENTITY="${CODE_SIGN_IDENTITY}"
                fi
            fi
            if [ -z "$SIGN_IDENTITY" ] || [ "$SIGN_IDENTITY" = "-" ]; then
                SIGN_IDENTITY="-"
            fi
            log_info "Signing FFmpeg with identity: $SIGN_IDENTITY"
            codesign --force --sign "$SIGN_IDENTITY" \
                --entitlements "$FFMPEG_ENTITLEMENTS" \
                --options runtime \
                "$FFMPEG_DST"
            log_info "FFmpeg copied and signed with sandbox entitlements"
        else
            log_warn "FFmpeg entitlements not found, using ad-hoc signing"
            codesign --force --sign - "$FFMPEG_DST" 2>/dev/null || true
        fi
    fi
else
    log_error "FFmpeg still not available after download attempt"
    exit 1
fi

log_info "Done!"
