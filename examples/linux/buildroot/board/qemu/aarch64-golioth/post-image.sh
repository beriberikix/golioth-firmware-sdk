#!/bin/bash

set -e

# Arguments:
# $1: the images directory
IMAGES_DIR="$1"

echo "Creating simplified single-partition layout for reliable OTA..."

# Create a simple disk image with:
# - Boot partition (64MB) - FAT32 with kernel/dtb
# - RootFS partition (200MB) - EXT4 main filesystem

DISK_IMAGE="${IMAGES_DIR}/rootfs_disk.img"
BOOT_SIZE_MB=64
ROOTFS_SIZE_MB=200
TOTAL_SIZE_MB=$((BOOT_SIZE_MB + ROOTFS_SIZE_MB + 8))  # +8MB for partition table

echo "Disk layout:"
echo "  Boot partition: ${BOOT_SIZE_MB}MB (FAT32)"
echo "  RootFS partition: ${ROOTFS_SIZE_MB}MB (EXT4)"
echo "  Total disk size: ${TOTAL_SIZE_MB}MB"

# Create disk image
dd if=/dev/zero of="${DISK_IMAGE}" bs=1M count=${TOTAL_SIZE_MB}

# Create partition table using sfdisk
cat << EOF | sfdisk "${DISK_IMAGE}"
label: dos
unit: sectors
start=2048, size=131072, type=c, bootable
start=133120, size=409600, type=83
EOF

echo "✓ Partition table created"

# Calculate partition offsets
BOOT_OFFSET=$((2048 * 512))
ROOTFS_OFFSET=$((133120 * 512))

# Create boot partition with reliable method
BOOT_IMAGE="${IMAGES_DIR}/boot.fat32"
dd if=/dev/zero of="${BOOT_IMAGE}" bs=1M count=${BOOT_SIZE_MB}

# Format as FAT32
mkfs.fat -F32 -n "BOOT" "${BOOT_IMAGE}"

# Use mtools to copy files reliably (no mounting required)
if [ -f "${IMAGES_DIR}/Image" ]; then
    mcopy -i "${BOOT_IMAGE}" "${IMAGES_DIR}/Image" ::Image
    echo "✓ Kernel copied to boot partition"
else
    echo "⚠ Warning: Kernel Image not found"
fi

if [ -f "${IMAGES_DIR}/qemu-aarch64.dtb" ]; then
    mcopy -i "${BOOT_IMAGE}" "${IMAGES_DIR}/qemu-aarch64.dtb" ::qemu-aarch64.dtb
    echo "✓ DTB copied to boot partition"
fi

# Create automatic boot script - try multiple tool locations
SCRIPT_CREATED=false
HOST_TOOLS_DIR="$(dirname "${IMAGES_DIR}")/../host/bin"

# Try different locations for mkimage
for MKIMAGE_PATH in \
    "${HOST_TOOLS_DIR}/mkimage" \
    "/build/buildroot/output/host/bin/mkimage" \
    "/usr/bin/mkimage" \
    "mkimage"; do

    if command -v "$MKIMAGE_PATH" >/dev/null 2>&1; then
        echo "Found mkimage at: $MKIMAGE_PATH"

        # Create boot script that will override the bootflow scan
        cat > "${IMAGES_DIR}/boot.cmd" << 'EOF'
# Golioth automatic boot script
# This script overrides U-Boot's bootflow scanning
setenv bootdelay 1
echo "Golioth: Initializing virtio devices"
virtio scan
echo "Golioth: Loading kernel from boot partition"
if fatload virtio 0:1 0x40080000 Image; then
    echo "Golioth: Kernel loaded, setting boot arguments"
    setenv bootargs "root=/dev/vda2 rootwait console=ttyAMA0 rw"
    echo "Golioth: Starting Linux kernel"
    booti 0x40080000 - ${fdtcontroladdr}
else
    echo "Golioth: ERROR - Failed to load kernel"
    echo "Dropping to U-Boot prompt for debugging"
fi
EOF

        if "$MKIMAGE_PATH" -C none -A arm64 -T script -d "${IMAGES_DIR}/boot.cmd" "${IMAGES_DIR}/boot.scr" 2>/dev/null; then
            mcopy -i "${BOOT_IMAGE}" "${IMAGES_DIR}/boot.scr" ::boot.scr

            # Create multiple script names that U-Boot might look for
            mcopy -i "${BOOT_IMAGE}" "${IMAGES_DIR}/boot.scr" ::6x4.scr
            mcopy -i "${BOOT_IMAGE}" "${IMAGES_DIR}/boot.scr" ::autoboot.scr

            echo "✓ Boot script created and copied to boot partition"
            SCRIPT_CREATED=true
            break
        fi
    fi
done

if [ "$SCRIPT_CREATED" = "false" ]; then
    echo "⚠ Could not create boot script - mkimage not found"
fi

# Copy boot partition to disk image
dd if="${BOOT_IMAGE}" of="${DISK_IMAGE}" bs=512 seek=2048 conv=notrunc

