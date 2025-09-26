################################################################################
#
# golioth-app
#
################################################################################

# Use embedded source from src/ directory
GOLIOTH_APP_DEPENDENCIES = golioth-firmware-sdk

# Get firmware version from environment or use default
ifndef BR2_GOLIOTH_FIRMWARE_VERSION
BR2_GOLIOTH_FIRMWARE_VERSION = "1.2.5"
endif

# Disable documentation and examples to avoid cmake warnings
GOLIOTH_APP_CONF_OPTS = \
	-DCMAKE_BUILD_TYPE=Release \
	-DFIRMWARE_VERSION=$(BR2_GOLIOTH_FIRMWARE_VERSION)

# Copy source files to build directory
define GOLIOTH_APP_EXTRACT_CMDS
	cp -r $(GOLIOTH_APP_PKGDIR)/src/* $(@D)/
endef

$(eval $(cmake-package))