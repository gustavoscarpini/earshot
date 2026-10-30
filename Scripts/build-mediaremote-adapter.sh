#!/bin/bash
#
# Builds the vendored mediaremote-adapter helper framework with plain clang and
# places it, together with the Perl script, inside the Earshot app bundle.
#
# Runs as an Xcode run-script build phase ("Build MediaRemoteAdapter") of the
# Earshot target, so it relies on Xcode's build environment (ARCHS,
# TARGET_BUILD_DIR, ...). It does not depend on the current directory.
#
# The compile is skipped when the framework binary is newer than every vendored
# source and this script. The Perl script copy and the code signature are always
# refreshed: the framework must be signed before Xcode signs the app.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SRCROOT:-$(dirname "$SCRIPT_DIR")}"
V="$ROOT/Vendor/mediaremote-adapter"

: "${TARGET_BUILD_DIR:?must run from an Xcode build phase}"
: "${FRAMEWORKS_FOLDER_PATH:?must run from an Xcode build phase}"
: "${UNLOCALIZED_RESOURCES_FOLDER_PATH:?must run from an Xcode build phase}"

ARCHS="${ARCHS:-$(uname -m)}"
DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.4}"

FRAMEWORKS_DIR="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
RESOURCES_DIR="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
FW="$FRAMEWORKS_DIR/MediaRemoteAdapter.framework"
BINARY="$FW/Versions/A/MediaRemoteAdapter"

mkdir -p "$FW/Versions/A/Resources" "$RESOURCES_DIR"

# Whether the binary is missing or older than a vendored file or this script.
needs_build() {
    [[ -f "$BINARY" ]] || return 0
    [[ -n "$(find "$V" "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" -type f -newer "$BINARY" -print -quit)" ]]
}

if needs_build; then
    echo "Building MediaRemoteAdapter.framework ($ARCHS)"
    ARCH_FLAGS=()
    for arch in $ARCHS; do
        ARCH_FLAGS+=(-arch "$arch")
    done

    # test.m backs the adapter's "test" function and needs the upstream test
    # client, which is not vendored; Earshot never calls it.
    SOURCES=()
    for source in "$V"/src/adapter/*.m "$V/src/private/MediaRemote.m" "$V"/src/utility/*.m; do
        [[ "$(basename "$source")" == "test.m" ]] || SOURCES+=("$source")
    done

    TMP_BINARY="$(mktemp "${TMPDIR:-/tmp}/MediaRemoteAdapter.XXXXXX")"
    trap 'rm -f "$TMP_BINARY"' EXIT

    clang -dynamiclib -fobjc-arc -fvisibility=default \
        "${ARCH_FLAGS[@]}" \
        -mmacosx-version-min="$DEPLOYMENT_TARGET" \
        -I"$V/include" -I"$V/src" \
        -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
        -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
        "${SOURCES[@]}" \
        -o "$TMP_BINARY"

    mv -f "$TMP_BINARY" "$BINARY"
    chmod 755 "$BINARY"

    cat > "$FW/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MediaRemoteAdapter</string>
    <key>CFBundleIdentifier</key>
    <string>com.vandenbe.MediaRemoteAdapter</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MediaRemoteAdapter</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>CFBundleVersion</key>
    <string>0.1.0</string>
</dict>
</plist>
PLIST

    ln -sfn A "$FW/Versions/Current"
    ln -sfn Versions/Current/MediaRemoteAdapter "$FW/MediaRemoteAdapter"
    ln -sfn Versions/Current/Resources "$FW/Resources"
else
    echo "MediaRemoteAdapter.framework is up to date; skipping compile"
fi

cp -f "$V/bin/mediaremote-adapter.pl" "$RESOURCES_DIR/mediaremote-adapter.pl"

# Ad-hoc when signing is off (CODE_SIGNING_ALLOWED=NO in tests and CI).
codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$FW"
