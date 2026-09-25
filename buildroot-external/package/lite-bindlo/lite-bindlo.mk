################################################################################
#
# lite-bindlo
#
################################################################################

# openccu-lite: the LD_PRELOAD shim that keeps hmipserver's port 39292 on the loopback.
LITE_BINDLO_VERSION = 1
LITE_BINDLO_SITE = $(BR2_EXTERNAL_EQ3_PATH)/package/lite-bindlo/src
LITE_BINDLO_SITE_METHOD = local
LITE_BINDLO_LICENSE = Apache-2.0

define LITE_BINDLO_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) -fPIC -shared -Wall -Werror \
		-o $(@D)/libbindlo.so $(@D)/bindlo.c $(TARGET_LDFLAGS) -ldl
endef

define LITE_BINDLO_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(@D)/libbindlo.so $(TARGET_DIR)/usr/lib/openccu-lite/libbindlo.so
endef

$(eval $(generic-package))
