#!/bin/sh
# Run PiGallery2 natively in the foreground. launchd runs this (see
# service.sh); running it by hand is fine for debugging -- stop the service
# first, both bind the same port.
#
# The data paths are passed on the command line, derived from where this repo
# is checked out, so they override config/config.macos.json. The settings page
# shows them read-only for that reason.
set -eu
REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/macos/env.sh"

APP=$REPO/app
if [ ! -f "$APP/src/backend/index.js" ]; then
    echo "No build in $APP -- run scripts/macos/build.sh first" >&2
    exit 1
fi

mkdir -p "$REPO/photos" "$REPO/db" "$REPO/tmp"

export NODE_ENV=production
cd "$APP"
exec node --expose-gc ./src/backend/index \
    --config-path="$REPO/config/config.macos.json" \
    --Media-folder="$REPO/photos" \
    --Media-tempFolder="$REPO/tmp" \
    --Database-dbFolder="$REPO/db" \
    --Extensions-folder="$REPO/config/extensions"
