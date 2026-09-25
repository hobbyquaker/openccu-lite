#!/bin/sh
#
# post-build.sh script with common stuff todo for all platforms
#

# Stop on error
set -e

# create VERSION file
echo "VERSION=${PRODUCT_VERSION}" >"${TARGET_DIR}/VERSION"
echo "PRODUCT=${PRODUCT}" >>"${TARGET_DIR}/VERSION"
echo "PLATFORM=${PRODUCT_PLATFORM}" >>"${TARGET_DIR}/VERSION"

# fix some permissions
[ -e "${TARGET_DIR}/etc/monitrc" ] && chmod 600 "${TARGET_DIR}/etc/monitrc"

# rename some stuff buildroot introduced but we need differently
[ -e "${TARGET_DIR}/etc/init.d/S10udevd" ] && mv -f "${TARGET_DIR}/etc/init.d/S10udevd" "${TARGET_DIR}/etc/init.d/S00udevd"

# remove unnecessary stuff from TARGET_DIR
rm -f "${TARGET_DIR}/etc/init.d/S50crond"
rm -f "${TARGET_DIR}/etc/init.d/S35iptables"

# remove the init scripts of optional packages this platform does not build: the overlays
# carry one for every daemon a platform may select, and without its daemon a script is dead
# weight in /etc/init.d (each exits at its "test -x", but is still listed and started)
for initscript_pkg in \
	S40bluetoothd:BR2_PACKAGE_BLUEZ5_UTILS \
	S49xinetd:BR2_PACKAGE_XINETD \
	S50ser2net:BR2_PACKAGE_SER2NET \
	S51nut:BR2_PACKAGE_NUT \
	S59snmpd:BR2_PACKAGE_NETSNMP \
	S60openvpn:BR2_PACKAGE_OPENVPN; do
	if ! grep -q "^${initscript_pkg#*:}=y$" "${BR2_CONFIG}"; then
		rm -f "${TARGET_DIR}/etc/init.d/${initscript_pkg%%:*}"
	fi
done

# link VERSION in /boot on rootfs
mkdir -p "${TARGET_DIR}/boot"
ln -sf ../VERSION "${TARGET_DIR}/boot/VERSION"
