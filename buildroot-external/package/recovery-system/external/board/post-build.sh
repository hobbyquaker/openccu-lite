#!/bin/sh
# shellcheck source=/dev/null
#
# post-build.sh script with common stuff todo for all platforms
#

# Stop on error
set -e

# make sure VERSION exists in root of recoveryfs
#
# openccu-lite (B-27): the recovery's own /VERSION is what fwinstall.sh compares an image against
# - every "incorrect hardware platform (X != Y)" in it reads PLATFORM from *this* file, because
# fwinstall runs inside the recovery. board/lite/post-build.sh rewrites the *image's* PRODUCT and
# PLATFORM to upstream's names (D-31) so that OpenCCU's recovery accepts a lite image; without the
# same rewrite here, the recovery a lite image installs says "x86_64-ova" while every lite image
# says "ova", and the box can never be updated again - measured on the lab box when the product
# was still called ova-lite-systemd:
#
#   [5/5] Checking for image file... found, ERROR: incorrect hardware platform (ova != ova-lite-systemd)
#
# The mapping is the one in board/lite/post-build.sh and the two must be changed together; it is a
# no-op for upstream's products, whose PRODUCT is none of the D-39/D-43 names.
case "${PRODUCT}" in
	aarch64-rpi3) LITE_UPSTREAM_PRODUCT="rpi3" ;;
	aarch64-rpi4) LITE_UPSTREAM_PRODUCT="rpi4" ;;
	aarch64-rpi5) LITE_UPSTREAM_PRODUCT="rpi5" ;;
	x86_64-ova)   LITE_UPSTREAM_PRODUCT="ova"  ;;
	*)            LITE_UPSTREAM_PRODUCT=""     ;;
esac
if [ -n "${LITE_UPSTREAM_PRODUCT}" ]; then
	LITE_PRODUCT="${LITE_UPSTREAM_PRODUCT}"
	LITE_PLATFORM="${LITE_UPSTREAM_PRODUCT}"
else
	LITE_PRODUCT=$(echo "${PRODUCT}" | sed -e 's/^\(.*\)-lite\(-systemd\)\?\(_.*\)\?$/\1\3/')
	LITE_PLATFORM=$(echo "${PRODUCT_PLATFORM}" | sed -e 's/^\(.*\)-lite\(-systemd\)\?$/\1/')
fi
# fwinstall.sh refuses every image when this PLATFORM is empty ("ERROR: (BOOTFS_PLATFORM)"): a
# recovery built without the top-level Makefile's PRODUCT (a `make -C build-<product>
# recovery-system-rebuild`) would install fine and then never install anything again - dev.21's did.
if [ -z "${LITE_PLATFORM}" ] || [ -z "${LITE_PRODUCT}" ]; then
	echo "recovery post-build: ERROR: PRODUCT/PRODUCT_PLATFORM are empty - build the recovery through the top-level Makefile (make PRODUCT=<product> ...), not with make -C build-<product>" >&2
	exit 1
fi
echo "VERSION=${BR2_RECOVERY_SYSTEM_VERSION}" >"${TARGET_DIR}/VERSION"
echo "PRODUCT=${LITE_PRODUCT}" >>"${TARGET_DIR}/VERSION"
echo "PLATFORM=${LITE_PLATFORM}" >>"${TARGET_DIR}/VERSION"

# Define parameters with default values
# (openccu-lite: its own DHCP vendor class, as the system's /etc/dhcp-vendor-class - B-243)
DHCP_VENDOR_ID=openccu-lite
 
# Load product specific parameters
if [ -r "${TARGET_DIR}/etc/product" ]; then
  . "${TARGET_DIR}/etc/product"
fi

# Replace vendor ID in interfaces
sed -i "s/eQ3-CCU3/${DHCP_VENDOR_ID}/g" "${TARGET_DIR}/etc/network/interfaces"
grep -q -- "-V ${DHCP_VENDOR_ID}\$" "${TARGET_DIR}/etc/network/interfaces" || {
	echo "recovery post-build: ERROR: the DHCP vendor class ${DHCP_VENDOR_ID} is not in etc/network/interfaces" >&2
	exit 1
}

# rename some stuff buildroot introduced but we need differently
[ -e "${TARGET_DIR}/etc/init.d/S10udevd" ] && mv -f "${TARGET_DIR}/etc/init.d/S10udevd" "${TARGET_DIR}/etc/init.d/S00udevd"

# remove unnecessary stuff from TARGET_DIR
rm -f "${TARGET_DIR}/etc/init.d/S35iptables"
