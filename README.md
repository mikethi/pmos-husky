# PostmarketOS linux and device config

## Mirror Pixel repositories locally

Use `mirror-pixel-repos.sh` to keep a local copy of Pixel-related repositories under `external/pixel-mirror`.

1. Edit `pixel-mirror.conf` entries:

```text
repo_url|ref|dest_dir
```

2. Run the mirror update:

```bash
./mirror-pixel-repos.sh
```

## Sync selected material into this repo

Use `sync-sources.sh` to pull specific files or directories from mirrored or external repositories before building.

1. Edit `sync-sources.conf` and add entries in this format:

```text
repo_url|ref|source_path|dest_path
```

2. Run the sync:

```bash
./sync-sources.sh
```

## Passive build loop

Use `passive-build.sh` to continuously:

1. Refresh local Pixel mirrors.
2. Sync selected source material.
3. Run your build command when source changes are detected.

Setup:

1. Edit `passive-build.conf` and set `BUILD_COMMAND`.
2. Keep `PRE_SYNC_COMMAND="./mirror-pixel-repos.sh"` enabled for automatic mirror updates.
3. Start passive mode:

```bash
./passive-build.sh
```

Optional custom config:

```bash
./passive-build.sh /path/to/passive-build.conf
```

## Bare-metal OTA digest

Dropped OTA metadata was digested into `bare-metal-husky.conf` and `external-ota-digest.md`.

- `bare-metal-husky.conf` holds the build fingerprint, board identity, and the partition list kept for bare-metal work.
- Android software partitions are intentionally hashed out there and in the digest notes.
