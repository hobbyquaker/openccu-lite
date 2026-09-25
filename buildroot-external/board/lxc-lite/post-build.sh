#!/bin/sh
#
# openccu-lite (task 34): post-build steps of the Proxmox LXC products, lxc-lite_amd64 and
# lxc-lite_arm64. Listed last in BR2_ROOTFS_POST_BUILD_SCRIPT, after board/lxc/post-build.sh
# (upstream's removals: ZRAM, USB gadget, rngd, bluetooth, chronyd, irqbalance, udevd, usbmount,
# sysctl) and the two lite scripts. What is left to do here is the systemd side of those
# removals plus what an *unprivileged* container cannot use at all:
#
#   - no hardware watchdog: PID 1 has no /dev/watchdog and RuntimeWatchdogSec= would only log
#     an error at every boot;
#   - no time daemon: the clock is the host's, settimeofday is EPERM in an unprivileged CT and
#     chrony is not even built for this product (the unit would point at a script upstream's
#     post-build has just deleted);
#   - no udev: /sys is read-only inside the container and the host owns the devices; the udev
#     units are masked rather than deleted so that a rebase that renames one cannot bring it
#     back enabled;
#   - no hardware clock: S02InitRTC probes I2C RTCs and loads modules, none of which a
#     container may do.
#
# Every unit taken out here has an init script that upstream's board/lxc/post-build.sh removes
# or a device that the container does not have; the table in
# overlay/lite/usr/lib/systemd/openccu-lite-initscripts is untouched (a script that is not in the
# image only draws a warning from post-build-systemd.sh).
#

# Stop on error
set -e

# Remove a unit (service, timer, socket) and every enablement link buildroot's preset made
# for it, so that nothing in a .wants/ directory dangles.
lite_drop_unit() {
	rm -f "${TARGET_DIR}/usr/lib/systemd/system/$1" "${TARGET_DIR}/etc/systemd/system/$1"
	find "${TARGET_DIR}/etc/systemd/system" "${TARGET_DIR}/usr/lib/systemd/system" -type l -name "$1" -delete 2>/dev/null || true
}

# Mask a unit: /etc/systemd/system/<unit> -> /dev/null wins over the shipped file and over any
# .wants/ link.
lite_mask_unit() {
	rm -f "${TARGET_DIR}/etc/systemd/system/$1"
	ln -s /dev/null "${TARGET_DIR}/etc/systemd/system/$1"
}

# the watchdog feeder in PID 1 (overlay/lite/etc/systemd/system.conf.d/lite-watchdog.conf)
rm -f "${TARGET_DIR}/etc/systemd/system.conf.d/lite-watchdog.conf"

# the time daemon (S46chronyd is gone, see above; timesyncd is not built, D-30)
lite_drop_unit chrony.service

# the hardware clock
lite_drop_unit occu-init-rtc.service

# the units whose init scripts upstream's board/lxc/post-build.sh removed
lite_drop_unit occu-zram-swap.service
lite_drop_unit occu-usb-gadget.service

# udev: masked. systemd-udevd would not start anyway (ConditionPathIsReadWrite=/sys), but a
# masked unit says so in "systemctl status" instead of sitting in the "failed" list.
for lite_unit in systemd-udevd.service systemd-udevd-control.socket systemd-udevd-kernel.socket systemd-udev-trigger.service systemd-udev-settle.service; do
	lite_mask_unit "${lite_unit}"
done

# fstrim on a container's filesystems is the host's business; the rootfs is a subvolume and
# "fstrim --listed-in fstab" inside the container finds nothing it may trim.
lite_drop_unit occu-fstrim.timer
lite_drop_unit occu-fstrim.service

# no kernel filesystems to mount in a container: configfs and debugfs are the host's, and the two
# mount units otherwise sit in "systemctl --failed" on every boot (seen on the first CT, 2026-09-09)
for lite_unit in sys-kernel-config.mount sys-kernel-debug.mount; do
	lite_mask_unit "${lite_unit}"
done

# the factory-reset marker: S04CheckFactoryReset (occu-factory-reset.service) empties
# /usr/local on the first boot when it finds this file, which is what a fresh template wants.
# Upstream's board/lxc/post-image.sh touches it in post-image - i.e. *after* rootfs.tar has been
# packed, so it only reaches the tarball of the next incremental build. Here it is set in
# post-build, and board/lxc-lite/post-image.sh checks that the tarball really carries it. With a
# Proxmox mount point on /usr/local the marker is hidden underneath the mount and the empty
# volume is used as it is; without one the container's own /usr/local is emptied once.
touch "${TARGET_DIR}/usr/local/.doFactoryReset"

# the interface daemons' device policies: no udev inside the container, so the host maps the
# nodes (install-lxc.sh allows every char device), and a DevicePolicy= may not be applied in a
# nested cgroup - a unit that fails on that is not acceptable. The users, the sandbox and the
# node groups (set by lite-radio-prep) stay; only the device drop-in goes.
for lite_unit in multimacd rfd hmipserver hs485d hmlangw; do
	rm -f "${TARGET_DIR}/usr/lib/systemd/system/${lite_unit}.service.d/20-devices.conf"
	rmdir "${TARGET_DIR}/usr/lib/systemd/system/${lite_unit}.service.d" 2>/dev/null || true
done
# the loop driver is the host's: nothing to load inside the container
rm -f "${TARGET_DIR}/usr/lib/modules-load.d/openccu-lite-radio.conf"
