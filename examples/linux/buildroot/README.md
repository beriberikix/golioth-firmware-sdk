# Golioth Firmware SDK Buildroot Example

This directory contains a complete Buildroot br2-external tree for building a Linux system with the Golioth Firmware SDK and the golioth_app example application. The system is configured to run on QEMU with network support for easy testing and development.

## Quick Start

### Docker Approach (Recommended)

For the most reliable experience, especially on macOS, use the provided Dockerfile. This builds everything inside Docker and exports the results to run with QEMU on your host:

```bash
# 1. Clone the repository and initialize submodules
git clone https://github.com/golioth/golioth-firmware-sdk.git
cd golioth-firmware-sdk

# Initialize required submodules for SDK dependencies
git submodule update --init --recursive external/libcoap external/zcbor external/fff external/unity

cd examples/linux/buildroot

# 2. Create output and cache directories
mkdir -p output ccache dl

# 3. Build with Docker (builds everything automatically with optimizations)
# For Apple Silicon Macs (recommended):
docker build \
  --build-arg TARGET_CONFIG=qemu_aarch64_golioth_defconfig \
  --build-arg USER_ID=$(id -u) \
  --build-arg GROUP_ID=$(id -g) \
  -t golioth-buildroot .
docker run --rm \
  -v "$(pwd)/../../../..":/workspace \
  -v "$(pwd)/output":/output \
  -v "$(pwd)/ccache":/ccache \
  -v "$(pwd)/dl":/dl \
  golioth-buildroot

# For Intel Macs or x86_64 systems:
docker build \
  --build-arg TARGET_CONFIG=qemu_x86_64_golioth_defconfig \
  --build-arg USER_ID=$(id -u) \
  --build-arg GROUP_ID=$(id -g) \
  -t golioth-buildroot .
docker run --rm \
  -v "$(pwd)/../../../..":/workspace \
  -v "$(pwd)/output":/output \
  -v "$(pwd)/ccache":/ccache \
  -v "$(pwd)/dl":/dl \
  golioth-buildroot

# 4. Install QEMU on your host system
# macOS: brew install qemu
# Ubuntu: sudo apt install qemu-system-x86 qemu-system-aarch64
# Other systems: install via your package manager

# 5. Run with QEMU on your host (networking works properly)
# For ARM64 build:
qemu-system-aarch64 \
  -M virt -cpu cortex-a57 -m 256M \
  -kernel output/Image \
  -drive file=output/rootfs.ext2,if=virtio,format=raw \
  -append "rootwait root=/dev/vda console=ttyAMA0" \
  -netdev user,id=net0 -device virtio-net-device,netdev=net0 \
  -nographic

# For x86_64 build:
qemu-system-x86_64 \
  -M pc -m 256M \
  -kernel output/bzImage \
  -drive file=output/rootfs.ext2,if=virtio,format=raw \
  -append "rootwait root=/dev/vda console=ttyS0" \
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
  -nographic

# 6. Inside QEMU, set your Golioth credentials and run
export GOLIOTH_SAMPLE_PSK_ID="your-device-psk-id"
export GOLIOTH_SAMPLE_PSK="your-device-psk"
golioth_app
```

**Build Optimizations:**
The Docker build includes several optimizations for maximum speed:
- **External toolchains**: Uses pre-built Bootlin toolchains instead of compiling GCC from scratch
- **Download cache (`dl/`)**: Caches all downloaded source files (Linux kernel, packages) to avoid re-downloading on subsequent builds
- **Per-package directories**: Enables safer parallel builds and better dependency tracking for faster incremental rebuilds
- **ccache**: Compiler cache that dramatically speeds up rebuilds (2GB cache)
- **Parallel builds**: Uses all available CPU cores (capped at 8 for Docker stability)
- **Persistent caches**: Both `ccache` and `dl` directories persist between builds for faster subsequent builds

**First build**: 10-20 minutes (downloads toolchain, Linux kernel ~100MB, and compiles packages)
**Subsequent builds**: 2-5 minutes (no re-downloads, with ccache hits for compilation)

**Docker Build Options:**
- `BUILDROOT_VERSION`: Buildroot branch/tag (default: 2025.08.x)
- `TARGET_CONFIG`: Target configuration (default: qemu_aarch64_golioth_defconfig)

