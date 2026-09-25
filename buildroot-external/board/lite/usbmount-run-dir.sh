#!/bin/sh
#
# openccu-lite (B-109): usbmount keeps its lock directory under /run, never under /var/run.
#
# udev runs /usr/share/usbmount/usbmount for every sd*, ub* and mmcblk* device, during the coldplug
# too, and the coldplug is ordered against nothing but sysinit.target. The script began with
# "mkdir -p /var/run/usbmount". Between var.mount (an empty tmpfs on /var) and
# systemd-tmpfiles-setup (the /var/run -> ../run link) that mkdir made /var/run a real directory.
# tmpfiles' "L" leaves a directory alone, so every daemon wrote its pid file where its unit does not
# look, and hmipserver, sshd, chrony and crond hung in "activating" and restarted in loops. It took a
# USB stick at boot - with or without a filesystem, the mkdir comes first - and a udev worker that
# ran after the /var mount; on the Charly that gap is about two seconds (tmpfiles waits for journald,
# which waits for the machine ID on the userfs). /run is PID 1's tmpfs from the first instant.
#
# The lite tmpfiles entry L+ /var/run repairs the link if anything else ever writes there early.
#
# Usage: usbmount-run-dir.sh <target dir>
#   post-build-systemd.sh runs it on the target; scripts/testcases/lite-unit-order-test.sh on a copy.
set -e
TARGET=${1:?usage: usbmount-run-dir.sh <target dir>}
F="${TARGET}/usr/share/usbmount/usbmount"
[ -f "${F}" ] || exit 0

sed -i 's|/var/run/usbmount|/run/usbmount|g' "${F}"

# A program run from a udev rule writes nothing under /var. The check is on code lines, not comments.
if grep -n -v '^[[:space:]]*#' "${F}" | grep '/var/'; then
	echo "usbmount-run-dir: ERROR: ${F#"${TARGET}"} still names /var on the lines above; a udev program must not write there" >&2
	exit 1
fi
