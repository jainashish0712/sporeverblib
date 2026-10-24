#!/usr/bin/env bash
set -e

echo "Building SpotifyReverb.dylib for arm64 iOS..."

SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || echo "")

if [ -n "$SDK_PATH" ]; then
    xcrun -sdk iphoneos clang -dynamiclib -arch arm64 -arch arm64e \
        -miphoneos-version-min=14.0 \
        -isysroot "$SDK_PATH" \
        -framework Foundation -framework AudioToolbox \
        -O3 -fobjc-arc \
        fishhook.c SpotifyReverb.m \
        -o SpotifyReverb.dylib
else
    echo "Using direct clang..."
    clang -dynamiclib -target arm64-apple-ios14.0 \
        -framework Foundation -framework AudioToolbox \
        -O3 -fobjc-arc \
        fishhook.c SpotifyReverb.m \
        -o SpotifyReverb.dylib
fi

echo "Successfully built SpotifyReverb.dylib!"
