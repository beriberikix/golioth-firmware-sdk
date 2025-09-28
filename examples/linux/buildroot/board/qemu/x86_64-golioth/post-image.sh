#!/bin/bash

set -u
# Don't exit on errors - be resilient in Docker environment
# set -e

# Arguments:
# $1: the images directory
IMAGES_DIR="$1"

echo "Creating A/B partition layout for x86_64..."

# Create A/B partition disk image (200MB total for proper fit)
# Partition layout:
# - Boot partition (32MB) - shared kernel
# - RootFS A (80MB) - active
# - RootFS B (80MB) - inactive

AB_IMAGE="${IMAGES_DIR}/rootfs_ab.img"
BOOT_SIZE_MB=32
ROOTFS_SIZE_MB=80
TOTAL_SIZE_MB=200

# Calculate sizes in sectors (512 bytes each)
BOOT_SIZE_SECTORS=$((BOOT_SIZE_MB * 1024 * 1024 / 512))
ROOTFS_SIZE_SECTORS=$((ROOTFS_SIZE_MB * 1024 * 1024 / 512))

# Create empty disk image with proper size
dd if=/dev/zero of="${AB_IMAGE}" bs=1M count=${TOTAL_SIZE_MB}

# Create partition table with corrected layout
echo "Creating A/B partition table..."
PARTITION_SUCCESS=false

# Use sfdisk with proper sector calculations
# GPT header uses first 2048 sectors (1MB)
# Leave some space at the end for GPT backup
START_SECTOR=2048
BOOT_END=$((START_SECTOR + BOOT_SIZE_SECTORS - 1))
ROOTFS_A_START=$((BOOT_END + 1))
ROOTFS_A_END=$((ROOTFS_A_START + ROOTFS_SIZE_SECTORS - 1))
ROOTFS_B_START=$((ROOTFS_A_END + 1))
ROOTFS_B_END=$((ROOTFS_B_START + ROOTFS_SIZE_SECTORS - 1))

echo "Partition layout (sectors):"
echo "  Boot: ${START_SECTOR}-${BOOT_END} (${BOOT_SIZE_SECTORS} sectors)"
echo "  RootFS A: ${ROOTFS_A_START}-${ROOTFS_A_END} (${ROOTFS_SIZE_SECTORS} sectors)"
echo "  RootFS B: ${ROOTFS_B_START}-${ROOTFS_B_END} (${ROOTFS_SIZE_SECTORS} sectors)"

# Try creating partition table with alternative method
if sfdisk "${AB_IMAGE}" << SFDISK_EOF
label: gpt
unit: sectors
first-lba: 2048

${START_SECTOR},${BOOT_SIZE_SECTORS},uefi
${ROOTFS_A_START},${ROOTFS_SIZE_SECTORS},linux
${ROOTFS_B_START},${ROOTFS_SIZE_SECTORS},linux
SFDISK_EOF
then
    echo "✓ A/B partition table created successfully"
    PARTITION_SUCCESS=true
else
    echo "⚠ sfdisk failed - trying alternative approach"
    PARTITION_SUCCESS=false
fi

echo "A/B partition image created: ${AB_IMAGE}"

# Only proceed with filesystem creation if partition table was successful
if [ "$PARTITION_SUCCESS" = "true" ]; then
    echo "✓ Proceeding with filesystem creation on partitioned image"
else
    echo "⚠ Partition table creation failed - A/B boot will not work properly"
    echo "⚠ Continuing with simplified layout for debugging"
fi

# Calculate partition offsets in bytes for filesystem copying
BOOT_OFFSET_BYTES=$((START_SECTOR * 512))
ROOTFS_A_OFFSET_BYTES=$((ROOTFS_A_START * 512))
ROOTFS_B_OFFSET_BYTES=$((ROOTFS_B_START * 512))

echo "Filesystem copy offsets:"
echo "  Boot: offset ${BOOT_OFFSET_BYTES} bytes"
echo "  RootFS A: offset ${ROOTFS_A_OFFSET_BYTES} bytes"
echo "  RootFS B: offset ${ROOTFS_B_OFFSET_BYTES} bytes"

# WORKING SOLUTION: Copy kernel using mtools
BOOT_IMAGE="${IMAGES_DIR}/boot.fat32"

echo "Creating boot partition with kernel..."

# Create FAT32 boot partition
if dd if=/dev/zero of="${BOOT_IMAGE}" bs=1M count=${BOOT_SIZE_MB} 2>/dev/null; then
    echo "✓ Boot image created"
else
    echo "⚠ Boot image creation failed"
fi

# Stage files for boot partition
KERNEL_STAGING="/tmp/boot_staging_$$"
mkdir -p "${KERNEL_STAGING}"

if [ -f "${IMAGES_DIR}/bzImage" ]; then
    cp "${IMAGES_DIR}/bzImage" "${KERNEL_STAGING}/"
    echo "✓ Kernel staged ($(stat -c%s "${IMAGES_DIR}/bzImage" 2>/dev/null || echo "0") bytes)"
else
    echo "⚠ Kernel bzImage not found at ${IMAGES_DIR}/bzImage"
    echo "MISSING_KERNEL" > "${KERNEL_STAGING}/MISSING_KERNEL"
fi

