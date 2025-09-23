################################################################################
#
# golioth-app
#
################################################################################

# Use embedded source from src/ directory
GOLIOTH_APP_DEPENDENCIES = golioth-firmware-sdk

# Disable documentation and examples to avoid cmake warnings
GOLIOTH_APP_CONF_OPTS = \
	-DCMAKE_BUILD_TYPE=Release

# Copy source files to build directory
define GOLIOTH_APP_EXTRACT_CMDS
	cp -r $(GOLIOTH_APP_PKGDIR)/src/* $(@D)/
endef

$(eval $(cmake-package))