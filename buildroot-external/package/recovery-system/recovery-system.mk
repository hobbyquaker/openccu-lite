################################################################################
#
# Recovery Image Package
#
################################################################################

RECOVERY_SYSTEM_VER = 1.24.1
# The outer stamps gate the entire nested build; as in package/multilib32 (openccu-lite task 353)
# its inputs are of two kinds:
# - what needs a fresh nested tree is in the version, i.e. the build directory: Buildroot and the
#   multilib configuration (MULTILIB32_VERSION), and the recovery's own configuration (hashed by
#   content, as multilib32 does);
# - what the nested build takes on its command line - OpenCCU-Base's version and release (the
#   nested multilib32 and hm-platform name their build directories by them), the recovery's
#   /VERSION, the splash image, the kernel of the OVA's recovery - is RECOVERY_SYSTEM_INPUTS: a
#   change reruns the nested build in the same directory, which rebuilds only what changed.
#   A rebuilt multilib32 reruns it as well: the nested build copies its directory (below).
ifneq ($(call qstrip,$(BR2_PACKAGE_RECOVERY_SYSTEM_CONFIG_FRAGMENT_FILE)),)
RECOVERY_SYSTEM_CONFIG_HASH := $(shell cat \
	$(pkgdir)/external/Buildroot.config \
	$(pkgdir)/external/configs/$(call qstrip,$(BR2_PACKAGE_RECOVERY_SYSTEM_CONFIG_FRAGMENT_FILE)) \
	| sha256sum | cut -c 1-16)
else
RECOVERY_SYSTEM_CONFIG_HASH = none
endif
RECOVERY_SYSTEM_VERSION = $(RECOVERY_SYSTEM_VER)-$(MULTILIB32_VERSION)-$(RECOVERY_SYSTEM_CONFIG_HASH)
RECOVERY_SYSTEM_INPUTS = openccu-base=$(OPENCCU_BASE_VERSION) \
	compat=$(OPENCCU_BASE_COMPAT_VERSION) \
	version=$(PRODUCT_VERSION)-$(RECOVERY_SYSTEM_VER) \
	psplash=$(call qstrip,$(BR2_PACKAGE_PSPLASH_IMAGE)) \
	kernel=$(call qstrip,$(BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE)) \
	kernel-tarball=$(call qstrip,$(BR2_LINUX_KERNEL_CUSTOM_TARBALL_LOCATION))
RECOVERY_SYSTEM_SOURCE =
RECOVERY_SYSTEM_LICENSE = Apache-2.0
RECOVERY_SYSTEM_DEPENDENCIES = $(if $(BR2_PACKAGE_MULTILIB32),multilib32)

define RECOVERY_SYSTEM_CONFIGURE_CMDS
	mkdir -p $(@D)/output/build
endef

