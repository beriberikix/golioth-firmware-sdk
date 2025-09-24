#!/bin/bash

set -euo pipefail

# QEMU launch script for Golioth Buildroot example (ARM64 for Apple Silicon)
# This script launches QEMU with ARM64 architecture for better performance on Apple Silicon Macs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDROOT_DIR="$(dirname "${SCRIPT_DIR}")"

# Try to find the buildroot build directory
# First check if we're running from a buildroot that used our br2-external
if [ -f "${BUILDROOT_DIR}/../../../output/images/Image" ]; then
    BUILD_DIR="${BUILDROOT_DIR}/../../../output"
elif [ -f "./output/images/Image" ]; then
    BUILD_DIR="./output"
else
    # Default assumption: buildroot output directory
    BUILD_DIR="output"
fi

# Check if images exist
if [ ! -f "${BUILD_DIR}/images/u-boot.bin" ]; then
    echo "Error: U-Boot image not found at ${BUILD_DIR}/images/u-boot.bin"
    echo "Please build the ARM64 system first with:"
    echo "  make BR2_EXTERNAL=${BUILDROOT_DIR} qemu_aarch64_golioth_defconfig"
    echo "  make"
    exit 1
fi

if [ ! -f "${BUILD_DIR}/images/Image" ]; then
    echo "Error: Kernel image not found at ${BUILD_DIR}/images/Image"
    echo "Please build the system first"
    exit 1
fi

if [ ! -f "${BUILD_DIR}/images/rootfs.ext2" ]; then
    echo "Error: Root filesystem not found at ${BUILD_DIR}/images/rootfs.ext2"
    echo "Please build the system first"
    exit 1
fi

# Check if QEMU is available
if ! command -v qemu-system-aarch64 &> /dev/null; then
    echo "Error: qemu-system-aarch64 not found"
    echo "Please install QEMU or use the host QEMU from Buildroot:"
    echo "  export PATH=${BUILD_DIR}/host/bin:\$PATH"
    echo ""
    echo "On macOS, install with Homebrew:"
    echo "  brew install qemu"
    exit 1
fi

echo "Starting QEMU with Golioth Buildroot system (ARM64 + U-Boot)..."
echo "Architecture: ARM64 (optimized for Apple Silicon)"
echo "Bootloader: U-Boot"
echo "Network: User networking enabled (NAT)"
echo "Console: Serial console (use Ctrl+A then X to exit)"
echo "Performance: Should be faster on Apple Silicon compared to x86_64 emulation"
echo ""
echo "Boot process: U-Boot will automatically load Linux kernel"
echo "Once booted, set your Golioth credentials:"
echo "  export GOLIOTH_SAMPLE_PSK_ID=your-device-psk-id"
echo "  export GOLIOTH_SAMPLE_PSK=your-device-psk"
echo "  golioth_basics"
echo ""

# Use HVF acceleration on macOS for better performance
ACCEL_ARGS=""
if [[ "$OSTYPE" == "darwin"* ]]; then
    ACCEL_ARGS="-accel hvf"
fi

exec qemu-system-aarch64 \
    -M virt \
    -cpu cortex-a57 \
    -smp 2 \
    -m 512M \
    $ACCEL_ARGS \
    -bios "${BUILD_DIR}/images/u-boot.bin" \
    -drive "file=${BUILD_DIR}/images/rootfs.ext2,if=virtio,format=raw" \
    -drive "file=${BUILD_DIR}/images/Image,if=virtio,format=raw" \
    -netdev user,id=net0 \
    -device virtio-net-device,netdev=net0 \
    -nographic \
    "$@"