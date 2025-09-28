/* U-Boot environment override for Golioth single partition boot */

#ifndef __CONFIG_GOLIOTH_ENV_H
#define __CONFIG_GOLIOTH_ENV_H

/* Disable bootflow system and use legacy boot */
#undef CONFIG_BOOTSTD
#undef CONFIG_BOOTSTD_DEFAULTS

/* Set our custom boot command as default */
#define CONFIG_BOOTCOMMAND \
    "virtio scan; " \
    "fatload virtio 0:1 0x40080000 Image; " \
    "setenv bootargs root=/dev/vda2 rootwait console=ttyAMA0 rw; " \
    "booti 0x40080000 - ${fdtcontroladdr}"

/* Memory addresses for ARM64 */
#define CONFIG_SYS_LOAD_ADDR 0x40080000
#define CONFIG_SYS_BOOTMAPSZ (256 << 20)

/* Environment variables */
#define CONFIG_EXTRA_ENV_SETTINGS \
    "kernel_addr_r=0x40080000\0" \
    "fdt_addr_r=0x47000000\0" \
    "ramdisk_addr_r=0x48000000\0" \
    "firmware_version=1.0.0\0" \
    "boot_method=single_partition\0"

#endif /* __CONFIG_GOLIOTH_ENV_H */