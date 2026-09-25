#!/bin/sh
#
# openccu-lite (task 111): no smartd on a lite image, and smartctl only on the products that build
# smartmontools.
#
# smartd had nothing to do here. An SD card, an eMMC and a USB stick have no SMART - with a stick
# plugged at boot the unit's /dev/sd* condition passed and smartd exited 17, a failed unit at every
# boot (B-125) - a VM's or a container's disks are the host's to watch, and nothing on the box read
# smartd's reports. The Status page's storage panel reads SMART itself, once an hour, through the
# privilege helper's smartctl operation. So the hardware products (aarch64-rpi*) keep smartctl and
# lose the daemon, its unit, any drop-in, its enable link and its configuration; the VM and the
# container products do not build smartmontools at all (their configs say "is not set").
#
# This runs from board/lite/post-build.sh, after every package has installed, so a reinstall that
# the overlay prune of an incremental build asks for (B-101) cannot bring the files back; systemd's
# preset-all runs later, at the rootfs step, and without the unit file it enables nothing. Buildroot
# never removes the files of a package that was switched off, so on a product without
# BR2_PACKAGE_SMARTMONTOOLS what an earlier build of the same output directory left goes too.
#
# The build stops when a smartd file is left anywhere in the target (a path this script does not
# know yet), when a systemd preset names smartd, when a product that builds smartmontools has no
# smartctl, and when a product that does not still has one.
#
# Usage: no-smartd.sh <target dir> <buildroot .config>
#   board/lite/post-build.sh runs it with $BR2_CONFIG; scripts/testcases/lite-smartd-test.sh on fake
#   targets.
set -e
TARGET=${1:?usage: no-smartd.sh <target dir> <buildroot .config>}
CONFIG=${2:?usage: no-smartd.sh <target dir> <buildroot .config>}
[ -d "${TARGET}" ] || { echo "no-smartd: ERROR: ${TARGET} is not a directory" >&2; exit 1; }
[ -f "${CONFIG}" ] || { echo "no-smartd: ERROR: no buildroot configuration at ${CONFIG}" >&2; exit 1; }

smartctl_built=no
if grep -q '^BR2_PACKAGE_SMARTMONTOOLS=y$' "${CONFIG}"; then
	smartctl_built=yes
fi

# remove <path below the target>...: files, links and directories; each one that was there is named
remove() {
	for rel in "$@"; do
		f="${TARGET}/${rel}"
		if [ -e "${f}" ] || [ -L "${f}" ]; then
			rm -rf "${f}"
			echo "no-smartd: removed /${rel}"
		fi
	done
}

# the daemon (usr/sbin is a link to bin on the merged /usr of the systemd products; both spellings
# for a split one), its unit with any drop-in, its configuration and its warning hooks
remove usr/sbin/smartd usr/bin/smartd \
	usr/lib/systemd/system/smartd.service usr/lib/systemd/system/smartd.service.d \
	etc/systemd/system/smartd.service etc/systemd/system/smartd.service.d \
	etc/smartd.conf etc/smartd_warning.sh etc/smartd_warning.d

# the enable links an earlier build's preset-all left in this output directory
for f in "${TARGET}"/etc/systemd/system/*.wants/smartd.service "${TARGET}"/usr/lib/systemd/system/*.wants/smartd.service; do
	if [ -L "${f}" ] || [ -e "${f}" ]; then
		rm -f "${f}"
		echo "no-smartd: removed ${f#"${TARGET}"}"
	fi
done

# the VM and the container products: what an earlier build with smartmontools left
if [ "${smartctl_built}" = no ]; then
	remove usr/sbin/smartctl usr/bin/smartctl \
		usr/sbin/update-smart-drivedb usr/bin/update-smart-drivedb \
		usr/share/smartmontools
fi

# the checks
left=$(find "${TARGET}" \( -name smartd -o -name 'smartd.*' -o -name 'smartd_*' \) -print)
if [ -n "${left}" ]; then
	echo "no-smartd: ERROR: smartd files are still in the target; add their paths to this script:" >&2
	echo "${left}" | while IFS= read -r f; do echo "  ${f#"${TARGET}"}" >&2; done
	exit 1
fi
# (only the preset directories that exist: grep answers 2 for a missing one even after a match)
for d in "${TARGET}/usr/lib/systemd/system-preset" "${TARGET}/etc/systemd/system-preset"; do
	[ -d "${d}" ] || continue
	if grep -rn 'smartd' "${d}" >&2; then
		echo "no-smartd: ERROR: a systemd preset names smartd (the lines above)" >&2
		exit 1
	fi
done
if [ "${smartctl_built}" = yes ]; then
	if [ ! -x "${TARGET}/usr/bin/smartctl" ] && [ ! -x "${TARGET}/usr/sbin/smartctl" ]; then
		echo "no-smartd: ERROR: the product builds smartmontools and smartctl is not in the target; the storage panel's SMART read needs it" >&2
		exit 1
	fi
else
	left=$(find "${TARGET}" \( -name smartctl -o -name update-smart-drivedb \) -print)
	if [ -n "${left}" ]; then
		echo "no-smartd: ERROR: the product does not build smartmontools and these are still in the target:" >&2
		echo "${left}" | while IFS= read -r f; do echo "  ${f#"${TARGET}"}" >&2; done
		exit 1
	fi
fi
exit 0
