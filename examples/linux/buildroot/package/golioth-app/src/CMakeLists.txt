cmake_minimum_required(VERSION 3.5)
set(projname "golioth_app")
project(${projname} C)

set(CMAKE_BUILD_TYPE Release)

# Include the user config file
get_filename_component(user_config_file "golioth_user_config.h" ABSOLUTE)
add_definitions(-DCONFIG_GOLIOTH_USER_CONFIG_INCLUDE="${user_config_file}")

# Source files for the application
set(srcs
    main.c
    golioth_app.c
)

# Create the executable
add_executable(${projname} ${srcs})

# Include directories
target_include_directories(${projname} PRIVATE .)

# Link with the installed golioth_sdk library and dependencies
target_link_libraries(${projname} golioth_sdk mbedtls mbedx509 mbedcrypto coap-3)

# Install the binary to /usr/bin
install(TARGETS ${projname} DESTINATION bin)