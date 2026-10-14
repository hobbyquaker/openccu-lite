################################################################################
#
# Multlib32 Package
#
################################################################################

# The outer stamps gate the entire nested build. Two kinds of input (openccu-lite task 353):
# - what needs a fresh nested tree goes into the version, i.e. the build directory: Buildroot
#   and the nested configuration (its toolchain/CPU settings). Hash contents, not paths: main
#   and recovery builds use different paths to the same fragments.
# - what the nested build takes on the command line, OpenCCU-Base's version, is not in the
#   version: the nested tree builds its own openccu-base (libXmlRpc and libxmlparser, the
#   compat-libraries target) in a directory named by that version, so a pin change rebuilds
#   only that package there, not the 32-bit toolchain and userland. MULTILIB32_INPUTS is
#   written to the build directory and the build step reruns when it changes (below).
ifneq ($(call qstrip,$(BR2_PACKAGE_MULTILIB32_CONFIG_FRAGMENT_FILE)),)
MULTILIB32_CONFIG_HASH := $(shell cat \
	$(pkgdir)/external/Buildroot.config \
	$(pkgdir)/external/configs/$(call qstrip,$(BR2_PACKAGE_MULTILIB32_CONFIG_FRAGMENT_FILE)) \
	| sha256sum | cut -c 1-16)
else
MULTILIB32_CONFIG_HASH = none
endif
MULTILIB32_VERSION = 1.3.0-$(BR2_VERSION)-$(MULTILIB32_CONFIG_HASH)
MULTILIB32_INPUTS = openccu-base=$(OPENCCU_BASE_VERSION)
MULTILIB32_SOURCE =

# The nested build directories of other OpenCCU-Base versions go first: the nested tree keeps
# them otherwise (~100 MB each), and the recovery's copy of this directory with them.
MULTILIB32_STALE_BASE_CMD = \
	test ! -d $(1)/output/build || find $(1)/output/build -mindepth 1 -maxdepth 1 -type d -name 'openccu-base-*' \
		! -name 'openccu-base-$(OPENCCU_BASE_VERSION)' -exec rm -rf {} +

define MULTILIB32_BUILD_CMDS
	mkdir -p $(@D)/output
	$(call MULTILIB32_STALE_BASE_CMD,$(@D))
	$(MAKE) O=$(@D)/output -C $(TOPDIR) HOSTCXX="$(HOSTCXX_NOCCACHE)" HOSTCC="$(HOSTCC_NOCCACHE)" BR2_EXTERNAL=$(MULTILIB32_PKGDIR)/external OPENCCU_BASE_VERSION="$(OPENCCU_BASE_VERSION)" alldefconfig
	(cd $(@D)/output && HOSTCXX="$(HOSTCXX_NOCCACHE)" HOSTCC="$(HOSTCC_NOCCACHE)" BR2_EXTERNAL=$(MULTILIB32_PKGDIR)/external $(TOPDIR)/support/kconfig/merge_config.sh $(MULTILIB32_PKGDIR)/external/Buildroot.config $(MULTILIB32_PKGDIR)/external/configs/$(BR2_PACKAGE_MULTILIB32_CONFIG_FRAGMENT_FILE))
	$(MAKE) O=$(@D)/output -C $(TOPDIR) HOSTCXX="$(HOSTCXX_NOCCACHE)" HOSTCC="$(HOSTCC_NOCCACHE)" BR2_EXTERNAL=$(MULTILIB32_PKGDIR)/external OPENCCU_BASE_VERSION="$(OPENCCU_BASE_VERSION)"
endef

define MULTILIB32_INSTALL_TARGET_CMDS
	tar xvf $(@D)/output/images/rootfs.tar --transform='s/.\/lib\//lib32\//' -C $(TARGET_DIR)/ --wildcards --show-transformed-names "./lib/*.so*"
	tar xvf $(@D)/output/images/rootfs.tar --transform='s/.\/usr\/lib\//usr\/lib32\//' -C $(TARGET_DIR)/ --wildcards --show-transformed-names "./usr/lib/*.so*"
	mkdir -p $(TARGET_DIR)/etc/ld.so.conf.d
	echo -e "/lib32\n/usr/lib32\n/usr/local/lib32" >$(TARGET_DIR)/etc/ld.so.conf.d/lib32.conf
	if [[ $(BR2_ARCH) == "x86_64" ]]; then ln -sf ../lib32/ld-linux.so.2 $(TARGET_DIR)/lib/ ; fi
	if [[ $(BR2_ARCH) == "aarch64" ]]; then ln -sf ../lib32/ld-linux-armhf.so.3 $(TARGET_DIR)/lib/ ; fi
endef

$(eval $(generic-package))

ifeq ($(BR2_PACKAGE_MULTILIB32),y)
$(eval $(call LITE_INPUTS_STAMP,multilib32,MULTILIB32))
endif
