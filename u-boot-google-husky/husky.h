#ifndef __HUSKY_H
#define __HUSKY_H

/* DRAM -- confirmed: pbl.bin + bl31.bin both embed these */
#define CONFIG_SYS_SDRAM_BASE    0x80000000UL   /* bank 0 base -- in pbl/bl2/bl31 */
#define CONFIG_SYS_SDRAM_SIZE    0x200000000ULL /* 8 GB (husky) */

/* Second DRAM bank -- bl31.bin has 0x0000000880000000 as a 64-bit constant */
#define DRAM_BANK1_BASE          0x880000000ULL  /* NOT 0x100000000 like SDM845 */
                                                 /* Tensor G3 maps it at 34 GB  */

/* U-Boot text/stack */
#ifndef CONFIG_SYS_TEXT_BASE
#define CONFIG_SYS_TEXT_BASE     0x80200000
#endif
#define CONFIG_SYS_INIT_SP_ADDR  (CONFIG_SYS_TEXT_BASE - 0x10)

/* Kernel / DTB / ramdisk staging -- same arm64 convention */
#define KERNEL_LOAD_ADDR         0x80080000      /* text_offset from abl format str */
#define DTB_LOAD_ADDR            0x81000000
#define INITRD_LOAD_ADDR         0x84000000

/* Secure DRAM -- abl.bin: "secure dram base 0x%lx, size 0x%zx" */
/* bl2 shows carve-outs up through 0x92800000 before usable DRAM */
#define SECURE_DRAM_BASE         0x88800000      /* from bl2.bin aligned constants */
#define SECURE_DRAM_SIZE         0x09A00000      /* ~154 MB TZ/BL31/GSA reservation */

/* UFS host -- from fstab.husky: /dev/block/platform/13200000.ufs */
#define UFS_BASE                 0x13200000

/* USB -- VID/PID confirmed in abl.bin binary */
#define USB_VID                  0x18D1          /* Google */
#define USB_PID_FASTBOOT         0x4EE7

/* Boot command */
#define CONFIG_BOOTCOMMAND \
    "abootimg addr 0x80080000; bootm 0x80080000"

#endif /* __HUSKY_H */