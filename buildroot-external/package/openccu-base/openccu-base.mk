################################################################################
#
# OpenCCU-Base package
#
################################################################################

# OpenCCU-Base's release; the compat version is the release's identity (PRODUCT_VERSION, the
# recovery's hm-platform; the top Makefile reads both lines) and stays a release when the
# version becomes a commit.
OPENCCU_BASE_VERSION = 3.89.11
OPENCCU_BASE_COMPAT_VERSION = 3.89.11
# OpenCCU-Base's own release archive from GitHub - the file the recovery's hm-platform downloads
# too - pruned right after the extract to the paths openccu-base-paths.txt lists: the build sees
# nothing else, so a file that list does not name cannot reach the image, and the extract fails
# when an entry names nothing in the archive (openccu-lite task 335). The list is the one place
# that says what openccu-lite takes from OpenCCU-Base; package/eq3_char_loop prunes the same way.
OPENCCU_BASE_SITE = $(call github,OpenCCU,OpenCCU-Base,$(OPENCCU_BASE_VERSION))
OPENCCU_BASE_SITE_METHOD = wget
OPENCCU_BASE_PATHS_FILE = $(OPENCCU_BASE_PKGDIR)/openccu-base-paths.txt
# python3 is one of buildroot's own host prerequisites, so it is there before any host package
OPENCCU_BASE_PRUNE_SOURCE_CMD = \
	python3 $(OPENCCU_BASE_PKGDIR)/scripts/prune_source.py $(OPENCCU_BASE_PATHS_FILE)

define OPENCCU_BASE_PRUNE_SOURCE
	$(OPENCCU_BASE_PRUNE_SOURCE_CMD) $(@D)
endef
OPENCCU_BASE_POST_EXTRACT_HOOKS += OPENCCU_BASE_PRUNE_SOURCE

# The WebUI sources and the prebuilt ReGaHss are not in openccu-base-paths.txt: a product that
# wants them needs the complete OpenCCU-Base (and the full rootfs patch series) again.
ifeq ($(BR2_PACKAGE_OPENCCU_BASE),y)
ifneq ($(BR2_PACKAGE_OPENCCU_BASE_REGAHSS)$(BR2_PACKAGE_OPENCCU_BASE_WEBUI),)
$(error openccu-base: BR2_PACKAGE_OPENCCU_BASE_REGAHSS and _WEBUI need paths openccu-base-paths.txt does not list (the WebUI, bin/<platform>/ReGaHss))
endif
endif
OPENCCU_BASE_LICENSE = HMSL-2.0, Apache-2.0 (WebUI), \
	GPL-2.0+ (kernel modules), LGPL-2.1 (libraries)
OPENCCU_BASE_LICENSE_FILES = licenses/licenses.md licenses/HMSL2.txt \
	licenses/gpl-2.0.txt licenses/lgpl-2.1.txt
OPENCCU_BASE_ROOTFS_PATCH_DIR = \
	$(OPENCCU_BASE_PKGDIR)/rootfs-patches
OPENCCU_BASE_ENABLE_ROOTFS_PATCHING ?= YES

OPENCCU_BASE_DEPENDENCIES = \
	$(if $(BR2_PACKAGE_OPENCCU_BASE_COMPAT_LIBS_ONLY),,\
	host-pkgconf host-python3 host-python-html2text host-tcl \
	libusb openssl tcl)

OPENCCU_BASE_BUILD_OPTS = \
	--target $(if $(BR2_PACKAGE_OPENCCU_BASE_COMPAT_LIBS_ONLY),compat-libraries,package)

