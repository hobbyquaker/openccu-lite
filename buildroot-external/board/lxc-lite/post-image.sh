#!/bin/bash
#
# openccu-lite (task 34): post-image step of the Proxmox LXC products. The template *is*
# buildroot's rootfs.tar (BR2_TARGET_ROOTFS_TAR, the default; upstream's lxc products ship the
# same file). Upstream's board/lxc/post-image.sh touches the factory-reset marker here, which is
# after the tarball has been packed - board/lxc-lite/post-build.sh sets it in time instead, and
# this script proves the tarball carries it, because a template without the marker would keep
# whatever a previous container left in /usr/local when the rootfs is reused without a mount
# point.
#

# Stop on error
set -e

TEMPLATE="${BINARIES_DIR}/rootfs.tar"
if [ ! -f "${TEMPLATE}" ]; then
	echo "post-image: ERROR: ${TEMPLATE} is missing - BR2_TARGET_ROOTFS_TAR must be set for an LXC product" >&2
	exit 1
fi
if ! tar -tf "${TEMPLATE}" ./usr/local/.doFactoryReset >/dev/null 2>&1; then
	echo "post-image: ERROR: ${TEMPLATE} does not carry usr/local/.doFactoryReset" >&2
	exit 1
fi
# systemd must be PID 1 of the template, and the template must say which platform it is
if ! tar -tf "${TEMPLATE}" ./usr/lib/systemd/systemd >/dev/null 2>&1; then
	echo "post-image: ERROR: ${TEMPLATE} has no /usr/lib/systemd/systemd" >&2
	exit 1
fi
echo "post-image: template $(stat -c %s "${TEMPLATE}") bytes, $(tar -tf "${TEMPLATE}" | wc -l) entries"
