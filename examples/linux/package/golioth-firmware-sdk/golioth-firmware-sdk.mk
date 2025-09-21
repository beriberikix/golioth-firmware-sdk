################################################################################
#
# golioth-firmware-sdk
#
################################################################################

GOLIOTH_FIRMWARE_SDK_VERSION = local
GOLIOTH_FIRMWARE_SDK_SITE = $(BR2_EXTERNAL_GOLIOTH_BUILDROOT_PATH)/../../../..
GOLIOTH_FIRMWARE_SDK_SITE_METHOD = local
GOLIOTH_FIRMWARE_SDK_DEPENDENCIES = openssl zlib
GOLIOTH_FIRMWARE_SDK_INSTALL_STAGING = YES
GOLIOTH_FIRMWARE_SDK_INSTALL_TARGET = NO

# Disable documentation and examples to avoid cmake warnings
GOLIOTH_FIRMWARE_SDK_CONF_OPTS = \
	-DENABLE_DOCS=OFF \
	-DENABLE_EXAMPLES=OFF \
	-DENABLE_SERVER_MODE=OFF \
	-DENABLE_TCP=OFF \
	-DWITH_EPOLL=OFF

# Create a CMakeLists.txt that builds just the SDK library
define GOLIOTH_FIRMWARE_SDK_CREATE_CMAKE
	echo 'cmake_minimum_required(VERSION 3.5)' > $(@D)/CMakeLists.txt
	echo 'project(golioth-firmware-sdk C)' >> $(@D)/CMakeLists.txt
	echo '' >> $(@D)/CMakeLists.txt
	echo '# Default to building shared library for buildroot' >> $(@D)/CMakeLists.txt
	echo 'if(NOT DEFINED BUILD_SHARED_LIBS)' >> $(@D)/CMakeLists.txt
	echo '    set(BUILD_SHARED_LIBS ON)' >> $(@D)/CMakeLists.txt
	echo 'endif()' >> $(@D)/CMakeLists.txt
	echo '' >> $(@D)/CMakeLists.txt
	echo '# Options that can be controlled by buildroot' >> $(@D)/CMakeLists.txt
	echo 'option(ENABLE_DOCS "Enable documentation" OFF)' >> $(@D)/CMakeLists.txt
	echo 'option(ENABLE_EXAMPLES "Enable examples" OFF)' >> $(@D)/CMakeLists.txt
	echo 'option(ENABLE_SERVER_MODE "Enable server mode" OFF)' >> $(@D)/CMakeLists.txt
	echo 'option(ENABLE_TCP "Enable TCP" OFF)' >> $(@D)/CMakeLists.txt
	echo 'option(WITH_EPOLL "Use epoll" OFF)' >> $(@D)/CMakeLists.txt
	echo '' >> $(@D)/CMakeLists.txt
	echo '# Only build the SDK library, not examples' >> $(@D)/CMakeLists.txt
	echo 'add_subdirectory(port/linux/golioth_sdk)' >> $(@D)/CMakeLists.txt
	echo '' >> $(@D)/CMakeLists.txt
	echo '# Installation rules for buildroot' >> $(@D)/CMakeLists.txt
	echo 'install(TARGETS golioth_sdk' >> $(@D)/CMakeLists.txt
	echo '    LIBRARY DESTINATION lib' >> $(@D)/CMakeLists.txt
	echo '    ARCHIVE DESTINATION lib' >> $(@D)/CMakeLists.txt
	echo '    RUNTIME DESTINATION bin' >> $(@D)/CMakeLists.txt
	echo ')' >> $(@D)/CMakeLists.txt
	echo '' >> $(@D)/CMakeLists.txt
	echo '# Install headers' >> $(@D)/CMakeLists.txt
	echo 'install(DIRECTORY include/' >> $(@D)/CMakeLists.txt
	echo '    DESTINATION include' >> $(@D)/CMakeLists.txt
	echo '    FILES_MATCHING PATTERN "*.h"' >> $(@D)/CMakeLists.txt
	echo ')' >> $(@D)/CMakeLists.txt
	echo '' >> $(@D)/CMakeLists.txt
	echo '# Install platform-specific headers' >> $(@D)/CMakeLists.txt
	echo 'install(FILES port/linux/golioth_port_config.h' >> $(@D)/CMakeLists.txt
	echo '    DESTINATION include' >> $(@D)/CMakeLists.txt
	echo ')' >> $(@D)/CMakeLists.txt
endef

GOLIOTH_FIRMWARE_SDK_PRE_CONFIGURE_HOOKS += GOLIOTH_FIRMWARE_SDK_CREATE_CMAKE

$(eval $(cmake-package))