OPENCCU_BASE_CONF_OPTS = \
	-DDEPLOY_TO_REPO=OFF \
	-DBUILD_TCL_MODULES=$(if $(BR2_PACKAGE_OPENCCU_BASE_COMPAT_LIBS_ONLY),OFF,ON) \
	-DBUILD_WEBUI_AND_DEVICETYPES=$(if $(BR2_PACKAGE_OPENCCU_BASE_COMPAT_LIBS_ONLY),OFF,ON) \
	-DHAS_USB_SUPPORT=$(if $(BR2_PACKAGE_OPENCCU_BASE_COMPAT_LIBS_ONLY),OFF,ON) \
	-DROOTFS_DIR=$(@D)/build/rootfs \
	$(if $(BR2_PACKAGE_OPENCCU_BASE_COMPAT_LIBS_ONLY),,\
	-DOPENCCU_PYTHON_EXECUTABLE=$(HOST_DIR)/bin/python3 \
	-DOPENCCU_TCLSH_EXECUTABLE=$(HOST_DIR)/bin/tclsh8.6)

ifeq ($(BR2_arm),y)
OPENCCU_BASE_TARGET_PLATFORM = arm-linux-gnueabihf
endif

ifeq ($(BR2_aarch64),y)
OPENCCU_BASE_TARGET_PLATFORM = aarch64-linux-gnu
endif

ifeq ($(BR2_i386),y)
OPENCCU_BASE_TARGET_PLATFORM = i686-linux-gnu
endif

ifeq ($(BR2_x86_64),y)
OPENCCU_BASE_TARGET_PLATFORM = x86_64-linux-gnu
endif

OPENCCU_BASE_CONF_OPTS += \
	-DTARGET_PLATFORM=$(OPENCCU_BASE_TARGET_PLATFORM) \
	-DCROSS_PREFIX=$(TARGET_CROSS)

# Keep build/rootfs as the canonical, pristine input for the post-build patch
# series. Do not remove the complete staging directory here: incremental CMake
# builds do not necessarily re-stage binaries and libraries that are already
# up to date.
define OPENCCU_BASE_PREPARE_ROOTFS_PATCH_INPUTS
	rm -rf \
		"$(@D)/build/rootfs/www" \
		"$(@D)/build/rootfs/opt" \
		"$(@D)/build/rootfs/firmware" \
		"$(@D)/build/rootfs/usr/lib/tcl8.2/homematic"
	rm -f \
		"$(@D)/build/rootfs/bin/hm_autoconf" \
		"$(@D)/build/rootfs/bin/hm_deldev" \
		"$(@D)/build/rootfs/bin/hm_startup" \
		"$(@D)/build/rootfs/.applied_patches_list"
	$(INSTALL) -d -m 0755 "$(@D)/build/rootfs/bin"
	for file in hm_autoconf hm_deldev hm_startup; do \
		$(INSTALL) -m 0755 "$(@D)/bin/$$file" \
			"$(@D)/build/rootfs/bin/$$file"; \
	done
	$(INSTALL) -d -m 0755 "$(@D)/build/rootfs/firmware"
	cp -a "$(@D)/firmware/." "$(@D)/build/rootfs/firmware/"
	# the WebUI's files addons read on a CCU (task 331): the device pictures, DEVDB.tcl generated
	# as the classic build generates it, stringtable_de.txt and the translate.lang*.js files
	$(OPENCCU_BASE_ROOTFS_PATCH_DIR)/stage_lite_www.sh "$(@D)" "$(@D)/build/rootfs" \
		"$(HOST_DIR)/bin/tclsh8.6" "$(HOST_DIR)/bin/python3"
endef
ifneq ($(BR2_PACKAGE_OPENCCU_BASE_COMPAT_LIBS_ONLY),y)
OPENCCU_BASE_PRE_BUILD_HOOKS += OPENCCU_BASE_PREPARE_ROOTFS_PATCH_INPUTS
endif

