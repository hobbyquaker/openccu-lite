#!/bin/sh
# openccu-lite: the interface daemons run confined - the units, the users, the device groups,
# and the root steps around each daemon, which are occulited's since task 129 (`occulited radio
# prep|ready|stopped <daemon>`; their behaviour is tested in occulited's internal/radio).
#
#   - the users table: rfd, hmipserver, multimacd, hs485d and hmlangw with their fixed ids and
#     an empty groups field; the four resource groups;
#   - the udev rules for the raw UART, the loop master and the two endpoints; the tmpfiles line
#     that sorts before systemd's legacy.conf;
#   - every daemon unit: its user, no capabilities, ProtectSystem=strict, the root steps marked
#     "+", the daemon started directly (no init script behind ExecStart), canonical userfs paths,
#     the device drop-in with DevicePolicy=closed; multimacd's real time without a capability;
#     hmipserver without MemoryDenyWriteExecute and with its own journal rate limit (task 234);
#     hs485d's private /var and its pid file;
#   - every daemon unit conditions on the plan's marker (/run/occulite/radio/<daemon>.enabled)
#     and runs occulited's root steps; the three scripts carry no lite init) case any more;
#   - the container post-build removes the device drop-ins and nothing else of the units;
#   - the lite post-build removes the radio chain's seven init scripts from the image and the
#     wrapper table has no row for them (task 129, D-83); the shell helpers are gone.
#
# Nothing needs root, systemd or a radio module.
#
# Usage: sh scripts/testcases/lite-radio-confine-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
EXT="$HERE/buildroot-external"
U="$EXT/overlay/lite/usr/lib/systemd/system"
LIBEXEC="$EXT/overlay/lite/usr/libexec/occu"

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

unit_has() { grep -qx "$2" "$U/$1" && ok "$1: $2" || bad "$1 must carry $2"; }
unit_lacks() { grep -qx "$2" "$U/$1" && bad "$1 must not carry $2" || ok "$1 without $2"; }
unit_matches() { grep -q "$2" "$U/$1" && ok "$1: $3" || bad "$1: $3"; }
unit_nomatch() { grep -q "$2" "$U/$1" && bad "$1: $3" || ok "$1: $3"; }

# --- the users table ---------------------------------------------------------------------------
MK="$EXT/package/occulited/occulited.mk"
for row in "rfd 8110 rfd 8110" "hmipserver 8111 hmipserver 8111" "multimacd 8112 multimacd 8112" "hs485d 8113 hs485d 8113" "hmlangw 8114 hmlangw 8114"; do
  # home "-" (mkusers refuses an explicit "/"), the default shell /bin/false, no groups field
  if grep -qE "^[[:space:]]+$row \\* - - - " "$MK"; then ok "users table: $row, no home, no shell, no groups field"; else bad "users table must carry '$row * - - -'"; fi
done
for row in "raw-uart 990" "eq3loop 991" "mmd-bidcos 992" "mmd-hmip 993"; do
  if grep -qE "^[[:space:]]+- -1 $row \\* - - - " "$MK"; then ok "users table: group $row"; else bad "users table must carry the group '$row'"; fi
done
if [ "$(sed -n '/^define OCCULITED_USERS/,/^endef/p' "$MK" | grep -cE '^[[:space:]]+[a-z0-9-]+ (8[0-9]{3}|-1) [a-z0-9-]+ (8[0-9]{3}|99[0-3]) ')" -eq 12 ]; then ok "users table: twelve pinned rows"; else bad "users table: twelve pinned rows expected"; fi
# udev deprecates GROUP= on a device node for a group above systemd's SYS_GID_MAX (999): every group
# the radio rules name is a system group, pinned at the top of the range automatic allocation fills last
for g in $(sed -n 's/.*GROUP="\([^"]*\)".*/\1/p' "$EXT/overlay/lite/usr/lib/udev/rules.d/60-openccu-lite-radio.rules" "$EXT/overlay/lite/usr/lib/udev/rules.d/61-openccu-lite-radio-hotplug.rules" 2>/dev/null | sort -u); do
  gid=$(sed -n "/^define OCCULITED_USERS/,/^endef/s/^[[:space:]]*[a-z0-9-]* -*[0-9]* $g \([0-9]*\) .*/\1/p" "$MK")
  if [ -n "$gid" ] && [ "$gid" -ge 900 ] && [ "$gid" -le 999 ]; then ok "udev group $g is a system group ($gid)"; else bad "udev group $g must be pinned in 900-999 (is: ${gid:-not in the users table})"; fi
