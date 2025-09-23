################################################################################
#
# golioth-basics
#
################################################################################

GOLIOTH_BASICS_VERSION = local
GOLIOTH_BASICS_SITE = $(BR2_EXTERNAL_GOLIOTH_BUILDROOT_PATH)/../golioth_basics
GOLIOTH_BASICS_SITE_METHOD = local
GOLIOTH_BASICS_DEPENDENCIES = golioth-firmware-sdk

# Point to the existing golioth_basics CMakeLists.txt
GOLIOTH_BASICS_CONF_OPTS = \
	-DCMAKE_BUILD_TYPE=Release

# Copy the common source file and create a buildroot-compatible CMakeLists.txt
define GOLIOTH_BASICS_CREATE_CMAKE
	# Copy the common golioth_basics.c file to the build directory
	cp /workspace/golioth-firmware-sdk/examples/common/golioth_basics.c $(@D)/
	cp /workspace/golioth-firmware-sdk/examples/common/golioth_basics.h $(@D)/
	# Create a simplified CMakeLists.txt that uses local files
	echo 'cmake_minimum_required(VERSION 3.5)' > $(@D)/CMakeLists.txt
	echo 'set(projname "golioth_basics")' >> $(@D)/CMakeLists.txt
	echo 'project($${projname} C)' >> $(@D)/CMakeLists.txt
	echo '' >> $(@D)/CMakeLists.txt
	echo 'set(CMAKE_BUILD_TYPE Release)' >> $(@D)/CMakeLists.txt
	echo '' >> $(@D)/CMakeLists.txt
	echo 'set(srcs' >> $(@D)/CMakeLists.txt
	echo '    main.c' >> $(@D)/CMakeLists.txt
	echo '    golioth_basics.c' >> $(@D)/CMakeLists.txt
	echo ')' >> $(@D)/CMakeLists.txt
	echo '' >> $(@D)/CMakeLists.txt
	echo 'get_filename_component(user_config_file "golioth_user_config.h" ABSOLUTE)' >> $(@D)/CMakeLists.txt
	echo 'add_definitions(-DCONFIG_GOLIOTH_USER_CONFIG_INCLUDE="$${user_config_file}")' >> $(@D)/CMakeLists.txt
	echo '' >> $(@D)/CMakeLists.txt
	echo '# Link with the installed golioth_sdk library' >> $(@D)/CMakeLists.txt
	echo 'add_executable($${projname} $${srcs})' >> $(@D)/CMakeLists.txt
	echo 'target_include_directories($${projname} PRIVATE .)' >> $(@D)/CMakeLists.txt
	echo 'target_link_libraries($${projname} golioth_sdk mbedtls mbedx509 mbedcrypto coap-3)' >> $(@D)/CMakeLists.txt
	echo '' >> $(@D)/CMakeLists.txt
	echo '# Install the binary to /usr/bin' >> $(@D)/CMakeLists.txt
	echo 'install(TARGETS $${projname} DESTINATION bin)' >> $(@D)/CMakeLists.txt
endef

GOLIOTH_BASICS_PRE_CONFIGURE_HOOKS += GOLIOTH_BASICS_CREATE_CMAKE

$(eval $(cmake-package))