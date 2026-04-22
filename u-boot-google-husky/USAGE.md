# Using u-boot-google-husky with U-Boot source

These files let you build U-Boot for the **Google Pixel 8 Pro (husky)**
against any recent upstream U-Boot tree.

## Files

| File | U-Boot destination | Purpose |
|------|--------------------|---------|
| `husky.h` | `include/configs/husky.h` | Board config header (addresses, memory map, boot command) |
| `husky_defconfig` | `configs/husky_defconfig` | Kconfig defconfig for `make husky_defconfig` |

## Quick-start

```sh
# 1. Clone U-Boot upstream
git clone https://github.com/u-boot/u-boot.git
cd u-boot

# 2. Drop in the Husky board files
cp /usr/share/u-boot-google-husky/include/configs/husky.h  include/configs/husky.h
cp /usr/share/u-boot-google-husky/configs/husky_defconfig   configs/husky_defconfig

# 3. Configure and build
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- husky_defconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- all

# 4. The resulting u-boot.bin can be staged for boot experiments
#    on the Pixel 8 Pro (Tensor G3 / Zuma SoC).
```

## Memory map reference

| Region | Base | Notes |
|--------|------|-------|
| DRAM bank 0 | `0x80000000` | 8 GB, confirmed in pbl/bl31 |
| DRAM bank 1 | `0x880000000` | Tensor G3 maps second bank at 34 GB |
| Secure DRAM | `0x88800000` -- `0x92200000` | ~154 MB TZ/BL31/GSA carve-out |
| U-Boot text | `0x80200000` | Above carve-outs |
| Kernel load | `0x80080000` | `text_offset` from Android boot format |
| DTB load | `0x81000000` | |
| Initrd load | `0x84000000` | |
| UFS host | `0x13200000` | `/dev/block/platform/13200000.ufs` |
| UART (console) | `0x10870000` | `earlycon=exynos4210` |

## Status

Full SoC bring-up (clock, pinmux, UFS, display) is in progress.
The defconfig and header here represent the known-good address map
derived from stock firmware artifacts (pbl, bl2, bl31, abl).
