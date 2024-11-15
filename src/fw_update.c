/*
 * Copyright (c) 2022 Golioth, Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

// TODO - fw_update_destroy, to clean up resources and stop thread

#include <inttypes.h>
#include <assert.h>
#include <string.h>
#include <golioth/golioth_sys.h>
#include <golioth/fw_update.h>
#include "golioth/ota.h"

#if defined(CONFIG_GOLIOTH_FW_UPDATE)

LOG_TAG_DEFINE(golioth_fw_update);

static struct golioth_client *_client;
static golioth_sys_sem_t _manifest_rcvd;
static struct golioth_ota_manifest _ota_manifest;
static const struct golioth_ota_component *_main_component;
static golioth_fw_update_state_change_callback _state_callback;
static void *_state_callback_arg;
static struct golioth_fw_update_config _config;

static enum golioth_status fw_write_block_cb(const struct golioth_ota_component *component,
                                             uint32_t block_idx,
                                             uint8_t *block_buffer,
                                             size_t block_buffer_len,
                                             bool is_last,
                                             size_t negotiated_block_size,
                                             void *arg)
{
    assert(arg);
    size_t *bytes_downloaded = (size_t *) arg;

    GLTH_LOGI(TAG,
              "Received block %" PRIu32 "/%zu",
              block_idx,
              (size_t) (component->size / negotiated_block_size));

    enum golioth_status status = fw_update_handle_block(block_buffer,
                                                        block_buffer_len,
                                                        negotiated_block_size * block_idx,
                                                        component->size);

    *bytes_downloaded += block_buffer_len;

    if (is_last)
    {
        fw_update_post_download();
    }

    return status;
}

static enum golioth_status golioth_fw_update_report_state_sync(struct golioth_client *client,
                                                               enum golioth_ota_state state,
                                                               enum golioth_ota_reason reason,
                                                               const char *package,
                                                               const char *current_version,
                                                               const char *target_version,
                                                               int32_t timeout_s)
{
    if (_state_callback)
    {
        _state_callback(state, reason, _state_callback_arg);
    }

    return golioth_ota_report_state_sync(client,
                                         state,
                                         reason,
                                         package,
                                         current_version,
                                         target_version,
                                         timeout_s);
}

static void on_ota_manifest(struct golioth_client *client,
                            const struct golioth_response *response,
                            const char *path,
                            const uint8_t *payload,
                            size_t payload_size,
                            void *arg)
{
    if (response->status != GOLIOTH_OK)
    {
        GLTH_LOGE(TAG, "Error in OTA manifest observation: %d", response->status);
        return;
    }

    GLTH_LOGD(TAG, "Received OTA manifest: %.*s", (int) payload_size, payload);

    enum golioth_ota_state state = golioth_ota_get_state();
    if (state == GOLIOTH_OTA_STATE_DOWNLOADING)
    {
        GLTH_LOGW(TAG, "Ignoring manifest while download in progress");
        return;
    }

    enum golioth_status status =
        golioth_ota_payload_as_manifest(payload, payload_size, &_ota_manifest);
    if (status != GOLIOTH_OK)
    {
        GLTH_LOGE(TAG, "Failed to parse manifest: %s", golioth_status_to_str(status));
        return;
    }
    golioth_sys_sem_give(_manifest_rcvd);
}

static bool manifest_version_is_different(const struct golioth_ota_manifest *manifest)
{
    _main_component = golioth_ota_find_component(manifest, _config.fw_package_name);
    if (_main_component)
    {
        if (0 != strcmp(_config.current_version, _main_component->version))
        {
            GLTH_LOGI(TAG,
                      "Current version = %s, Target version = %s",
                      _config.current_version,
                      _main_component->version);
            return true;
        }
    }
    return false;
}

static void fw_report_and_observe(void)
{
    enum golioth_status status;

    status = golioth_fw_update_report_state_sync(_client,
                                                 GOLIOTH_OTA_STATE_IDLE,
                                                 GOLIOTH_OTA_REASON_READY,
                                                 _config.fw_package_name,
                                                 _config.current_version,
                                                 NULL,
                                                 GOLIOTH_SYS_WAIT_FOREVER);

    if (status != GOLIOTH_OK)
    {
        GLTH_LOGE(TAG, "Failed to report firmware state: %d", status);
    }

    status = GOLIOTH_ERR_NULL;
    uint32_t retry_delay_s = 5;

    while (status != GOLIOTH_OK)
    {
        status = golioth_ota_observe_manifest_async(_client, on_ota_manifest, NULL);

        if (status == GOLIOTH_OK)
        {
            break;
        }

        GLTH_LOGW(TAG,
                  "Failed to observe manifest, retry in %" PRIu32 "s: %d",
                  retry_delay_s,
                  status);

        golioth_sys_msleep(retry_delay_s * 1000);

        retry_delay_s = retry_delay_s * 2;

        if (retry_delay_s > CONFIG_GOLIOTH_FW_UPDATE_OBSERVATION_RETRY_MAX_DELAY_S)
        {
            retry_delay_s = CONFIG_GOLIOTH_FW_UPDATE_OBSERVATION_RETRY_MAX_DELAY_S;
        }
    }
}

static void fw_update_thread(void *arg)
{
    // If it's the first time booting a new OTA image,
    // wait for successful connection to Golioth.
    //
    // If we don't connect after 60 seconds, roll back to the old image.
    if (fw_update_is_pending_verify())
    {
        GLTH_LOGI(TAG, "Waiting for golioth client to connect before cancelling rollback");
        int seconds_elapsed = 0;
        while (seconds_elapsed < 60)
        {
            if (golioth_client_is_connected(_client))
            {
                break;
            }
            golioth_sys_msleep(1000);
            seconds_elapsed++;
        }

        if (seconds_elapsed == 60)
        {
            // We didn't connect to Golioth cloud, so something might be wrong with
            // this firmware. Roll back and reboot.
            GLTH_LOGW(TAG, "Failed to connect to Golioth");
            GLTH_LOGW(TAG, "!!!");
            GLTH_LOGW(TAG, "!!! Rolling back and rebooting now!");
            GLTH_LOGW(TAG, "!!!");
            fw_update_rollback();
            fw_update_reboot();
        }
        else
        {
            GLTH_LOGI(TAG, "Firmware updated successfully!");
            fw_update_cancel_rollback();

            GLTH_LOGI(TAG, "State = Idle");
            golioth_fw_update_report_state_sync(_client,
                                                GOLIOTH_OTA_STATE_UPDATING,
                                                GOLIOTH_OTA_REASON_FIRMWARE_UPDATED_SUCCESSFULLY,
                                                _config.fw_package_name,
                                                _config.current_version,
                                                NULL,
                                                GOLIOTH_SYS_WAIT_FOREVER);
        }
    }

    fw_report_and_observe();

    while (1)
    {
        GLTH_LOGI(TAG, "Waiting to receive OTA manifest");
        golioth_sys_sem_take(_manifest_rcvd, GOLIOTH_SYS_WAIT_FOREVER);
        GLTH_LOGI(TAG, "Received OTA manifest");
        if (!manifest_version_is_different(&_ota_manifest))
        {
            GLTH_LOGI(TAG, "Manifest does not contain different firmware version. Nothing to do.");
            continue;
        }

        GLTH_LOGI(TAG, "State = Downloading");
        golioth_fw_update_report_state_sync(_client,
                                            GOLIOTH_OTA_STATE_DOWNLOADING,
                                            GOLIOTH_OTA_REASON_READY,
                                            _config.fw_package_name,
                                            _config.current_version,
                                            _main_component->version,
                                            GOLIOTH_SYS_WAIT_FOREVER);

        uint64_t start_time_ms = golioth_sys_now_ms();
        size_t bytes_downloaded = 0;

        int err = golioth_ota_download_component(_client,
                                                 _main_component,
                                                 NULL,
                                                 fw_write_block_cb,
                                                 (void *) &bytes_downloaded);
        if (err != GOLIOTH_OK)
        {
            GLTH_LOGE(TAG, "Firmware download failed");
            fw_update_end();

            GLTH_LOGI(TAG, "State = Idle");
            golioth_fw_update_report_state_sync(_client,
                                                GOLIOTH_OTA_STATE_IDLE,
                                                GOLIOTH_OTA_REASON_FIRMWARE_UPDATE_FAILED,
                                                _config.fw_package_name,
                                                _config.current_version,
                                                _main_component->version,
                                                GOLIOTH_SYS_WAIT_FOREVER);

            continue;
        }
        GLTH_LOGI(TAG,
                  "Successfully downloaded %zu bytes in %" PRIu64 " ms",
                  bytes_downloaded,
                  golioth_sys_now_ms() - start_time_ms);

        if (fw_update_validate() != GOLIOTH_OK)
        {
            GLTH_LOGE(TAG, "Firmware validate failed");
            fw_update_end();

            GLTH_LOGI(TAG, "State = Idle");
            golioth_fw_update_report_state_sync(_client,
                                                GOLIOTH_OTA_STATE_IDLE,
                                                GOLIOTH_OTA_REASON_INTEGRITY_CHECK_FAILURE,
                                                _config.fw_package_name,
                                                _config.current_version,
                                                _main_component->version,
                                                GOLIOTH_SYS_WAIT_FOREVER);

            continue;
        }

        GLTH_LOGI(TAG, "State = Downloaded");
        golioth_fw_update_report_state_sync(_client,
                                            GOLIOTH_OTA_STATE_DOWNLOADED,
                                            GOLIOTH_OTA_REASON_READY,
                                            _config.fw_package_name,
                                            _config.current_version,
                                            _main_component->version,
                                            GOLIOTH_SYS_WAIT_FOREVER);

        GLTH_LOGI(TAG, "State = Updating");
        golioth_fw_update_report_state_sync(_client,
                                            GOLIOTH_OTA_STATE_UPDATING,
                                            GOLIOTH_OTA_REASON_READY,
                                            _config.fw_package_name,
                                            _config.current_version,
                                            _main_component->version,
                                            GOLIOTH_SYS_WAIT_FOREVER);

        if (fw_update_change_boot_image() != GOLIOTH_OK)
        {
            GLTH_LOGE(TAG, "Firmware change boot image failed");
            fw_update_end();
            continue;
        }

        int countdown = 5;
        while (countdown > 0)
        {
            GLTH_LOGI(TAG, "Rebooting into new image in %d seconds", countdown);
            golioth_sys_msleep(1000);
            countdown--;
        }
        fw_update_reboot();
    }
}

void golioth_fw_update_init(struct golioth_client *client, const char *current_version)
{
    struct golioth_fw_update_config config = {
        .current_version = current_version,
        .fw_package_name = GOLIOTH_FW_UPDATE_DEFAULT_PACKAGE_NAME,
    };
    golioth_fw_update_init_with_config(client, &config);
}

void golioth_fw_update_init_with_config(struct golioth_client *client,
                                        const struct golioth_fw_update_config *config)
{
    static bool initialized = false;

    _client = client;
    _config = *config;
    _manifest_rcvd = golioth_sys_sem_create(1, 0);  // never destroyed

    GLTH_LOGI(TAG,
              "Current firmware version: %s - %s",
              _config.fw_package_name,
              _config.current_version);

    if (!initialized)
    {
        struct golioth_thread_config thread_cfg = {
            .name = "fw_update",
            .fn = fw_update_thread,
            .user_arg = NULL,
            .stack_size = CONFIG_GOLIOTH_FW_UPDATE_THREAD_STACK_SIZE,
            .prio = 3,
        };

        golioth_sys_thread_t thread = golioth_sys_thread_create(&thread_cfg);
        if (!thread)
        {
            GLTH_LOGE(TAG, "Failed to create firmware update thread");
        }
        else
        {
            initialized = true;
        }
    }
}

void golioth_fw_update_register_state_change_callback(
    golioth_fw_update_state_change_callback callback,
    void *user_arg)
{
    _state_callback = callback;
    _state_callback_arg = user_arg;
}

#endif  // CONFIG_GOLIOTH_FW_UPDATE