# Apply the OpenCCU rootfs patch stack after CMake has generated the device types and the
# homematic Tcl package, but before any files are installed into TARGET_DIR. The pruned source
# has neither the WebUI nor HMServer's pages, so only the patches' sections outside www/ and
# opt/HMServer/pages/ apply, plus those on the WebUI files staged above (lite_series.py writes
# them); the series itself stays as OpenCCU keeps it (tasks 329, 331, 335).
define OPENCCU_BASE_APPLY_ROOTFS_PATCHES
	test -s "$(@D)/build/rootfs/bin/hm_autoconf"
	test -s "$(@D)/build/rootfs/usr/lib/tcl8.2/homematic/homematic.tcl"
	test -s "$(@D)/build/rootfs/firmware/rftypes/rf_cfm_tw.xml"
	rm -rf "$(@D)/rootfs-patches-lite"
	$(HOST_DIR)/bin/python3 "$(OPENCCU_BASE_ROOTFS_PATCH_DIR)/lite_series.py" \
		"$(OPENCCU_BASE_ROOTFS_PATCH_DIR)" "$(@D)/rootfs-patches-lite"
	rm -f "$(@D)/build/rootfs/.applied_patches_list"
	$(APPLY_PATCHES) "$(@D)/build/rootfs" \
		"$(@D)/rootfs-patches-lite" \*.patch
endef
ifeq ($(OPENCCU_BASE_ENABLE_ROOTFS_PATCHING),YES)
ifneq ($(BR2_PACKAGE_OPENCCU_BASE_COMPAT_LIBS_ONLY),y)
OPENCCU_BASE_POST_BUILD_HOOKS += OPENCCU_BASE_APPLY_ROOTFS_PATCHES
endif
endif

ifneq ($(BR2_PACKAGE_OPENCCU_BASE_COMPAT_LIBS_ONLY),y)
define OPENCCU_BASE_INSTALL_TARGET_CMDS

	# generate /bin
	$(INSTALL) -d -m 0755 $(TARGET_DIR)/bin

	# collect own compiled binaries from $(@D)/build/rootfs/bin
	for file in SetInterfaceClock crypttool eq3configcmd hs485d hs485dLoader multimacd rfd; do \
		$(INSTALL) -m 0755 "$(@D)/build/rootfs/bin/$$file" "$(TARGET_DIR)/bin/$$file"; \
	done
	# collect staged scripts/bins from $(@D)/build/rootfs/bin
	for file in hm_autoconf hm_deldev hm_startup; do \
		$(INSTALL) -m 0755 "$(@D)/build/rootfs/bin/$$file" "$(TARGET_DIR)/bin/$$file"; \
	done
	# generate /lib
	$(INSTALL) -d -m 0755 $(TARGET_DIR)/lib

	# collect own compiled libraries from $(@D)/build/rootfs/lib
	for lib in libLanDeviceUtils.so libUnifiedLanComm.so libXmlRpc.so libelvutils.so libeq3config.so libhsscomm.so libxmlparser.so tclrpc.so; do \
		$(INSTALL) -m 0644 "$(@D)/build/rootfs/lib/$$lib" "$(TARGET_DIR)/lib/$$lib"; \
	done

	# copy homematic tcl package to target dir
	$(INSTALL) -d -m 0755 "$(TARGET_DIR)/usr/lib/tcl8.6/homematic"
	cp -av "$(@D)/build/rootfs/usr/lib/tcl8.2/homematic/." \
		"$(TARGET_DIR)/usr/lib/tcl8.6/homematic/"

	# copy all static /etc stuff from main and build directory
	$(INSTALL) -d -m 0755 "$(TARGET_DIR)/etc"
	cp -av "$(@D)/etc/." "$(TARGET_DIR)/etc/"
	cp -av "$(@D)/build/rootfs/etc/." "$(TARGET_DIR)/etc/"

	# copy the complete staged /firmware tree
	$(INSTALL) -d -m 0755 "$(TARGET_DIR)/firmware"
	cp -av "$(@D)/build/rootfs/firmware/." "$(TARGET_DIR)/firmware/"

	# copy the complete staged /opt tree: what openccu-base-paths.txt lists of opt/, HMServer.jar
	# among it - a system without an HmIP module runs hmipserver as HMServer.jar for its
	# VirtualDevices half (B-313)
	$(INSTALL) -d -m 0755 "$(TARGET_DIR)/opt"
	cp -av "$(@D)/build/rootfs/opt/." "$(TARGET_DIR)/opt/"
	test -s "$(TARGET_DIR)/opt/HMServer/HMServer.jar"

	# the WebUI's files addons read on a CCU, at the CCU's paths under /www (task 331): staged by
	# stage_lite_www.sh and patched by the series as in the classic build; root, 0644, dirs 0755
	rm -rf "$(TARGET_DIR)/www/config" "$(TARGET_DIR)/www/webui"
	cd "$(@D)/build/rootfs/www" && \
	find config/img/devices config/devdescr config/stringtable_de.txt webui/js/lang -type f \
		\( -path 'config/img/devices/*.png' -o -path config/devdescr/DEVDB.tcl \
		-o -path config/stringtable_de.txt -o -path 'webui/js/lang/*/translate.lang*.js' \) \
		-print | LC_ALL=C sort | while read -r file; do \
		$(INSTALL) -D -m 0644 "$$file" "$(TARGET_DIR)/www/$$file" || exit 1; \
	done
	find "$(TARGET_DIR)/www/config" "$(TARGET_DIR)/www/webui" -type d -exec chmod 0755 {} +
