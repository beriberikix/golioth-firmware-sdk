#!/bin/bash
#
# Create swupdate package (.swu) for Golioth OTA deployment
# Simplified single-partition approach for reliable OTA updates
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/output"
SWU_DIR="${SCRIPT_DIR}/swu-package"

# Default values
VERSION=""
ARCH=""
ROOTFS_IMAGE=""
OUTPUT_FILE=""
DESCRIPTION=""
VERSIONED_OUTPUT_DIR=""

usage() {
    echo "Usage: $0 -v VERSION -a ARCH [-i ROOTFS_IMAGE] [-o OUTPUT] [-d DESCRIPTION]"
    echo ""
    echo "Options:"
    echo "  -v VERSION        Firmware version (e.g., 1.2.6)"
    echo "  -a ARCH           Architecture (aarch64 or x86_64)"
    echo "  -i ROOTFS_IMAGE   Path to rootfs image (default: auto-detect from versioned output)"
    echo "  -o OUTPUT         Output .swu filename (default: golioth-fw-VERSION-ARCH.swu)"
    echo "  -d DESCRIPTION    Update description (default: Golioth firmware vVERSION)"
    echo ""
    echo "Examples:"
    echo "  $0 -v 1.2.6 -a aarch64"
    echo "  $0 -v 1.2.6 -a x86_64 -i custom-rootfs.ext2"
    echo ""
    echo "This script will automatically find rootfs images in versioned output directories."
    echo ""
    exit 1
}

# Parse command line arguments
while getopts "v:a:i:o:d:h" opt; do
    case $opt in
        v) VERSION="$OPTARG" ;;
        a) ARCH="$OPTARG" ;;
        i) ROOTFS_IMAGE="$OPTARG" ;;
        o) OUTPUT_FILE="$OPTARG" ;;
        d) DESCRIPTION="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Validate required arguments
if [ -z "$VERSION" ] || [ -z "$ARCH" ]; then
    echo "Error: Version (-v) and Architecture (-a) are required"
    usage
fi

if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "x86_64" ]; then
    echo "Error: Architecture must be 'aarch64' or 'x86_64'"
    exit 1
fi

# Auto-detect versioned output directory
VERSIONED_OUTPUT_DIR="${BUILD_DIR}/${ARCH}-${VERSION}"
if [ ! -d "$VERSIONED_OUTPUT_DIR" ]; then
    echo "Error: Versioned output directory not found: $VERSIONED_OUTPUT_DIR"
    echo "Make sure you built the firmware with version $VERSION"
    exit 1
fi

# Set defaults based on versioned output
if [ -z "$ROOTFS_IMAGE" ]; then
    ROOTFS_IMAGE="${VERSIONED_OUTPUT_DIR}/rootfs.ext2"
    if [ ! -f "$ROOTFS_IMAGE" ]; then
        echo "Error: RootFS image not found in versioned output: $ROOTFS_IMAGE"
        echo "Available files in $VERSIONED_OUTPUT_DIR:"
        ls -la "$VERSIONED_OUTPUT_DIR/" || echo "Directory not accessible"
        exit 1
    fi
fi

if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="${VERSIONED_OUTPUT_DIR}/golioth-fw-${VERSION}-${ARCH}.swu"
fi

if [ -z "$DESCRIPTION" ]; then
    DESCRIPTION="Golioth firmware v${VERSION} for ${ARCH}"
fi

echo "Creating simplified single-partition swupdate package..."
echo "  Version: $VERSION"
echo "  Architecture: $ARCH"
echo "  RootFS: $ROOTFS_IMAGE"
echo "  Output: $OUTPUT_FILE"
echo "  Description: $DESCRIPTION"

# Verify rootfs image exists
if [ ! -f "$ROOTFS_IMAGE" ]; then
    echo "Error: RootFS image not found: $ROOTFS_IMAGE"
    exit 1
fi

# Create temporary directory for swu package
rm -rf "$SWU_DIR"
mkdir -p "$SWU_DIR"

# Copy rootfs image to package directory
cp "$ROOTFS_IMAGE" "$SWU_DIR/rootfs.ext2"

