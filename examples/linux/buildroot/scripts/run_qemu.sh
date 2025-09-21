#!/bin/bash

set -euo pipefail

# QEMU launch script for Golioth Buildroot example
# This script launches QEMU with network support for testing Golioth connectivity

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDROOT_DIR="$(dirname "${SCRIPT_DIR}")"

# Try to find the buildroot build directory
# First check if we're running from a buildroot that used our br2-external
if [ -f "${BUILDROOT_DIR}/../../../output/images/bzImage" ]; then
    BUILD_DIR="${BUILDROOT_DIR}/../../../output"
elif [ -f "./output/images/bzImage" ]; then
    BUILD_DIR="./output"
else
    # Default assumption: buildroot output directory
    BUILD_DIR="output"
fi

# Check if images exist
if [ ! -f "${BUILD_DIR}/images/bzImage" ]; then
    echo "Error: Kernel image not found at ${BUILD_DIR}/images/bzImage"
    echo "Please build the system first with:"
    echo "  make BR2_EXTERNAL=${BUILDROOT_DIR} qemu_x86_64_golioth_defconfig"
    echo "  make"
    exit 1
fi

if [ ! -f "${BUILD_DIR}/images/rootfs.ext2" ]; then
    echo "Error: Root filesystem not found at ${BUILD_DIR}/images/rootfs.ext2"
    echo "Please build the system first"
    exit 1
fi

# Check if QEMU is available
if ! command -v qemu-system-x86_64 &> /dev/null; then
    echo "Error: qemu-system-x86_64 not found"
    echo "Please install QEMU or use the host QEMU from Buildroot:"
    echo "  export PATH=${BUILD_DIR}/host/bin:\$PATH"
    exit 1
fi

echo "Starting QEMU with Golioth Buildroot system..."
echo "Network: User networking enabled (NAT)"
echo "Console: Serial console (use Ctrl+A then X to exit)"
echo ""
echo "Once booted, set your Golioth credentials:"
echo "  export GOLIOTH_SAMPLE_PSK_ID=your-device-psk-id"
echo "  export GOLIOTH_SAMPLE_PSK=your-device-psk"
echo "  golioth_basics"
echo ""

exec qemu-system-x86_64 \
    -M pc \
    -kernel "${BUILD_DIR}/images/bzImage" \
    -drive "file=${BUILD_DIR}/images/rootfs.ext2,if=virtio,format=raw" \
    -append "rootwait root=/dev/vda console=ttyS0" \
    -net nic,model=virtio \
    -net user \
    -nographic \
    "$@"