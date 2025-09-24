/*
 * Copyright (c) 2024 Golioth, Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#include <string.h>
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <signal.h>
#include <syslog.h>
#include <errno.h>

#include <golioth/client.h>
#include "golioth_app.h"

#define TAG "main"
#define PID_FILE "/var/run/golioth_app.pid"
#define CONFIG_FILE "/etc/golioth_app.conf"

static volatile sig_atomic_t keep_running = 1;

static void signal_handler(int sig)
{
    keep_running = 0;
    syslog(LOG_INFO, "Received signal %d, shutting down gracefully", sig);
    golioth_app_shutdown();
}

static int daemonize(void)
{
    pid_t pid, sid;

    // Fork off the parent process
    pid = fork();
    if (pid < 0) {
        return -1;
    }

    // Exit parent process
    if (pid > 0) {
        exit(EXIT_SUCCESS);
    }

    // Change the file mode mask
    umask(0);

    // Open syslog
    openlog("golioth_app", LOG_PID | LOG_CONS, LOG_DAEMON);

    // Create a new SID for the child process
    sid = setsid();
    if (sid < 0) {
        syslog(LOG_ERR, "Failed to create new session: %s", strerror(errno));
        return -1;
    }

    // Change the current working directory
    if ((chdir("/")) < 0) {
        syslog(LOG_ERR, "Failed to change directory: %s", strerror(errno));
        return -1;
    }

    // Close out the standard file descriptors
    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    close(STDERR_FILENO);

    return 0;
}

static int write_pid_file(void)
{
    FILE *pid_file = fopen(PID_FILE, "w");
    if (!pid_file) {
        syslog(LOG_ERR, "Failed to open PID file %s: %s", PID_FILE, strerror(errno));
        return -1;
    }

    fprintf(pid_file, "%d\n", getpid());
    fclose(pid_file);

    return 0;
}

static void remove_pid_file(void)
{
    unlink(PID_FILE);
}

static int load_config(char **psk_id, char **psk)
{
    FILE *config_file = fopen(CONFIG_FILE, "r");
    char line[512];

    *psk_id = NULL;
    *psk = NULL;

    if (!config_file) {
        syslog(LOG_WARNING, "Config file %s not found, using environment variables", CONFIG_FILE);
        return 0;  // Not an error, will fall back to env vars
    }

    while (fgets(line, sizeof(line), config_file)) {
        // Skip comments and empty lines
        if (line[0] == '#' || line[0] == '\n' || line[0] == '\r') {
            continue;
        }

        // Remove trailing newline
        char *newline = strchr(line, '\n');
        if (newline) *newline = '\0';

        // Parse key=value pairs
        char *equals = strchr(line, '=');
        if (!equals) continue;

        *equals = '\0';
        char *key = line;
        char *value = equals + 1;

        // Remove quotes from value if present
        if (value[0] == '"' && value[strlen(value) - 1] == '"') {
            value[strlen(value) - 1] = '\0';
            value++;
        }

        if (strcmp(key, "GOLIOTH_SAMPLE_PSK_ID") == 0) {
            *psk_id = strdup(value);
        } else if (strcmp(key, "GOLIOTH_SAMPLE_PSK") == 0) {
            *psk = strdup(value);
        }
    }

    fclose(config_file);

    syslog(LOG_INFO, "Loaded configuration from %s", CONFIG_FILE);
    return 0;
}

int main(int argc, char *argv[])
{
    int daemon_mode = 1;

    // Check for --no-daemon flag for debugging
    if (argc > 1 && strcmp(argv[1], "--no-daemon") == 0) {
        daemon_mode = 0;
    }

    if (daemon_mode) {
        if (daemonize() < 0) {
            fprintf(stderr, "Failed to daemonize\n");
            return 1;
        }

        if (write_pid_file() < 0) {
            return 1;
        }
    } else {
        // For debugging mode, still open syslog but keep console output
        openlog("golioth_app", LOG_PID | LOG_CONS | LOG_PERROR, LOG_DAEMON);
    }

    // Set up signal handlers
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    signal(SIGHUP, signal_handler);

    syslog(LOG_INFO, "Golioth application starting");

    // Load configuration from file first, then fall back to environment
    char *config_psk_id = NULL;
    char *config_psk = NULL;
    load_config(&config_psk_id, &config_psk);

    // Use config file values if available, otherwise environment variables
    char *golioth_psk_id = config_psk_id ? config_psk_id : getenv("GOLIOTH_SAMPLE_PSK_ID");
    char *golioth_psk = config_psk ? config_psk : getenv("GOLIOTH_SAMPLE_PSK");

    if ((!golioth_psk_id) || strlen(golioth_psk_id) <= 0)
    {
        syslog(LOG_ERR, "PSK ID is not specified in config file or environment");
        if (daemon_mode) remove_pid_file();
        if (config_psk_id) free(config_psk_id);
        if (config_psk) free(config_psk);
        return 1;
    }
    if ((!golioth_psk) || strlen(golioth_psk) <= 0)
    {
        syslog(LOG_ERR, "PSK is not specified in config file or environment");
        if (daemon_mode) remove_pid_file();
        if (config_psk_id) free(config_psk_id);
        if (config_psk) free(config_psk);
        return 1;
    }

    struct golioth_client_config config = {
        .credentials =
            {
                .auth_type = GOLIOTH_TLS_AUTH_TYPE_PSK,
                .psk =
                    {
                        .psk_id = golioth_psk_id,
                        .psk_id_len = strlen(golioth_psk_id),
                        .psk = golioth_psk,
                        .psk_len = strlen(golioth_psk),
                    },
            },
    };

    struct golioth_client *client = golioth_client_create(&config);
    if (!client) {
        syslog(LOG_ERR, "Failed to create Golioth client");
        if (daemon_mode) remove_pid_file();
        return 1;
    }

    syslog(LOG_INFO, "Golioth client created successfully");

    int result = golioth_app_main(client);

    syslog(LOG_INFO, "Golioth application shutting down");
    golioth_client_destroy(client);

    // Clean up allocated memory
    if (config_psk_id) free(config_psk_id);
    if (config_psk) free(config_psk);

    if (daemon_mode) {
        remove_pid_file();
    }

    closelog();
    return result;
}
