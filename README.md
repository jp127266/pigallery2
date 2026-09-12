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

`config/config.json` is versioned, but a git clean filter empties its
`sessionSecret` before anything is committed, and a pre-commit hook blocks any
commit that carries a live credential. Both are enabled by `scripts/setup-git.sh`
and are inert until you run it — do that first in every clone.

See [CLAUDE.md](CLAUDE.md) for the fuller operational notes.