# hm-platform takes its prebuilt binaries from OpenCCU-Base's GitHub tarball of the release, so
# the inner build gets the release as OPENCCU_BASE_COMPAT_VERSION besides OPENCCU_BASE_VERSION
# (the same today; a commit pin would differ - for the multilib32 it shares; task 330).
define RECOVERY_SYSTEM_BUILD_CMDS
	$(MAKE) O=$(@D)/output -C $(TOPDIR) HOSTCXX="$(HOSTCXX_NOCCACHE)" HOSTCC="$(HOSTCC_NOCCACHE)" BR2_EXTERNAL=$(RECOVERY_SYSTEM_PKGDIR)/external OPENCCU_BASE_VERSION="$(OPENCCU_BASE_VERSION)" OPENCCU_BASE_COMPAT_VERSION="$(OPENCCU_BASE_COMPAT_VERSION)" alldefconfig
	(cd $(@D)/output && HOSTCXX="$(HOSTCXX_NOCCACHE)" HOSTCC="$(HOSTCC_NOCCACHE)" BR2_EXTERNAL=$(RECOVERY_SYSTEM_PKGDIR)/external BR2_RECOVERY_SYSTEM_VERSION=$(PRODUCT_VERSION)-$(RECOVERY_SYSTEM_VER) BR2_PACKAGE_PSPLASH_IMAGE=$(BR2_PACKAGE_PSPLASH_IMAGE) BR2_EXTERNAL_LINUX_KERNEL_CUSTOM_VERSION_VALUE=$(BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE) BR2_EXTERNAL_LINUX_KERNEL_CUSTOM_TARBALL_LOCATION=$(BR2_LINUX_KERNEL_CUSTOM_TARBALL_LOCATION) $(TOPDIR)/support/kconfig/merge_config.sh $(RECOVERY_SYSTEM_PKGDIR)/external/Buildroot.config $(RECOVERY_SYSTEM_PKGDIR)/external/configs/$(BR2_PACKAGE_RECOVERY_SYSTEM_CONFIG_FRAGMENT_FILE))
	# Only reuse the completed current build if recovery selects the same
	# multilib fragment. Otherwise let recovery build its own variant.
	# The copy's nested openccu-base directories of other versions go first (the copy is
	# not mirrored: its own install stamps stay; rsync -a keeps the build stamp's time, so a
	# rebuilt multilib32 is installed into the recovery again).
	if test -f "$(MULTILIB32_DIR)/.stamp_built" && \
		grep -qx 'BR2_PACKAGE_MULTILIB32=y' "$(@D)/output/.config" && \
		grep -Fxq 'BR2_PACKAGE_MULTILIB32_CONFIG_FRAGMENT_FILE=$(BR2_PACKAGE_MULTILIB32_CONFIG_FRAGMENT_FILE)' "$(@D)/output/.config"; then \
		$(call MULTILIB32_STALE_BASE_CMD,$(@D)/output/build/multilib32-$(MULTILIB32_VERSION)); \
		rsync -a --exclude '.stamp_target_installed' \
			--exclude '.stamp_staging_installed' --exclude '.stamp_images_installed' \
			--exclude '.stamp_installed' \
			"$(MULTILIB32_DIR)" "$(@D)/output/build/"; \
	fi
	$(MAKE) O=$(@D)/output -C $(TOPDIR) HOSTCXX="$(HOSTCXX_NOCCACHE)" HOSTCC="$(HOSTCC_NOCCACHE)" BR2_EXTERNAL=$(RECOVERY_SYSTEM_PKGDIR)/external OPENCCU_BASE_VERSION="$(OPENCCU_BASE_VERSION)" OPENCCU_BASE_COMPAT_VERSION="$(OPENCCU_BASE_COMPAT_VERSION)" BR2_RECOVERY_SYSTEM_VERSION=$(PRODUCT_VERSION)-$(RECOVERY_SYSTEM_VER) BR2_PACKAGE_PSPLASH_IMAGE=$(BR2_PACKAGE_PSPLASH_IMAGE) BR2_EXTERNAL_LINUX_KERNEL_CUSTOM_VERSION_VALUE=$(BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE) BR2_EXTERNAL_LINUX_KERNEL_CUSTOM_TARBALL_LOCATION=$(BR2_LINUX_KERNEL_CUSTOM_TARBALL_LOCATION)
endef

define RECOVERY_SYSTEM_INSTALL_TARGET_CMDS
	test -f $(@D)/output/images/rootfs.cpio.uboot && cp -a $(@D)/output/images/rootfs.cpio.uboot $(BINARIES_DIR)/recoveryfs-initrd || cp -a $(@D)/output/images/rootfs.cpio.lz4 $(BINARIES_DIR)/recoveryfs-initrd
	test -f $(@D)/output/images/bzImage && cp -a $(@D)/output/images/bzImage $(BINARIES_DIR)/recoveryfs-zImage || true
	test -f $(@D)/output/images/zImage && cp -a $(@D)/output/images/zImage $(BINARIES_DIR)/recoveryfs-zImage || true
	test -f $(@D)/output/images/Image && cp -a $(@D)/output/images/Image $(BINARIES_DIR)/recoveryfs-Image || true
endef

$(eval $(generic-package))

ifeq ($(BR2_PACKAGE_RECOVERY_SYSTEM),y)
$(eval $(call LITE_INPUTS_STAMP,recovery-system,RECOVERY_SYSTEM))
ifeq ($(BR2_PACKAGE_MULTILIB32),y)
$(RECOVERY_SYSTEM_DIR)/.stamp_configured: $(MULTILIB32_DIR)/.stamp_target_installed
endif
endif