done

# --- udev and tmpfiles ---------------------------------------------------------------------------
RULES="$EXT/overlay/lite/usr/lib/udev/rules.d/60-openccu-lite-radio.rules"
for r in 'SUBSYSTEM=="raw-uart", GROUP="raw-uart", MODE="0660"' 'KERNEL=="eq3loop", GROUP="eq3loop", MODE="0660"' 'KERNEL=="mmd_bidcos", GROUP="mmd-bidcos", MODE="0660"' 'KERNEL=="mmd_hmip", GROUP="mmd-hmip", MODE="0660"' 'ATTR{idVendor}=="1b1f", ATTR{idProduct}=="c00f", GROUP="mmd-bidcos"'; do
  if grep -qF "$r" "$RULES"; then ok "udev: $r"; else bad "udev rule missing: $r"; fi
done
TMPF="$EXT/overlay/lite/usr/lib/tmpfiles.d/00-openccu-lite-radio.conf"
grep -qx 'd /run/lock 1775 root lock -' "$TMPF" && ok "tmpfiles: /run/lock 1775 root lock" || bad "tmpfiles: /run/lock 1775 root lock expected"
grep -qx 'd /var/hmipserver 0750 hmipserver hmipserver -' "$TMPF" && ok "tmpfiles: /var/hmipserver" || bad "tmpfiles: /var/hmipserver expected"
[ "$(printf '%s\n' "$(basename "$TMPF")" legacy.conf | LC_ALL=C sort | head -1)" = "$(basename "$TMPF")" ] && ok "tmpfiles: the file sorts before legacy.conf" || bad "tmpfiles: the file must sort before legacy.conf"

# --- the units -----------------------------------------------------------------------------------
for d in rfd hmipserver multimacd hs485d hmlangw; do
  u="$d.service"
  unit_has "$u" "User=$d"
  unit_has "$u" "Group=$d"
  unit_has "$u" "CapabilityBoundingSet="
  unit_has "$u" "NoNewPrivileges=yes"
  unit_has "$u" "ProtectSystem=strict"
  unit_has "$u" "PrivateTmp=yes"
  unit_has "$u" "ProtectKernelModules=yes"
  unit_nomatch "$u" '^ExecStart=.*\.script' "the daemon is started directly, not through the script"
  unit_nomatch "$u" '^ReadWritePaths=.*[ =]-\?/etc/config' "ReadWritePaths names the userfs canonically"
  # B-145: a userfs path without "-" fails the unit's namespace setup when the directory is missing
  # (a restored OpenCCU backup, a factory reset) - even for the "+" step that would create it
  unit_nomatch "$u" '^ReadWritePaths=.*[ =]/usr/local' "every userfs ReadWritePaths entry carries the - prefix (B-145)"
  unit_nomatch "$u" '^Exec[A-Za-z]*=-\?/usr/libexec/occu/lite-psplash' "the boot-screen steps run as root (+)"
  [ -f "$U/$u.d/20-devices.conf" ] && grep -qx 'DevicePolicy=closed' "$U/$u.d/20-devices.conf" && ok "$u: device drop-in with DevicePolicy=closed" || bad "$u needs $u.d/20-devices.conf with DevicePolicy=closed"
  head -1 "$U/$u.d/20-devices.conf" 2>/dev/null | grep -q '^# openccu-lite' && ok "$u: the drop-in is marked as lite's" || bad "$u: the drop-in must begin with '# openccu-lite'"
  grep -q 'DevicePolicy\|DeviceAllow' "$U/$u" && bad "$u: the device policy belongs in the drop-in only" || ok "$u: no device policy in the unit itself"
