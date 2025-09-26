/*
 * Copyright (c) 2024 Golioth, Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <fcntl.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>

#include <golioth/golioth_status.h>
#include <golioth/golioth_sys.h>
#include <golioth/log.h>

LOG_TAG_DEFINE(fw_update_swupdate);

// swupdate IPC socket path
#define SWUPDATE_SOCKET_PATH "/tmp/swupdate_ipc"

// Boot environment file for U-Boot
#define UBOOT_ENV_FILE "/etc/fw_env.config"

// Global state for the update
static struct {
    int socket_fd;
    bool update_in_progress;
    size_t total_size;
    size_t bytes_written;
    char *temp_file_path;
    FILE *temp_file;
} g_swupdate_ctx = {
    .socket_fd = -1,
    .update_in_progress = false,
    .total_size = 0,
    .bytes_written = 0,
    .temp_file_path = NULL,
    .temp_file = NULL
};

// Connect to swupdate IPC socket
static int swupdate_connect(void)
{
    struct sockaddr_un server_addr;
    int socket_fd;
    int ret;

    socket_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (socket_fd < 0)
    {
        GLTH_LOGE(TAG, "Failed to create socket: %s", strerror(errno));
        return -1;
    }

    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sun_family = AF_UNIX;
    strncpy(server_addr.sun_path, SWUPDATE_SOCKET_PATH, sizeof(server_addr.sun_path) - 1);

    ret = connect(socket_fd, (struct sockaddr *)&server_addr, sizeof(server_addr));
    if (ret < 0)
    {
        GLTH_LOGE(TAG, "Failed to connect to swupdate: %s", strerror(errno));
        close(socket_fd);
        return -1;
    }

    GLTH_LOGI(TAG, "Connected to swupdate IPC socket");
    return socket_fd;
}

// Create temporary file for firmware image
static int create_temp_file(void)
{
    char temp_template[] = "/tmp/golioth_fw_XXXXXX";
    int fd;

    fd = mkstemp(temp_template);
    if (fd < 0)
    {
        GLTH_LOGE(TAG, "Failed to create temporary file: %s", strerror(errno));
        return -1;
    }

    g_swupdate_ctx.temp_file_path = malloc(strlen(temp_template) + 1);
    if (!g_swupdate_ctx.temp_file_path)
    {
        GLTH_LOGE(TAG, "Failed to allocate memory for temp file path");
        close(fd);
        unlink(temp_template);
        return -1;
    }

    strcpy(g_swupdate_ctx.temp_file_path, temp_template);

    g_swupdate_ctx.temp_file = fdopen(fd, "wb");
    if (!g_swupdate_ctx.temp_file)
    {
        GLTH_LOGE(TAG, "Failed to open temp file stream: %s", strerror(errno));
        close(fd);
        free(g_swupdate_ctx.temp_file_path);
        g_swupdate_ctx.temp_file_path = NULL;
        unlink(temp_template);
        return -1;
    }

    GLTH_LOGI(TAG, "Created temporary file: %s", g_swupdate_ctx.temp_file_path);
    return 0;
}

// Cleanup temporary file
static void cleanup_temp_file(void)
{
    if (g_swupdate_ctx.temp_file)
    {
        fclose(g_swupdate_ctx.temp_file);
        g_swupdate_ctx.temp_file = NULL;
    }

    if (g_swupdate_ctx.temp_file_path)
    {
        unlink(g_swupdate_ctx.temp_file_path);
        free(g_swupdate_ctx.temp_file_path);
        g_swupdate_ctx.temp_file_path = NULL;
    }
}

// Send firmware image to swupdate
static int send_firmware_to_swupdate(const char *file_path)
{
    char command[512];
    int ret;

    // Use swupdate-client to send the firmware image
    snprintf(command, sizeof(command), "swupdate-client -v -i %s", file_path);

    GLTH_LOGI(TAG, "Sending firmware to swupdate: %s", command);
    ret = system(command);

    if (ret != 0)
    {
        GLTH_LOGE(TAG, "swupdate-client failed with code: %d", ret);
        return -1;
    }

    GLTH_LOGI(TAG, "Firmware successfully sent to swupdate");
    return 0;
}

// Switch boot slot using U-Boot environment
static int switch_boot_slot(void)
{
    char command[256];
    int ret;

    // Toggle boot slot in U-Boot environment
    // Assume we're using fw_setenv from u-boot-tools
    snprintf(command, sizeof(command), "fw_setenv boot_slot_retry 3");
    ret = system(command);
    if (ret != 0)
    {
        GLTH_LOGE(TAG, "Failed to set boot_slot_retry: %d", ret);
        return -1;
    }

    snprintf(command, sizeof(command), "fw_setenv boot_slot b");
    ret = system(command);
    if (ret != 0)
    {
        GLTH_LOGE(TAG, "Failed to set boot_slot: %d", ret);
        return -1;
    }

    GLTH_LOGI(TAG, "Boot slot switched to B (inactive -> active)");
    return 0;
}

//
// Golioth firmware update backend API implementation
//

bool fw_update_is_pending_verify(void)
{
    // Check if we're in a pending verify state after reboot
    // This would check U-Boot environment variables
    char *boot_status = getenv("BOOT_STATUS");
    return (boot_status && strcmp(boot_status, "pending") == 0);
}

void fw_update_rollback(void)
{
    GLTH_LOGI(TAG, "Rolling back firmware update");

    // Switch back to the previous slot
    int ret = system("fw_setenv boot_slot a");
    if (ret != 0)
    {
        GLTH_LOGE(TAG, "Failed to rollback boot slot");
    }
    else
    {
        GLTH_LOGI(TAG, "Rolled back to slot A");
    }
}

void fw_update_reboot(void)
{
    GLTH_LOGI(TAG, "Rebooting system for firmware update");
    golioth_sys_msleep(1000);  // Give time for logs to flush
    system("reboot");
}

void fw_update_cancel_rollback(void)
{
    GLTH_LOGI(TAG, "Canceling rollback - marking boot as successful");

    // Mark the current boot as successful
    int ret = system("fw_setenv boot_slot_retry 0");
    if (ret != 0)
    {
        GLTH_LOGE(TAG, "Failed to cancel rollback");
    }
    else
    {
        GLTH_LOGI(TAG, "Boot marked as successful");
    }
}

enum golioth_status fw_update_handle_block(const uint8_t *block,
                                          size_t block_size,
                                          size_t offset,
                                          size_t total_size)
{
    if (!g_swupdate_ctx.update_in_progress)
    {
        GLTH_LOGI(TAG, "Starting firmware update (total size: %zu bytes)", total_size);

        g_swupdate_ctx.total_size = total_size;
        g_swupdate_ctx.bytes_written = 0;
        g_swupdate_ctx.update_in_progress = true;

        // Create temporary file for the firmware image
        if (create_temp_file() != 0)
        {
            return GOLIOTH_ERR_IO;
        }
    }

    // Write block to temporary file
    size_t written = fwrite(block, 1, block_size, g_swupdate_ctx.temp_file);
    if (written != block_size)
    {
        GLTH_LOGE(TAG, "Failed to write block at offset %zu: %s", offset, strerror(errno));
        cleanup_temp_file();
        g_swupdate_ctx.update_in_progress = false;
        return GOLIOTH_ERR_IO;
    }

    g_swupdate_ctx.bytes_written += block_size;

    // Log progress periodically
    if ((g_swupdate_ctx.bytes_written % (64 * 1024)) == 0)
    {
        int progress = (g_swupdate_ctx.bytes_written * 100) / g_swupdate_ctx.total_size;
        GLTH_LOGI(TAG, "Firmware download progress: %d%% (%zu/%zu bytes)",
                  progress, g_swupdate_ctx.bytes_written, g_swupdate_ctx.total_size);
    }

    return GOLIOTH_OK;
}

enum golioth_status fw_update_post_download(void)
{
    GLTH_LOGI(TAG, "Firmware download complete, sending to swupdate");

    if (!g_swupdate_ctx.update_in_progress || !g_swupdate_ctx.temp_file)
    {
        GLTH_LOGE(TAG, "No update in progress or temp file missing");
        return GOLIOTH_ERR_INVALID_STATE;
    }

    // Close the temporary file to flush data
    fclose(g_swupdate_ctx.temp_file);
    g_swupdate_ctx.temp_file = NULL;

    // Send the firmware image to swupdate
    if (send_firmware_to_swupdate(g_swupdate_ctx.temp_file_path) != 0)
    {
        cleanup_temp_file();
        g_swupdate_ctx.update_in_progress = false;
        return GOLIOTH_ERR_IO;
    }

    // Clean up temporary file
    cleanup_temp_file();
    g_swupdate_ctx.update_in_progress = false;

    GLTH_LOGI(TAG, "Firmware successfully applied via swupdate");
    return GOLIOTH_OK;
}

enum golioth_status fw_update_check_candidate(const uint8_t *hash, size_t img_size)
{
    // For now, always proceed with the update
    // In a production system, this could check if the image is already installed
    GLTH_LOGI(TAG, "Checking candidate image (size: %zu bytes)", img_size);
    return GOLIOTH_OK;
}

enum golioth_status fw_update_change_boot_image(void)
{
    GLTH_LOGI(TAG, "Switching to new boot image");

    if (switch_boot_slot() != 0)
    {
        return GOLIOTH_ERR_IO;
    }

    return GOLIOTH_OK;
}

void fw_update_end(void)
{
    GLTH_LOGI(TAG, "Firmware update process ended");

    // Clean up any remaining state
    cleanup_temp_file();
    g_swupdate_ctx.update_in_progress = false;

    if (g_swupdate_ctx.socket_fd >= 0)
    {
        close(g_swupdate_ctx.socket_fd);
        g_swupdate_ctx.socket_fd = -1;
    }
}