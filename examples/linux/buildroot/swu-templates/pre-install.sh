#!/bin/sh
#
# Pre-install script for Golioth swupdate integration
# This script runs before the update installation begins
#

echo "Golioth swupdate pre-install: Preparing for firmware update"

# Check available disk space
REQUIRED_SPACE=60000000  # 60MB for rootfs
AVAILABLE_SPACE=$(df /tmp | tail -1 | awk '{print $4}')
AVAILABLE_BYTES=$((AVAILABLE_SPACE * 1024))

if [ $AVAILABLE_BYTES -lt $REQUIRED_SPACE ]; then
    echo "Error: Insufficient disk space. Need $REQUIRED_SPACE bytes, have $AVAILABLE_BYTES"
    exit 1
fi

# Determine inactive slot for A/B update
CURRENT_SLOT=$(fw_printenv -n boot_slot 2>/dev/null || echo "a")
if [ "$CURRENT_SLOT" = "a" ]; then
    INACTIVE_SLOT="b"
    INACTIVE_DEV="/dev/vdb3"
else
    INACTIVE_SLOT="a"
    INACTIVE_DEV="/dev/vdb2"
fi

echo "Current slot: $CURRENT_SLOT"
echo "Installing to inactive slot: $INACTIVE_SLOT ($INACTIVE_DEV)"

# Verify target device exists
if [ ! -e "$INACTIVE_DEV" ]; then
    echo "Error: Target device $INACTIVE_DEV not found"
    exit 1
fi

# Create marker for update in progress
echo "$(date): Starting update to slot $INACTIVE_SLOT" > /tmp/golioth_update_progress

# Stop non-essential services to reduce filesystem activity
echo "Stopping non-essential services..."
# Add any service stops here if needed

echo "Pre-install checks completed successfully"
exit 0