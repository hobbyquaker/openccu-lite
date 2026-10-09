# openccu-lite (D-44): a lite product's version is openccu-lite's own semantic version from
# LITE-VERSION (1.0.0-alpha.0, 1.0.0-beta.1, 1.0.0, 1.1.0 ...), never the build date and no
# longer the OpenCCU base tag with a suffix - the base tag is BASE in the same file and goes into
# /VERSION's VERSION= line for the recovery. The Makefile includes this after its own
# PRODUCT_VERSION line, and only the lite products are affected.
# D-88: every build is 1.0.0-beta.<N> (1.0.0-dev.<N> until dev.45), one number per build round (all
# products from the same fork commit and pins), N from the project's build list (never reused):
#   make PRODUCT=... LITE_VERSION=1.0.0-beta.<N> release
# The -snapshot.<sha> form of D-44 is not used any more.
LITE_BASE:=$(shell sed -n 's/^BASE=//p' LITE-VERSION)
LITE_VERSION?=$(shell sed -n 's/^VERSION=//p' LITE-VERSION)
# Which products are lite ones. Since D-39/D-43 every lite product is named <arch>[-<form>] and
# carries no "-lite" in its name, so the list below is what decides. Add a product here when it is
# added to configs/ - a lite product not listed would silently get upstream's date-based version.
LITE_PRODUCTS:=x86_64-ova aarch64-rpi3 aarch64-rpi4 aarch64-rpi5 lxc-lite_amd64 lxc-lite_arm64
ifneq ($(findstring -lite,$(PRODUCT))$(filter $(PRODUCT),$(LITE_PRODUCTS)),)
ifneq ($(LITE_VERSION),)
PRODUCT_VERSION:=$(LITE_VERSION)
export LITE_BASE LITE_VERSION
endif
endif
