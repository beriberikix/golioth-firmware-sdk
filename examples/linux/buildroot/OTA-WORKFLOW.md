# Advanced OTA Deployment Workflows

This document covers advanced deployment scenarios, troubleshooting, and best practices for Golioth + swupdate A/B OTA updates.

> **Quick Start**: See [README.md](README.md) for basic OTA deployment workflow.

## Advanced Deployment Scenarios

### Gradual Fleet Deployment

Deploy updates to subsets of devices to minimize risk:

```bash
# Build multiple versions for staged rollout
docker build --build-arg FIRMWARE_VERSION=1.2.5 --build-arg CREATE_SWU=true -t golioth-buildroot .
docker run --rm -v "$(pwd)/../../../..":/workspace -v "$(pwd)/output":/output -v "$(pwd)/ccache":/ccache -v "$(pwd)/dl":/dl golioth-buildroot

# In Golioth Console:
# 1. Upload firmware
# 2. Create release targeting device tags/groups
# 3. Deploy to 10% of fleet first
# 4. Monitor for 24-48 hours
# 5. Expand to 50%, then 100%
```

### Multi-Component Updates

Update multiple system components in a coordinated fashion:

```bash
# Use advanced sw-description template
cd output/aarch64-1.2.5/swu-templates
cp sw-description-multi.template ../sw-description-custom

# Edit for your specific components
vi ../sw-description-custom

# Create multi-component .swu
../create-swu.sh -v 1.2.5 -a aarch64 \
  -i ../rootfs.ext2 \
  -o multi-component-1.2.5.swu \
  -d "Kernel + rootfs + configuration update"
```

### Emergency Rollback Procedures

When immediate rollback is needed:

#### Method 1: Via Golioth Console
1. Create emergency release with previous firmware version
2. Set high priority deployment
3. Push to affected devices immediately

#### Method 2: Device-Side Emergency Rollback
```bash
# Via SSH/console access to device:
fw_setenv boot_slot a            # Switch to known-good slot
fw_setenv boot_slot_retry 3      # Reset retry counter
fw_setenv upgrade_available 0    # Clear upgrade flag
reboot
```

#### Method 3: U-Boot Recovery
```bash
# At U-Boot prompt (interrupt boot):
=> setenv boot_slot a
=> setenv boot_slot_retry 3
=> saveenv
=> run ab_boot
```

### Development & Testing Workflows

#### Full Development Cycle
```bash
# 1. Code changes
vim package/golioth-app/src/golioth_app.c

# 2. Version bump
# Update version strings in code and configs

# 3. Local build and test
docker build --build-arg FIRMWARE_VERSION=1.2.6-dev --build-arg CREATE_SWU=false -t golioth-buildroot .
docker run --rm -v "$(pwd)/../../../..":/workspace -v "$(pwd)/output":/output -v "$(pwd)/ccache":/ccache -v "$(pwd)/dl":/dl golioth-buildroot

# 4. Test in QEMU
qemu-system-aarch64 -M virt -cpu cortex-a57 -m 512M \
  -kernel output/aarch64-1.2.6-dev/Image \
  -drive file=output/aarch64-1.2.6-dev/rootfs.ext2,if=virtio,format=raw \
  -append "rootwait root=/dev/vda console=ttyAMA0" \
  -netdev user,id=net0 -device virtio-net-device,netdev=net0 \
  -nographic

# 5. Create production build with .swu
docker build --build-arg FIRMWARE_VERSION=1.2.6 --build-arg CREATE_SWU=true -t golioth-buildroot .
docker run --rm -v "$(pwd)/../../../..":/workspace -v "$(pwd)/output":/output -v "$(pwd)/ccache":/ccache -v "$(pwd)/dl":/dl golioth-buildroot

# 6. Test A/B update flow locally
# Start with baseline version, deploy .swu via Golioth
```

#### Regression Testing
```bash
# Test update path: 1.2.4 → 1.2.5 → 1.2.6
versions=("1.2.4" "1.2.5" "1.2.6")
for version in "${versions[@]}"; do
    docker build --build-arg FIRMWARE_VERSION=$version --build-arg CREATE_SWU=true -t golioth-buildroot .
    docker run --rm -v "$(pwd)/../../../..":/workspace -v "$(pwd)/output":/output -v "$(pwd)/ccache":/ccache -v "$(pwd)/dl":/dl golioth-buildroot
done

# Test each upgrade path in QEMU
# Start with 1.2.4, update to 1.2.5, then to 1.2.6
```

## Advanced Monitoring & Alerting

### Device Health Monitoring
```bash
# Add health check to your golioth_app
# Report system metrics to Golioth LightDB State

# Example health metrics:
# - CPU usage
# - Memory usage
# - Disk space
# - Update slot status
# - Last successful boot time
```

### Update Success Tracking
```bash
# Track update completion in device logs
echo "UPDATE_SUCCESS: $(date): Version $(cat /etc/version) boot successful" >> /var/log/messages

# Report to Golioth
golioth_client update_status --version=$(cat /etc/version) --status=success
```