**Custom build example:**
```bash
docker build \
  --build-arg BUILDROOT_VERSION=2024.11.x \
  --build-arg TARGET_CONFIG=qemu_x86_64_golioth_defconfig \
  --build-arg USER_ID=$(id -u) \
  --build-arg GROUP_ID=$(id -g) \
  -t golioth-buildroot .
```

### Native Build

### Prerequisites

- **Host development tools**: gcc, make, git, wget, cpio, unzip, rsync, bc, file
- **QEMU** (for testing): Install via your package manager
- **Buildroot** (tested with 2025.08 and later)
- **Golioth SDK submodules**: Must be initialized before building

### Initialize Golioth SDK Dependencies

Before building, ensure the required git submodules are initialized:

```bash
# From the golioth-firmware-sdk root directory
git submodule update --init --recursive external/libcoap external/zcbor external/fff external/unity
```

**Why these submodules are needed:**
- `libcoap`: CoAP library for network communication
- `zcbor`: CBOR encoding/decoding library
- `fff`: Fake Function Framework for unit testing
- `unity`: Unit testing framework

**Note**: If you skip this step, the Docker build or native build will fail with CMake configuration errors about missing dependencies.

### Setting Up Buildroot

If you don't have Buildroot installed:

1. **Download and extract Buildroot:**
   ```bash
   # Download latest stable release
   wget https://buildroot.org/downloads/buildroot-2025.08.1.tar.xz
   tar -xf buildroot-2025.08.1.tar.xz
   cd buildroot-2025.08.1
   ```

2. **Or clone from Git for latest version:**
   ```bash
   git clone https://gitlab.com/buildroot.org/buildroot.git
   cd buildroot
   git checkout 2025.08.x  # Use stable branch
   ```

3. **Install host dependencies** (Ubuntu/Debian example):
   ```bash
   sudo apt update
   sudo apt install build-essential git wget cpio python3 unzip rsync bc libncurses5-dev
   sudo apt install qemu-system-x86 qemu-utils  # For QEMU testing
   ```

   **For other distributions:**
   - **RHEL/CentOS/Fedora**: `dnf install gcc gcc-c++ git wget cpio python3 unzip rsync bc ncurses-devel qemu-system-x86`
   - **Arch Linux**: `pacman -S base-devel git wget cpio python unzip rsync bc ncurses qemu-system-x86`
   - **macOS (Recommended: Docker)**: Use Docker for the best compatibility:
     ```bash
     # Install Docker Desktop for Mac
     # Visit https://www.docker.com/products/docker-desktop/
     
     # Run buildroot in a Ubuntu container
     docker run -it --rm \
       -v "$(pwd)":/workspace \
       -w /workspace \
       ubuntu:22.04 /bin/bash
     
     # Inside the container, install dependencies:
     apt update && apt install -y \
       build-essential git wget cpio python3 unzip rsync bc \
       libncurses5-dev qemu-system-x86 qemu-utils
     
     # Then follow the Linux build instructions
     ```

   - **macOS (Native Build - Advanced)**: Install Xcode command line tools and GNU tools via Homebrew:
     ```bash
     # Install Xcode command line tools
     xcode-select --install
     
     # Install required dependencies via Homebrew
     brew install wget cpio qemu gcc bash gpatch flock findutils coreutils libiconv
     
     # Set up environment for GNU tools (required for buildroot)
     export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:/opt/homebrew/opt/findutils/libexec/gnubin:/opt/homebrew/opt/gpatch/libexec/gnubin:/opt/homebrew/bin:$PATH"
     export CONFIG_SHELL="/opt/homebrew/bin/bash"
     export SHELL="/opt/homebrew/bin/bash"
     
     # For permanent setup, add to your shell profile (~/.zshrc or ~/.bash_profile):
     echo 'export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:/opt/homebrew/opt/findutils/libexec/gnubin:/opt/homebrew/opt/gpatch/libexec/gnubin:/opt/homebrew/bin:$PATH"' >> ~/.zshrc
     echo 'export CONFIG_SHELL="/opt/homebrew/bin/bash"' >> ~/.zshrc
     echo 'export SHELL="/opt/homebrew/bin/bash"' >> ~/.zshrc
     ```
     
     **Note**: Buildroot requires GNU versions of standard tools. The setup above ensures:
     - GNU `gcc` instead of Apple's clang
     - GNU `find` with `-printf` support
     - GNU `patch` utility
     - Modern `bash` with `mapfile` builtin
     - `flock` utility for build synchronization

