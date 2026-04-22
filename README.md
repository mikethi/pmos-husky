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

## Canonical hardware sources

The repo has a strict source-of-truth order for bare-metal work. Start with these files before relying on any derived note.

1. `bare-metal-zuma.dts`

	Normalized board-facing DTS for direct bring-up work. This is the best working hardware definition in the repo for:

	- root SoC identity
	- reserved-memory layout
	- UART and console path
	- pinctrl and UART mux
	- UFS rail enable
	- chosen bootargs

2. `626000system.dtb.txt`, `6840A5systemdtb.txt`, `6e2142system.dtb.txt`, `740543system.dtb.txt`

	Decompiled stock DTB evidence. These are closer to stock hardware truth than the markdown analysis and should be used to verify carveouts, compatibles, and peripheral definitions.

3. `external/newfile.txt`

	Raw overlay and board wiring evidence. This is the strongest source in the repo for:

	- board pin assignments
	- thermal and protection zones
	- wireless charger tuning
	- board model and compatible strings
	- rail-class bindings
	- panel supply bindings

4. `external/metadata` and `external/payload_properties.txt`

	Raw OTA identity and payload verification inputs.

## Canonical config surface

These files are not raw hardware dumps, but they are the cleanest normalized bare-metal config artifacts built from that evidence.

1. `bare-metal-husky.conf`

	Canonical bare-metal manifest for:

	- OTA identity
	- board identity
	- hardware and firmware partition boundary

2. `bare-metal-install.sh`

	Operational installer logic built on the manifest above. Treat it as config surface and workflow tooling, not as raw hardware truth.

## Derived material

These files are downstream interpretation or scaffolding, not canonical hardware sources:

- `external-ota-digest.md`
- `tensor-g1-g2-g3-comparison.md`
- `husky-ground-up-rail-and-schema-map.md`
- `u-boot-spl-vs-zuma-map.md`
- `minimal-zuma-dt-cut-list.md`
- `zuma-reserved-memory-keep-drop.md`
- `zuma_first_stage_skeleton.c`
- `zuma_first_stage.ld`

## U-Boot integration scaffold for Husky

This repository now ships a dedicated `u-boot-google-husky` package scaffold.

- `uboothusky.cfg` remains the source board config artifact.
- `u-boot-google-husky/husky.h` mirrors that artifact in U-Boot header form.
- `device-google-husky/APKBUILD` now depends on `u-boot-google-husky` so the device package includes the Husky U-Boot config payload.
