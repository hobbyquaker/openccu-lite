################################################################################
#
# rpi-eeprom
#
################################################################################

RPI_EEPROM_VERSION = 7ed1cc2b210053b5d6537b2beb542663cab7e10b
RPI_EEPROM_SITE = $(call github,raspberrypi,rpi-eeprom,$(RPI_EEPROM_VERSION))
RPI_EEPROM_LICENSE = BSD-3-Clause, MIT, uIP, custom
RPI_EEPROM_LICENSE_FILES = LICENSE
RPI_EEPROM_INSTALL_IMAGES = YES

# openccu-lite (task 394): the images come from the "default" channel, the one Raspberry Pi OS's
# rpi-eeprom-update installs by default, not from "latest" (the "stable" link points there): the
# bootloader is written into the SPI flash, where proven beats new. scripts/update-rpi-eeprom.sh
# picks the newest pieeprom-*.bin of default/; occulited's Hardware page offers an image only when
# it is newer than the flashed one, so a Pi that has flashed a newer latest keeps it.
ifeq ($(BR2_PACKAGE_RPI_EEPROM_RPI4),y)
  # Raspberry Pi 4 (2711)
  RPI_EEPROM_FIRMWARE_PATH = firmware-2711/default/pieeprom-2026-09-23.bin
  RPI_EEPROM_RECOVERY_PATH = firmware-2711/default/recovery.bin
  RPI_EEPROM_VL805_GLOB = firmware-2711/default/vl805-*.bin
  RPI_EEPROM_CHIP = 2711
else ifeq ($(BR2_PACKAGE_RPI_EEPROM_RPI5),y)
  # Raspberry Pi 5 (2712)
  RPI_EEPROM_FIRMWARE_PATH = firmware-2712/default/pieeprom-2026-09-25.bin
  RPI_EEPROM_RECOVERY_PATH = firmware-2712/default/recovery.bin
  RPI_EEPROM_CHIP = 2712
endif

define RPI_EEPROM_BUILD_CMDS
	$(@D)/rpi-eeprom-config $(@D)/$(RPI_EEPROM_FIRMWARE_PATH) --out $(@D)/default.conf
	(cat $(@D)/default.conf | grep -v ^$$; echo HDMI_DELAY=0) > $(@D)/boot.conf
	$(@D)/rpi-eeprom-config $(@D)/$(RPI_EEPROM_FIRMWARE_PATH) --config $(@D)/boot.conf --out $(@D)/pieeprom.upd
	$(@D)/rpi-eeprom-digest -i $(@D)/pieeprom.upd -o $(@D)/pieeprom.sig
	$(RPI_EEPROM_BUILD_VL805_CMDS)
endef

ifeq ($(BR2_PACKAGE_RPI_EEPROM_RPI4),y)
define RPI_EEPROM_BUILD_VL805_CMDS
	RPI_EEPROM_VL805_PATH=$$(ls -1 $(@D)/$(RPI_EEPROM_VL805_GLOB) 2>/dev/null | sort -r | head -n1); \
	[ -n "$$RPI_EEPROM_VL805_PATH" ] || { echo "No VL805 firmware image found matching $(RPI_EEPROM_VL805_GLOB)"; exit 1; }; \
	cp "$$RPI_EEPROM_VL805_PATH" $(@D)/vl805.bin; \
	$(@D)/rpi-eeprom-digest -i $(@D)/vl805.bin -o $(@D)/vl805.sig; \
	VL805_BASENAME=$${RPI_EEPROM_VL805_PATH##*vl805-}; \
	echo "$${VL805_BASENAME%.bin}" >$(@D)/vl805.ver
endef
endif

define RPI_EEPROM_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(RPI_EEPROM_PKGDIR)/rpi-eeprom-info $(TARGET_DIR)/bin
	$(RPI_EEPROM_INSTALL_OFFER_CMDS)
endef

# openccu-lite (task 366): the update goes to the root file system, not into the boot partition -
# occulited's helper stages it into /boot when an administrator asks for it on the Hardware page
ifeq ($(BR2_PACKAGE_RPI_EEPROM_OFFER),y)
RPI_EEPROM_OFFER_DIR = $(TARGET_DIR)/usr/share/rpi-eeprom/firmware-$(RPI_EEPROM_CHIP)
define RPI_EEPROM_INSTALL_OFFER_CMDS
	$(INSTALL) -D -m 0644 $(@D)/pieeprom.upd $(RPI_EEPROM_OFFER_DIR)/pieeprom.upd
	$(INSTALL) -D -m 0644 $(@D)/pieeprom.sig $(RPI_EEPROM_OFFER_DIR)/pieeprom.sig
	$(INSTALL) -D -m 0644 $(@D)/$(RPI_EEPROM_RECOVERY_PATH) $(RPI_EEPROM_OFFER_DIR)/recovery.bin
	$(RPI_EEPROM_INSTALL_OFFER_VL805_CMDS)
endef
ifeq ($(BR2_PACKAGE_RPI_EEPROM_RPI4),y)
define RPI_EEPROM_INSTALL_OFFER_VL805_CMDS
	$(INSTALL) -D -m 0644 $(@D)/vl805.bin $(RPI_EEPROM_OFFER_DIR)/vl805.bin
	$(INSTALL) -D -m 0644 $(@D)/vl805.sig $(RPI_EEPROM_OFFER_DIR)/vl805.sig
	$(INSTALL) -D -m 0644 $(@D)/vl805.ver $(RPI_EEPROM_OFFER_DIR)/vl805.ver
endef
endif
endif

define RPI_EEPROM_INSTALL_IMAGES_CMDS
	$(INSTALL) -D -m 0644 $(@D)/pieeprom.sig $(BINARIES_DIR)/rpi-eeprom/pieeprom.sig
	$(INSTALL) -D -m 0644 $(@D)/pieeprom.upd $(BINARIES_DIR)/rpi-eeprom/pieeprom.upd
	$(INSTALL) -D -m 0644 $(@D)/$(RPI_EEPROM_RECOVERY_PATH) $(BINARIES_DIR)/rpi-eeprom/recovery.bin
	$(RPI_EEPROM_INSTALL_VL805_IMAGES_CMDS)
endef

ifeq ($(BR2_PACKAGE_RPI_EEPROM_RPI4),y)
define RPI_EEPROM_INSTALL_VL805_IMAGES_CMDS
  # VL805 firmware + version sidecar
	$(INSTALL) -D -m 0644 $(@D)/vl805.bin $(BINARIES_DIR)/rpi-eeprom/vl805.bin
	$(INSTALL) -D -m 0644 $(@D)/vl805.sig $(BINARIES_DIR)/rpi-eeprom/vl805.sig
	$(INSTALL) -D -m 0644 $(@D)/vl805.ver $(BINARIES_DIR)/rpi-eeprom/vl805.ver
endef
endif

$(eval $(generic-package))
