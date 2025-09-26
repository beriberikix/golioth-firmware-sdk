#!/bin/bash
set -e

echo "Starting Buildroot build..."
echo "Buildroot version: $BUILDROOT_VERSION"
echo "Target config: $TARGET_CONFIG"
echo "Firmware version: $FIRMWARE_VERSION"
echo "Create SWU: $CREATE_SWU"

# Extract board name from config (aarch64 or x86_64)
BOARD_NAME=$(echo "$TARGET_CONFIG" | grep -o 'aarch64\|x86_64')
if [ -z "$BOARD_NAME" ]; then
    echo "Warning: Could not extract board name from $TARGET_CONFIG, using 'unknown'"
    BOARD_NAME="unknown"
fi

# Create versioned output directory name
VERSIONED_OUTPUT_DIR="${BOARD_NAME}-${FIRMWARE_VERSION}"
echo "Versioned output directory: $VERSIONED_OUTPUT_DIR"

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

# Enable ccache for faster rebuilds and set firmware version
echo "Enabling ccache for faster rebuilds and setting firmware version..."
echo "BR2_CCACHE=y" >> .config
echo "BR2_CCACHE_DIR=\"/ccache\"" >> .config
echo "BR2_GOLIOTH_FIRMWARE_VERSION=\"$FIRMWARE_VERSION\"" >> .config
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

# Copy output to versioned directory
echo "Copying build output to versioned directory: /output/$VERSIONED_OUTPUT_DIR..."
VERSIONED_PATH="/output/$VERSIONED_OUTPUT_DIR"
mkdir -p "$VERSIONED_PATH"

