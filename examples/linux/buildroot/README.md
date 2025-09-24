# Golioth Firmware SDK Buildroot Example

This directory contains a complete Buildroot br2-external tree for building a Linux system with the Golioth Firmware SDK and a production-ready `golioth_app` daemon. The system uses U-Boot as the bootloader and runs on QEMU with full network support for easy testing and development.

## Quick Start

### 1. Get Golioth Credentials

First, you need device credentials from the Golioth Console:

1. Visit [Golioth Console](https://console.golioth.io/)
2. Create an account or log in
3. Create a new project
4. Add a device and note the **PSK-ID** and **PSK** credentials

### 2. Build with Docker

For the most reliable experience, use Docker:

```bash
# Clone and prepare
git clone https://github.com/golioth/golioth-firmware-sdk.git
cd golioth-firmware-sdk
git submodule update --init --recursive external/libcoap external/zcbor external/fff external/unity
cd examples/linux/buildroot

# Create cache directories
mkdir -p output ccache dl

# Build (choose your architecture)
# For Apple Silicon Macs (ARM64):
docker build --build-arg TARGET_CONFIG=qemu_aarch64_golioth_defconfig -t golioth-buildroot .
docker run --rm -v "$(pwd)/../../../..":/workspace -v "$(pwd)/output":/output -v "$(pwd)/ccache":/ccache -v "$(pwd)/dl":/dl golioth-buildroot

# For Intel/x86_64 systems:
docker build --build-arg TARGET_CONFIG=qemu_x86_64_golioth_defconfig -t golioth-buildroot .
docker run --rm -v "$(pwd)/../../../..":/workspace -v "$(pwd)/output":/output -v "$(pwd)/ccache":/ccache -v "$(pwd)/dl":/dl golioth-buildroot
```

**Build time**: 10-20 minutes first time, 2-5 minutes subsequent builds (with caching)

### 3. Run with QEMU

Install QEMU on your host:
```bash
# macOS
brew install qemu

# Ubuntu/Debian
sudo apt install qemu-system-x86 qemu-system-aarch64
```

Launch the system:
```bash
# For ARM64 build (Apple Silicon):
qemu-system-aarch64 -M virt -cpu cortex-a57 -m 512M \
  -bios output/u-boot.bin \
  -drive file=output/rootfs.ext2,if=virtio,format=raw \
  -drive file=output/Image,if=virtio,format=raw \
  -netdev user,id=net0 -device virtio-net-device,netdev=net0 -nographic

# For x86_64 build:
qemu-system-x86_64 -M pc -m 256M \
  -bios output/u-boot.bin \
  -drive file=output/rootfs.ext2,if=virtio,format=raw \
  -drive file=output/bzImage,if=virtio,format=raw \
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0 -nographic
```

**Note:** The system now boots through U-Boot, which provides a more realistic embedded Linux boot experience. U-Boot will automatically detect and load the kernel from the virtio drive.

### 4. Configure and Start Daemon

Once booted, log in as `root` (no password):

```bash
# Edit configuration file
vi /etc/golioth_app.conf

# Set your credentials (from step 1):
GOLIOTH_SAMPLE_PSK_ID="your-device@your-project"
GOLIOTH_SAMPLE_PSK="your-device-psk-key"

# Start the daemon
/etc/init.d/S99golioth_app start

# Check status
/etc/init.d/S99golioth_app status

# View logs (real-time)
tail -f /var/log/messages | grep golioth_app

# View all daemon logs
grep golioth_app /var/log/messages
```

You should see logs like:
```
golioth_app[123]: Golioth application starting
golioth_app[123]: Golioth client created successfully
golioth_app[123]: Hello, Golioth!
```

### 5. Verify in Golioth Console

- Go to your Golioth Console
- Check **Devices** → your device should show as "Connected"
- View **LightDB State** for real-time data
- Check **Logs** for cloud-uploaded log messages

## Daemon Features

The `golioth_app` is a production-ready daemon with:

- **Automatic startup** on boot
- **Configuration file** at `/etc/golioth_app.conf`
- **Graceful shutdown** (handles SIGTERM/SIGINT properly)
- **Syslog integration** (use `logread` to view logs)
- **Cloud logging** (logs also appear in Golioth Console)
- **Status monitoring** via init script
- **Debug mode** (`golioth_app --no-daemon` for testing)

## Daemon Management

```bash
# Control the daemon
/etc/init.d/S99golioth_app {start|stop|restart|status}

# View logs
tail -f /var/log/messages | grep golioth_app  # Follow logs
grep golioth_app /var/log/messages             # All logs
```

## Development

### Incremental Builds

```bash
# Rebuild only the app
make golioth-app-rebuild

# Rebuild SDK
make golioth-firmware-sdk-rebuild
```

### Architecture Options

- **ARM64** (`qemu_aarch64_golioth_defconfig`): Recommended for Apple Silicon
- **x86_64** (`qemu_x86_64_golioth_defconfig`): For Intel/AMD systems

### Troubleshooting

**Problem**: Daemon fails to start
```bash
# Check credentials are set
cat /etc/golioth_app.conf

# Check logs for errors
tail -f /var/log/messages | grep golioth_app

# Run in debug mode
golioth_app --no-daemon
```

**Problem**: No network connectivity
```bash
# Check network
ip addr show eth0
ping golioth.io
```

**Problem**: Build fails on macOS
- Use Docker (recommended)
- Or install GNU tools: `brew install gcc bash findutils coreutils`

**Problem**: U-Boot doesn't boot or hangs
```bash
# Check if U-Boot binary was created
ls -la output/images/u-boot.bin

# If missing, check build logs for U-Boot errors
make uboot-rebuild

# For debugging, you can run U-Boot interactively
# Add -monitor stdio to QEMU command to get U-Boot prompt
```

**Problem**: U-Boot build fails with crypto library errors
- System uses **mbedTLS only** - no OpenSSL to avoid crypto library bloat
- U-Boot, Golioth SDK, and SSH all use mbedTLS for consistency
- If you see crypto errors, ensure `BR2_PACKAGE_HOST_MBEDTLS=y` and `BR2_TARGET_UBOOT_NEEDS_MBEDTLS=y` are set
- Note: Removed `BR2_LINUX_KERNEL_NEEDS_HOST_OPENSSL=y` to eliminate OpenSSL dependency from kernel builds

**Problem**: Kernel doesn't load after U-Boot
- U-Boot expects kernel on virtio drive - ensure both rootfs and kernel drives are attached
- Check U-Boot environment variables with `printenv` command in U-Boot prompt

## System Details

- **Bootloader**: U-Boot (production-ready embedded bootloader)
- **Crypto Library**: mbedTLS (lightweight, embedded-optimized)
- **Init system**: BusyBox init (simple, embedded-friendly)
- **Logging**: syslog + Golioth cloud logging
- **Network**: DHCP with DNS fallback (8.8.8.8)
- **Filesystem**: ext4, 120MB root filesystem
- **Security**: Runs as root (embedded system pattern)

### Boot Process
1. QEMU starts and loads U-Boot from BIOS flash
2. U-Boot initializes hardware and discovers virtio drives
3. U-Boot automatically loads and boots Linux kernel
4. Linux mounts root filesystem and starts BusyBox init
5. Golioth daemon starts automatically via init script

## Support

- [Golioth Documentation](https://docs.golioth.io/)
- [Golioth Forum](https://forum.golioth.io/)
- [Golioth Discord](https://discord.com/invite/qKjmvzMVYR)

Exit QEMU: Press `Ctrl+A` then `X`