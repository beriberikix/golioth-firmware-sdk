################################################################################
#
# golioth-firmware-sdk
#
################################################################################

GOLIOTH_FIRMWARE_SDK_VERSION = local
GOLIOTH_FIRMWARE_SDK_SITE = $(BR2_EXTERNAL_GOLIOTH_BUILDROOT_PATH)/../../../../golioth-firmware-sdk
GOLIOTH_FIRMWARE_SDK_SITE_METHOD = local
GOLIOTH_FIRMWARE_SDK_DEPENDENCIES = mbedtls zlib
GOLIOTH_FIRMWARE_SDK_INSTALL_STAGING = YES
GOLIOTH_FIRMWARE_SDK_INSTALL_TARGET = YES

# Disable documentation and examples to avoid cmake warnings
GOLIOTH_FIRMWARE_SDK_CONF_OPTS = \
	-DENABLE_DOCS=OFF \
	-DENABLE_EXAMPLES=OFF \
	-DENABLE_SERVER_MODE=OFF \
	-DENABLE_TCP=OFF \
	-DWITH_EPOLL=OFF \
	-DDTLS_BACKEND=mbedtls \
	-DWITH_MBEDTLS=ON \
	-DWITH_OPENSSL=OFF \
	-DENABLE_OPENSSL_ENGINE=OFF \
	-DOPENSSL_FOUND=FALSE

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
	echo '# Configure libcoap to use mbedTLS backend exclusively' >> $(@D)/CMakeLists.txt
	echo 'set(DTLS_BACKEND mbedtls CACHE STRING "Use mbedTLS backend")' >> $(@D)/CMakeLists.txt
	echo 'set(ENABLE_DTLS ON CACHE BOOL "Enable DTLS")' >> $(@D)/CMakeLists.txt
	echo 'set(WITH_MBEDTLS ON CACHE BOOL "Use mbedTLS")' >> $(@D)/CMakeLists.txt
	echo 'set(WITH_OPENSSL OFF CACHE BOOL "Do not use OpenSSL")' >> $(@D)/CMakeLists.txt
	echo 'set(ENABLE_OPENSSL_ENGINE OFF CACHE BOOL "Disable OpenSSL ENGINE")' >> $(@D)/CMakeLists.txt
	echo 'set(USE_WOLFSSL OFF CACHE BOOL "Do not use WolfSSL")' >> $(@D)/CMakeLists.txt
	echo 'set(OPENSSL_FOUND FALSE CACHE BOOL "Force OpenSSL not found")' >> $(@D)/CMakeLists.txt
	echo 'set(OPENSSL_CRYPTO_LIBRARY "" CACHE STRING "Clear OpenSSL crypto lib")' >> $(@D)/CMakeLists.txt
	echo '' >> $(@D)/CMakeLists.txt
	echo '# Configure Golioth SDK to use mbedTLS for crypto operations' >> $(@D)/CMakeLists.txt
	echo 'add_compile_definitions(GOLIOTH_USE_MBEDTLS)' >> $(@D)/CMakeLists.txt
	echo 'set(CMAKE_C_FLAGS "$${CMAKE_C_FLAGS} -DGOLIOTH_USE_MBEDTLS")' >> $(@D)/CMakeLists.txt
	echo '' >> $(@D)/CMakeLists.txt
	echo '# Enable Golioth features' >> $(@D)/CMakeLists.txt
	echo 'add_compile_definitions(CONFIG_GOLIOTH_LIGHTDB_STATE)' >> $(@D)/CMakeLists.txt
	echo 'add_compile_definitions(CONFIG_GOLIOTH_STREAM)' >> $(@D)/CMakeLists.txt
	echo 'add_compile_definitions(CONFIG_GOLIOTH_RPC)' >> $(@D)/CMakeLists.txt
	echo 'add_compile_definitions(CONFIG_GOLIOTH_SETTINGS)' >> $(@D)/CMakeLists.txt
	echo 'add_compile_definitions(CONFIG_GOLIOTH_FW_UPDATE)' >> $(@D)/CMakeLists.txt
	echo 'add_compile_definitions(CONFIG_GOLIOTH_DEBUG_LOG)' >> $(@D)/CMakeLists.txt
	echo '' >> $(@D)/CMakeLists.txt
	echo '# Set CMake policy to allow linking libraries from other directories' >> $(@D)/CMakeLists.txt
	echo 'cmake_policy(SET CMP0079 NEW)' >> $(@D)/CMakeLists.txt
	echo '' >> $(@D)/CMakeLists.txt
	echo '# Only build the SDK library, not examples' >> $(@D)/CMakeLists.txt
	echo 'add_subdirectory(port/linux/golioth_sdk)' >> $(@D)/CMakeLists.txt
	echo '' >> $(@D)/CMakeLists.txt
	echo '# Override crypto library linking for mbedTLS' >> $(@D)/CMakeLists.txt
	echo 'target_link_libraries(golioth_sdk PRIVATE mbedtls mbedx509 mbedcrypto)' >> $(@D)/CMakeLists.txt
	echo '' >> $(@D)/CMakeLists.txt
	echo '# Remove any OpenSSL crypto library dependencies' >> $(@D)/CMakeLists.txt
	echo 'set(CMAKE_C_FLAGS "$${CMAKE_C_FLAGS} -DWITH_MBEDTLS=1 -DWITH_OPENSSL=0")' >> $(@D)/CMakeLists.txt
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
	echo '# Install zcbor headers' >> $(@D)/CMakeLists.txt
	echo 'install(DIRECTORY external/zcbor/include/' >> $(@D)/CMakeLists.txt
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

# OpenSSL ENGINE compatibility patch removed - using mbedTLS backend instead

$(eval $(cmake-package))