#!/bin/bash
set -e

echo "Starting Buildroot build..."
echo "Buildroot version: $BUILDROOT_VERSION"
echo "Target config: $TARGET_CONFIG"

# Clone buildroot if not already present
if [ ! -d "buildroot" ]; then
    echo "Cloning Buildroot..."
    git clone https://gitlab.com/buildroot.org/buildroot.git
    cd buildroot
    git checkout "$BUILDROOT_VERSION"
else
    cd buildroot
fi

# Configure buildroot with the Golioth external tree
echo "Configuring Buildroot..."
# Find the correct BR2_EXTERNAL path
BR2_EXTERNAL_PATH=""
for path in "/workspace/golioth-firmware-sdk/examples/linux/buildroot" "/workspace/golioth-firmware-sdk/golioth-firmware-sdk/examples/linux/buildroot"; do
    if [ -d "$path" ] && [ -f "$path/external.desc" ]; then
        BR2_EXTERNAL_PATH="$path"
        break
    fi
done

if [ -z "$BR2_EXTERNAL_PATH" ]; then
    echo "Error: Could not find BR2_EXTERNAL path"
    echo "Available paths in /workspace:"
    ls -la /workspace/ || echo "Cannot list /workspace"
    if [ -d "/workspace" ]; then
        find /workspace -name "buildroot" -type d 2>/dev/null || echo "No buildroot directories found"
        find /workspace -name "external.desc" 2>/dev/null || echo "No external.desc files found"
    fi
    exit 1
fi
echo "Using BR2_EXTERNAL path: $BR2_EXTERNAL_PATH"
make BR2_EXTERNAL="$BR2_EXTERNAL_PATH" "$TARGET_CONFIG"

# Enable ccache for faster rebuilds
echo "Enabling ccache for faster rebuilds..."
echo "BR2_CCACHE=y" >> .config
echo "BR2_CCACHE_DIR=\"/ccache\"" >> .config
make olddefconfig  # Update config with new settings

# Configure ccache environment
export CCACHE_DIR="/ccache"
export CCACHE_MAXSIZE="2G"
mkdir -p "$CCACHE_DIR"

# Determine optimal number of parallel jobs
NPROC=$(nproc)
PARALLEL_JOBS=$((NPROC > 8 ? 8 : NPROC))  # Cap at 8 to avoid overwhelming Docker

echo "Building system with $PARALLEL_JOBS parallel jobs using external toolchain (this may take 10-20 minutes on first build, much faster on rebuilds)..."
echo "Using ccache directory: $CCACHE_DIR"
ccache -s  # Show cache statistics

# Build the system with parallel jobs
make -j"$PARALLEL_JOBS"

echo "Build completed! Final ccache statistics:"
ccache -s

# Copy output to mounted directory
echo "Copying build output to /output..."
mkdir -p /output
cp -r output/images/* /output/
cp -r output/host /output/ 2>/dev/null || true

echo "Build complete! Output files are in the mounted output directory."
echo ""
echo "External toolchain build completed successfully!"
echo ""
echo "To run with QEMU on your host machine:"
if [[ "$TARGET_CONFIG" == *"aarch64"* ]]; then
    echo "  qemu-system-aarch64 \\"
    echo "    -M virt -cpu cortex-a57 -m 256M \\"
    echo "    -kernel output/Image \\"
    echo "    -drive file=output/rootfs.ext2,if=virtio,format=raw \\"
    echo "    -append \"rootwait root=/dev/vda console=ttyAMA0\" \\"
    echo "    -netdev user,id=net0 -device virtio-net-device,netdev=net0 \\"
    echo "    -nographic"
else
    echo "  qemu-system-x86_64 \\"
    echo "    -M pc -m 256M \\"
    echo "    -kernel output/bzImage \\"
    echo "    -drive file=output/rootfs.ext2,if=virtio,format=raw \\"
    echo "    -append \"rootwait root=/dev/vda console=ttyS0\" \\"
    echo "    -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \\"
    echo "    -nographic"
fi
echo ""
echo "Inside QEMU, set your Golioth credentials:"
echo "  export GOLIOTH_SAMPLE_PSK_ID=\"your-device-psk-id\""
echo "  export GOLIOTH_SAMPLE_PSK=\"your-device-psk\""
echo "  golioth_basics"