done
for d in rfd hmipserver multimacd hs485d hmlangw; do
  unit_has "$d.service" "ExecStartPre=+/usr/bin/occulited radio prep $d"
  unit_has "$d.service" "ConditionPathExists=/run/occulite/radio/$d.enabled"
  # the ExecConditions are the plan's marker again (systemd checks Condition*= only at a requested
  # start, not at its own restarts) and, for hmipserver, the fatal-error marker (D-102) - nothing
  # else: a failing prep is a failure, never a skip
  marker="ExecCondition=/bin/sh -c 'test -e /run/occulite/radio/$d.enabled'"
  others=$(grep "^ExecCondition=" "$U/$d.service" | grep -vxF "$marker")
  if [ "$d" = hmipserver ]; then
    want="ExecCondition=/bin/sh -c '! test -e /run/occulite/radio/hmipserver.fatal'"
  else
    want=""
  fi
  if grep -qxF "$marker" "$U/$d.service" && [ "$others" = "$want" ]; then
    ok "$d.service: its ExecConditions are the plan's marker${want:+ and the fatal-error marker}"
  else
    bad "$d.service: ExecConditions must be the plan's marker${want:+ and the fatal-error marker} only, found: $(grep '^ExecCondition=' "$U/$d.service" | tr '\n' ' ')"
  fi
  unit_nomatch "$d.service" 'lite-radio-prep' "no shell helper"
