# Sourced by the other scripts in this directory: toolchain for the native
# macOS deployment. Override any of these in the environment if needed.

# Node 22 from Homebrew (package.json requires >=22 <24). Keg-only, so it does
# not clash with nvm, and its path is stable for launchd.
NODE_BIN=${NODE_BIN:-/opt/homebrew/opt/node@22/bin}
if [ ! -x "$NODE_BIN/node" ]; then
    echo "Node 22 not found in $NODE_BIN -- run: brew install node@22" >&2
    exit 1
fi

# ffmpeg with VideoToolbox (hardware video encode/decode). Prefer ffmpeg-full,
# fall back to the plain Homebrew formula.
if [ -z "${FFMPEG_PATH:-}" ]; then
    for dir in /opt/homebrew/opt/ffmpeg-full/bin /opt/homebrew/opt/ffmpeg/bin; do
        if [ -x "$dir/ffmpeg" ]; then
            FFMPEG_PATH=$dir/ffmpeg
            FFPROBE_PATH=$dir/ffprobe
            break
        fi
    done
fi
if [ -z "${FFMPEG_PATH:-}" ]; then
    echo "ffmpeg not found -- run: brew install ffmpeg" >&2
    exit 1
fi

# launchd starts jobs with a minimal PATH, so set everything explicitly.
# /opt/homebrew/bin provides pkg-config, which sharp's source build needs.
PATH="$NODE_BIN:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
NODE_OPTIONS=--max_old_space_size=4096
export PATH NODE_OPTIONS FFMPEG_PATH FFPROBE_PATH
