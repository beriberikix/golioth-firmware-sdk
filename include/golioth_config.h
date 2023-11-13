#pragma once

// This file defines default configuration values.
//
// These can be overridden from golioth_user_config.h or
// golioth_port_config.h, with user config taking priority
// over port config.

#ifdef CONFIG_GOLIOTH_USER_CONFIG_INCLUDE
#include CONFIG_GOLIOTH_USER_CONFIG_INCLUDE
#endif

#include "golioth_port_config.h"

#ifndef CONFIG_GOLIOTH_COAP_HOST_URI
#define CONFIG_GOLIOTH_COAP_HOST_URI "coaps://coap.golioth.io"
#endif

#ifndef CONFIG_GOLIOTH_COAP_RESPONSE_TIMEOUT_S
#define CONFIG_GOLIOTH_COAP_RESPONSE_TIMEOUT_S 10
#endif

#ifndef CONFIG_GOLIOTH_COAP_REQUEST_QUEUE_TIMEOUT_MS
#define CONFIG_GOLIOTH_COAP_REQUEST_QUEUE_TIMEOUT_MS 1000
#endif

#ifndef CONFIG_GOLIOTH_COAP_REQUEST_QUEUE_MAX_ITEMS
#define CONFIG_GOLIOTH_COAP_REQUEST_QUEUE_MAX_ITEMS 10
#endif

#ifndef CONFIG_GOLIOTH_COAP_THREAD_PRIORITY
#define CONFIG_GOLIOTH_COAP_THREAD_PRIORITY 5
#endif

#ifndef CONFIG_GOLIOTH_COAP_THREAD_STACK_SIZE
#define CONFIG_GOLIOTH_COAP_THREAD_STACK_SIZE 6144
#endif

#ifndef CONFIG_GOLIOTH_COAP_KEEPALIVE_INTERVAL_S
#define CONFIG_GOLIOTH_COAP_KEEPALIVE_INTERVAL_S 9
#endif

#ifndef CONFIG_GOLIOTH_MAX_NUM_OBSERVATIONS
#define CONFIG_GOLIOTH_MAX_NUM_OBSERVATIONS 8
#endif

#ifndef CONFIG_GOLIOTH_OTA_THREAD_STACK_SIZE
#define CONFIG_GOLIOTH_OTA_THREAD_STACK_SIZE 4096
#endif

#ifndef CONFIG_GOLIOTH_OTA_MAX_PACKAGE_NAME_LEN
#define CONFIG_GOLIOTH_OTA_MAX_PACKAGE_NAME_LEN 64
#endif

#ifndef CONFIG_GOLIOTH_OTA_MAX_VERSION_LEN
#define CONFIG_GOLIOTH_OTA_MAX_VERSION_LEN 64
#endif

#ifndef CONFIG_GOLIOTH_OTA_MAX_NUM_COMPONENTS
#define CONFIG_GOLIOTH_OTA_MAX_NUM_COMPONENTS 4
#endif

#ifndef CONFIG_GOLIOTH_OTA_DECOMPRESS_METHOD_ZLIB
#define CONFIG_GOLIOTH_OTA_DECOMPRESS_METHOD_ZLIB 0
#endif

#ifndef CONFIG_GOLIOTH_OTA_DECOMPRESS_METHOD_HEATSHRINK
#define CONFIG_GOLIOTH_OTA_DECOMPRESS_METHOD_HEATSHRINK 0
#endif

#ifndef CONFIG_GOLIOTH_OTA_PATCH
#define CONFIG_GOLIOTH_OTA_PATCH 0
#endif

#ifndef CONFIG_GOLIOTH_COAP_MAX_PATH_LEN
#define CONFIG_GOLIOTH_COAP_MAX_PATH_LEN 39
#endif

#ifndef CONFIG_GOLIOTH_RPC_ENABLE
#define CONFIG_GOLIOTH_RPC_ENABLE 1
#endif

#ifndef CONFIG_GOLIOTH_SETTINGS_ENABLE
#define CONFIG_GOLIOTH_SETTINGS_ENABLE 1
#endif

#ifndef CONFIG_GOLIOTH_MAX_NUM_SETTINGS
#define CONFIG_GOLIOTH_MAX_NUM_SETTINGS 16
#endif

#ifndef CONFIG_GOLIOTH_RPC_MAX_NUM_METHODS
#define CONFIG_GOLIOTH_RPC_MAX_NUM_METHODS 8
#endif

#ifndef CONFIG_GOLIOTH_ALLOCATION_TRACKING
#define CONFIG_GOLIOTH_ALLOCATION_TRACKING 0
#endif

#ifndef CONFIG_GOLIOTH_DEBUG_LOG_ENABLE
#define CONFIG_GOLIOTH_DEBUG_LOG_ENABLE 1
#endif

#ifndef CONFIG_GOLIOTH_AUTO_LOG_TO_CLOUD
#define CONFIG_GOLIOTH_AUTO_LOG_TO_CLOUD 0
#endif

#ifndef CONFIG_GOLIOTH_REMOTE_SHELL_ENABLE
#define CONFIG_GOLIOTH_REMOTE_SHELL_ENABLE 0
#endif

#ifndef CONFIG_GOLIOTH_REMOTE_SHELL_THREAD_STACK_SIZE
#define CONFIG_GOLIOTH_REMOTE_SHELL_THREAD_STACK_SIZE 4096
#endif

#ifndef CONFIG_GOLIOTH_REMOTE_SHELL_BUF_SIZE
#define CONFIG_GOLIOTH_REMOTE_SHELL_BUF_SIZE 8192
#endif

#ifndef CONFIG_GOLIOTH_REMOTE_SHELL_THREAD_DELAY_MS
#define CONFIG_GOLIOTH_REMOTE_SHELL_THREAD_DELAY_MS 500
#endif

#ifndef CONFIG_GOLIOTH_DEBUG_DEFAULT_LOG_LEVEL
#define CONFIG_GOLIOTH_DEBUG_DEFAULT_LOG_LEVEL GOLIOTH_DEBUG_LOG_LEVEL_INFO
#endif

#ifndef GOLIOTH_OVERRIDE_LIBCOAP_LOG_HANDLER
#define GOLIOTH_OVERRIDE_LIBCOAP_LOG_HANDLER 1
#endif