### Build the System

1. **Navigate to your Buildroot directory:**
   ```bash
   cd /path/to/buildroot
   ```

2. **Configure Buildroot with the Golioth external tree:**

   **For x86_64 systems (most Linux hosts, Intel Macs):**
   ```bash
   make BR2_EXTERNAL=/path/to/golioth-firmware-sdk/examples/linux/buildroot qemu_x86_64_golioth_defconfig
   ```

   **For Apple Silicon Macs (M1/M2/M3) - RECOMMENDED:**
   ```bash
   make BR2_EXTERNAL=/path/to/golioth-firmware-sdk/examples/linux/buildroot qemu_aarch64_golioth_defconfig
   ```

   **Why use ARM64 on Apple Silicon?**
   - **Better performance**: Native ARM64 code runs faster than x86_64 emulation
   - **HVF acceleration**: Uses Apple's Hypervisor framework for near-native speed
   - **Lower resource usage**: Less CPU and battery consumption

   **Example with actual paths:**
   ```bash
   # Apple Silicon Mac (M1/M2/M3)
   make BR2_EXTERNAL=~/golioth-firmware-sdk/examples/linux/buildroot qemu_aarch64_golioth_defconfig

   # Intel Mac or Linux
   make BR2_EXTERNAL=~/golioth-firmware-sdk/examples/linux/buildroot qemu_x86_64_golioth_defconfig
   ```

3. **Build the system:**

   **For Linux or Docker:**
   ```bash
   make
   ```

   **For macOS (Docker - Recommended):**
   ```bash
   # From your buildroot directory in the Docker container
   cd /workspace
   make BR2_EXTERNAL=/workspace/golioth-firmware-sdk/examples/linux/buildroot qemu_aarch64_golioth_defconfig
   make
   ```

   **For macOS (Native Build - Advanced):**
   ```bash
   # Ensure GNU tools are in PATH and proper shell is set
   PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:/opt/homebrew/opt/findutils/libexec/gnubin:/opt/homebrew/opt/gpatch/libexec/gnubin:/opt/homebrew/bin:$PATH" \
   CONFIG_SHELL="/opt/homebrew/bin/bash" \
   SHELL="/opt/homebrew/bin/bash" \
   LIBS="-L/opt/homebrew/opt/libiconv/lib -liconv" \
   make HOSTCC="/opt/homebrew/bin/gcc-15" HOSTCXX="/opt/homebrew/bin/g++-15"
   ```

   **Build Details:**
   - **Duration**: First build takes 10-20 minutes (downloads external toolchain and compiles packages)
   - **Disk space**: Requires ~1-2GB for complete build
   - **Output**: Creates kernel, rootfs, and bootloader in `output/images/`
   - **What gets built**:
     - Linux kernel with VirtIO networking support
     - Golioth Firmware SDK library (using external toolchain)
     - golioth_app example application
     - Root filesystem with network configuration
     - QEMU-compatible system images

   **Build progress monitoring:**
   ```bash
   # Monitor build progress in another terminal
   tail -f output/build/build-time.log
   ```

4. **Run in QEMU:**

   **For ARM64 systems (Apple Silicon Macs):**
   ```bash
   cd /path/to/golioth-firmware-sdk/examples/linux/buildroot
   ./scripts/run_qemu_aarch64.sh
   ```

   **For x86_64 systems:**
   ```bash
   cd /path/to/golioth-firmware-sdk/examples/linux/buildroot
   ./scripts/run_qemu.sh
   ```

   **Alternative manual QEMU launch:**

   *ARM64 (Apple Silicon):*
   ```bash
   # From your buildroot directory
   output/host/bin/qemu-system-aarch64 \
       -M virt \
       -cpu cortex-a57 \
       -accel hvf \
       -kernel output/images/Image \
       -drive file=output/images/rootfs.ext2,if=virtio,format=raw \
       -append "rootwait root=/dev/vda console=ttyAMA0" \
       -netdev user,id=net0 \
       -device virtio-net-device,netdev=net0 \
       -nographic
   ```

   *x86_64:*
   ```bash
   # From your buildroot directory
   output/host/bin/qemu-system-x86_64 \
       -M pc \
       -kernel output/images/bzImage \
       -drive file=output/images/rootfs.ext2,if=virtio,format=raw \
       -append "rootwait root=/dev/vda console=ttyS0" \
       -net nic,model=virtio \
       -net user \
       -nographic
   ```