done
for d in rfd hmipserver multimacd hs485d; do unit_has "$d.service" "EnvironmentFile=-/run/occulite/radio/$d.env"; done
for d in rfd multimacd hmipserver; do unit_has "$d.service" "ExecStartPost=+/usr/bin/occulited radio ready $d"; done
unit_has hmipserver.service "ExecStopPost=-+/usr/bin/occulited radio stopped hmipserver"
unit_lacks multimacd.service "ExecStopPost=-+/usr/bin/occulited radio stopped multimacd"
unit_has occu-init-rf-hardware.service "ExecStart=/usr/bin/occulited radio run"
unit_has occu-init-rf-hardware.service "ExecStop=/usr/bin/occulited radio stop"
unit_has occu-init-hs485d.service 'ExecStart=/bin/hs485dLoader -l ${LOGLEVEL_HS485D} -ds -dd /var/etc/hs485d.conf'
unit_has occu-init-hs485d.service "ConditionPathExists=/run/occulite/radio/hs485d.enabled"
unit_has occu-interface-clock.service "ExecCondition=/usr/bin/systemctl is-active --quiet rfd.service"
unit_has occu-radio-shadow-check.service "ExecStart=/usr/bin/occulited radio check"
for f in lite-radio-prep lite-rf-stop lite-rfd-listen; do [ -e "$LIBEXEC/$f" ] && bad "$LIBEXEC/$f must be gone (task 129)" || ok "no $f in the overlay"; done
for u in occu-update-rf-hardware.service occu-radio-shadow.service; do [ -e "$U/$u" ] && bad "$u must be gone (task 129)" || ok "no $u"; done
grep -qx eq3_char_loop "$EXT/overlay/lite/usr/lib/modules-load.d/openccu-lite-radio.conf" && ok "eq3_char_loop is loaded at boot by modules-load.d" || bad "modules-load.d must load eq3_char_loop"
unit_has rfd.service "Type=exec"; unit_has multimacd.service "Type=exec"; unit_has hmipserver.service "Type=exec"; unit_has hs485d.service "Type=forking"
unit_has rfd.service 'ExecStart=/bin/rfd -f /var/etc/rfd.conf -l ${LOGLEVEL_RFD}'
unit_has multimacd.service 'ExecStart=/bin/multimacd -f /var/etc/multimacd.conf -l ${MULTIMACD_LOGLEVEL}'
unit_has hs485d.service 'ExecStart=/bin/hs485dLoader -l ${LOGLEVEL_HS485D} -dw /var/etc/hs485d.conf'
unit_matches hmipserver.service '^ExecStart=/opt/java/bin/java \$HMIP_JAVA_OPTS .*-cp \${HMIP_CLASSPATH} \${HMIP_CLASS} \$HMIP_ARGS$' "the JVM's line from the environment file"
unit_has rfd.service "SupplementaryGroups=mmd-bidcos status"
unit_has multimacd.service "SupplementaryGroups=raw-uart eq3loop status"
unit_has hmipserver.service "SupplementaryGroups=mmd-hmip raw-uart status lock"
unit_has hs485d.service "SupplementaryGroups=dialout status"
unit_has hmlangw.service "SupplementaryGroups=mmd-bidcos status"
unit_has multimacd.service "LimitRTPRIO=99"; unit_has multimacd.service "Nice=-15"; unit_has multimacd.service "LimitNOFILE=1000"
unit_lacks multimacd.service "RestrictRealtime=yes"; unit_has multimacd.service "PrivateNetwork=yes"
unit_nomatch multimacd.service '^AmbientCapabilities' "no capability for the real time"
unit_lacks hmipserver.service "MemoryDenyWriteExecute=yes"
unit_has hmipserver.service "SuccessExitStatus=143"
# task 234: a listener that does not answer makes hmipserver log a stack trace a second
unit_has hmipserver.service "LogRateLimitIntervalSec=30s"; unit_has hmipserver.service "LogRateLimitBurst=100"
# a userfs directory may be missing (a restored OpenCCU backup, a factory reset): the prep step makes
# it, and a path that is not optional fails the namespace setup of that very step
for d in rfd multimacd hmipserver hs485d hmlangw; do unit_nomatch "$d.service" '^ReadWritePaths=\(.* \)\{0,1\}/usr/local' "$d: its userfs paths are optional"; done
unit_has rfd.service "ReadWritePaths=/var/status -/usr/local/etc/config/rfd"
unit_has hmipserver.service "ReadWritePaths=-/usr/local/etc/config/crRFD -/usr/local/etc/config/eshlight"
unit_has hs485d.service "ReadWritePaths=/var/status -/usr/local/etc/config/hs485d"
for d in rfd hs485d hmlangw; do unit_has "$d.service" "RestrictRealtime=yes"; unit_has "$d.service" "MemoryDenyWriteExecute=yes"; done
unit_has hmipserver.service "ReadWritePaths=/var/status /var/hmipserver /run/lock"
unit_has hs485d.service "PIDFile=/run/hs485d/run/hs485dLoader.pid"
unit_has hs485d.service "TemporaryFileSystem=/var:mode=1777"
unit_has hs485d.service "BindPaths=-/var/status -/var/HS485D.handlers -/run/hs485d/run:/var/run -/run/hs485d/log:/var/log"
grep -qx 'd /run/hs485d/run 0750 hs485d hs485d -' "$TMPF" && grep -qx 'd /run/hs485d/log 0750 hs485d hs485d -' "$TMPF" && ok "tmpfiles: hs485d's bind sources exist at boot" || bad "tmpfiles: /run/hs485d/run and /run/hs485d/log expected"
# B-163: /var/etc is written by the prep step, bound writable
unit_has hs485d.service "BindPaths=/var/etc"
unit_has hs485d.service "BindReadOnlyPaths=-/var/hm_mode"
unit_has hmipserver.service 'Environment="HMIP_ARGS=/var/etc/crRFD.conf /var/etc/HMServer.conf"'
unit_has hs485d.service "RuntimeDirectory=hs485d"
grep -q 'DeviceAllow=char-raw-uart rw' "$U/multimacd.service.d/20-devices.conf" && ok "multimacd may open the raw UART" || bad "multimacd's drop-in must allow char-raw-uart"
grep -q 'DeviceAllow=char-eq3loop rw' "$U/rfd.service.d/20-devices.conf" && ok "rfd may open the loop endpoint" || bad "rfd's drop-in must allow char-eq3loop"
grep -q 'DeviceAllow=char-raw-uart rw' "$U/rfd.service.d/20-devices.conf" && bad "rfd must not open the raw UART" || ok "rfd's drop-in keeps the raw UART closed"
# the psplash steps keep the scripts' names as labels (the step's message and progress number)
for d in "rfd S61rfd" "multimacd S60multimacd" "hmipserver S62HMServer" "hs485d S60hs485d" "hmlangw S61hmlangw"; do
  set -- $d
  unit_has "$1.service" "ExecStartPre=-+/usr/libexec/occu/lite-psplash boot $2"
done