endef
else
define OPENCCU_BASE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 \
		"$(@D)/build/rootfs/lib/libxmlparser.so" \
		"$(TARGET_DIR)/lib/libxmlparser.so"
	$(INSTALL) -D -m 0644 \
		"$(@D)/build/rootfs/lib/libXmlRpc.so" \
		"$(TARGET_DIR)/lib/libXmlRpc.so"
endef
endif

ifneq ($(BR2_PACKAGE_OPENCCU_BASE_COMPAT_LIBS_ONLY),y)
ifeq ($(BR2_PACKAGE_OPENCCU_BASE_REGAHSS),y)
define OPENCCU_BASE_INSTALL_REGAHSS
	# collect the pre-compiled ReGaHss from $(@D)/bin/$(OPENCCU_BASE_TARGET_PLATFORM)
	$(INSTALL) -D -m 0755 "$(@D)/bin/$(OPENCCU_BASE_TARGET_PLATFORM)/ReGaHss" \
		"$(TARGET_DIR)/bin/ReGaHss"
	# the Tcl extension scripts load to talk to ReGaHss
	$(INSTALL) -D -m 0644 "$(@D)/build/rootfs/lib/tclrega.so" \
		"$(TARGET_DIR)/lib/tclrega.so"
endef
OPENCCU_BASE_POST_INSTALL_TARGET_HOOKS += OPENCCU_BASE_INSTALL_REGAHSS
endif

ifeq ($(BR2_PACKAGE_OPENCCU_BASE_WEBUI),y)
define OPENCCU_BASE_INSTALL_WEBUI
	# collect own compiled WebUI from $(@D)/build/rootfs/www
	$(INSTALL) -d -m 0755 $(TARGET_DIR)/www
	cp -av "$(@D)/build/rootfs/www/." "$(TARGET_DIR)/www/"

	# patch XXX-WEBUI-VERSION-XXX and XXX-PRODUCT-XXX templates
	grep -rl 'XXX-WEBUI-VERSION-XXX' $(TARGET_DIR)/www | xargs sed -i 's/XXX-WEBUI-VERSION-XXX/$(PRODUCT_VERSION)/g' || true
	grep -rl 'XXX-PRODUCT-XXX' $(TARGET_DIR)/www | xargs sed -i 's/XXX-PRODUCT-XXX/$(PRODUCT)/g' || true
endef
else
define OPENCCU_BASE_INSTALL_WEBUI
	# without the WebUI, only the link addons publish their pages through
	$(INSTALL) -d -m 0755 $(TARGET_DIR)/www
	ln -snf /etc/config/addons/www $(TARGET_DIR)/www/addons
endef
endif
OPENCCU_BASE_POST_INSTALL_TARGET_HOOKS += OPENCCU_BASE_INSTALL_WEBUI
endif

