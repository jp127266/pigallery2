# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this directory is

A self-hosted **Docker deployment** of PiGallery2 (a photo gallery server), together with the patched source it is built from. It runs a locally built image, `pigallery2:custom-3.5.2` — **not** the upstream `bpatrik/pigallery2:latest`.

Two halves live here:

- **Deployment** — `docker-compose.yml`, `config/`, `db/`, `tmp/`: the running service and its state.
- **Source** — [pigallery2-src/](pigallery2-src/): upstream (https://github.com/bpatrik/pigallery2) `master` as of 2026-08-11 (3.5.2 + 60 unreleased commits) plus local patches, imported as a **git subtree** of this repo. Used only to build the image; it is *not* mounted into the container.

Everything is orchestrated by [docker-compose.yml](docker-compose.yml). The container is named `pigallery2` and the web UI is published on host port **8082** (mapped to container port 80).

On macOS (Apple Silicon) the same source instead runs **natively** — no Docker, no VM — via [scripts/macos/](scripts/macos/); see *Native macOS deployment* below. Which of the two is in use depends on the host.

This directory is a git repo pushed to `git@github.com:jp127266/pigallery2.git`. The source under `pigallery2-src/` was imported with **git subtree**, so upstream's full history came along and upstream upgrades are still possible (see *Upgrading* below).

### After cloning

```bash
scripts/setup-git.sh          # REQUIRED: enables the secret filter + pre-commit hook
cp .env.example .env          # then set PHOTOS_DIR for this host
docker compose up -d          # builds the image on first run, then starts
```

Git does not clone filter or hook configuration, so without this the session
secrets in `config/config.json` would be committed in the clear. The hook
refuses such a commit, so the worst case is a blocked commit rather than a leak
— but run it first thing regardless.

## Common commands

```bash
# Lifecycle
docker compose up -d            # start (or apply compose changes)
docker compose down             # stop and remove the container
docker restart pigallery2       # restart in place — REQUIRED after editing config/config.json

# Rebuild the custom image after changing anything in pigallery2-src/.
# compose builds it automatically when the image is missing; --build forces it.
docker compose up -d --build

# Observe
docker ps --filter name=pigallery2          # status / health
docker logs -f pigallery2                    # follow logs
docker exec -it pigallery2 sh                # shell into the container
```

After changing [config/config.json](config/config.json), the running server does **not** hot-reload — restart the container for changes to take effect, then hard-refresh the browser (Ctrl+Shift+R) to clear cached view state.

## Layout & volume mounts

The host directory is bind-mounted into the container (see [docker-compose.yml](docker-compose.yml)):

| Host path | Container path | Purpose |
|---|---|---|
| `./config` | `/app/data/config` | `config.json` — the single source of truth for settings |
| `./db` | `/app/data/db` | SQLite databases: `sqlite.db` (gallery index, users, faces) and `jobs.db` |
| `./tmp` | `/app/data/tmp` | Speed cache: generated thumbnails & screen-sized previews. Safe to delete; will regenerate. |
| `$PHOTOS_DIR` | `/app/data/images` | Photo originals, mounted **read-only** (`:ro`). Set per host in `.env`; defaults to `/home/jp127266/Codes/vripper/download`. |
| `./pigallery2-src` | *(not mounted)* | Patched PiGallery2 source (upstream master, post-3.5.2). Build input for the image only — the container never reads it at runtime. |

On this host the photo source is the download output of a sibling `vripper` deployment; elsewhere it is whatever `PHOTOS_DIR` points at. A wrong path fails silently — Docker creates the missing directory and the gallery comes up empty. Files written by the container (`db/`, `tmp/`) are owned by `root` because the container runs as root — use `sudo`/`docker exec` if you need to manipulate them from the host.

## The custom source

[pigallery2-src/](pigallery2-src/) is upstream `master` (commit `dc456950`, merged 2026-09-27; there has been no release after `3.5.2`) plus local patches. The patches were originally one commit on top of `3.5.2`; see it with:

```bash
git diff upstream-3.5.2 custom-3.5.2
```

Both are tags in *this* repo. The image tag `custom-3.5.2` was kept as-is even though the source is now past 3.5.2. `pigallery2-src/` is a subtree, not a nested repo,
so `git -C pigallery2-src ...` will not work — run git from the repo root.
Note that those two commits predate the subtree import, so the paths in that
diff are repo-root relative (`src/frontend/...`) with no `pigallery2-src/` prefix.

The patches:

- **HiDPI lightbox previews** — [media.lightbox.gallery.component.ts](pigallery2-src/src/frontend/app/ui/gallery/lightbox/media/media.lightbox.gallery.component.ts) requests previews at physical (`devicePixelRatio`-scaled, capped at 3×) pixels instead of CSS pixels, so previews are no longer blurry on HiDPI displays.
- **Close key `Escape` → `x`** — in both the gallery and map lightbox controls components.
- **[Dockerfile.custom](pigallery2-src/Dockerfile.custom)** — adds a `srcbuild` stage that compiles this source (`npm ci`, `tsc`, `gulp create-release`) and feeds it into upstream's alpine build/runtime stages. Its runtime stage deliberately pulls `vips` from the *same* Alpine edge repos as the builder; a mismatch breaks thumbnailing with `vips_colourspace: no known route from 'srgb' to 'last'` (that comment in the file is load-bearing — don't "clean it up").

