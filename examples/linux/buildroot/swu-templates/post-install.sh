#!/bin/sh
#
# Post-install script for Golioth swupdate integration
# This script runs after the update installation completes
#

echo "Golioth swupdate post-install: Finalizing firmware update"

# Determine which slot was updated
CURRENT_SLOT=$(fw_printenv -n boot_slot 2>/dev/null || echo "a")
if [ "$CURRENT_SLOT" = "a" ]; then
    NEW_SLOT="b"
    NEW_DEV="/dev/vdb3"
else
    NEW_SLOT="a"
    NEW_DEV="/dev/vdb2"
fi

echo "Updated slot: $NEW_SLOT ($NEW_DEV)"

# Verify the newly installed rootfs
echo "Verifying installed rootfs..."
if [ ! -e "$NEW_DEV" ]; then
    echo "Error: Updated device $NEW_DEV not found"
    exit 1
fi

# Basic filesystem check
fsck.ext4 -n "$NEW_DEV" > /tmp/fsck.log 2>&1
FSCK_RESULT=$?
if [ $FSCK_RESULT -ne 0 ] && [ $FSCK_RESULT -ne 1 ]; then
    echo "Error: Filesystem check failed on $NEW_DEV"
    cat /tmp/fsck.log
    exit 1
fi

echo "Filesystem verification passed"

# Switch boot slot in U-Boot environment
echo "Switching boot slot to: $NEW_SLOT"
fw_setenv boot_slot "$NEW_SLOT"
fw_setenv boot_slot_retry 3

# Mark update as completed but pending verification
fw_setenv upgrade_available 1
fw_setenv pending_verification 1

# Create completion marker
echo "$(date): Update completed, slot switched to $NEW_SLOT" >> /tmp/golioth_update_progress
echo "reboot_required" > /tmp/golioth_update_status

# Sync filesystems
sync

echo "Post-install completed successfully"
echo "System will reboot into new firmware on next restart"

# Optional: Trigger immediate reboot (uncomment if desired)
# echo "Rebooting to activate new firmware..."
# reboot

exit 0