define OPENCCU_BASE_FINALIZE_TARGET
	# setup /usr/local/etc/config
	mkdir -p $(TARGET_DIR)/usr/local/etc/config
	rm -rf $(TARGET_DIR)/etc/config
	ln -snf ../usr/local/etc/config $(TARGET_DIR)/etc/

	# shadow file setup
	touch $(TARGET_DIR)/usr/local/etc/config/shadow
	chmod 0640 $(TARGET_DIR)/usr/local/etc/config/shadow
	rm -f $(TARGET_DIR)/etc/shadow
	ln -snf config/shadow $(TARGET_DIR)/etc/

	# relink /run to /var/run
	rm -rf $(TARGET_DIR)/run $(TARGET_DIR)/var/run
	mkdir -p $(TARGET_DIR)/var/run
	ln -snf var/run $(TARGET_DIR)/

	# relink resolv.conf to /var/etc
	rm -f $(TARGET_DIR)/etc/resolv.conf
	ln -snf ../var/etc/resolv.conf $(TARGET_DIR)/etc/

	# remove the local wpa_supplicant config
	rm -f $(TARGET_DIR)/etc/wpa_supplicant.conf

	# relink the NUT config files
	rm -f $(TARGET_DIR)/etc/upssched.conf.sample
	ln -snf config/nut/upssched.conf $(TARGET_DIR)/etc/
	rm -f $(TARGET_DIR)/etc/upsmon.conf.sample
	ln -snf config/nut/upsmon.conf $(TARGET_DIR)/etc/
	rm -f $(TARGET_DIR)/etc/upsd.conf.sample
	ln -snf config/nut/upsd.conf $(TARGET_DIR)/etc/
	rm -f $(TARGET_DIR)/etc/upsd.users.sample
	ln -snf config/nut/upsd.users $(TARGET_DIR)/etc/
	rm -f $(TARGET_DIR)/etc/ups.conf.sample
	ln -snf config/nut/ups.conf $(TARGET_DIR)/etc/
	rm -f $(TARGET_DIR)/etc/nut.conf.sample
	ln -snf config/nut/nut.conf $(TARGET_DIR)/etc/

	# link timezone information files
	ln -snf config/localtime $(TARGET_DIR)/etc/
	ln -snf config/timezone $(TARGET_DIR)/etc/

	# link /etc/firmware to /lib/firmware
	ln -snf ../lib/firmware $(TARGET_DIR)/etc/

	# link /bin/tclsh to /usr/bin/tclsh
	ln -snf /usr/bin/tclsh $(TARGET_DIR)/bin/tclsh

	# remove obsolete init.d jobs
	rm -f $(TARGET_DIR)/etc/init.d/S01logging
	rm -f $(TARGET_DIR)/etc/init.d/S20urandom
	rm -f $(TARGET_DIR)/etc/init.d/S01syslogd
	rm -f $(TARGET_DIR)/etc/init.d/S02klogd
	rm -f $(TARGET_DIR)/etc/init.d/S49chronyd

	# remove obsolete config templates
	rm -f $(TARGET_DIR)/etc/config_templates/hmip_networkkey.conf

	# remove obsolete lighttpd config files
	rm -f $(TARGET_DIR)/etc/lighttpd/lighttpd_ssl.conf

	# make sure ReGaHss.* is deleted
	rm -f $(TARGET_DIR)/bin/ReGaHss.*

	# make sure no /etc/ntp.conf is there anymore (chrony used)
	rm -f $(TARGET_DIR)/etc/ntp.conf

	# extract license infos from JAR files
	$(HOST_DIR)/bin/python3 $(OPENCCU_BASE_PKGDIR)/scripts/createLicenseForJar.py \
		--packagedir=$(TARGET_DIR)/opt/HMServer \
		--jarfile=HMIPServer.jar \
		--output=$(OPENCCU_BASE_BUILDDIR)/HMIPServer.jar-JARLICENSEINFO.txt
	$(HOST_DIR)/bin/python3 $(OPENCCU_BASE_PKGDIR)/scripts/createLicenseForJar.py \
		--packagedir=$(TARGET_DIR)/opt/HMServer \
		--jarfile=HMServer.jar \
		--output=$(OPENCCU_BASE_BUILDDIR)/HMServer.jar-JARLICENSEINFO.txt
	$(HOST_DIR)/bin/python3 $(OPENCCU_BASE_PKGDIR)/scripts/createLicenseForJar.py \
		--packagedir=$(TARGET_DIR)/opt/HmIP \
		--jarfile=hmip-copro-update.jar \
		--output=$(OPENCCU_BASE_BUILDDIR)/hmip-copro-update.jar-JARLICENSEINFO.txt
	$(HOST_DIR)/bin/python3 $(OPENCCU_BASE_PKGDIR)/scripts/createLicenseForJar.py \
		--packagedir=$(TARGET_DIR)/opt/HMServer/coupling \
		--jarfile=ESHBridge.jar \
		--output=$(OPENCCU_BASE_BUILDDIR)/ESHBridge.jar-JARLICENSEINFO.txt

	# create licenseinfo.htm, also without the WebUI, so every image
	# carries the license information
	$(INSTALL) -d -m 0755 $(TARGET_DIR)/www/rega
	$(HOST_DIR)/bin/python3 $(OPENCCU_BASE_PKGDIR)/scripts/createLicenseHtml.py \
		--build-dir=$(BUILD_DIR)/../ \
		--jar-license-info=$(OPENCCU_BASE_BUILDDIR)/HMIPServer.jar-JARLICENSEINFO.txt \
		--jar-license-info=$(OPENCCU_BASE_BUILDDIR)/HMServer.jar-JARLICENSEINFO.txt \
		--jar-license-info=$(OPENCCU_BASE_BUILDDIR)/hmip-copro-update.jar-JARLICENSEINFO.txt \
		--jar-license-info=$(OPENCCU_BASE_BUILDDIR)/ESHBridge.jar-JARLICENSEINFO.txt \
		--output=$(TARGET_DIR)/www/rega/licenseinfo.htm
