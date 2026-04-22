# PostmarketOS linux and device config

## Bare-metal install helper: prerequisites, risk notes, and usage

> ⚠️ **High risk:** flashing can hard-brick your device or force data loss.
> This workflow is currently **untested on a physical device**.

### Host OS and tool requirements

- Recommended host: modern Linux (for example Ubuntu 22.04/24.04) with Bash and USB access.
- Required commands used by the helper:
  - `adb`, `fastboot` (Android platform-tools)
  - `bash`, `find`, `grep`, `sort`, `mktemp`, `unzip`
- Optional extraction helpers used by menu option 20:
  - `tar`, `gzip`, `bzip2`, `xz`, `lz4`, `zstd`, `7z`, `simg2img`
  - `payload-dumper-go` or `payload_dumper`
- No pinned host OS version matrix is validated yet in this repo; treat all host setups as experimental.

### Device/software state and version checks

- Device target: Pixel 8 Pro (`husky`).
- Before flash operations, the phone must be in **bootloader/fastboot mode** and normally must have an **unlocked bootloader**.
- For ADB-based checks (menu options 3, 18, 19), boot Android and enable USB debugging.
- Check active build identity before flashing and match it to your expected baseline (build fingerprint / partition set) to reduce cross-build mismatch risk.
- Rollback-protection reminder: do **not** flash older firmware/security-patch-level components than currently fused/accepted by the device chain of trust.

### Locked bootloader and rollback-protection concerns

- `fastboot flashing unlock` wipes user data.
- Relocking (`fastboot flashing lock`) after non-stock or mismatched images can leave the device unbootable.
- Rollback protection/anti-rollback fuses may prevent booting downgraded firmware even if flashing appears to succeed.
- Keep boot/recovery/vendor_boot/dtbo/firmware components from a compatible build generation and avoid downgrade mixes across slots.

### Always back up partitions first

Before any flashing, back up all important partitions and metadata (both slots where applicable). Keep backups off-device so you can restore if boot fails.

### Install and run `bare-metal-install.sh`

1. From the repository root, ensure the helper is executable:
   ```bash
   chmod +x ./bare-metal-install.sh
   ```
2. Install Android platform-tools (`adb` and `fastboot`) on your host OS.
3. (Optional) Install extraction tools listed above if you plan to use option 20.
4. Connect device over USB and verify connectivity:
   ```bash
   adb devices
   fastboot devices
   ```
5. Start the helper:
   ```bash
   ./bare-metal-install.sh
   ```
6. Use menu options carefully:
   - ADB checks while Android is booted
   - Fastboot flashing only when intentionally in bootloader mode
7. Re-check fingerprints/partition expectations before each flash operation.

### Community support and discussion

If you want to ask questions, share outcomes, or help others troubleshoot, please open a GitHub Discussion:

- https://github.com/mikethi/pmos-husky/discussions/new/choose

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
- `uboothusky.cfg`
- `minimal-zuma-dt-cut-list.md`
- `zuma-reserved-memory-keep-drop.md`
- `zuma_first_stage_skeleton.c`
- `zuma_first_stage.ld`
