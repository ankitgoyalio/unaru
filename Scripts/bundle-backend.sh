#!/bin/sh
# Build the native helper for each app architecture, then sign it inside the app.
set -eu
[ "$PLATFORM_NAME" = macosx ] || exit 0
repo_root=$(CDPATH= cd -- "$SRCROOT/../.." && pwd)
build_mode=$(printf '%s' "$CONFIGURATION" | tr '[:upper:]' '[:lower:]')
helper_dir="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
mkdir -p "$helper_dir"
set --
for architecture in $ARCHS; do
    scratch="$repo_root/.build/bundled-backend/$build_mode-$architecture"
    # Xcode exports SDKROOT for the app; SwiftPM must select the native macOS SDK.
    env -u SDKROOT -u SDK_DIR xcrun swift build --package-path "$repo_root/backend" \
        --scratch-path "$scratch" --configuration "$build_mode" --arch "$architecture" \
        --disable-index-store --product Backend
    binary_dir=$(env -u SDKROOT -u SDK_DIR xcrun swift build --package-path "$repo_root/backend" \
        --scratch-path "$scratch" --configuration "$build_mode" --arch "$architecture" \
        --disable-index-store --show-bin-path)
    set -- "$@" "$binary_dir/Backend"
done
xcrun lipo -create "$@" -output "$helper_dir/Backend"
chmod 755 "$helper_dir/Backend"
if [ "${CODE_SIGNING_ALLOWED:-YES}" != NO ]; then
    identity=${EXPANDED_CODE_SIGN_IDENTITY:--}
    [ -n "$identity" ] || identity=-
    /usr/bin/codesign --force --sign "$identity" --options runtime \
        --entitlements "$repo_root/backend/BundledBackend.entitlements" "$helper_dir/Backend"
fi
