/*
 * Copyright (c) 2024 Golioth, Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#include <golioth/client.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Main application function that demonstrates Golioth functionality
 *
 * This function contains the core logic of the Golioth application,
 * including lightdb operations, settings, RPC, and firmware updates.
 *
 * @param client Initialized Golioth client instance
 * @return int 0 on success, non-zero on error
 */
int golioth_app_main(struct golioth_client *client);

/**
 * @brief Set shutdown flag for graceful termination
 *
 * This function sets a flag that causes golioth_app_main to exit
 * gracefully from its main loop.
 */
void golioth_app_shutdown(void);

#ifdef __cplusplus
}
#endif