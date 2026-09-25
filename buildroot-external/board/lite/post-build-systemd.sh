#!/bin/sh
#
# openccu-lite: post-build steps of the systemd products (task 20, D-30)
#
# Listed after board/lite/post-build.sh in BR2_ROOTFS_POST_BUILD_SCRIPT of
# every lite product with BR2_INIT_SYSTEMD.
#

# Stop on error
set -e

# overlay/base ships /run as a symlink to var/run: busybox init keeps the
# pid files on the tmpfs /var. systemd's skeleton has /var/run -> ../run
# instead, and PID 1 mounts a tmpfs on /run before anything else, which a
# symlink loop cannot take. The overlay rsync keeps directory links, so
# the symlink survives it and is undone here: /run is a directory, /var/run
# points to it (systemd-tmpfiles recreates that link on the tmpfs /var at
# every boot).
if [ -L "${TARGET_DIR}/run" ]; then
	rm -f "${TARGET_DIR}/run"
	mkdir -p "${TARGET_DIR}/run"
fi
if [ ! -L "${TARGET_DIR}/var/run" ]; then
	rm -rf "${TARGET_DIR}/var/run"
	ln -s ../run "${TARGET_DIR}/var/run"
fi

# openccu-lite (B-109): /var/run stays that link at boot. usbmount, which udev runs for a USB stick
# during the coldplug, made it a directory on the fresh /var tmpfs before systemd-tmpfiles-setup
# linked it, and every pid file then missed its unit. usbmount-run-dir.sh moves usbmount's lock to
# /run/usbmount and fails the build if the script still names /var; overlay/lite's
# usr/lib/tmpfiles.d/lite-var-run.conf (L+) replaces such a directory should anything else write there.
sh "$(dirname "$0")/usbmount-run-dir.sh" "${TARGET_DIR}"

# openccu-lite (task 161): a USB stick is mounted by occu-usb-mount@.service in the host's namespace
# (63-openccu-lite-usb-storage.rules); usbmount.rules would run usbmount a second time inside
# udevd's private mounts, where the mount helps nobody and holds the stick.
rm -f "${TARGET_DIR}/lib/udev/rules.d/usbmount.rules" "${TARGET_DIR}/usr/lib/udev/rules.d/usbmount.rules"

# Busybox.config is shared with the busybox-init products and keeps the
# init applet, so busybox installs an /sbin/init of its own; systemd's
# install links it to systemd afterwards, but PID 1 is not something to
# leave to package order.
if [ "$(readlink -f "${TARGET_DIR}/sbin/init")" != "$(readlink -f "${TARGET_DIR}/usr/lib/systemd/systemd")" ]; then
	ln -sf ../lib/systemd/systemd "${TARGET_DIR}/sbin/init"
fi

# openccu-lite (B-12): repair the 32-bit ELF interpreter link.
#
# package/multilib32 unpacks a second, non-merged buildroot into /lib32 and /usr/lib32 and then
# does "ln -sf ../lib32/ld-linux.so.2 $(TARGET_DIR)/lib/" (ld-linux-armhf.so.3 on aarch64). On
# upstream's split-/usr target that lands in /lib and resolves to /lib32/ld-linux*, which is where
# the loader is. Here /lib is a symlink to usr/lib, so the link lands in /usr/lib and resolves to
# /usr/lib32/ld-linux*, where it is not: the link dangles and every 32-bit binary fails to exec,
# because /lib/ld-linux* is the interpreter path compiled into them. Point it at the real loader
# (from /usr/lib, "../.." is the root). Nothing 32-bit is executed on the x86 products - only the
# libraries are there - but the ARM products carry eQ-3's 32-bit pieces.
for lite_loader in "${TARGET_DIR}"/lib32/ld-linux*.so.*; do
	[ -e "${lite_loader}" ] || continue
	lite_loader_name=$(basename "${lite_loader}")
	if [ ! -e "${TARGET_DIR}/usr/lib/${lite_loader_name}" ]; then
		ln -sf "../../lib32/${lite_loader_name}" "${TARGET_DIR}/usr/lib/${lite_loader_name}"
	fi