endef

define OPENCCU_BASE_FINALIZE_TARGET_WEBUI
	# fix permissions
	chmod 755 $(TARGET_DIR)/www/config/fileupload.ccc
endef
ifeq ($(BR2_PACKAGE_OPENCCU_BASE),y)
ifneq ($(BR2_PACKAGE_OPENCCU_BASE_COMPAT_LIBS_ONLY),y)
TARGET_FINALIZE_HOOKS += OPENCCU_BASE_FINALIZE_TARGET
ifeq ($(BR2_PACKAGE_OPENCCU_BASE_WEBUI),y)
TARGET_FINALIZE_HOOKS += OPENCCU_BASE_FINALIZE_TARGET_WEBUI
endif
endif
endif

ifneq ($(BR2_PACKAGE_OPENCCU_BASE_COMPAT_LIBS_ONLY),y)
ifeq ($(BR2_PACKAGE_OPENCCU_BASE_REGAHSS),y)
define OPENCCU_BASE_INSTALL_INIT_SYSV_REGAHSS
	$(INSTALL) -D -m 0755 $(OPENCCU_BASE_PKGDIR)/S70ReGaHss \
		$(TARGET_DIR)/etc/init.d/S70ReGaHss
endef
endif

define OPENCCU_BASE_INSTALL_INIT_SYSV
	$(INSTALL) -D -m 0755 $(OPENCCU_BASE_PKGDIR)/S50eq3configd \
		$(TARGET_DIR)/etc/init.d/S50eq3configd
	$(INSTALL) -D -m 0755 $(OPENCCU_BASE_PKGDIR)/S50ssdpd \
		$(TARGET_DIR)/etc/init.d/S50ssdpd
	$(OPENCCU_BASE_INSTALL_INIT_SYSV_REGAHSS)
endef

define OPENCCU_BASE_USERS
	-      -1 hm     -1 * - - -      homematic access group
	-      -1 status -1 * - - -      status access group
	hssled -1 hssled -1 * - - status hss_led user
	eq3cfg -1 eq3cfg -1 * - - -      eq3configd user
	ssdp   -1 ssdp   -1 * - - -      ssdpd user
endef
endif

$(eval $(cmake-package))