# --- the scripts: upstream's form, no lite init) case ---------------------------------------------
for s in RFD/etc/init.d/S60multimacd RFD/etc/init.d/S61rfd base/etc/init.d/S62HMServer; do
  f="$EXT/overlay/$s"
  if sed -n '/^case "\$1" in/,/^esac/p' "$f" | grep -qx '  init)'; then bad "$(basename "$f") still carries the transitional init) case"; else ok "$(basename "$f") without a lite init) case"; fi
  sh -n "$f" && ok "$(basename "$f") parses" || bad "$(basename "$f") does not parse"
done

# --- the container post-build drops the device drop-ins ------------------------------------------
TD="$T/target"
mkdir -p "$TD/usr/lib/systemd/system" "$TD/etc/systemd/system" "$TD/etc/systemd/system.conf.d" "$TD/usr/local" "$TD/usr/lib/modules-load.d"
cp -r "$U"/. "$TD/usr/lib/systemd/system/"; cp "$EXT/overlay/lite/usr/lib/modules-load.d/openccu-lite-radio.conf" "$TD/usr/lib/modules-load.d/"
touch "$TD/etc/systemd/system.conf.d/lite-watchdog.conf"
if TARGET_DIR="$TD" sh "$EXT/board/lxc-lite/post-build.sh" >"$T/lxc.log" 2>&1; then
  ok "lxc-lite post-build runs on the fake target"
  left=0
  for d in rfd hmipserver multimacd hs485d hmlangw; do
    [ -e "$TD/usr/lib/systemd/system/$d.service.d/20-devices.conf" ] && left=$((left+1))
    [ -f "$TD/usr/lib/systemd/system/$d.service" ] || left=$((left+1))
  done
  [ "$left" -eq 0 ] && ok "lxc-lite: the five device drop-ins are gone, the units stay" || bad "lxc-lite: device drop-ins left or a unit gone ($left)"
  [ -e "$TD/usr/lib/modules-load.d/openccu-lite-radio.conf" ] && bad "lxc-lite: modules-load.d entry must go" || ok "lxc-lite: no modules-load.d entry in the container"
  grep -q '^User=rfd$' "$TD/usr/lib/systemd/system/rfd.service" && ok "lxc-lite: the confinement stays" || bad "lxc-lite: rfd's User= lost"
else
  bad "lxc-lite post-build failed: $(tail -2 "$T/lxc.log")"
fi

# --- the radio chain's scripts leave the image (task 129, D-83) ----------------------------------
TABLE="$EXT/overlay/lite/usr/lib/systemd/openccu-lite-initscripts"
for s in S47InitRFHardware S48UpdateRFHardware S49hs485d S60hs485d S60multimacd S61rfd S62HMServer S58LGWFirmwareUpdate S59SetLGWKey; do
  grep -qE "^${s}[[:space:]]" "$TABLE" && bad "the wrapper table must not list $s" || ok "wrapper table without $s"
