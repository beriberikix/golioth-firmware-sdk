#!/bin/bash

set -u
set -e

# Arguments:
# $1: the images directory
IMAGES_DIR="$1"

# Create U-Boot environment script for automatic kernel loading
# This will be embedded in the U-Boot environment
cat << 'EOF' > "${IMAGES_DIR}/uboot.env"
# U-Boot environment for Golioth QEMU ARM64
# Automatically load and boot Linux kernel from virtio drives

# Kernel loading from virtio drive
load_kernel=virtio dev 1; fatload virtio 1:1 $kernel_addr_r /Image
load_rootfs_args=setenv bootargs rootwait root=/dev/vda console=ttyAMA0

# Boot sequence
autoboot=run load_kernel; run load_rootfs_args; booti $kernel_addr_r

# Set default boot delay
bootdelay=2

# Automatically run autoboot command
bootcmd=run autoboot
EOF

echo "Created U-Boot environment configuration for ARM64"