Keep the working tree clean: commit further customizations here rather than leaving them as uncommitted edits, so a rebuild is always reproducible from a committed state.

### Upgrading to a newer upstream release

`pigallery2-src/` is a subtree, not a plain copy, so upstream can still be merged in.
It was imported with full history, so pull **without** `--squash` — git then
does a real three-way merge against the shared upstream base:

```bash
git subtree pull --prefix=pigallery2-src \
    https://github.com/bpatrik/pigallery2.git master     # or a release tag
```

Upstream's own Dockerfile (`docker/alpine/Dockerfile.build`) has since moved to
Alpine 3.23 without edge repos; `Dockerfile.custom` still uses edge for all
stages, which is consistent and works — change it only as a whole.

Resolve conflicts in the patched lightbox files, rebuild the image, then bump
the `custom-3.5.2` tag in docker-compose.yml to match the new version.

## Secrets

Nothing secret may enter this repo. Two mechanisms enforce that, both enabled by
`scripts/setup-git.sh`:

- **Clean filter** ([scripts/strip-config-secrets.py](scripts/strip-config-secrets.py)) — `config/config.json` is committed with the `sessionSecret` key *removed*, while the file on disk keeps the real keys. Blanking the live file instead would invalidate every login session on the next restart, and the filter also keeps `git status` quiet, since it normalises both sides of the comparison.

  The key must be **absent, not empty**. PiGallery2 generates a secret in its config constructor, before `config.json` is read ([PrivateConfigClass.ts](pigallery2-src/src/common/config/private/PrivateConfigClass.ts)); an explicit `"sessionSecret": []` overwrites that generated value and nothing regenerates it, so `cookie-session` throws `Keys must be provided.` and **every login fails**. Do not "tidy" the filter into emitting an empty array.
- **Pre-commit hook** ([scripts/git-hooks/pre-commit](scripts/git-hooks/pre-commit)) — inspects staged content and blocks any commit carrying a live `sessionSecret` or a populated `mapboxAccessToken` / `clientSecret` / `password` / `apiKey`. This is the backstop for clones where the filter was never set up.

`db/` and `tmp/` are gitignored: the database holds user password hashes and face
data, and `tmp/` is a multi-GB regenerable cache.

## Native macOS deployment

Used on the Apple Silicon Mac instead of Docker. Same source, same patches, same `db/`/`tmp/` layout and port 8082.

