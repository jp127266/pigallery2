#!/bin/sh
# Build PiGallery2 from pigallery2-src/ to run natively on macOS (no Docker).
#
# The native counterpart of Dockerfile.custom's srcbuild + builder stages: it
# compiles the patched source and installs the result, with its runtime
# dependencies, into app/ (gitignored). Re-run after changing anything in
# pigallery2-src/; if the launchd service is installed it is restarted onto
# the new build at the end.
#
# The build happens in app.new/ and replaces app/ only once it has passed its
# checks, so a running server keeps working throughout, and a failed build
# leaves the old one in place.
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
rm -rf "$REPO/app.new"
mv release "$REPO/app.new"
cd "$REPO/app.new"
# Compile sharp against Homebrew's libvips rather than using its prebuilt one:
# the prebuilt libvips has no HEVC decoder, so it cannot read HEIC (only AVIF).
# Same approach as Dockerfile.custom's builder stage. The build links to the
# installed libvips, so re-run this script after `brew upgrade vips`.
if ! pkg-config --exists vips-cpp; then
    echo "libvips not found -- run: brew install vips" >&2
    exit 1
fi
export SHARP_FORCE_GLOBAL_LIBVIPS=1
# No lockfile ships with the release (see gulpfile copy-static-text), so this
# resolves from package.json -- the same as upstream's Docker build.
# node-addon-api and node-gyp are only needed for sharp's source build, and are
# pruned right after.
npm install --no-package-lock --save-dev node-addon-api@8.5.0 node-gyp@11.5.0
npm prune --omit=dev

# sharp falls back to its prebuilt binary, with only a log line, when the
# source build cannot run -- so check the result rather than trusting it.
node -e '
const sharp = require("sharp");
if (!sharp.format.heif.input.fileSuffix.includes(".heic")) {
    console.error("sharp was not built against Homebrew libvips: no HEIC support");
    process.exit(1);
}
console.log("sharp uses libvips " + sharp.versions.vips + " with HEIC support");
'

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

# Swap the new build in and restart onto it straight away: the old process
# lazily loads modules by path, and those paths now point at the new build.
cd "$REPO"
rm -rf app.old
if [ -d app ]; then mv app app.old; fi
mv app.new app
rm -rf app.old
echo "Built $REPO/app"

if launchctl print "gui/$(id -u)/local.pigallery2" >/dev/null 2>&1; then
    "$REPO/scripts/macos/service.sh" restart
    echo "Restarted the service onto the new build"
fi
