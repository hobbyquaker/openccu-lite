#!/bin/sh
#
# openccu-lite: post-build steps shared by every lite product
#
# Runs after board/post-build.sh and the upstream board's post-build.sh; each
# lite product lists it last in BR2_ROOTFS_POST_BUILD_SCRIPT.
#

# Stop on error
set -e

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
# D-44 (was D-37): VERSION stays the OpenCCU base tag (what the recovery
# compares); LITE is openccu-lite's own semantic version, the release
# identity occulited shows and compares against the feed
if [ -n "${LITE_BASE:-}" ]; then
  sed -i -e "s/^VERSION=.*/VERSION=${LITE_BASE}/" "${TARGET_DIR}/VERSION"
  grep -q "^LITE=" "${TARGET_DIR}/VERSION" || echo "LITE=${LITE_VERSION:-0.0.0}" >>"${TARGET_DIR}/VERSION"
fi

# The firmware's own ReGa consumers. There is no ReGaHss here, so these
# would fail on every invocation; delete them rather than leave them to
# fail silently (roadmap task 12).
rm -f "${TARGET_DIR}/bin/updateDCVars.tcl"
# triggerAlarm.tcl has callers that stay in the image (cronBackup.sh, on both of its failure
# paths), so the systemd overlay ships a shell stand-in under the same name that writes the
# alarm to the journal (D-41, task 22). Only upstream's ReGa version is deleted.
if ! grep -q "openccu-lite" "${TARGET_DIR}/bin/triggerAlarm.tcl" 2>/dev/null; then
  rm -f "${TARGET_DIR}/bin/triggerAlarm.tcl"
fi
rm -f "${TARGET_DIR}/bin/checkHmIPconsistency.tcl"
rm -f "${TARGET_DIR}/bin/checkHmIPdevices.sh"
rm -f "${TARGET_DIR}/bin/checkPortForwarding.sh"

# The addon update check moves into the system service (D-23).
rm -f "${TARGET_DIR}/bin/checkAddonUpdates.sh"
# So does the firmware update check (B-244): occulited's update check (internal/sysupdate) replaced
# upstream's checkFirmwareUpdate.sh, which asked GitHub for OpenCCU's releases and could download
# one. Nothing starts it here (no cron line, no unit, not on the helper's program list), and a
# script that talks to the internet whenever anyone runs it does not belong in the image.
rm -f "${TARGET_DIR}/bin/checkFirmwareUpdate.sh"

# hss_led leaves the image (D-63, task 95): its health check needs ReGaHss, so it could only show
# red here, and occulited's status LED controller is the LED's one writer after the boot. Its udev
# rule gave the hssled group the rpi_rf_mod LEDs; the controller writes through its root helper.
# The starts in S06InitSystem and S47InitRFHardware test for the binary and do nothing without it.
rm -f "${TARGET_DIR}/bin/hss_led"
rm -f "${TARGET_DIR}/lib/udev/rules.d/82-hss_led.rules"

# eq3configd leaves the image (task 163, the maintainer 2026-09-18: "drop eq3configd, reply to
# 43439 from occulited ... no network configuration anymore with Netfinder on openccu-lite").
# occulited answers the discovery on UDP 43439 itself, with the type eQ3-HmIP-CCU3-App-lite, and
# refuses every other opcode: an openccu-lite system's network is changed on its Network page and
# nowhere else. What the daemon's unit did besides starting it - /var/ids, /etc/config/ids on a
# first start with a radio, and crypttool.cfg - is `occulited radio run`'s now. `eq3configcmd`
# stays: occu-update-rf-hardware flashes the coprocessors with it. The `eq3cfg` user stays in
# openccu-base's user table, which the classic products share, and is unused here.
rm -f "${TARGET_DIR}/bin/eq3configd"

# ssdpd leaves the image (D-108, task 165): occulited announces the system over SSDP itself and
# serves the UPnP description at the same path, /upnp/basic_dev.cgi. The Tcl CGI behind that path
# was already dead here - lighttpd proxies everything that is not /api or /addons to occulited, so
# the URL answered with the UI page instead of XML. The `ssdp` user stays in openccu-base's user
# table, which the classic products share; nothing on this image uses it.
rm -f "${TARGET_DIR}/bin/ssdpd"
rm -rf "${TARGET_DIR}/www/upnp"

# monit is not installed (D-23), so its configuration is dead weight.
rm -f "${TARGET_DIR}/etc/monitrc"

