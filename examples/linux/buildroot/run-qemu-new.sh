#!/bin/bash

# Quick script to run QEMU with the new single-partition layout
# Usage: ./run-qemu-new.sh [version]

VERSION=${1:-"1.0.0"}
ARCH="aarch64"
OUTPUT_DIR="output/${ARCH}-${VERSION}"

if [ ! -d "$OUTPUT_DIR" ]; then
    echo "Error: Output directory not found: $OUTPUT_DIR"
    echo "Available versions:"
    ls -1 output/ | grep "^${ARCH}-" || echo "  No ${ARCH} builds found"
    exit 1
fi

if [ ! -f "$OUTPUT_DIR/rootfs_disk.img" ]; then
    echo "Error: Disk image not found: $OUTPUT_DIR/rootfs_disk.img"
    echo "Available files in $OUTPUT_DIR:"
    ls -la "$OUTPUT_DIR/"
    exit 1
fi

echo "🚀 Starting QEMU with simplified single-partition layout"
echo "   Version: $VERSION"
echo "   Disk: $OUTPUT_DIR/rootfs_disk.img"
echo "   U-Boot: $OUTPUT_DIR/u-boot.bin"
echo ""
echo "   Boot process: U-Boot → Kernel from /dev/vda1 → RootFS from /dev/vda2"
echo "   To exit: Ctrl+A then X"
echo ""

exec qemu-system-aarch64 \
    -M virt \
    -cpu cortex-a57 \
    -m 512M \
    -bios "$OUTPUT_DIR/u-boot.bin" \
    -drive "file=$OUTPUT_DIR/rootfs_disk.img,if=virtio,format=raw" \
    -netdev user,id=net0 \
    -device virtio-net-device,netdev=net0 \
    -nographic