done
PB="$EXT/board/lite/post-build-initscripts.sh"
if grep -q 'for lite_radio_script in S47InitRFHardware S48UpdateRFHardware S49hs485d S60hs485d S60multimacd S61rfd S62HMServer S58LGWFirmwareUpdate S59SetLGWKey;' "$PB"; then ok "post-build-initscripts removes the nine radio scripts"; else bad "post-build-initscripts.sh must remove the radio chain's scripts"; fi
grep -q 'post-build-initscripts.sh" "${TARGET_DIR}"' "$EXT/board/lite/post-build-systemd.sh" && ok "post-build-systemd runs post-build-initscripts.sh" || bad "post-build-systemd.sh must run post-build-initscripts.sh"
# the removal on a fake target: the scripts go, the other init scripts are wrapped as before
TD2="$T/target2"
mkdir -p "$TD2/etc/init.d" "$TD2/usr/lib/systemd/system" "$TD2/usr/libexec/occu"
cp "$TABLE" "$TD2/usr/lib/systemd/"; mkdir -p "$TD2/usr/lib/systemd"; cp "$TABLE" "$TD2/usr/lib/systemd/openccu-lite-initscripts"
mkdir -p "$TD2/bin"; printf '#!/bin/sh\n' >"$TD2/bin/setlgwkey.sh"
for s in S47InitRFHardware S48UpdateRFHardware S49hs485d S60hs485d S60multimacd S61rfd S62HMServer S58LGWFirmwareUpdate S59SetLGWKey S50lighttpd; do printf '#!/bin/sh\n' >"$TD2/etc/init.d/$s"; chmod 755 "$TD2/etc/init.d/$s"; done
cp "$LIBEXEC/initscript-wrapper" "$TD2/usr/libexec/occu/"; chmod 755 "$TD2/usr/libexec/occu/initscript-wrapper"
# the init.d step is its own script (task 115) and runs on the fake target as it is
if sh "$PB" "$TD2" >"$T/pb.log" 2>&1; then
  left=""
  for s in S47InitRFHardware S48UpdateRFHardware S49hs485d S60hs485d S60multimacd S61rfd S62HMServer S58LGWFirmwareUpdate S59SetLGWKey; do [ -e "$TD2/etc/init.d/$s" ] && left="$left $s"; done
  [ -e "$TD2/bin/setlgwkey.sh" ] && left="$left setlgwkey.sh"
  [ -z "$left" ] && ok "post-build: the nine scripts and setlgwkey.sh are gone from the target" || bad "post-build left:$left"
  [ -L "$TD2/etc/init.d/S50lighttpd" ] && [ -f "$TD2/etc/init.d/S50lighttpd.script" ] && ok "post-build: the other scripts are still wrapped" || bad "post-build: S50lighttpd was not wrapped"
else
  bad "the post-build step failed on the fake target: $(tail -3 "$T/pb.log")"
fi

# --- phase 4 (D-99): the LAN gateway steps and the hotplug are occulited's ------------------------
UD="$EXT/overlay/lite/usr/lib/systemd/system"
grep -q '^ExecStart=/usr/bin/occulited radio lgw-firmware$' "$UD/occu-lgw-firmware-update.service" && ok "the LAN gateway firmware step runs occulited" || bad "occu-lgw-firmware-update.service must run occulited radio lgw-firmware"
grep -q '^ExecStart=/usr/bin/occulited radio lgw-keys$' "$UD/occu-set-lgw-key.service" && ok "the LAN gateway key step runs occulited" || bad "occu-set-lgw-key.service must run occulited radio lgw-keys"
grep -q '^Exec.*init.d/S5[89]' "$UD/occu-lgw-firmware-update.service" "$UD/occu-set-lgw-key.service" && bad "a LAN gateway unit still names its init script" || ok "no LAN gateway unit names an init script"
grep -q '^ExecStart=/usr/bin/occulited radio hotplug$' "$UD/occu-radio-hotplug.service" && grep -q '^After=occu-init-rf-hardware.service$' "$UD/occu-radio-hotplug.service" && ok "occu-radio-hotplug runs occulited after the boot's detection" || bad "occu-radio-hotplug.service: occulited radio hotplug after occu-init-rf-hardware"
HR="$EXT/overlay/lite/usr/lib/udev/rules.d/61-openccu-lite-radio-hotplug.rules"
grep -q '^SUBSYSTEM=="raw-uart", ACTION=="add|remove", RUN+="/bin/systemctl --no-block start occu-radio-hotplug.service"$' "$HR" && ok "udev: a raw UART node added or removed starts the hotplug" || bad "udev: the raw-uart hotplug rule is missing"
grep -q 'ENV{PRODUCT}=="1b1f/c00f/\*", ACTION=="add|remove", RUN+="/bin/systemctl --no-block start occu-radio-hotplug.service"' "$HR" && ok "udev: the HM-CFG-USB-2 added or removed starts the hotplug" || bad "udev: the HM-CFG-USB-2 hotplug rule is missing"
grep -q '^SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ACTION=="remove", RUN+="/bin/systemctl --no-block start occu-radio-hotplug.service"$' "$HR" && ok "udev: any USB device removed starts the hotplug (a held node stays)" || bad "udev: the USB remove rule is missing"


echo; [ "$fails" -eq 0 ] && { echo "lite-radio-confine-test: all checks passed"; exit 0; }
echo "lite-radio-confine-test: $fails check(s) failed"; exit 1