# Copy build artifacts
cp -r output/images/* "$VERSIONED_PATH/"
cp -r output/host "$VERSIONED_PATH/" 2>/dev/null || true

# Copy swupdate tools and templates for .swu generation
echo "Copying swupdate tools for .swu generation..."
if [ -f "$BR2_EXTERNAL_PATH/create-swu.sh" ]; then
    cp "$BR2_EXTERNAL_PATH/create-swu.sh" "$VERSIONED_PATH/"
    chmod +x "$VERSIONED_PATH/create-swu.sh"
fi

if [ -d "$BR2_EXTERNAL_PATH/swu-templates" ]; then
    cp -r "$BR2_EXTERNAL_PATH/swu-templates" "$VERSIONED_PATH/"
    chmod +x "$VERSIONED_PATH/swu-templates/"*.sh
fi

# Copy OTA workflow documentation
if [ -f "$BR2_EXTERNAL_PATH/OTA-WORKFLOW.md" ]; then
    cp "$BR2_EXTERNAL_PATH/OTA-WORKFLOW.md" "$VERSIONED_PATH/"
fi

# Create a convenience symlink to latest build for this board
echo "Creating convenience symlink: /output/${BOARD_NAME}-latest -> $VERSIONED_OUTPUT_DIR"
cd /output
ln -sfn "$VERSIONED_OUTPUT_DIR" "${BOARD_NAME}-latest"

# Create version info file
echo "Creating version info file..."
cat > "$VERSIONED_PATH/VERSION_INFO" << EOF
# Build Information
BUILD_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
FIRMWARE_VERSION=${FIRMWARE_VERSION}
BOARD_NAME=${BOARD_NAME}
TARGET_CONFIG=${TARGET_CONFIG}
BUILDROOT_VERSION=${BUILDROOT_VERSION}
DOCKER_BUILD=true

# Build Command Used:
# docker build --build-arg TARGET_CONFIG=${TARGET_CONFIG} --build-arg FIRMWARE_VERSION=${FIRMWARE_VERSION} --build-arg CREATE_SWU=${CREATE_SWU} -t golioth-buildroot .
# docker run --rm -v "\$(pwd)/../../../..":/workspace -v "\$(pwd)/output":/output -v "\$(pwd)/ccache":/ccache -v "\$(pwd)/dl":/dl golioth-buildroot
EOF

echo "Build complete! Output files are in versioned directory: /output/$VERSIONED_OUTPUT_DIR"
echo ""
echo "✅ External toolchain build completed successfully!"
echo ""
echo "📦 Versioned output structure:"
echo "  output/$VERSIONED_OUTPUT_DIR/        # This build"
echo "  output/${BOARD_NAME}-latest/         # Symlink to latest"
echo "  output/${BOARD_NAME}-1.2.4/         # Previous versions..."
echo "  output/${BOARD_NAME}-1.2.6/         # Other versions..."
echo ""
echo "📂 Available files in output/$VERSIONED_OUTPUT_DIR/:"
echo "  - rootfs.ext2: Single rootfs image"
echo "  - rootfs_ab.img: A/B partition disk image"
echo "  - u-boot.bin: U-Boot bootloader"
echo "  - create-swu.sh: .swu package generation script"
echo "  - swu-templates/: Advanced swupdate templates"
echo "  - VERSION_INFO: Build metadata"
echo ""
echo "🚀 To run with QEMU on your host machine:"
echo ""
echo "Option 1 - Direct kernel boot (simple):"
if [[ "$TARGET_CONFIG" == *"aarch64"* ]]; then
    echo "  qemu-system-aarch64 -M virt -cpu cortex-a57 -m 512M \\"
    echo "    -kernel output/$VERSIONED_OUTPUT_DIR/Image \\"
    echo "    -drive file=output/$VERSIONED_OUTPUT_DIR/rootfs.ext2,if=virtio,format=raw \\"
    echo "    -append \"rootwait root=/dev/vda console=ttyAMA0\" \\"
    echo "    -netdev user,id=net0 -device virtio-net-device,netdev=net0 \\"
    echo "    -nographic"
else
    echo "  qemu-system-x86_64 -M pc -m 256M \\"
    echo "    -kernel output/$VERSIONED_OUTPUT_DIR/bzImage \\"
    echo "    -drive file=output/$VERSIONED_OUTPUT_DIR/rootfs.ext2,if=virtio,format=raw \\"
    echo "    -append \"rootwait root=/dev/vda console=ttyS0\" \\"
    echo "    -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \\"
    echo "    -nographic"
fi
echo ""
echo "Option 2 - A/B partition boot with swupdate:"
if [[ "$TARGET_CONFIG" == *"aarch64"* ]]; then
    echo "  qemu-system-aarch64 -M virt -cpu cortex-a57 -m 512M \\"
    echo "    -bios output/$VERSIONED_OUTPUT_DIR/u-boot.bin \\"
    echo "    -drive file=output/$VERSIONED_OUTPUT_DIR/rootfs_ab.img,if=virtio,format=raw \\"
    echo "    -netdev user,id=net0 -device virtio-net-device,netdev=net0 \\"
    echo "    -nographic"
else
    echo "  qemu-system-x86_64 -M pc -m 256M \\"
    echo "    -bios output/$VERSIONED_OUTPUT_DIR/u-boot.bin \\"
    echo "    -drive file=output/$VERSIONED_OUTPUT_DIR/rootfs_ab.img,if=virtio,format=raw \\"
    echo "    -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \\"
    echo "    -nographic"
fi
echo ""
echo "🔄 To create .swu packages for Golioth OTA:"
echo "  cd output/$VERSIONED_OUTPUT_DIR"
echo "  ./create-swu.sh -v $FIRMWARE_VERSION -a $BOARD_NAME"
echo ""
echo "💡 For OTA testing between versions:"
echo "  # Start with older version, then update to newer:"
echo "  qemu-system-${BOARD_NAME} ... -drive file=output/${BOARD_NAME}-1.2.4/rootfs_ab.img ..."
echo "  # Deploy output/${BOARD_NAME}-${FIRMWARE_VERSION}/golioth-fw-${FIRMWARE_VERSION}-${BOARD_NAME}.swu via Golioth"
echo ""
echo "⚙️  Inside QEMU, configure the Golioth daemon:"
echo "  vi /etc/golioth_app.conf"
echo "  # Set: GOLIOTH_SAMPLE_PSK_ID=\"your-device@your-project\""
echo "  # Set: GOLIOTH_SAMPLE_PSK=\"your-device-psk\""
echo "  /etc/init.d/S99golioth_app start"
echo "  tail -f /var/log/messages | grep golioth_app"
echo ""
echo "📚 See output/$VERSIONED_OUTPUT_DIR/OTA-WORKFLOW.md for complete deployment instructions"

# Automatically create .swu file if requested
if [ "$CREATE_SWU" = "true" ]; then
    echo ""
    echo "🔄 Creating .swu file automatically..."
    cd "$VERSIONED_PATH"
    if [ -x "./create-swu.sh" ] && [ -f "rootfs.ext2" ]; then
        if ./create-swu.sh -v "$FIRMWARE_VERSION" -a "$BOARD_NAME" -i "./rootfs.ext2"; then
            echo "✅ SWU file created successfully!"
            SWU_FILE="golioth-fw-${FIRMWARE_VERSION}-${BOARD_NAME}.swu"
            if [ -f "$SWU_FILE" ]; then
                echo "📦 Generated: $SWU_FILE ($(du -h "$SWU_FILE" | cut -f1))"
                echo ""
                echo "🚀 Ready for Golioth OTA deployment!"
                echo "  Upload $SWU_FILE to Golioth Console"
            fi
        else
            echo "⚠️  SWU creation failed, but build artifacts are available"
        fi
    else
        echo "⚠️  Cannot create SWU: missing create-swu.sh or rootfs.ext2"
    fi
    cd /output
fi