done

# openccu-lite (B-11): repair /usr/bin/tclsh.
#
# package/openccu-base (package/occu until 3.89.8) ends its finalize hook with
# "ln -snf /usr/bin/tclsh $(TARGET_DIR)/bin/tclsh",
# which is right on upstream's target, where /bin and /usr/bin are separate directories and tcl
# has installed /usr/bin/tclsh -> tclsh8.6. systemd selects BR2_ROOTFS_MERGED_USR, so here /bin
# *is* /usr/bin and that command replaces tcl's link with a link to itself. Every Tcl script on
# the box then dies with ELOOP: setfirewall.tcl (and with it the firewall, the SSH switch and
# the network apply), the eQ-3 helper scripts, and every addon settings page - lighttpd's
# cgi.assign maps ".cgi" to /bin/tclsh. Point the link back at the interpreter tcl installed.
# The test is on the link's *text*, not "[ -e ]": the link says /usr/bin/tclsh, an absolute path,
# and a test on the build host follows it out of the target root to the host's own /usr/bin/tclsh -
# which exists on any machine with tcl installed, so "[ ! -e ]" was false and the repair was
# skipped. That cost one image. Resolve the target inside TARGET_DIR and repair when it is this
# very file or is not there.
lite_tclsh="${TARGET_DIR}/usr/bin/tclsh"
if [ -L "${lite_tclsh}" ]; then
	lite_tclsh_to=$(readlink "${lite_tclsh}")
	case "${lite_tclsh_to}" in
		/*) lite_tclsh_dest="${TARGET_DIR}${lite_tclsh_to}" ;;
		*)  lite_tclsh_dest="${TARGET_DIR}/usr/bin/${lite_tclsh_to}" ;;
	esac
	if [ "${lite_tclsh_dest}" = "${lite_tclsh}" ] || [ ! -e "${lite_tclsh_dest}" ]; then
		lite_tclsh_real=$(cd "${TARGET_DIR}/usr/bin" && ls -1 tclsh[0-9]* 2>/dev/null | head -n 1)
		if [ -z "${lite_tclsh_real}" ]; then
			echo "post-build-systemd: ERROR: /usr/bin/tclsh points at ${lite_tclsh_to} and no tclsh<version> is in the target" >&2
			exit 1
		fi
		ln -sf "${lite_tclsh_real}" "${lite_tclsh}"
		echo "post-build-systemd: /usr/bin/tclsh ${lite_tclsh_to} -> ${lite_tclsh_real} (B-11)"
	fi
fi

# openccu-lite: /etc/init.d as the compatibility entry point (B-3, task 129, task 115). The
# radio chain's scripts and busybox init's rcS/rcK leave the image, every script with a unit is
# renamed to <name>.script behind the init-script wrapper, a script whose table row says "-" is
# the wrapper alone, and a renamed original whose script left an overlay (B-101) is removed.
# post-build-initscripts.sh has the whole story; scripts/testcases/lite-initscripts-test.sh runs
# it on a fake target.
sh "$(dirname "$0")/post-build-initscripts.sh" "${TARGET_DIR}"

# openccu-lite: every unit a lite unit orders against or pulls in exists in the image. An After= on
# a unit that is not there orders nothing, silently. The boot splash is the one unit that exists
# only on the products that build psplash.
lite_refs_allowed=
[ -e "${TARGET_DIR}/usr/lib/systemd/system/psplash-start.service" ] || lite_refs_allowed="psplash-start.service"
# shellcheck disable=SC2086
if ! sh "$(cd "$(dirname "$0")/../../.." && pwd)/scripts/lite-unit-refs.sh" "${TARGET_DIR}" ${lite_refs_allowed}; then
	echo "post-build-systemd: ERROR: a lite unit names a unit the image does not have (above)" >&2
	exit 1
fi

# openccu-lite (B-5): /etc/issue is on the read-only rootfs; occu-boot-message.service writes the
# end-of-boot hint to /run/issue and a getty reads it through this link.
rm -f "${TARGET_DIR}/etc/issue"
ln -s ../run/issue "${TARGET_DIR}/etc/issue"
