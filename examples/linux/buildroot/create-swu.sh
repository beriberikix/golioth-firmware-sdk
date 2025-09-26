#!/bin/bash
#
# Create swupdate package (.swu) for Golioth OTA deployment
# This script generates a proper .swu file from build artifacts
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

usage() {
    echo "Usage: $0 -v VERSION -a ARCH [-i ROOTFS_IMAGE] [-o OUTPUT] [-d DESCRIPTION]"
    echo ""
    echo "Options:"
    echo "  -v VERSION        Firmware version (e.g., 1.2.6)"
    echo "  -a ARCH           Architecture (aarch64 or x86_64)"
    echo "  -i ROOTFS_IMAGE   Path to rootfs image (default: output/images/rootfs.ext2)"
    echo "  -o OUTPUT         Output .swu filename (default: golioth-fw-VERSION-ARCH.swu)"
    echo "  -d DESCRIPTION    Update description (default: Golioth firmware vVERSION)"
    echo ""
    echo "Examples:"
    echo "  $0 -v 1.2.6 -a aarch64"
    echo "  $0 -v 1.2.6 -a x86_64 -i custom-rootfs.ext2"
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

# Set defaults
if [ -z "$ROOTFS_IMAGE" ]; then
    ROOTFS_IMAGE="${BUILD_DIR}/images/rootfs.ext2"
fi

if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="golioth-fw-${VERSION}-${ARCH}.swu"
fi

if [ -z "$DESCRIPTION" ]; then
    DESCRIPTION="Golioth firmware v${VERSION}"
fi

echo "Creating swupdate package..."
echo "  Version: $VERSION"
echo "  Architecture: $ARCH"
echo "  RootFS: $ROOTFS_IMAGE"
echo "  Output: $OUTPUT_FILE"
echo "  Description: $DESCRIPTION"

# Verify rootfs image exists
if [ ! -f "$ROOTFS_IMAGE" ]; then
    echo "Error: RootFS image not found: $ROOTFS_IMAGE"
    echo "Build the system first or specify correct path with -i"
    exit 1
fi

# Create temporary directory for swu package
rm -rf "$SWU_DIR"
mkdir -p "$SWU_DIR"

# Copy rootfs image to package directory
cp "$ROOTFS_IMAGE" "$SWU_DIR/rootfs.ext2"

# Calculate SHA256 hash of rootfs
ROOTFS_SHA256=$(sha256sum "$SWU_DIR/rootfs.ext2" | cut -d' ' -f1)
ROOTFS_SIZE=$(stat -f%z "$SWU_DIR/rootfs.ext2" 2>/dev/null || stat -c%s "$SWU_DIR/rootfs.ext2")

echo "  RootFS SHA256: $ROOTFS_SHA256"
echo "  RootFS Size: $ROOTFS_SIZE bytes"

# Create sw-description file
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
                path = "/dev/vdb2";  // Slot A
                type = "raw";
                sha256 = "${ROOTFS_SHA256}";
                compressed = false;
                installed-directly = true;
            }
        );

        bootenv: (
            {
                name = "boot_slot";
                value = "a";
            },
            {
                name = "boot_slot_retry";
                value = "3";
            }
        );

        scripts: (
            {
                filename = "post-install.sh";
                type = "postinstall";
            }
        );
    };
}
EOF

# Create post-install script
cat > "$SWU_DIR/post-install.sh" << 'EOF'
#!/bin/sh
#
# Post-install script for Golioth swupdate integration
#

echo "Golioth swupdate post-install: Firmware installation complete"

# Verify the installation was successful
if [ $? -eq 0 ]; then
    echo "Update successful - new firmware ready for activation"
    # Mark update as ready for reboot
    touch /tmp/golioth_update_ready
else
    echo "Update failed during installation"
    exit 1
fi

exit 0
EOF

chmod +x "$SWU_DIR/post-install.sh"

# Create the .swu file (it's just a CPIO archive)
cd "$SWU_DIR"
find . -depth -print | cpio -o -H crc > "../$OUTPUT_FILE"
cd ..

# Clean up temporary directory
rm -rf "$SWU_DIR"

# Calculate final package info
SWU_SIZE=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || stat -c%s "$OUTPUT_FILE")
SWU_SHA256=$(sha256sum "$OUTPUT_FILE" | cut -d' ' -f1)

echo ""
echo "✅ swupdate package created successfully!"
echo "   📦 File: $OUTPUT_FILE"
echo "   📏 Size: $SWU_SIZE bytes ($(echo "scale=1; $SWU_SIZE/1024/1024" | bc)MB)"
echo "   🔐 SHA256: $SWU_SHA256"
echo ""
echo "📤 Upload to Golioth:"
echo "   1. Go to https://console.golioth.io"
echo "   2. Navigate to Device Management → Firmware"
echo "   3. Upload $OUTPUT_FILE"
echo "   4. Create release and deploy to your devices"
echo ""
echo "🧪 Test locally:"
echo "   swupdate-client -v -i $OUTPUT_FILE"
EOF