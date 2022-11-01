#include "golioth_fw_update.h"

// TODO - add implementation
//
// One idea is to do a "lightweight" OTA, where there is a loader process
// that dynamically loads the app as a .so.

bool fw_update_is_pending_verify(void) {
    return false;
}

void fw_update_rollback(void) {}

void fw_update_reboot(void) {}

void fw_update_cancel_rollback(void) {}

golioth_status_t fw_update_handle_block(
        const uint8_t* block,
        size_t block_size,
        size_t offset,
        size_t total_size) {
    return GOLIOTH_OK;
}

void fw_update_post_download(void) {}

golioth_status_t fw_update_validate(void) {
    return GOLIOTH_OK;
}

golioth_status_t fw_update_change_boot_image(void) {
    return GOLIOTH_OK;
}

void fw_update_end(void) {}