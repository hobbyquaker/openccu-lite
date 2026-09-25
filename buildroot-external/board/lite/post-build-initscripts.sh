#!/bin/sh
#
# openccu-lite: /etc/init.d on the systemd products (task 20, B-3, task 129, task 115).
#
# systemd does not run /etc/init.d/S* - every script the lite image keeps has a unit in
# overlay/lite that names it. What is left in /etc/init.d afterwards is the compatibility entry
# point for addons and people who call the scripts by hand, and nothing else:
#
#   - the radio chain's scripts leave the image: occulited's `radio run`
#     (occu-init-rf-hardware.service) does what S47InitRFHardware, S49hs485d, S60multimacd,
#     S61rfd and S62HMServer rendered, the daemon units start the daemons directly,
#     S48UpdateRFHardware's firmware compare is occulited's Interfaces page (D-89), S60hs485d's
#     start is hs485d.service, and the LAN gateway steps S58LGWFirmwareUpdate and S59SetLGWKey
#     (with /bin/setlgwkey.sh) are occulited's `radio lgw-firmware` and `radio lgw-keys` in their
#     units (D-99). The scripts stay in the source overlays for the differential harness
#     (scripts/testcases/lite-radio-oracle-test.sh), which runs them as the oracle of the plan
#     (task 129, D-83);
#   - rcS and rcK, busybox init's runners, leave the image: nothing runs them under systemd
#     (task 115). What rcS did around the scripts is occu-ldconfig, lite-psplash and
#     occu-boot-message;
#   - every script named in /usr/lib/systemd/openccu-lite-initscripts is renamed to
#     /etc/init.d/<name>.script and the original path becomes a symlink to
#     /usr/libexec/occu/initscript-wrapper (B-3). Addons and people call these scripts by hand -
#     RedMatic's uninstall restarts lighttpd after removing its lighttpd config - and under
#     systemd that ran the daemon outside its unit while the unit stayed "active (exited)":
#     lighttpd and sshd dead with the box still up. The wrapper maps start|stop|restart|reload
#     to systemctl and passes everything else to the script. The units' Exec lines call the
#     .script path directly;
#   - a script whose table row says "-" has no unit on this product (S07logging is journald's
#     job, S11InitLEDs is part of occu-leds): the wrapper answers "ignored" for it, and the
#     script itself is not shipped (task 115). The symlink stays - eQ3StartNetwork calls
#     "/etc/init.d/S07logging restart";
#   - what is left of a script that left an overlay (B-101) - its renamed original without the
#     symlink - is removed. A clean build never has one.
#
# The init scripts of optional packages (S40bluetoothd, S49xinetd, S50ser2net, S51nut,
# S59snmpd, S60openvpn) are not this script's business: board/post-build.sh removes each of
# them on every product whose configuration does not build its package.
#
# run-parts over /usr/local/etc/config/rc.d is untouched: those are the addon generator's job.
#
# Called as: post-build-initscripts.sh <target dir>
set -e
TARGET_DIR=${1:?usage: post-build-initscripts.sh <target dir>}

for lite_radio_script in S47InitRFHardware S48UpdateRFHardware S49hs485d S60hs485d S60multimacd S61rfd S62HMServer S58LGWFirmwareUpdate S59SetLGWKey; do
	rm -f "${TARGET_DIR}/etc/init.d/${lite_radio_script}" "${TARGET_DIR}/etc/init.d/${lite_radio_script}.script"
done
rm -f "${TARGET_DIR}/bin/setlgwkey.sh"

rm -f "${TARGET_DIR}/etc/init.d/rcS" "${TARGET_DIR}/etc/init.d/rcK"

LITE_INITSCRIPT_TABLE="${TARGET_DIR}/usr/lib/systemd/openccu-lite-initscripts"
LITE_INITSCRIPT_WRAPPER="/usr/libexec/occu/initscript-wrapper"
if [ ! -r "${LITE_INITSCRIPT_TABLE}" ]; then
	echo "post-build-initscripts: ERROR: ${LITE_INITSCRIPT_TABLE} is missing" >&2
	exit 1
fi
if [ ! -x "${TARGET_DIR}${LITE_INITSCRIPT_WRAPPER}" ]; then
	echo "post-build-initscripts: ERROR: ${LITE_INITSCRIPT_WRAPPER} is not in the target" >&2
	exit 1
fi
while read -r lite_script lite_unit lite_rest; do
	case "${lite_script}" in ''|\#*) continue ;; esac
	lite_path="${TARGET_DIR}/etc/init.d/${lite_script}"
	if [ "${lite_unit}" = "-" ]; then
		# no unit on this product: the wrapper alone, which answers "ignored"; the script is not
		# shipped, and a previous build's renamed copy goes too (incremental build)
		rm -f "${lite_path}.script"
		if [ ! -L "${lite_path}" ]; then
			rm -f "${lite_path}"
			ln -sf "../..${LITE_INITSCRIPT_WRAPPER}" "${lite_path}"
		fi
		continue
	fi
	if [ ! -e "${TARGET_DIR}/usr/lib/systemd/system/${lite_unit}" ] &&
	   [ ! -e "${TARGET_DIR}/etc/systemd/system/${lite_unit}" ] &&
	   [ "${lite_unit#systemd-}" = "${lite_unit}" ]; then
		echo "post-build-initscripts: WARNING: ${lite_script} maps to ${lite_unit}, which is not in the image" >&2
	fi
	if [ -L "${lite_path}" ]; then
		continue	# already wrapped (incremental build without an overlay rsync)
	fi
	if [ ! -f "${lite_path}" ]; then
		echo "post-build-initscripts: WARNING: ${lite_script} is in the unit table but not in /etc/init.d" >&2
		continue
	fi
	mv -f "${lite_path}" "${lite_path}.script"
	ln -sf "../..${LITE_INITSCRIPT_WRAPPER}" "${lite_path}"
done <"${LITE_INITSCRIPT_TABLE}"

# what is left of an init script that left an overlay (B-101): <name>.script without <name>
for lite_orphan in "${TARGET_DIR}"/etc/init.d/*.script; do
	[ -f "${lite_orphan}" ] || continue
	lite_base="${lite_orphan%.script}"
	if [ ! -e "${lite_base}" ] && [ ! -L "${lite_base}" ]; then
		rm -f "${lite_orphan}"
		echo "post-build-initscripts: removed ${lite_orphan#"${TARGET_DIR}"}, its init script left the overlays"
	fi
done