### Testing Golioth Connectivity

Once the system boots in QEMU:

1. **First time setup - Get Golioth device credentials:**
   - Visit [Golioth Console](https://console.golioth.io/)
   - Create an account or log in
   - Create a new project
   - Add a device and note the PSK-ID and PSK credentials

2. **Wait for system boot:**

   *x86_64 system:*
   ```
   Welcome to Golioth QEMU
   golioth-qemu login: root
   ```

   *ARM64 system:*
   ```
   Welcome to Golioth QEMU (ARM64)
   golioth-qemu login: root
   ```

   **Login as root** (no password required)

3. **Verify network connectivity:**
   ```bash
   # Check network interface
   ip addr show eth0

   # Test internet connectivity
   ping -c 3 golioth.io

   # Test DNS resolution
   nslookup golioth.io
   ```

4. **Set up your Golioth credentials:**
   ```bash
   export GOLIOTH_SAMPLE_PSK_ID="your-device-psk-id"
   export GOLIOTH_SAMPLE_PSK="your-device-psk"
   ```

   **Example:**
   ```bash
   export GOLIOTH_SAMPLE_PSK_ID="my-device@my-project"
   export GOLIOTH_SAMPLE_PSK="super-secret-psk-key"
   ```

5. **Run the Golioth application:**
   ```bash
   golioth_app
   ```

   **Expected output:**
   ```
   [00:00:02.123] <info> main: Waiting for connection to Golioth...
   [00:00:03.456] <info> golioth_app: Golioth client connected
   [00:00:03.789] <info> golioth_app: Hello, Golioth!
   ```

6. **Verify connectivity in Golioth Console:**
   - Check your Golioth console for device activity
   - View LightDB State data
   - Monitor device logs and telemetry

7. **Exit QEMU:**
   - Press `Ctrl+A` then `X` to exit QEMU
   - Or use `shutdown -h now` from within the VM

## Configuration Details

### Packages Included

- **golioth-firmware-sdk**: The core Golioth SDK library with all services enabled
- **golioth-app**: Self-contained example application demonstrating SDK features (builds golioth_app binary)
- **OpenSSL**: Required for TLS/DTLS connectivity
- **Network tools**: wget, dhcpcd, openssh for connectivity and debugging
- **Development tools**: strace, gdb for debugging

### Network Configuration

The system is configured with:
- **DHCP**: eth0 automatically configured via DHCP
- **DNS**: Fallback to 8.8.8.8, 8.8.4.4 for reliable internet access
- **VirtIO networking**: Optimized virtual network drivers for QEMU

### QEMU Features

- **User networking**: NAT-style networking for internet access
- **VirtIO devices**: Optimized virtual hardware
- **Serial console**: Direct console access (no graphics required)
- **Root filesystem**: ext4 filesystem with 120MB space

## Customization

### Adding Your Own Applications

1. Create a new package directory:
   ```
   package/your-app/
   ├── Config.in
   └── your-app.mk
   ```

2. Add the package to the main Config.in:
   ```bash
   echo 'source "$BR2_EXTERNAL_GOLIOTH_BUILDROOT_PATH/package/your-app/Config.in"' >> Config.in
   ```

3. Enable the package in menuconfig:
   ```bash
   make menuconfig
   ```

### Modifying the Configuration

To customize the build:

1. **Edit packages and kernel options:**
   ```bash
   make menuconfig
   ```

2. **Save your configuration:**
   ```bash
   make savedefconfig
   cp defconfig configs/qemu_x86_64_golioth_defconfig
   ```

3. **Modify rootfs overlay:**
   Edit files in `board/qemu/x86_64-golioth/rootfs_overlay/`

## Development Workflow

### Incremental Development

For faster development cycles:

1. **Rebuild only changed packages:**
   ```bash
   make golioth-app-rebuild
   make golioth-firmware-sdk-rebuild
   ```

2. **Update rootfs without full rebuild:**
   ```bash
   make target-finalize
   ```

3. **Test in QEMU:**
   ```bash
   ./scripts/run_qemu.sh
   ```

### Debugging

The system includes debugging tools:

- **GDB**: For debugging applications
- **Strace**: For system call tracing
- **SSH**: For remote access (if configured)

Example debugging session:
```bash
# In QEMU
gdb golioth_app
(gdb) run
```

### Cross-compilation Outside Buildroot

To use the Buildroot toolchain for standalone development:

```bash
export PATH=/path/to/buildroot/output/host/bin:$PATH
export STAGING_DIR=/path/to/buildroot/output/staging
export TARGET_DIR=/path/to/buildroot/output/target

# Use the cross-compiler
x86_64-linux-gcc -o myapp myapp.c -I$STAGING_DIR/usr/include -L$STAGING_DIR/usr/lib -lgolioth_sdk
```

## Directory Structure

```
buildroot/
├── external.desc              # br2-external metadata
├── Config.in                  # Package menu integration
├── external.mk               # Package makefile integration
├── package/
│   ├── golioth-firmware-sdk/  # SDK package definition
│   └── golioth-app/           # Self-contained example app package
│       └── src/               # Embedded source files (golioth_app.c, main.c, etc.)
├── configs/
│   └── qemu_x86_64_golioth_defconfig  # System configuration
├── board/qemu/x86_64-golioth/
│   ├── linux.fragment        # Kernel config additions
│   ├── post-build.sh         # Post-build customization
│   └── rootfs_overlay/       # Additional rootfs files
├── scripts/
│   └── run_qemu.sh           # QEMU launch script
└── README.md                 # This file
```

## Apple Silicon Mac Specific Notes

### Architecture Choice
- **ARM64 configuration**: Use `qemu_aarch64_golioth_defconfig` for best performance
- **x86_64 configuration**: Still works but runs slower due to emulation
- **HVF acceleration**: ARM64 QEMU can use Apple's Hypervisor framework for near-native performance

### Performance Comparison
- **ARM64 + HVF**: Near-native performance, low CPU usage
- **x86_64 emulation**: ~10-50x slower, high CPU usage, drains battery faster

### Compatibility
- Both configurations run the same Golioth code
- ARM64 kernel may boot slightly differently but functionality is identical
- All network features work the same on both architectures

### Build Time Differences
- **ARM64**: Faster builds on Apple Silicon due to native compilation
- **x86_64**: Cross-compilation overhead adds ~10-20% to build time

## Troubleshooting

### General Recommendation for macOS

**The simplest solution for macOS users is to use Docker** as shown in the Quick Start section above. This avoids all the GNU tool compatibility issues and provides a consistent Linux environment.

### macOS Native Build Issues

If you choose to build natively on macOS, you may encounter these issues:

- **"You must install 'gcc' on your build machine"**: Install GNU gcc via Homebrew
  ```bash
  brew install gcc
  # Use gcc-15 specifically in make command
  make HOSTCC="/opt/homebrew/bin/gcc-15" HOSTCXX="/opt/homebrew/bin/g++-15"
  ```

- **"mapfile: command not found"**: Install modern bash and set it as CONFIG_SHELL
  ```bash
  brew install bash
  export CONFIG_SHELL="/opt/homebrew/bin/bash"
  export SHELL="/opt/homebrew/bin/bash"
  ```

- **"find: -printf: unknown primary or operator"**: Install GNU findutils
  ```bash
  brew install findutils
  export PATH="/opt/homebrew/opt/findutils/libexec/gnubin:$PATH"
  ```

- **"flock: command not found"**: Install flock utility
  ```bash
  brew install flock
  ```

- **"patch" command issues**: Install GNU patch
  ```bash
  brew install gpatch
  export PATH="/opt/homebrew/opt/gpatch/libexec/gnubin:$PATH"
  ```

- **"required mntent.h header file not available"**: This error occurs because some Linux utilities require Linux-specific headers. This is expected on macOS and the build can continue with a different configuration.

- **All-in-one fix for macOS**: If you encounter multiple tool issues, run:
  ```bash
  # Install all required GNU tools
  brew install gcc bash gpatch flock findutils coreutils libiconv wget cpio qemu
  
  # Set up environment (add to ~/.zshrc for persistence)
  export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:/opt/homebrew/opt/findutils/libexec/gnubin:/opt/homebrew/opt/gpatch/libexec/gnubin:/opt/homebrew/bin:$PATH"
  export CONFIG_SHELL="/opt/homebrew/bin/bash"
  export SHELL="/opt/homebrew/bin/bash"
  
  # Build with proper tools and libraries
  PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:/opt/homebrew/opt/findutils/libexec/gnubin:/opt/homebrew/opt/gpatch/libexec/gnubin:/opt/homebrew/bin:$PATH" \
  CONFIG_SHELL="/opt/homebrew/bin/bash" \
  SHELL="/opt/homebrew/bin/bash" \
  LIBS="-L/opt/homebrew/opt/libiconv/lib -liconv" \
  make HOSTCC="/opt/homebrew/bin/gcc-15" HOSTCXX="/opt/homebrew/bin/g++-15"
  ```

### Apple Silicon Mac Issues

- **QEMU performance poor**: Make sure you're using the ARM64 configuration
  ```bash
  # Check which configuration you built
  grep "BR2_aarch64=y" output/.config  # Should show ARM64
  # If not, reconfigure:
  make qemu_aarch64_golioth_defconfig
  ```

- **HVF acceleration not working**: Ensure you have macOS 10.15+ and SIP allows virtualization
  ```bash
  # Check if HVF is available
  qemu-system-aarch64 -accel help | grep hvf
  ```

- **Build fails on Apple Silicon**: Use Xcode command line tools, not Xcode app
  ```bash
  # Reinstall command line tools if needed
  sudo xcode-select --reset
  xcode-select --install
  ```

### Build Issues

- **Missing dependencies**: Ensure your host has development tools installed
  ```bash
  # Ubuntu/Debian
  sudo apt install build-essential git wget cpio python3 unzip rsync bc libncurses5-dev
  ```

- **Download failures**: Check internet connectivity and proxy settings
  ```bash
  # If behind a corporate proxy, set:
  export http_proxy=http://proxy.company.com:8080
  export https_proxy=http://proxy.company.com:8080
  ```

- **Disk space**: Buildroot builds require several GB of free space
  ```bash
  # Check available space
  df -h .
  # Clean previous builds if needed
  make clean
  ```

- **Permission errors**: Ensure you have write permissions
  ```bash
  # Fix buildroot directory permissions
  chmod -R u+w /path/to/buildroot
  ```

- **Parallel build issues**: If build fails, try single-threaded build
  ```bash
  # Instead of 'make'
  make -j1
  ```

- **Host tool version conflicts**: Use Buildroot's host tools
  ```bash
  # Add Buildroot's host tools to PATH
  export PATH=/path/to/buildroot/output/host/bin:$PATH
  ```

### Runtime Issues

- **Network not working**: Check if DHCP is working with `ip addr show`
- **DNS resolution failing**: Verify `/etc/resolv.conf` content
- **Golioth connection timeout**: Verify credentials and internet connectivity

### QEMU Issues

- **QEMU not found**: Install QEMU or use Buildroot's host QEMU:
  ```bash
  export PATH=/path/to/buildroot/output/host/bin:$PATH
  ```
- **No network in QEMU**: Ensure user networking is enabled (default)
- **Console not responsive**: Use Ctrl+A then X to exit QEMU

## Resources

- [Buildroot User Manual](https://buildroot.org/manual.html)
- [Golioth Documentation](https://docs.golioth.io/)
- [Golioth Firmware SDK API](https://firmware-sdk-docs.golioth.io/)
- [QEMU Documentation](https://www.qemu.org/docs/master/)

## Support

For Golioth-specific issues:
- [Golioth Forum](https://forum.golioth.io/)
- [Golioth Discord](https://discord.com/invite/qKjmvzMVYR)

For Buildroot issues:
- [Buildroot Mailing List](http://buildroot.busybox.net/lists.html)
- [Buildroot Documentation](https://buildroot.org/manual.html)