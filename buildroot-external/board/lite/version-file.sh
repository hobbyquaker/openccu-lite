#!/bin/sh
#
# openccu-lite: the lite lines of /VERSION, run from board/lite/post-build.sh with the target
# directory as $1 and PRODUCT, LITE_BASE, LITE_VERSION from the environment (lite-version.mk).
#
# /VERSION carries upstream's product and platform names plus VARIANT=lite
# (D-17, D-31): the firmware updater compares PRODUCT/PLATFORM, so update
# packages stay interchangeable with OpenCCU in both directions, and
# openccu-lite identifies itself by the extra line.
#
# Since D-39/D-43 every lite product is named <arch>[-<form>] and carries no
# upstream name to strip, so the case below is the whole mapping and it must
# list every product in configs/. What upstream's own image writes is what the
# recovery compares on an in-place update, so a product missing here would
# leave its own name in PLATFORM and could never be updated again (B-27).
# The sed in the else branch is what the older "-lite"/"-lite-systemd" names
# needed; it stays for a snapshot branch that still builds one, and is a no-op
# for upstream's own products.
#
# The LXC products (task 34) are the one pair whose upstream PRODUCT and PLATFORM differ:
# upstream's configs are lxc_amd64 / lxc_arm64 and board/post-build.sh writes PLATFORM from the
# Makefile's PRODUCT_PLATFORM, which strips the "_amd64"/"_arm64" - so PLATFORM=lxc, which is
# what every "HM_HOST =~ oci|lxc" test in the init scripts looks for.
#
# Test: scripts/testcases/lite-version-file-test.sh

set -e
TARGET_DIR=${1:?usage: version-file.sh <target dir>}

LITE_UPSTREAM_PLATFORM=""
case "${PRODUCT}" in
	aarch64-rpi3)   LITE_UPSTREAM_PRODUCT="rpi3" ;;
	aarch64-rpi4)   LITE_UPSTREAM_PRODUCT="rpi4" ;;
	aarch64-rpi5)   LITE_UPSTREAM_PRODUCT="rpi5" ;;
	x86_64-ova)     LITE_UPSTREAM_PRODUCT="ova"  ;;
	lxc-lite_amd64) LITE_UPSTREAM_PRODUCT="lxc_amd64"; LITE_UPSTREAM_PLATFORM="lxc" ;;
	lxc-lite_arm64) LITE_UPSTREAM_PRODUCT="lxc_arm64"; LITE_UPSTREAM_PLATFORM="lxc" ;;
	*)              LITE_UPSTREAM_PRODUCT=""     ;;
esac
if [ -n "${LITE_UPSTREAM_PRODUCT}" ]; then
	sed -i -e "s/^PRODUCT=.*/PRODUCT=${LITE_UPSTREAM_PRODUCT}/" -e "s/^PLATFORM=.*/PLATFORM=${LITE_UPSTREAM_PLATFORM:-${LITE_UPSTREAM_PRODUCT}}/" "${TARGET_DIR}/VERSION"
else
	sed -i -e 's/^PRODUCT=\(.*\)-lite\(-systemd\)\?\(_.*\)\?$/PRODUCT=\1\3/' -e 's/^PLATFORM=\(.*\)-lite\(-systemd\)\?$/PLATFORM=\1/' "${TARGET_DIR}/VERSION"
fi
grep -q "^VARIANT=" "${TARGET_DIR}/VERSION" || echo "VARIANT=lite" >>"${TARGET_DIR}/VERSION"

# D-44 (was D-37): VERSION is the firmware version of the OpenCCU base, LITE openccu-lite's own
# semantic version, the release identity occulited shows and compares against the feed.
# Task 396 (maintainer, 2026-10-25): VERSION has the three parts of the eQ-3/OpenCCU-Base release
# (3.89.11), as a CCU3's /VERSION does, not OpenCCU's tag with its build date (3.89.11.20260919);
# BASE in LITE-VERSION keeps the full OpenCCU tag the branch is rebased on. hmipserver's getVersion
# answers this line, and the classic tools read it as the CCU firmware version.
if [ -n "${LITE_BASE:-}" ]; then
	LITE_FIRMWARE=$(echo "${LITE_BASE}" | cut -d. -f1-3)
	if ! echo "${LITE_FIRMWARE}" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
		echo "version-file.sh: BASE=${LITE_BASE} in LITE-VERSION is not <major>.<minor>.<patch>[.<date>]" >&2
		exit 1
	fi
	sed -i -e "s/^VERSION=.*/VERSION=${LITE_FIRMWARE}/" "${TARGET_DIR}/VERSION"
	grep -q "^LITE=" "${TARGET_DIR}/VERSION" || echo "LITE=${LITE_VERSION:-0.0.0}" >>"${TARGET_DIR}/VERSION"
fi