# Calculate SHA256 hash and size of rootfs
ROOTFS_SHA256=$(sha256sum "$SWU_DIR/rootfs.ext2" | cut -d' ' -f1)
ROOTFS_SIZE=$(stat -c%s "$SWU_DIR/rootfs.ext2" 2>/dev/null || stat -f%z "$SWU_DIR/rootfs.ext2" 2>/dev/null)

echo "  RootFS SHA256: $ROOTFS_SHA256"
echo "  RootFS Size: $ROOTFS_SIZE bytes ($(echo "scale=1; $ROOTFS_SIZE/1024/1024" | bc -l)MB)"

# Create sw-description file for single partition update
cat > "$SWU_DIR/sw-description" << EOF
software =
{
    version = "${VERSION}";
    description = "${DESCRIPTION}";

    ${ARCH} = {
        hardware-compatibility: [ "1.0" ];

        files: (
            {
                filename = "rootfs.ext2";
                path = "/dev/vda2";
                type = "raw";
                sha256 = "${ROOTFS_SHA256}";
                compressed = false;
                installed-directly = true;
            }
        );

        bootenv: (
            {
                name = "firmware_version";
                value = "${VERSION}";
            },
            {
                name = "update_available";
                value = "0";
            }
        );

        scripts: (
            {
                filename = "pre-install.sh";
                type = "preinstall";
            },
            {
                filename = "post-install.sh";
                type = "postinstall";
            }
        );
    };
}
EOF

# Create pre-install script
cat > "$SWU_DIR/pre-install.sh" << 'EOF'
#!/bin/sh
#
# Pre-install script for Golioth single partition update
#

echo "Golioth SWUpdate: Starting firmware update process"
echo "Target device: /dev/vda2"
echo "Update method: Single partition in-place update"

# Create backup marker
echo "$(date): Update started" >> /var/log/golioth_updates.log

# Stop non-essential services to free up resources
/etc/init.d/S99golioth_app stop 2>/dev/null || true

echo "Pre-install checks complete"
exit 0
EOF

# Create post-install script
cat > "$SWU_DIR/post-install.sh" << 'EOF'
#!/bin/sh
#
# Post-install script for Golioth single partition update
#

echo "Golioth SWUpdate: Firmware installation completed successfully"

# Mark update as successful
echo "$(date): Update completed successfully" >> /var/log/golioth_updates.log
touch /tmp/golioth_update_ready

# Sync filesystem
sync

echo "Post-install complete - system ready for reboot"
exit 0
EOF

chmod +x "$SWU_DIR/pre-install.sh"
chmod +x "$SWU_DIR/post-install.sh"

# Create the .swu file (CPIO archive with CRC)
echo "Creating .swu package..."
cd "$SWU_DIR"
find . -depth -print | cpio -o -H crc > "../$(basename "$OUTPUT_FILE")"
cd ..

# Move to final location
if [ "$(dirname "$OUTPUT_FILE")" != "." ]; then
    mv "$(basename "$OUTPUT_FILE")" "$OUTPUT_FILE"
fi

# Clean up temporary directory
rm -rf "$SWU_DIR"

# Calculate final package info
SWU_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || stat -f%z "$OUTPUT_FILE" 2>/dev/null)
SWU_SHA256=$(sha256sum "$OUTPUT_FILE" | cut -d' ' -f1)

echo ""
echo "✅ SWUpdate package created successfully!"
echo "   📦 File: $OUTPUT_FILE"
echo "   📏 Size: $SWU_SIZE bytes ($(echo "scale=1; $SWU_SIZE/1024/1024" | bc -l)MB)"
echo "   🔐 SHA256: $SWU_SHA256"
echo ""
echo "📤 Upload to Golioth Console:"
echo "   1. Go to https://console.golioth.io"
echo "   2. Navigate to Device Management → Firmware"
echo "   3. Upload $(basename "$OUTPUT_FILE")"
echo "   4. Create release with version $VERSION"
echo "   5. Deploy to your devices"
echo ""
echo "🧪 Test locally (inside QEMU):"
echo "   swupdate-client -v -i /tmp/$(basename "$OUTPUT_FILE")"
echo ""
echo "📋 Update details:"
echo "   - Update method: Single partition in-place"
echo "   - Target device: /dev/vda2"
echo "   - Reboot required: Yes (automatic)"
echo "   - Rollback: Not supported (ensure thorough testing)"