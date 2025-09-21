#!/bin/bash

set -u
set -e

# Arguments:
# $1: the filesystem staging directory
# $2: the images directory
TARGET_DIR="$1"

# Create a simple startup script to set environment variables
cat << EOF > "${TARGET_DIR}/etc/profile.d/golioth.sh"
#!/bin/sh
# Golioth environment variables
# Set these to your actual Golioth device credentials
# export GOLIOTH_SAMPLE_PSK_ID="your-device-psk-id"
# export GOLIOTH_SAMPLE_PSK="your-device-psk"
echo "Golioth environment variables not set. Please export:"
echo "  GOLIOTH_SAMPLE_PSK_ID=your-device-psk-id"
echo "  GOLIOTH_SAMPLE_PSK=your-device-psk"
echo "Then run: golioth_basics"
echo ""
echo "Running on ARM64 architecture"
EOF

chmod +x "${TARGET_DIR}/etc/profile.d/golioth.sh"

# Ensure resolv.conf is not overwritten by DHCP
if [ -f "${TARGET_DIR}/etc/dhcp/dhclient.conf" ]; then
    echo "supersede domain-name-servers 8.8.8.8, 8.8.4.4;" >> "${TARGET_DIR}/etc/dhcp/dhclient.conf"
fi