### Failed Update Analysis
```bash
# Check for common failure patterns
grep -E "(swupdate|golioth|boot)" /var/log/messages | tail -100

# Analyze partition health
fw_printenv | grep -E "(boot_slot|retry|upgrade)"
fsck.ext4 -n /dev/vdb2  # Check active partition
fsck.ext4 -n /dev/vdb3  # Check inactive partition

# Check available space for downloads
df -h /tmp
du -sh /tmp/golioth_*
```

## Troubleshooting Complex Issues

### Update Stuck in DOWNLOADING
```bash
# Check network connectivity and DNS
ping -c 3 golioth.io
nslookup golioth.io

# Check available disk space
df -h /tmp
du -sh /tmp/*

# Restart Golioth daemon with debug logging
/etc/init.d/S99golioth_app stop
golioth_app --no-daemon --log-level=debug

# Check for firewall/proxy issues
curl -v https://golioth.io

# Clear partial downloads
rm -f /tmp/golioth_*
/etc/init.d/S99golioth_app restart
```

### swupdate Installation Failures
```bash
# Check swupdate daemon status
ps aux | grep swupdate
/etc/init.d/S80swupdate status

# Examine detailed swupdate logs
grep swupdate /var/log/messages | tail -50

# Test swupdate manually with verbose output
swupdate-client -v -i /path/to/firmware.swu

# Check partition write permissions
mount | grep vdb
ls -la /dev/vdb*

# Verify .swu package integrity
file firmware.swu
mkdir /tmp/swu-test && cd /tmp/swu-test
cpio -idv < firmware.swu
cat sw-description  # Verify manifest
```

### Boot Slot Confusion
```bash
# Current environment
fw_printenv | sort

# Expected vs actual boot slot
fw_printenv boot_slot
mount | grep "/dev/vdb"  # See which partition is actually mounted

# Reset to known state
fw_setenv boot_slot a
fw_setenv boot_slot_retry 3
fw_setenv upgrade_available 0
reboot

# U-Boot environment corruption recovery
# Boot to U-Boot prompt and recreate environment:
=> env default -f -a
=> setenv boot_slot a
=> setenv boot_slot_retry 3
=> saveenv
```

### Network Connectivity Issues
```bash
# Check physical network interface
ip link show
ip addr show

# Check DHCP lease
cat /var/lib/dhcp/dhclient.leases

# DNS resolution
cat /etc/resolv.conf
nslookup golioth.io
dig golioth.io

# Firewall rules (if any)
iptables -L -n

# Test connectivity step by step
ping -c 3 8.8.8.8        # Internet connectivity
ping -c 3 golioth.io     # DNS resolution
curl -v https://golioth.io # HTTPS connectivity
```

## Performance Optimization

### Build Time Optimization
```bash
# Use persistent cache volumes
docker run --rm \
  -v "$(pwd)/../../../..":/workspace \
  -v "$(pwd)/output":/output \
  -v persistent-ccache:/ccache \
  -v persistent-dl:/dl \
  golioth-buildroot

# Parallel builds (adjust based on your system)
export BR2_JLEVEL=$(nproc)

# Use RAM disk for temporary files (Linux)
sudo mount -t tmpfs -o size=2G tmpfs /tmp/buildroot-tmp
export BR2_DL_DIR=/tmp/buildroot-tmp/dl
```

### Update Download Optimization
```bash
# Configure Golioth client for optimal download
vi /etc/golioth_app.conf

# Add download optimization settings:
GOLIOTH_DOWNLOAD_BLOCK_SIZE=4096
GOLIOTH_DOWNLOAD_TIMEOUT=30
GOLIOTH_MAX_CONCURRENT_DOWNLOADS=1

# Monitor download performance
tail -f /var/log/messages | grep -E "(download|block)"
```

### A/B Partition Optimization
```bash
# Optimize filesystem creation for faster updates
# In post-image.sh, use optimized mkfs parameters:
mkfs.ext4 -F -O ^has_journal,^ext_attr /dev/loop0p2  # Disable journal for speed
mkfs.ext4 -F -O ^has_journal,^ext_attr /dev/loop0p3
```

## Security Considerations

### Secure Boot Chain
- U-Boot signature verification (requires secure boot setup)
- .swu package signing and verification
- TLS certificate pinning for Golioth connections

### Update Authentication
```bash
# Sign .swu packages (requires swupdate with crypto support)
./create-swu.sh -v 1.2.6 -a aarch64 --sign

# Verify signatures before installation
swupdate-client -v -k /etc/swupdate-public.pem -i firmware.swu
```

### Network Security
```bash
# Use certificate pinning
vi /etc/golioth_app.conf
# Add: GOLIOTH_TLS_CERT_PATH="/etc/golioth-cert.pem"

# Monitor for security events
grep -E "(auth|cert|tls|ssl)" /var/log/messages
```

This workflow ensures robust, monitored, and secure firmware updates with comprehensive troubleshooting capabilities.