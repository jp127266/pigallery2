#!/bin/sh
# Build PiGallery2 from pigallery2-src/ to run natively on macOS (no Docker).
#
# The native counterpart of Dockerfile.custom's srcbuild + builder stages: it
# compiles the patched source and installs the result, with its runtime
# dependencies, into app/ (gitignored). Re-run after changing anything in
# pigallery2-src/, then `scripts/macos/service.sh restart`.
set -eu
REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/macos/env.sh"

cd "$REPO/pigallery2-src"
npm ci
npx tsc
# ffmpeg-static/ffprobe-static would shadow Homebrew's ffmpeg (FFmpegFactory
# prefers them), and their builds are not guaranteed to have VideoToolbox.
# Dropping them makes fluent-ffmpeg use FFMPEG_PATH/FFPROBE_PATH from env.sh.
npx gulp create-release --skip-opt-packages=ffmpeg-static,ffprobe-static

# Move the release out of the source tree. Left in pigallery2-src/release, Node
# would resolve modules from pigallery2-src/node_modules (the build deps) too --
# including ffprobe-static, whose macOS binary is x86-only and fails to spawn.
rm -rf "$REPO/app"
mv release "$REPO/app"
cd "$REPO/app"
# No lockfile ships with the release (see gulpfile copy-static-text), so this
# resolves from package.json -- the same as upstream's Docker build.
npm install --omit=dev --no-package-lock

# Same smoke test the Docker build runs: checks sharp, ffmpeg and the DB layer.
# It gets a throwaway config and data folders so it cannot touch the real ones.
DIAG=$(mktemp -d)
trap 'rm -rf "$DIAG"' EXIT
mkdir -p "$DIAG/images" "$DIAG/tmp" "$DIAG/db"
node ./src/backend/index --run-diagnostics \
    --config-path="$DIAG/config.json" \
    --Media-folder="$DIAG/images" \
    --Media-tempFolder="$DIAG/tmp" \
    --Database-dbFolder="$DIAG/db" \
    --Extensions-folder="$DIAG/extensions"

echo "Built $REPO/app"
