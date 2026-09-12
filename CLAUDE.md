# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this directory is

A self-hosted **Docker deployment** of PiGallery2 (a photo gallery server), together with the patched source it is built from. It runs a locally built image, `pigallery2:custom-3.5.2` — **not** the upstream `bpatrik/pigallery2:latest`.

Two halves live here:

- **Deployment** — `docker-compose.yml`, `config/`, `db/`, `tmp/`: the running service and its state.
- **Source** — [pigallery2-src/](pigallery2-src/): a git clone of upstream (https://github.com/bpatrik/pigallery2) at tag `3.5.2`, with local patches committed on branch **`custom-3.5.2`**. Used only to build the image; it is *not* mounted into the container.

Everything is orchestrated by [docker-compose.yml](docker-compose.yml). The container is named `pigallery2` and the web UI is published on host port **8082** (mapped to container port 80).

## Common commands

```bash
# Lifecycle
docker compose up -d            # start (or apply compose changes)
docker compose down             # stop and remove the container
docker restart pigallery2       # restart in place — REQUIRED after editing config/config.json

# Rebuild the custom image after changing anything in pigallery2-src/
# (run from this directory; the build context is pigallery2-src, NOT `.` —
#  a `.` context would ship the multi-GB tmp/ cache to the docker daemon)
docker build -f pigallery2-src/Dockerfile.custom -t pigallery2:custom-3.5.2 pigallery2-src
docker compose up -d

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
| `/home/jp127266/Codes/vripper/download` | `/app/data/images` | Photo originals, mounted **read-only** (`:ro`). PiGallery2 never modifies originals. |
| `./pigallery2-src` | *(not mounted)* | Patched PiGallery2 3.5.2 source (git, branch `custom-3.5.2`). Build input for the image only — the container never reads it at runtime. |

Note the photo source is the download output of a sibling `vripper` deployment. Files written by the container (`db/`, `tmp/`) are owned by `root` because the container runs as root — use `sudo`/`docker exec` if you need to manipulate them from the host.

## The custom source

[pigallery2-src/](pigallery2-src/) is upstream at tag `3.5.2` plus one commit on branch `custom-3.5.2`. See exactly what is customized with:

```bash
git -C pigallery2-src diff 3.5.2..custom-3.5.2
```

The patches:

- **HiDPI lightbox previews** — [media.lightbox.gallery.component.ts](pigallery2-src/src/frontend/app/ui/gallery/lightbox/media/media.lightbox.gallery.component.ts) requests previews at physical (`devicePixelRatio`-scaled, capped at 3×) pixels instead of CSS pixels, so previews are no longer blurry on HiDPI displays.
- **Close key `Escape` → `x`** — in both the gallery and map lightbox controls components.
- **[Dockerfile.custom](pigallery2-src/Dockerfile.custom)** — adds a `srcbuild` stage that compiles this source (`npm ci`, `tsc`, `gulp create-release`) and feeds it into upstream's alpine build/runtime stages. Its runtime stage deliberately pulls `vips` from the *same* Alpine edge repos as the builder; a mismatch breaks thumbnailing with `vips_colourspace: no known route from 'srgb' to 'last'` (that comment in the file is load-bearing — don't "clean it up").

Keep the working tree clean: commit further customizations to `custom-3.5.2` rather than leaving them as uncommitted edits. `origin` is upstream, so never push this branch there.

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
