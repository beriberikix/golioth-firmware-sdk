# Golioth Firmware SDK Buildroot Example

A complete Linux system with Golioth IoT integration, A/B OTA updates, and production-ready `golioth_app` daemon. Runs on QEMU with U-Boot bootloader for easy testing and development.

## Quick Start

### 1. Get Golioth Credentials

1. Visit [Golioth Console](https://console.golioth.io/)
2. Create a project and add a device
3. Note the **PSK-ID** and **PSK** credentials

### 2. Build with Docker (Recommended)

```bash
# Clone and prepare
git clone https://github.com/golioth/golioth-firmware-sdk.git
cd golioth-firmware-sdk
git submodule update --init --recursive external/libcoap external/zcbor external/fff external/unity
cd examples/linux/buildroot

# Create cache directories
mkdir -p output ccache dl

# Build firmware with automatic .swu generation
# For ARM64 (Apple Silicon):
docker build \
  --build-arg TARGET_CONFIG=qemu_aarch64_golioth_defconfig \
  --build-arg FIRMWARE_VERSION=1.0.1 \
  --build-arg CREATE_SWU=true \
  -t golioth-buildroot .

docker run --rm \
  -v "$(pwd)/../../../..":/workspace \
  -v "$(pwd)/output":/output \
  -v "$(pwd)/ccache":/ccache \
  -v "$(pwd)/dl":/dl \
  golioth-buildroot

# For x86_64:
docker build \
  --build-arg TARGET_CONFIG=qemu_x86_64_golioth_defconfig \
  --build-arg FIRMWARE_VERSION=1.0.1 \
  --build-arg CREATE_SWU=true \
  -t golioth-buildroot .
```

**Build time**: 10-20 minutes first time, 2-5 minutes with caching

### 3. Run with QEMU

Install QEMU:
```bash
# macOS
brew install qemu

# Ubuntu/Debian
sudo apt install qemu-system-x86 qemu-system-aarch64
```

#### Option 1: Simple Testing (Direct Kernel Boot)
```bash
# ARM64:
qemu-system-aarch64 -M virt -cpu cortex-a57 -m 512M \
  -kernel output/aarch64-latest/Image \
  -drive file=output/aarch64-latest/rootfs.ext2,if=virtio,format=raw \
  -append "rootwait root=/dev/vda console=ttyAMA0" \
  -netdev user,id=net0 -device virtio-net-device,netdev=net0 \
  -nographic

# x86_64:
qemu-system-x86_64 -M pc -m 256M \
  -kernel output/x86_64-latest/bzImage \
  -drive file=output/x86_64-latest/rootfs.ext2,if=virtio,format=raw \
  -append "rootwait root=/dev/vda console=ttyS0" \
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
  -nographic
```

#### Option 2: A/B OTA Updates (Recommended)
```bash
# ARM64:
qemu-system-aarch64 -M virt -cpu cortex-a57 -m 512M \
  -bios output/aarch64-latest/u-boot.bin \
  -drive file=output/aarch64-latest/rootfs_ab.img,if=virtio,format=raw \
  -netdev user,id=net0 -device virtio-net-device,netdev=net0 \
  -nographic

# x86_64:
qemu-system-x86_64 -M pc -m 256M \
  -bios output/x86_64-latest/u-boot.bin \
  -drive file=output/x86_64-latest/rootfs_ab.img,if=virtio,format=raw \
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
  -nographic
```

### 4. Configure Golioth

Once booted, log in as `root` (no password):

```bash
# Edit configuration
vi /etc/golioth_app.conf

# Set your credentials:
GOLIOTH_SAMPLE_PSK_ID="your-device@your-project"
GOLIOTH_SAMPLE_PSK="your-device-psk-key"

# Start daemon
/etc/init.d/S99golioth_app start

# View logs
tail -f /var/log/messages | grep golioth_app
```

### 5. Verify Connection

- Go to [Golioth Console](https://console.golioth.io/)
- Check **Devices** → your device should show "Connected"
- View **LightDB State** and **Logs** for real-time data

## OTA Updates with .swu Packages

The Docker build automatically creates `.swu` packages ready for Golioth OTA deployment.

### Versioned Build Structure

```
output/
├── aarch64-1.0.1/
│   ├── rootfs.ext2                    # Single rootfs image
│   ├── rootfs_ab.img                  # A/B partition disk image
│   ├── golioth-fw-1.0.1-aarch64.swu  # Ready for OTA deployment
│   ├── u-boot.bin                    # U-Boot bootloader
│   └── VERSION_INFO                  # Build metadata
└── aarch64-latest -> aarch64-1.0.1/  # Symlink to latest
```

### Multi-Version OTA Testing

```bash
# Build baseline version (for starting QEMU)
docker build --build-arg FIRMWARE_VERSION=1.0.0 --build-arg CREATE_SWU=false -t golioth-buildroot .
docker run --rm -v "$(pwd)/../../../..":/workspace -v "$(pwd)/output":/output -v "$(pwd)/ccache":/ccache -v "$(pwd)/dl":/dl golioth-buildroot

# Build update version (with .swu for deployment)
docker build --build-arg FIRMWARE_VERSION=1.0.1 --build-arg CREATE_SWU=true -t golioth-buildroot .
docker run --rm -v "$(pwd)/../../../..":/workspace -v "$(pwd)/output":/output -v "$(pwd)/ccache":/ccache -v "$(pwd)/dl":/dl golioth-buildroot

# Start QEMU with baseline version
qemu-system-aarch64 -M virt -cpu cortex-a57 -m 512M \
  -bios output/aarch64-1.0.0/u-boot.bin \
  -drive file=output/aarch64-1.0.0/rootfs_ab.img,if=virtio,format=raw \
  -netdev user,id=net0 -device virtio-net-device,netdev=net0 \
  -nographic

# Deploy output/aarch64-1.0.1/golioth-fw-1.0.1-aarch64.swu via Golioth Console
```

### Deploy to Golioth Console

1. **Upload Firmware**:
   - Go to https://console.golioth.io
   - Navigate to **Device Management** → **Firmware**
   - Upload your `.swu` file
   - Set version and description

2. **Create Release**:
   - Go to **Device Management** → **Releases**
   - Create new release with uploaded firmware
   - Deploy to target devices

3. **Monitor Update**:
   - Watch **Devices** for update progress
   - View real-time logs during installation
   - Verify successful A/B switch after reboot

### Update Flow

1. **Cloud Trigger**: Golioth pushes firmware to device
2. **Download**: Device downloads firmware blocks
3. **Stream to swupdate**: Data streamed to swupdate daemon
4. **A/B Install**: swupdate writes to inactive partition
5. **Boot Switch**: U-Boot environment updated for new partition
6. **Verification**: Device boots from new partition and reports success
7. **Rollback Protection**: Automatic rollback on boot failure

## A/B Partition System

### Architecture
- **Golioth**: Cloud management and update orchestration
- **swupdate**: Local A/B partition management and installation
- **U-Boot**: Boot slot selection and automatic rollback

### Partition Layout
```
/dev/vdb1  - Boot partition (16MB) - shared kernel/devicetree
/dev/vdb2  - RootFS A (56MB) - active slot
/dev/vdb3  - RootFS B (56MB) - inactive slot
```

### Managing Updates
```bash
# Check current boot slot
fw_printenv boot_slot

# Check swupdate status
/etc/init.d/S80swupdate status

# View update logs
grep swupdate /var/log/messages
```

## Build Options

Docker build arguments:

- `TARGET_CONFIG`: `qemu_aarch64_golioth_defconfig` or `qemu_x86_64_golioth_defconfig`
- `FIRMWARE_VERSION`: Version string (e.g., `1.0.1`)
- `CREATE_SWU`: Auto-generate .swu file (`true`/`false`, default: `true`)
- `BUILDROOT_VERSION`: Buildroot version (default: `2025.08.x`)

## System Features

- **Bootloader**: U-Boot with A/B boot selection
- **Crypto**: mbedTLS (lightweight, embedded-optimized)
- **Init**: BusyBox init with syslog integration
- **Network**: DHCP with DNS fallback
- **Security**: Embedded security patterns
- **OTA**: Golioth + swupdate A/B updates with rollback protection

## Troubleshooting

### Build Issues
```bash
# Use Docker for reliable builds
# Ensure submodules are updated
git submodule update --init --recursive
```

### Boot Issues
```bash
# Check U-Boot binary exists
ls -la output/*/u-boot.bin

# For debugging, add -monitor stdio to QEMU
```

### Network Issues
```bash
# In QEMU, check network
ip addr show eth0
ping golioth.io
```

### Update Issues
```bash
# Check swupdate daemon
/etc/init.d/S80swupdate status

# Monitor update process
tail -f /var/log/messages | grep -E "(golioth|swupdate)"

# Check partition health
fw_printenv boot_slot
```

## Development

```bash
# Rebuild specific components
make golioth-app-rebuild
make golioth-firmware-sdk-rebuild

# Clean build
make clean && make
```

## Support

- [Golioth Documentation](https://docs.golioth.io/)
- [Golioth Forum](https://forum.golioth.io/)
- [Golioth Discord](https://discord.com/invite/qKjmvzMVYR)

**Exit QEMU**: Press `Ctrl+A` then `X`