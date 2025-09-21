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

$(eval $(cmake-package))