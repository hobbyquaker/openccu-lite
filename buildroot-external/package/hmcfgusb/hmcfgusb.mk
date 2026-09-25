################################################################################
#
# hmcfgusb - https://git.zerfleddert.de/cgi-bin/gitweb.cgi/hmcfgusb
#
################################################################################

# openccu-lite (task 147, D-100): only flash-hmcfgusb, the HM-CFG-USB-2's firmware flasher. The
# firmware itself (eQ-3's hmusbif.03c7.enc) is not shipped: the user uploads it.
HMCFGUSB_VERSION = 715728607ae77bebf3ac50fdbdb46639551995e4
HMCFGUSB_SITE = https://git.zerfleddert.de/git/hmcfgusb
HMCFGUSB_SITE_METHOD = git
HMCFGUSB_LICENSE = MIT
HMCFGUSB_LICENSE_FILES = LICENSE
HMCFGUSB_DEPENDENCIES = libusb

define HMCFGUSB_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) CC="$(TARGET_CC)" \
		CFLAGS="$(TARGET_CFLAGS) -I$(STAGING_DIR)/usr/include/libusb-1.0" \
		LDFLAGS="$(TARGET_LDFLAGS)" flash-hmcfgusb
endef

define HMCFGUSB_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/flash-hmcfgusb $(TARGET_DIR)/usr/bin/flash-hmcfgusb
endef

$(eval $(generic-package))