# No internet check (D-90): the box connects to the internet only when the user asks for it.
# checkInternet reached out to google.com three ways at every network start and DHCP renewal, and
# only wrote /var/status/hasInternet, which nothing here reads. eQ3StartNetwork and dhcp.script call
# it only where it is installed.
rm -f "${TARGET_DIR}/bin/checkInternet"

# occulited owns the firewall (task 157, D-105): its rules load at boot from occu-firewall.service,
# so OpenCCU's libfirewall and what sources it leave the image. eQ3StartNetwork calls setfirewall.tcl
# only where it is installed.
rm -f "${TARGET_DIR}/bin/setfirewall.tcl" "${TARGET_DIR}/lib/libfirewall.tcl" \
	"${TARGET_DIR}/lib/libsecuritylevel.tcl" "${TARGET_DIR}/bin/enforcesecuritylevel.tcl"

# The CA bundle ships prebuilt (D-89): the boot copies it instead of running
# update-ca-certificates, unless the user has added certificates (lite-ca-certificates).
sh "$(dirname "$0")/ca-prebuilt.sh" "${TARGET_DIR}" "${HOST_DIR:-}"

# No Node.js in the image (D-18), so the Home Assistant WebUI proxy
# cannot run.
rm -f "${TARGET_DIR}/bin/ha-proxy.js"
rm -f "${TARGET_DIR}/etc/init.d/S51ha-proxy"

# The journal is the one log (D-59, task 84). lighttpd's error log goes to syslog, which is
# journald's /dev/log here, instead of /var/log/lighttpd-error.log on the /var tmpfs; the access
# log is the lite overlay's conf.d/access_log.conf, off until the Log page switches it on.
# server.errorlog is set in upstream's lighttpd.conf itself, so it is replaced here rather than by
# a copy of that file. The build stops when the line is gone, so a rebase that moves it is noticed
# instead of shipping the file log again. (Measured on lighttpd 1.4.82: errorlog-use-syslog wins
# over a server.errorlog file anyway, but the file name would stay in the shipped config.)
LIGHTTPD_CONF="${TARGET_DIR}/etc/lighttpd/lighttpd.conf"
if grep -q '^server\.errorlog[[:space:]]*=' "${LIGHTTPD_CONF}"; then
	sed -i 's|^server\.errorlog[[:space:]]*=.*$|server.errorlog-use-syslog = "enable"|' "${LIGHTTPD_CONF}"
elif ! grep -q '^server\.errorlog-use-syslog[[:space:]]*=[[:space:]]*"enable"' "${LIGHTTPD_CONF}"; then
	echo "post-build (lite): no server.errorlog line to replace in ${LIGHTTPD_CONF}" >&2
	exit 1
fi

# buildroot's lighttpd package creates both log files at every boot through tmpfiles.d (its
# lighttpd_tmpfiles.conf has nothing else); with the logs in the journal they would only be empty
# files that look like a log.
rm -f "${TARGET_DIR}/usr/lib/tmpfiles.d/lighttpd.conf"

# lighttpd runs sandboxed as www-data (the lite lighttpd.service): its pid file goes into the
# unit's own runtime directory /run/lighttpd, the one place under /run it may write, instead of
# upstream's /var/run/lighttpd.pid, which the unit had to create for it as root. The line is
# upstream's lighttpd.conf's, so it is replaced here rather than by a copy of that file, and the
# build stops when it is gone, as for server.errorlog above. Nothing on a lite image reads the
# pid file: systemd tracks the angel, and occulited's Services page asks systemd.
if grep -q '^server\.pid-file[[:space:]]*=' "${LIGHTTPD_CONF}"; then
	sed -i 's|^server\.pid-file[[:space:]]*=.*$|server.pid-file = "/run/lighttpd/lighttpd.pid"|' "${LIGHTTPD_CONF}"
elif ! grep -q '^server\.pid-file[[:space:]]*=[[:space:]]*"/run/lighttpd/lighttpd.pid"' "${LIGHTTPD_CONF}"; then
	echo "post-build (lite): no server.pid-file line to replace in ${LIGHTTPD_CONF}" >&2
	exit 1
fi