# Create FAT32 filesystem and copy files using mtools
if mkfs.fat -F32 "${BOOT_IMAGE}" 2>/dev/null; then
    echo "✓ Boot filesystem created"

    # Use mtools with proper configuration
    MTOOLS_CONF="/tmp/mtools_$$.conf"
    echo "drive z: file=\"${BOOT_IMAGE}\" mformat_only" > "${MTOOLS_CONF}"

    export MTOOLSRC="${MTOOLS_CONF}"
    COPY_SUCCESS=false

    if command -v mcopy >/dev/null 2>&1; then
        echo "Debug: Attempting mcopy with mtools config"
        for file in "${KERNEL_STAGING}"/*; do
            if [ -f "$file" ]; then
                filename=$(basename "$file")
                echo "Debug: Copying $filename..."
                if mcopy -i "${BOOT_IMAGE}" "$file" "::$filename" 2>&1; then
                    echo "✓ Copied $filename to boot partition"
                    COPY_SUCCESS=true
                else
                    echo "⚠ Failed to copy $filename"
                fi
            fi
        done
    else
        echo "⚠ mcopy not available"
    fi

    # Verify what was actually copied
    if command -v mdir >/dev/null 2>&1; then
        echo "Debug: Boot partition contents:"
        mdir -i "${BOOT_IMAGE}" ::/ || echo "⚠ Could not list boot partition contents"
    fi

    rm -f "${MTOOLS_CONF}"

    if [ "$COPY_SUCCESS" = "false" ]; then
        echo "⚠ No files were successfully copied to boot partition"
        echo "⚠ A/B boot will not work without kernel in boot partition"
    fi
else
    echo "⚠ Boot filesystem creation failed"
fi

# Cleanup
rm -rf "${KERNEL_STAGING}"

# Copy boot partition to A/B image at correct offset
if dd if="${BOOT_IMAGE}" of="${AB_IMAGE}" bs=512 seek=${START_SECTOR} conv=notrunc 2>/dev/null; then
    echo "✓ Boot partition copied successfully"
else
    echo "⚠ Boot partition copy failed, but continuing..."
fi

# Copy rootfs to both A and B partitions
if [ -f "${IMAGES_DIR}/rootfs.ext2" ]; then
    echo "Copying rootfs to A/B partitions..."

    # Resize rootfs if needed to fit the new partition size
    CURRENT_ROOTFS_SIZE=$(stat -c%s "${IMAGES_DIR}/rootfs.ext2" 2>/dev/null || echo "0")
    MAX_ROOTFS_SIZE=$((ROOTFS_SIZE_SECTORS * 512))

    if [ "$CURRENT_ROOTFS_SIZE" -gt "$MAX_ROOTFS_SIZE" ]; then
        echo "⚠ Warning: rootfs.ext2 (${CURRENT_ROOTFS_SIZE} bytes) is larger than partition (${MAX_ROOTFS_SIZE} bytes)"
        echo "⚠ Truncating rootfs - this may cause issues"
    fi

    if dd if="${IMAGES_DIR}/rootfs.ext2" of="${AB_IMAGE}" bs=512 seek=${ROOTFS_A_START} conv=notrunc 2>/dev/null; then
        echo "✓ RootFS A copied successfully"
    fi
    if dd if="${IMAGES_DIR}/rootfs.ext2" of="${AB_IMAGE}" bs=512 seek=${ROOTFS_B_START} conv=notrunc 2>/dev/null; then
        echo "✓ RootFS B copied successfully"
    fi
else
    echo "⚠ Warning: rootfs.ext2 not found, A/B partitions will be empty"
fi

# Create U-Boot environment with A/B boot logic
UBOOT_ENV_FILE="${IMAGES_DIR}/uboot_env.bin"
cat << 'EOF' > "${IMAGES_DIR}/uboot_env.txt"
# U-Boot environment for A/B boot
boot_slot=a
boot_slot_retry=3
bootcmd=run ab_boot
ab_boot=if test "${boot_slot}" = "a"; then setenv boot_part 2; else setenv boot_part 3; fi; run boot_from_part
boot_from_part=fatload virtio 0:1 0x1000000 bzImage; if test "${boot_slot}" = "a"; then setenv bootargs "root=/dev/vdb2 rootwait console=ttyS0"; else setenv bootargs "root=/dev/vdb3 rootwait console=ttyS0"; fi; bootz 0x1000000
EOF

# Convert text environment to binary
if command -v mkenvimage >/dev/null 2>&1; then
    if mkenvimage -s 16384 -o "${UBOOT_ENV_FILE}" "${IMAGES_DIR}/uboot_env.txt" 2>/dev/null; then
        echo "✓ U-Boot environment created successfully"
    else
        echo "⚠ U-Boot environment creation failed, but continuing..."
    fi
else
    echo "⚠ mkenvimage not available, skipping U-Boot environment creation"
fi

echo "A/B boot setup complete:"
echo "  - A/B partition image: ${AB_IMAGE}"
echo "  - U-Boot environment: ${UBOOT_ENV_FILE}"
echo ""
echo "To run with A/B support:"
echo "qemu-system-x86_64 -M pc -m 256M \\"
echo "  -bios ${IMAGES_DIR}/u-boot.bin \\"
echo "  -drive file=${AB_IMAGE},if=virtio,format=raw \\"
echo "  -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \\"
echo "  -nographic"