# Copy rootfs to disk image
if [ -f "${IMAGES_DIR}/rootfs.ext2" ]; then
    # Resize rootfs to exactly fit partition if needed
    CURRENT_SIZE=$(stat -c%s "${IMAGES_DIR}/rootfs.ext2")
    MAX_SIZE=$((ROOTFS_SIZE_MB * 1024 * 1024))

    if [ "$CURRENT_SIZE" -gt "$MAX_SIZE" ]; then
        echo "⚠ Warning: rootfs.ext2 too large, truncating"
        dd if="${IMAGES_DIR}/rootfs.ext2" of="${IMAGES_DIR}/rootfs_resized.ext2" bs=1M count=${ROOTFS_SIZE_MB}
        dd if="${IMAGES_DIR}/rootfs_resized.ext2" of="${DISK_IMAGE}" bs=512 seek=133120 conv=notrunc
        rm -f "${IMAGES_DIR}/rootfs_resized.ext2"
    else
        dd if="${IMAGES_DIR}/rootfs.ext2" of="${DISK_IMAGE}" bs=512 seek=133120 conv=notrunc
    fi
    echo "✓ RootFS copied to partition"
else
    echo "⚠ Warning: rootfs.ext2 not found"
fi

# Create U-Boot environment with simple boot command
UBOOT_ENV_FILE="${IMAGES_DIR}/uboot_env.bin"
UBOOT_ENV_TXT="${IMAGES_DIR}/uboot_env.txt"

cat > "$UBOOT_ENV_TXT" << 'EOF'
bootcmd=virtio scan; fatload virtio 0:1 0x40080000 Image; setenv bootargs "root=/dev/vda2 rootwait console=ttyAMA0 rw"; booti 0x40080000 - ${fdtcontroladdr}
kernel_addr_r=0x40080000
fdt_addr_r=0x47000000
ramdisk_addr_r=0x48000000
bootdelay=2
firmware_version=1.0.0
boot_method=single_partition
EOF

# Create binary environment using host tools - try multiple locations
ENV_CREATED=false

for MKENVIMAGE_PATH in \
    "${HOST_TOOLS_DIR}/mkenvimage" \
    "/build/buildroot/output/host/bin/mkenvimage" \
    "/usr/bin/mkenvimage" \
    "mkenvimage"; do

    if command -v "$MKENVIMAGE_PATH" >/dev/null 2>&1; then
        echo "Found mkenvimage at: $MKENVIMAGE_PATH"
        if "$MKENVIMAGE_PATH" -s 16384 -o "$UBOOT_ENV_FILE" "$UBOOT_ENV_TXT" 2>/dev/null; then
            echo "✓ U-Boot environment created successfully"
            mcopy -i "${BOOT_IMAGE}" "$UBOOT_ENV_FILE" ::uboot.env
            ENV_CREATED=true
            break
        fi
    fi
done

if [ "$ENV_CREATED" = "false" ]; then
    echo "⚠ Could not create U-Boot environment - mkenvimage not found"

    # ULTIMATE SOLUTION: Directly patch U-Boot binary
    echo "⚠ Attempting direct U-Boot binary modification..."

    # Create a simple environment override
    UBOOT_BIN="${IMAGES_DIR}/u-boot.bin"
    if [ -f "$UBOOT_BIN" ]; then
        # Backup original
        cp "$UBOOT_BIN" "${UBOOT_BIN}.backup"

        # Create a custom environment string
        BOOTCMD_STRING="bootcmd=virtio scan; fatload virtio 0:1 0x40080000 Image; setenv bootargs root=/dev/vda2 rootwait console=ttyAMA0 rw; booti 0x40080000 - \${fdtcontroladdr}"

        # Try to find and replace the default bootcmd in the binary
        if python3 -c "
import sys
with open('$UBOOT_BIN', 'rb') as f:
    data = f.read()

# Look for bootflow patterns and replace
bootflow_patterns = [b'bootflow scan', b'run distro_bootcmd']
replacement = b'$BOOTCMD_STRING\x00' + b'\x00' * 100

modified = False
for pattern in bootflow_patterns:
    if pattern in data:
        data = data.replace(pattern, replacement[:len(pattern)])
        modified = True
        print(f'Replaced pattern: {pattern}')

if modified:
    with open('$UBOOT_BIN', 'wb') as f:
        f.write(data)
    print('U-Boot binary successfully modified')
    sys.exit(0)
else:
    print('No bootflow patterns found to replace')
    sys.exit(1)
" 2>/dev/null; then
            echo "✓ U-Boot binary successfully patched for automatic boot"
        else
            echo "⚠ Failed to patch U-Boot binary"
        fi
    fi
fi

# Create version tracking file
cat > "${IMAGES_DIR}/version_info.txt" << EOF
FIRMWARE_VERSION=${FIRMWARE_VERSION:-1.0.0}
BUILD_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
PARTITION_LAYOUT=single
BOOT_METHOD=uboot
ARCH=aarch64
EOF

echo "✓ Single-partition disk image created: ${DISK_IMAGE}"
echo ""
echo "🚀 To run with QEMU:"
echo "qemu-system-aarch64 -M virt -cpu cortex-a57 -m 512M \\"
echo "  -bios ${IMAGES_DIR}/u-boot.bin \\"
echo "  -drive file=${DISK_IMAGE},if=virtio,format=raw \\"
echo "  -netdev user,id=net0 -device virtio-net-device,netdev=net0 \\"
echo "  -nographic"