# No mod_cgi on a lite image: the addons' CGIs run through occulited (conf.d/occulited.conf proxies
# all of /addons/ to it), the lite modules.conf loads neither the module nor conf.d/cgi.conf, and
# the base overlay's cgi.conf (".cgi" to tclsh, X-Sendfile from /usr/local/tmp) would only be a
# fragment nothing includes. The recovery system keeps its own copy for its own CGIs.
rm -f "${TARGET_DIR}/etc/lighttpd/conf.d/cgi.conf"

# Files that name log files nothing writes here: lighttpd's annotated sample configuration, which
# nothing loads, and logrotate's entry for busybox syslogd - neither logrotate nor syslogd's files
# exist on a lite image.
rm -f "${TARGET_DIR}/etc/lighttpd/lighttpd.annotated.conf"
rm -f "${TARGET_DIR}/etc/logrotate.d/syslogd.conf"
rmdir "${TARGET_DIR}/etc/logrotate.d" 2>/dev/null || true

# No smartd on any lite product, and smartctl only where the product builds smartmontools, for the
# storage panel's SMART read (task 111). The script says why, and stops the build when a smartd file
# is left.
sh "$(dirname "$0")/no-smartd.sh" "${TARGET_DIR}" "${BR2_CONFIG}"

# The boot splash shows the openccu-lite logo, and so does the recovery system's (task 112). The
# script stops the build when a product with psplash names another image.
sh "$(dirname "$0")/psplash-logo.sh" "${BR2_CONFIG}"

# The two guards of the 3.89.9 rebase (task 126, pitfalls 1 and 2). package/openccu-base installs
# the real tclrega.so and /bin/ReGaHss with BR2_PACKAGE_OPENCCU_BASE_REGAHSS and the complete WebUI
# with BR2_PACKAGE_OPENCCU_BASE_WEBUI; the lite configs switch both off, and merge_config.sh drops a
# symbol it does not know without a word. Nothing would fail at build time: the real tclrega asks a
# ReGaHss that does not run, and every addon settings page would refuse every session. So the build
# stops here when /lib/tclrega.so is not package/occulited's shim (it names the session directory)
# or when ReGaHss, its init script or a WebUI tree is in the image.
#
# /www/rega goes as a whole (task 179, the maintainer, 2026-09-19): its one file, OpenCCU-Base's
# licenseinfo.htm (upstream builds it without the WebUI too, #4183), is eQ-3's CCU3 list of 2018 and
# names packages this image does not ship. lite's licence information is the SBOM,
# /usr/share/openccu-lite/sbom.cdx.json.gz (post-build-sbom.sh), which occulited's /licenses shows.
LITE_TCLREGA="${TARGET_DIR}/lib/tclrega.so"
if [ ! -f "${LITE_TCLREGA}" ] || ! grep -q "/var/run/occulite/sessions" "${LITE_TCLREGA}"; then
	echo "post-build (lite): ERROR: /lib/tclrega.so is missing or not package/occulited's shim" >&2
	exit 1
fi
for lite_rega in bin/ReGaHss etc/init.d/S70ReGaHss www/webui www/config www/api www/ise www/pda; do
	if [ -e "${TARGET_DIR}/${lite_rega}" ] || [ -L "${TARGET_DIR}/${lite_rega}" ]; then
		echo "post-build (lite): ERROR: /${lite_rega} is in the image - ReGaHss or the WebUI came back" >&2
		exit 1
	fi
done
rm -f "${TARGET_DIR}/www/rega/licenseinfo.htm"
rmdir "${TARGET_DIR}/www/rega" 2>/dev/null || true
if [ -e "${TARGET_DIR}/www/rega" ]; then
	lite_rega_extra=$(cd "${TARGET_DIR}/www/rega" && find . -mindepth 1 | head -n 5)
	echo "post-build (lite): ERROR: /www/rega is in the image, with: ${lite_rega_extra}" >&2
	exit 1
fi

# And the guard: no shipped configuration names a log file outside its documented exceptions.
"$(cd "$(dirname "$0")/../../.." && pwd)/scripts/lite-log-guard.sh" "${TARGET_DIR}"

# And the out-of-tree kernel modules (the radio drivers under /lib/modules/<kernel>/updates) must be
# signed with the key of the kernel beside them: the kernel enforces signatures, and a kernel tree
# rebuilt from scratch has a new key that the module packages do not follow by themselves - an image
# built so boots without its radio (1.0.0-dev.21). Rebuild those packages after a kernel dirclean.
"$(cd "$(dirname "$0")/../../.." && pwd)/scripts/lite-module-sig-guard.sh" "${TARGET_DIR}"