```bash
brew install node@22 ffmpeg                 # node@22: package.json requires >=22 <24
scripts/macos/build.sh                      # pigallery2-src -> app/ (+ runtime deps, diagnostics)
scripts/macos/service.sh install            # launchd agent local.pigallery2: starts now and at login, restarts on crash
scripts/macos/service.sh restart|status|logs|uninstall
```

- **Build output is `app/`** (gitignored), deliberately *outside* `pigallery2-src/`. A release left in `pigallery2-src/release` resolves modules from `pigallery2-src/node_modules` too, picking up `ffprobe-static`, whose macOS binary is x86-only and fails to spawn (`Unknown system error -86`). For the same reason the build skips `ffmpeg-static`/`ffprobe-static`; [scripts/macos/env.sh](scripts/macos/env.sh) points `FFMPEG_PATH`/`FFPROBE_PATH` at Homebrew's ffmpeg instead.
- **Config is [config/config.macos.json](config/config.macos.json)**, not `config/config.json`. It differs in port (8082), data paths, and video encoding. Do not merge the two: the settings page saves the *whole* file, including values given on the command line, so one shared file would get this host's paths written into it and break the other deployment. It gets the same `sessionSecret` clean filter (see `.gitattributes`).
- **Data paths are CLI overrides** in [scripts/macos/run.sh](scripts/macos/run.sh) (`--Media-folder=<repo>/photos` etc.), computed from the checkout location, so they win over the file and appear read-only in the UI. Photos live in `photos/` (gitignored).
- **Video transcoding uses VideoToolbox**: `mp4Codec: h264_videotoolbox`, `customInputOptions: ["-hwaccel videotoolbox"]`, `customOutputOptions: ["-q:v 65"]`. The `-q:v` is required, not tuning: PiGallery2 only passes `-b:v` when the source exceeds the bitrate cap, and VideoToolbox ignores `-crf`, so without it the output bitrate is uncontrolled. PiGallery2 always adds `-crf`/`-preset`; VideoToolbox ignores both (a warning, not an error).
- **Photos are CPU-only** (sharp's prebuilt libvips). That libvips cannot decode HEIC (AVIF only) — the HEIF errors in the startup diagnostics are expected.
- Log: `~/Library/Logs/pigallery2/pigallery2.log` (not rotated).

## Configuration model

[config/config.json](config/config.json) is a large, fully-populated config (every option is written out with adjacent `"//[key]"` comment strings describing it). Paths inside it (e.g. `/app/data/images`) are **container** paths, not host paths. Key sections:

- **Server** — `port` (80 inside container), threading, caching.
- **Users** — `authenticationRequired: true`; login is enforced.
- **Database** — `type: sqlite`, stored under `/app/data/db`.
- **Media** — `folder` = `/app/data/images` (the read-only originals), `tempFolder` = `/app/data/tmp`.
- **Gallery.NavBar.SortingGrouping** — default sort/group for directory and search views (`defaultPhotoSortingMethod`, `defaultSearchSortingMethod`, and the matching `*GroupingMethod`). Each has a `method` (`Name`/`Date`/`Rating`/`PersonCount`/`FileSize`/`Random`) and `ascending` bool.
- **Faces**, **Sharing**, **Search**, **Album**, **Map**, **Jobs/Indexing**, **Duplicates** — feature toggles and their settings.

When changing a setting, prefer editing `config.json` over the web UI's settings page so the change is captured in this directory, then restart the container.

## Operational notes

- The gallery index (folders, photos, faces) is built into `db/sqlite.db` by background indexing jobs. If new photos appear in the source folder but not in the gallery, trigger re-indexing from the UI's admin/jobs page (config under the `Jobs`/`Indexing` sections).
- Deleting `tmp/` only drops the cache; the next view regenerates thumbnails (slower first load). Deleting `db/sqlite.db` discards the index, users, and face data — destructive.
