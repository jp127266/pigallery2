# pigallery2 deployment

Self-hosted [PiGallery2](https://github.com/bpatrik/pigallery2) photo gallery,
running a locally built image with a few local patches. This repo holds both the
deployment (compose file, settings) and the patched source it is built from.

## Run it on a new machine

Requires Docker with the Compose plugin. Photos are read from a directory you
already have; nothing in this repo contains images.

```bash
git clone git@github.com:jp127266/pigallery2.git
cd pigallery2

./scripts/setup-git.sh          # enables the secret filter + pre-commit hook

cp .env.example .env
$EDITOR .env                    # set PHOTOS_DIR to your photo library

docker compose up -d            # builds the image on first run, then starts
```

The first run builds the image from `pigallery2-src/`, which takes several
minutes (it compiles the frontend). Later runs reuse it. Then open
<http://localhost:8082> and log in with **`admin` / `admin`**.

**Change that password immediately** — it is the default PiGallery2 creates for
an empty database, and it is an admin account.

### First-run expectations

- The gallery starts empty. Indexing runs in the background; large libraries
  take a while. Trigger it manually from *Settings → Jobs* if needed.
- Thumbnails generate on demand, so the first browse through a folder is slow.
- `db/` and `tmp/` are created automatically (owned by root, since the container
  runs as root). Neither is in the repo: `db/` holds password hashes and face
  data, `tmp/` is a regenerable multi-GB cache.

## Everyday commands

```bash
docker compose up -d            # start, or apply compose/.env changes
docker compose up -d --build    # rebuild after editing pigallery2-src/
docker restart pigallery2       # apply a config/config.json edit
docker logs -f pigallery2
```

`config/config.json` is not hot-reloaded — restart the container after editing
it, then hard-refresh the browser (Ctrl+Shift+R).

## Run it natively on macOS (Apple Silicon)

No Docker and no VM: the same patched source runs directly on Node, kept alive
by a launchd agent. Photos are read from `photos/` in this repo (gitignored).

```bash
./scripts/setup-git.sh                  # once per clone, as above
brew install node@22 ffmpeg             # ffmpeg-full also works
scripts/macos/build.sh                  # compile into app/ (a few minutes)
scripts/macos/service.sh install        # start now and at every login
```

Then open <http://localhost:8082> and log in with **`admin` / `admin`** —
change that password immediately.

```bash
scripts/macos/service.sh restart        # apply a config/config.macos.json edit
scripts/macos/service.sh logs           # follow ~/Library/Logs/pigallery2/pigallery2.log
scripts/macos/service.sh status
scripts/macos/service.sh uninstall      # stop and remove the agent
scripts/macos/build.sh && scripts/macos/service.sh restart   # after editing pigallery2-src/
```

Settings live in `config/config.macos.json`, not `config/config.json`. The two
hosts need different values (paths, port, video encoder), and the settings page
saves the whole file, so sharing one file would let a save on one host break
the other.

Differences from the Docker deployment:

- Video transcoding uses Apple's hardware encoder (`h264_videotoolbox`, with
  hardware decoding and constant quality `-q:v 65`) — about 6× less CPU than
  `libx264`. Photo thumbnails are CPU-only either way (sharp/libvips).
- HEIC photos are not supported: the prebuilt libvips that sharp ships decodes
  AVIF but not HEVC-based HEIC.
- The data paths are passed on the command line by `scripts/macos/run.sh`, so
  they follow wherever the repo is checked out, and show as read-only in the
  settings page.

## What is patched

`pigallery2-src/` is upstream 3.5.2 plus one commit, imported as a git subtree:

```bash
git diff upstream-3.5.2 custom-3.5.2
```

- Lightbox previews are requested at physical (devicePixelRatio-scaled) pixels,
  so they are not blurry on HiDPI displays.
- The lightbox close key is `x` instead of `Escape`.
- `Dockerfile.custom` builds the release from source and pins runtime `vips` to
  the same Alpine repos as the builder (an ABI mismatch there breaks
  thumbnailing).

Because it is a subtree, upstream releases can still be merged in:

```bash
git subtree pull --prefix=pigallery2-src \
    https://github.com/bpatrik/pigallery2.git 3.6 --squash
```

## Secrets

`config/config.json` is versioned, but a git clean filter strips its
`sessionSecret` before anything is committed, and a pre-commit hook blocks any
commit that carries a live credential. The key is removed rather than emptied:
PiGallery2 generates a secret at startup, and an explicit empty array would
overwrite it, leaving the server unable to sign cookies (login fails with
`Keys must be provided.`). Both are enabled by `scripts/setup-git.sh`
and are inert until you run it — do that first in every clone.

See [CLAUDE.md](CLAUDE.md) for the fuller operational notes.
