#!/bin/sh
# openccu-lite: the boot order of the lite units is a dependency graph, not a serial chain.
#
# The systemd conversion once kept upstream's S40..S98 numbering as one serial After= chain, and
# every step waited for every earlier one (multimacd behind hs485d, the radio detection behind
# chrony, lighttpd behind occulited, hmipserver behind rfd). This checks the unit files against the
# intended graph: the edges each unit really needs are there, the old serial links are not, and the
# After=/Before= edges of all units together contain no cycle. Nothing needs root or systemd.
#
# Usage: sh scripts/testcases/lite-unit-order-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
U="$HERE/buildroot-external/overlay/lite/usr/lib/systemd/system"
[ -d "$U" ] || { echo "unit directory not found at $U"; exit 2; }

fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

# the After= words of a unit: the unit file and its drop-ins in the overlay
after() {
  cat "$U/$1" "$U/$1.d/"*.conf 2>/dev/null | sed -n 's/^After=//p' | tr ' ' '\n' | grep -v '^$'
}
wants() {
  cat "$U/$1" "$U/$1.d/"*.conf 2>/dev/null | sed -n 's/^Wants=//p' | tr ' ' '\n' | grep -v '^$'
}
need() {
  unit=$1; shift
  [ -f "$U/$unit" ] || { bad "$unit does not exist"; return; }
  for dep in "$@"; do
    if after "$unit" | grep -qx "$dep"; then ok "$unit after $dep"; else bad "$unit must order after $dep"; fi
  done
}
never() {
  unit=$1; shift
  for dep in "$@"; do
    if after "$unit" | grep -qx "$dep"; then bad "$unit after $dep: a serial link the graph removed"; else ok "$unit not after $dep"; fi
  done
}

before() {
  cat "$U/$1" "$U/$1.d/"*.conf 2>/dev/null | sed -n 's/^Before=//p' | tr ' ' '\n' | grep -v '^$'
}

# the serial base: every one of them rewrites /var/hm_mode
need occu-init-rtc.service occu-init-host.service
need occu-init-system.service occu-persist.service occu-init-host.service occu-init-rtc.service
# the userfs is final before anything mounts or writes it: resize, then factory reset, then the
# restore at boot, and only then the journal's bind mount - mounted, the partition refuses parted
# and mkfs.ext4 (a fresh x86_64-ova's first boot kept its 2 MB userfs and its factory reset)
need occu-factory-reset.service occu-userfs-resize.service
need occu-backup-restore.service occu-factory-reset.service
need occu-persist.service occu-backup-restore.service
# S06 empties /usr/local/tmp, where the restore at boot (S05) finds its archive: S05 first
need occu-init-system.service occu-backup-restore.service
# S06 creates /var/etc, where the DHCP hook's resolvconf writes resolv.conf (B-148): S40 after S06
need occu-network.service occu-init-system.service
# the firewall's rules are loaded before any interface comes up (task 157), from the final userfs:
# after the restore at boot (task 207, B-188), so a restoring boot loads the restored rules and a
# fresh userfs is not written before its reset
need occu-network.service occu-firewall.service
need occu-firewall.service occu-backup-restore.service
need occu-init-rf-hardware.service occu-init-system.service occu-init-host.service

# the real-time clock needs S01InitHost only; the other S01 scripts run beside it
if [ "$(after occu-init-rtc.service | tr '\n' ' ')" = "occu-init-host.service " ]; then
  ok "occu-init-rtc is after occu-init-host and nothing else"
else
  bad "occu-init-rtc must be after occu-init-host only: $(after occu-init-rtc.service | tr '\n' ' ')"
fi
never occu-init-rtc.service occu-zram-swap.service occu-usb-gadget.service

# the radio detection does not wait for the network or the web server (an HB-RF-ETH waits inside
# S47 for a route to its address)
never occu-init-rf-hardware.service occu-network.service network.target network-online.target lighttpd.service
if grep -q '^ *wait_for_hb_rf_eth_route "${HB_RF_ETH_ADDRESS}"$' "$HERE/buildroot-external/overlay/base/etc/init.d/S47InitRFHardware"; then
  ok "S47 waits for a route to a configured HB-RF-ETH itself"
else
  bad "S47 must wait for the network itself before it connects an HB-RF-ETH"
fi
if grep -v '^[[:space:]]*#' "$HERE/buildroot-external/overlay/base/etc/init.d/S47InitRFHardware" | grep -q 'ip route show default.*address'; then
  bad "S47's board-serial fallback still reads the default route's interface"
else
  ok "S47's board-serial fallback does not need the default route"
fi

# the coprocessor is never flashed at boot: the unit sets the script's guard
# task 129, D-83/D-89: the firmware check unit is gone with S48UpdateRFHardware (no flash at boot,
# occulited's Interfaces page shows and flashes newer firmware); the detection unit runs
# occulited's radio run, and the daemon units condition on its markers
[ -e "$U/occu-update-rf-hardware.service" ] && bad "occu-update-rf-hardware.service must not exist (task 129)" || ok "no occu-update-rf-hardware.service"
[ -e "$U/occu-radio-shadow.service" ] && bad "occu-radio-shadow.service must not exist (the run step replaced it)" || ok "no occu-radio-shadow.service"
grep -qx 'ExecStart=/usr/bin/occulited radio run' "$U/occu-init-rf-hardware.service" && ok "occu-init-rf-hardware runs occulited radio run" || bad "occu-init-rf-hardware.service must run /usr/bin/occulited radio run"
grep -qx 'ExecStop=/usr/bin/occulited radio stop' "$U/occu-init-rf-hardware.service" && ok "occu-init-rf-hardware stops through occulited radio stop" || bad "occu-init-rf-hardware.service must stop through /usr/bin/occulited radio stop"
for d in multimacd rfd hmipserver hs485d hmlangw; do
  grep -qx "ConditionPathExists=/run/occulite/radio/$d.enabled" "$U/$d.service" && ok "$d.service conditions on its marker" || bad "$d.service must carry ConditionPathExists=/run/occulite/radio/$d.enabled"
done
grep -qx 'ConditionPathExists=/run/occulite/radio/hs485d.enabled' "$U/occu-init-hs485d.service" && ok "occu-init-hs485d conditions on the hs485d marker" || bad "occu-init-hs485d.service must condition on /run/occulite/radio/hs485d.enabled"
grep -qx 'ExecCondition=/usr/bin/systemctl is-active --quiet rfd.service' "$U/occu-interface-clock.service" && ok "occu-interface-clock only while rfd is active (skipped, not failed)" || bad "occu-interface-clock.service must carry ExecCondition=/usr/bin/systemctl is-active --quiet rfd.service"
grep -q '^ConditionPathExists=/run/occulite/radio/rfd.enabled' "$U/occu-interface-clock.service" && bad "occu-interface-clock.service conditions on rfd's plan marker (planned is not running)" || ok "occu-interface-clock does not condition on rfd's plan marker"

# the writable extension directories: after the userfs is final, before rfd reads /firmware/rftypes
# and before the addons write there
need occu-extension-dirs.service occu-init-system.service
for d in rfd.service occu-addons.service; do
  if before occu-extension-dirs.service | grep -qx "$d"; then ok "occu-extension-dirs before $d"; else bad "occu-extension-dirs.service must order before $d"; fi
done
never occu-extension-dirs.service occu-network.service network.target lighttpd.service occulited.service

# the network does not wait for the CA bundle; the bundle comes before whoever uses it
never occu-network.service ca-certificates.service
for d in network-online.target occulited.service chrony.service occu-syslog-forward.service occu-addons.service; do
  if before ca-certificates.service | grep -qx "$d"; then ok "ca-certificates before $d"; else bad "ca-certificates.service must order before $d"; fi
done
if grep -qx 'ExecStart=/usr/libexec/occu/lite-ca-certificates' "$U/ca-certificates.service" &&
   ! grep -q '^ExecStart=.*update-ca-certificates' "$U/ca-certificates.service"; then
  ok "ca-certificates copies the prebuilt or cached bundle (lite-ca-certificates)"
else
  bad "ca-certificates.service must run lite-ca-certificates, not update-ca-certificates"
fi
[ -x "$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-ca-certificates" ] && ok "lite-ca-certificates is executable" || bad "lite-ca-certificates is not executable"
if grep -v '^[[:space:]]*#' "$HERE/buildroot-external/board/lite/post-build.sh" | grep -q 'ca-prebuilt\.sh'; then
  ok "the lite post-build writes the prebuilt bundle"
else
  bad "board/lite/post-build.sh must run ca-prebuilt.sh"
fi

# no internet check in the image: the post-build removes it, and its callers test for it
if grep -v '^[[:space:]]*#' "$HERE/buildroot-external/board/lite/post-build.sh" | grep -q 'rm -f "${TARGET_DIR}/bin/checkInternet"'; then
  ok "the lite post-build removes checkInternet"
else
  bad "board/lite/post-build.sh must remove /bin/checkInternet"
fi
for f in overlay/base/etc/network/if-up.d/eQ3StartNetwork overlay/base/bin/dhcp.script; do
  unguarded=$(grep -v '^[[:space:]]*#' "$HERE/buildroot-external/$f" | grep '/bin/checkInternet' | grep -v -- '-x /bin/checkInternet' | grep -v '^[[:space:]]*/bin/checkInternet' || true)
  guards=$(grep -c -- '-x /bin/checkInternet' "$HERE/buildroot-external/$f")
  guards=${guards:-0}
  calls=$(grep -v '^[[:space:]]*#' "$HERE/buildroot-external/$f" | grep -c '/bin/checkInternet')
  if [ -z "$unguarded" ] && [ "$guards" -gt 0 ] && [ "$calls" -le $((guards * 2)) ]; then
    ok "$f calls checkInternet only where it is installed"
  else
    bad "$f: a checkInternet call without the -x test ($calls calls, $guards tests)"
  fi
done

# the link wait polls every 0.2 s for the same 12 s, with a dot every 2 s
f=overlay/base/etc/network/if-up.d/eQ3StartNetwork
if grep -q '^ *sleep 0\.2$' "$HERE/buildroot-external/$f" && grep -q 'if \[\[ \$i -ge 60 \]\]' "$HERE/buildroot-external/$f" &&
   grep -q '\[\[* \$((i % 10)) -eq 0 \]\]*' "$HERE/buildroot-external/$f"; then
  ok "$f: the link wait polls every 0.2 s up to 12 s"
else
  bad "$f: the link wait is not the 0.2 s poll"
fi

# a timer that catches up at boot runs after the boot
need occu-fstrim.service multi-user.target
need occu-backup-create@.service multi-user.target occulited.service
need occu-backup-deliver@.service occu-backup-create@%i.service

# the watchdog is systemd's own: no unit orders against the old one
never occu-init-host.service occu-watchdog.service

# the radio stack
need multimacd.service occu-init-rf-hardware.service
need rfd.service multimacd.service occu-set-lgw-key.service
need hmipserver.service multimacd.service
need hmlangw.service multimacd.service
# B-86: whatever holds a /dev/mmd_* endpoint is part of multimacd - a restart of multimacd (by hand,
# or systemd's after a crash) stops it first, or the re-created eq3_char_loop masters lock the kernel
# up and the watchdog resets the system. PartOf, never BindsTo or Requires: without multimacd (no
# shared radio module) the daemons run on their own.
partof() {
  cat "$U/$1" "$U/$1.d/"*.conf 2>/dev/null | sed -n 's/^PartOf=//p' | tr ' ' '\n' | grep -v '^$'
}
binds() {
  cat "$U/$1" "$U/$1.d/"*.conf 2>/dev/null | sed -n 's/^\(BindsTo\|Requires\|Requisite\)=//p' | tr ' ' '\n' | grep -v '^$'
}
for d in rfd hmipserver hmlangw; do
  if partof $d.service | grep -qx multimacd.service; then ok "$d.service is PartOf multimacd"; else bad "$d.service must be PartOf=multimacd.service (B-86)"; fi
  if binds $d.service | grep -qx multimacd.service; then bad "$d.service binds to or requires multimacd: it would not run without it"; else ok "$d.service does not bind to multimacd"; fi
done
# the radio plan's marker is checked by ExecCondition= too: Condition*= is not checked at systemd's
# own restarts, so a unit the plan dropped while it was failing would restart forever
for d in rfd hmipserver multimacd hmlangw hs485d; do
  if cat "$U/$d.service" | grep -qx "ExecCondition=/bin/sh -c 'test -e /run/occulite/radio/$d.enabled'"; then
    ok "$d.service re-checks its plan marker at every start (ExecCondition)"
  else
    bad "$d.service lacks ExecCondition on /run/occulite/radio/$d.enabled"
  fi
  # B-307: and refuses a start while a radio change holds the units (lite-radio-gate-test.sh)
  if grep -qx "ExecCondition=+/usr/libexec/occu/lite-radio-gate $d" "$U/$d.service"; then
    ok "$d.service waits out a radio change (ExecCondition lite-radio-gate)"
  else
    bad "$d.service lacks ExecCondition=+/usr/libexec/occu/lite-radio-gate $d"
  fi
done
# and nothing the other way round: multimacd's stop must not wait for, or pull in, its dependants
if partof multimacd.service | grep -qx 'rfd.service\|hmipserver.service\|hmlangw.service'; then bad "multimacd is PartOf a dependant"; else ok "multimacd is PartOf none of its dependants"; fi

# LAN gateways and wired
need occu-lgw-firmware-update.service occu-network.service occu-init-rf-hardware.service
need occu-set-lgw-key.service occu-lgw-firmware-update.service
need hs485d.service occu-init-hs485d.service occu-set-lgw-key.service
need occu-init-hs485d.service occu-init-rf-hardware.service

# the web server right after the network, and at shutdown after the radio stack - by a stop that
# waits, not by an ordering that would hold the radio detection back at boot
need lighttpd.service network.target
if before lighttpd.service | grep -qx 'occu-init-rf-hardware.service\|multimacd.service\|rfd.service\|hmipserver.service'; then
  bad "lighttpd orders itself before a radio unit: $(before lighttpd.service | tr '\n' ' ')"
else
  ok "lighttpd is not ordered before the radio units"
fi
# B-120: lighttpd runs as www-data, so the stop step runs as root (the + prefix)
stopwait=$(sed -n 's/^ExecStop=+\{0,1\}-\/usr\/libexec\/occu\/lite-radio-stop-wait \([0-9]*\)$/\1/p' "$U/lighttpd.service")
stoptimeout=$(sed -n 's/^TimeoutStopSec=\([0-9]*\)$/\1/p' "$U/lighttpd.service")
if [ -n "$stopwait" ] && [ -n "$stoptimeout" ] && [ "$stoptimeout" -gt "$stopwait" ]; then
  ok "lighttpd's stop waits for the radio stack (${stopwait} s, within TimeoutStopSec=${stoptimeout})"
else
  bad "lighttpd.service needs ExecStop=-/usr/libexec/occu/lite-radio-stop-wait <s> below its TimeoutStopSec (${stopwait:-none}/${stoptimeout:-none})"
fi
[ -x "$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-radio-stop-wait" ] && ok "lite-radio-stop-wait is executable" || bad "lite-radio-stop-wait is not executable"

# the web server's sandbox: root's preparation (S50lighttpd's reload, the starting page, the
# certificate group, the addon drop-ins) is a unit of its own that runs before every start and
# from the reload - a "+" line would run inside the daemon's read-only mount namespace - and the
# daemon's unit holds the confinement, with its pid file in its runtime directory
need lighttpd.service lighttpd-prepare.service
need lighttpd-prepare.service occu-init-system.service
if wants lighttpd.service | grep -qx lighttpd-prepare.service; then ok "lighttpd wants its preparation"; else bad "lighttpd.service must want lighttpd-prepare.service"; fi
never lighttpd-prepare.service lighttpd.service occulited.service occu-init-rf-hardware.service
for step in '/etc/init.d/S50lighttpd.script reload' '/usr/libexec/occu/lite-starting-page' '/usr/libexec/occu/lite-cert-perms' '/usr/bin/occulited -lighttpd-dropins'; do
  if grep -qx "ExecStart=-$step" "$U/lighttpd-prepare.service"; then ok "lighttpd-prepare runs $step"; else bad "lighttpd-prepare.service must run ExecStart=-$step"; fi
  if grep -q "^Exec.*$step" "$U/lighttpd.service"; then bad "lighttpd.service still runs $step itself (inside its sandbox)"; else ok "lighttpd.service does not run $step itself"; fi
done
grep -qx 'ExecReload=+-/usr/bin/systemctl start lighttpd-prepare.service' "$U/lighttpd.service" && ok "lighttpd's reload runs the preparation first" || bad "lighttpd.service's ExecReload must start lighttpd-prepare.service before the signal"
# the signal only when the configuration changed (a graceful restart cuts long-lived streams): the
# preparation, then lite-lighttpd-reload, and no bare kill; the fingerprint recorded at the start
if [ "$(sed -n 's/^ExecReload=//p' "$U/lighttpd.service" | tr '\n' '|')" = '+-/usr/bin/systemctl start lighttpd-prepare.service|/usr/libexec/occu/lite-lighttpd-reload reload $MAINPID|' ]; then
  ok "lighttpd's reload: the preparation, then the signal only on a changed configuration"
else
  bad "lighttpd.service's ExecReload must be the preparation, then lite-lighttpd-reload reload \$MAINPID (is: $(sed -n 's/^ExecReload=//p' "$U/lighttpd.service" | tr '\n' '|'))"
fi
grep -qx 'ExecStartPost=-/usr/libexec/occu/lite-lighttpd-reload record' "$U/lighttpd.service" && ok "lighttpd records its configuration at the start" || bad "lighttpd.service must record its configuration (ExecStartPost=-/usr/libexec/occu/lite-lighttpd-reload record)"
grep -qx 'Type=oneshot' "$U/lighttpd-prepare.service" && ok "lighttpd-prepare is a oneshot" || bad "lighttpd-prepare.service must be Type=oneshot"
grep -qx 'ConditionPathExists=!/usr/local/HMLGW' "$U/lighttpd-prepare.service" && ok "lighttpd-prepare is skipped in LAN-gateway mode" || bad "lighttpd-prepare.service must carry ConditionPathExists=!/usr/local/HMLGW"
for line in 'User=www-data' 'RuntimeDirectory=lighttpd' 'ProtectSystem=strict' 'TemporaryFileSystem=/usr/local:ro' 'NoExecPaths=/' 'SystemCallFilter=@system-service' 'SystemCallArchitectures=native' 'RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6' 'MemoryDenyWriteExecute=yes' 'CapabilityBoundingSet=CAP_NET_BIND_SERVICE' 'AmbientCapabilities=CAP_NET_BIND_SERVICE'; do
  grep -qx "$line" "$U/lighttpd.service" && ok "lighttpd.service: $line" || bad "lighttpd.service must carry $line"
done
grep -q '^SystemCallFilter=.*~@privileged' "$U/lighttpd.service" && bad "lighttpd.service filters @privileged: the setuid busybox's applets die at start" || ok "lighttpd.service leaves @setuid to busybox"
# the pid file where the unit's runtime directory is: the lite post-build points lighttpd.conf there
if grep -v '^[[:space:]]*#' "$HERE/buildroot-external/board/lite/post-build.sh" | grep -q 'server\.pid-file = "/run/lighttpd/lighttpd\.pid"'; then
  ok "the lite post-build points server.pid-file into /run/lighttpd"
else
  bad "board/lite/post-build.sh must set server.pid-file = \"/run/lighttpd/lighttpd.pid\""
fi
# no mod_cgi: the CGIs run through occulited; the module is not loaded and its fragment leaves the image
if grep -v '^[[:space:]]*#' "$HERE/buildroot-external/overlay/lite/etc/lighttpd/modules.conf" | grep -q 'mod_cgi\|cgi\.conf'; then
  bad "the lite modules.conf still loads mod_cgi or includes conf.d/cgi.conf"
else
  ok "the lite modules.conf loads no mod_cgi"
fi
if grep -v '^[[:space:]]*#' "$HERE/buildroot-external/board/lite/post-build.sh" | grep -q 'rm -f "${TARGET_DIR}/etc/lighttpd/conf.d/cgi.conf"'; then
  ok "the lite post-build removes conf.d/cgi.conf"
else
  bad "board/lite/post-build.sh must remove /etc/lighttpd/conf.d/cgi.conf"
fi

# the clock gate: whoever hands the time on, or runs by it, waits for a trusted clock - and not for
# chrony's first sync
# (multimacd reads no wall clock and passes on only the time rfd hands it: not behind the gate)
need rfd.service occu-clock-valid.service
need hmipserver.service occu-clock-valid.service
need hs485d.service occu-clock-valid.service
need crond.service occu-clock-valid.service
for u in rfd.service hmipserver.service hs485d.service crond.service; do
  if wants "$u" | grep -qx occu-clock-valid.service; then ok "$u wants the clock gate"; else bad "$u must want occu-clock-valid.service"; fi
done
never multimacd.service occu-clock-valid.service
if wants multimacd.service | grep -qx occu-clock-valid.service; then bad "multimacd still wants the clock gate"; else ok "multimacd does not want the clock gate"; fi
# the journal's ram-sync copy stamps its next copy after the saved clock is back (B-205), and waits
# for the gate inside its loop: an edge after the gate would hold the daemons it is Before= behind NTP
need occu-journal-sync.service occu-clock-save.service
never occu-journal-sync.service occu-clock-valid.service chrony.service time-sync.target
# the gate itself is not after chrony (which is after the network): with a real-time clock it
# passes before the network is up; without one it polls chronyd
never occu-clock-valid.service chrony.service occu-network.service network.target
t_start=$(sed -n 's/^TimeoutStartSec=\([0-9]*\)$/\1/p' "$U/occu-clock-valid.service")
t_args=$(sed -n 's/^ExecStart=\/usr\/libexec\/occu\/lite-clock-valid *//p' "$U/occu-clock-valid.service")
t_ntp=$(echo "$t_args" | cut -d' ' -f1); t_chronyd=$(echo "$t_args" | cut -s -d' ' -f2)
[ -n "$t_chronyd" ] || t_chronyd=90
if [ -n "$t_start" ] && [ -n "$t_ntp" ] && [ "$t_start" -gt $((t_ntp + t_chronyd)) ]; then
  ok "the gate's start timeout ($t_start s) is above its NTP wait plus its wait for chronyd ($t_ntp + $t_chronyd s)"
else
  bad "occu-clock-valid: TimeoutStartSec=${t_start:-none} must exceed ${t_ntp:-?} + ${t_chronyd} s"
fi
never multimacd.service chrony.service
never rfd.service chrony.service
never hmipserver.service chrony.service
if grep -v '^#' "$U/chrony.service" | grep -q 'ntpdate\|S46chronyd.script'; then bad "chrony.service still runs ntpdate"; else ok "chrony.service without ntpdate"; fi
# nothing calls ntpdate on lite, so no lite product builds it (the shared Buildroot.config does, for
# the upstream products)
for cfg in $(grep -l '^BR2_PACKAGE_OCCULITED=y' "$HERE/buildroot-external/configs/"*.config); do
  if grep -qx '# BR2_PACKAGE_NTP is not set' "$cfg"; then ok "${cfg##*/}: no ntpdate"; else bad "${cfg##*/} must carry '# BR2_PACKAGE_NTP is not set'"; fi
done

# the serial links that are gone and must not come back
never multimacd.service hs485d.service rfd.service hmipserver.service occu-set-lgw-key.service
never hmipserver.service rfd.service
never rfd.service hmipserver.service
never occu-init-rf-hardware.service chrony.service
never lighttpd.service occulited.service occu-init-hs485d.service occu-init-rf-hardware.service
never occu-init-hs485d.service occulited.service
# sshd prepares its keys on the userfs as S06 leaves it; the wired interface is not its business
need sshd.service occu-init-system.service network.target
never sshd.service occu-init-hs485d.service hs485d.service occu-init-rf-hardware.service
never occu-lgw-firmware-update.service occu-init-addons.service
never crond.service hmipserver.service rfd.service
never occu-addons.service hmipserver.service rfd.service crond.service
if grep -qs '^After=.*occu-\(init\|update\)-rf-hardware' "$U/occulited.service.d/"*.conf; then
  bad "an occulited drop-in orders it behind the radio hardware"
else
  ok "no occulited drop-in behind the radio hardware"
fi

# /var/run is the link to /run before anything writes under it. /var is a tmpfs mounted at boot, the
# link comes from systemd-tmpfiles-setup, and the udev coldplug - whose programs run in between - is
# ordered against neither. A directory made there first stays (systemd's var.conf says "L"), and
# every pid file under /var/run then misses the PIDFile= of its unit.
BOARD="$HERE/buildroot-external/board/lite"
TMPF="$HERE/buildroot-external/overlay/lite/usr/lib/tmpfiles.d/lite-var-run.conf"
if [ -f "$TMPF" ] && grep -v '^#' "$TMPF" | grep -qx 'L+ /var/run - - - - \.\./run'; then
  ok "tmpfiles replaces a /var/run directory with the link (L+)"
else
  bad "overlay/lite needs usr/lib/tmpfiles.d/lite-var-run.conf with: L+ /var/run - - - - ../run"
fi
if [ "$(printf '%s\n' var.conf "${TMPF##*/}" | LC_ALL=C sort | sed -n 1p)" = "${TMPF##*/}" ]; then
  ok "${TMPF##*/} sorts before systemd's var.conf, so its line is the one applied"
else
  bad "${TMPF##*/} must sort before var.conf, or systemd's plain L line wins"
fi
um_tmp=$(mktemp -d) || exit 2
um_file="$um_tmp/t/usr/share/usbmount/usbmount"
mkdir -p "${um_file%/*}"
cp "$HERE/buildroot-external/overlay/base/usr/share/usbmount/usbmount" "$um_file"
if sh "$BOARD/usbmount-run-dir.sh" "$um_tmp/t" >"$um_tmp/out" 2>&1 &&
   ! grep -v '^[[:space:]]*#' "$um_file" | grep -q '/var/' &&
   grep -q 'mkdir -p /run/usbmount' "$um_file"; then
  ok "usbmount (a udev program) keeps its lock under /run/usbmount and names nothing under /var"
else
  bad "usbmount after usbmount-run-dir.sh still writes under /var: $(cat "$um_tmp/out")"
fi
printf '#!/bin/sh\n# /var/run in a comment is fine\nmkdir -p /var/lib/usbmount\n' >"$um_file"
if sh "$BOARD/usbmount-run-dir.sh" "$um_tmp/t" >/dev/null 2>&1; then
  bad "usbmount-run-dir.sh lets a udev program through that writes under /var"
else
  ok "usbmount-run-dir.sh stops the build on any other /var path in usbmount"
fi
rm -rf "$um_tmp"
if grep -v '^[[:space:]]*#' "$BOARD/post-build-systemd.sh" | grep -q 'usbmount-run-dir\.sh'; then
  ok "post-build-systemd runs usbmount-run-dir.sh on the target"
else
  bad "post-build-systemd.sh must run usbmount-run-dir.sh on the target"
fi
early=0
for f in "$U"/*.service; do
  n=${f##*/}
  cat "$f" "$f.d/"*.conf 2>/dev/null | grep -q '^DefaultDependencies=no' || continue
  after "$n" | grep -qx systemd-tmpfiles-setup.service && continue
  if cat "$f" "$f.d/"*.conf 2>/dev/null | grep -v '^#' | grep -q '/var/run'; then
    bad "$n starts before systemd-tmpfiles-setup and names /var/run"; early=$((early+1))
  fi
done
[ "$early" = 0 ] && ok "no unit that starts before systemd-tmpfiles-setup names /var/run"
if cat "$U"/*.service "$U"/*.service.d/*.conf 2>/dev/null | grep '^PIDFile=' | grep -qv '^PIDFile=/run/'; then
  bad "a PIDFile= outside /run: $(cat "$U"/*.service "$U"/*.service.d/*.conf 2>/dev/null | grep '^PIDFile=' | grep -v '^PIDFile=/run/' | tr '\n' ' ')"
else
  ok "every PIDFile= is under /run"
fi

# the LAN gateway steps run only with a LAN gateway in the radio configuration: both units carry the
# condition before their script, the condition's test is S58LGWFirmwareUpdate's own on the same two
# files, and it says in the journal when it skips. No LAN gateway hardware is needed: fake configs.
COND="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-lgw-configured"
S58="$HERE/buildroot-external/overlay/base/etc/init.d/S58LGWFirmwareUpdate"
for n in occu-lgw-firmware-update occu-set-lgw-key; do
  f="$U/$n.service"
  cl=$(grep -n "^ExecCondition=/usr/libexec/occu/lite-lgw-configured $n\$" "$f" | cut -d: -f1)
  sl=$(grep -n '^ExecStart=' "$f" | cut -d: -f1)
  if [ -n "$cl" ] && [ -n "$sl" ] && [ "$cl" -lt "$sl" ]; then ok "$n runs only with a LAN gateway"; else bad "$n: no ExecCondition=/usr/libexec/occu/lite-lgw-configured $n before its ExecStart"; fi
done
[ -x "$COND" ] && ok "lite-lgw-configured is executable" || bad "lite-lgw-configured is not executable"
for p in '"^Type = \(HMLGW2\|Lan Interface\)"' '"^Type = HMWLGW"'; do
  if grep -qF "grep -qm1 $p" "$S58" && grep -qF "grep -qm1 $p" "$COND"; then ok "the condition reads what S58 reads: $p"; else bad "S58 and the condition differ on $p"; fi
done
lgw=$(mktemp -d) || exit 2
printf '#!/bin/sh\necho "$*" >> "%s/logged"\n' "$lgw" > "$lgw/logger"
chmod +x "$lgw/logger"
lgw_case() {  # lgw_case <rfd.conf text or -> <hs485d.conf text or -> <0|1> <what>
  rm -f "$lgw/rfd.conf" "$lgw/hs485d.conf" "$lgw/logged"
  [ "$1" = - ] || printf "$1" > "$lgw/rfd.conf"
  [ "$2" = - ] || printf "$2" > "$lgw/hs485d.conf"
  OCCU_RFD_CONF="$lgw/rfd.conf" OCCU_HS485D_CONF="$lgw/hs485d.conf" OCCU_LOGGER="$lgw/logger" sh "$COND" occu-lgw-firmware-update
  rc=$?
  if [ "$rc" != "$3" ]; then bad "LAN gateway condition, $4: exit $rc, want $3"; return; fi
  if [ "$3" = 1 ]; then
    grep -q 'no LAN gateway in .*: occu-lgw-firmware-update is skipped' "$lgw/logged" 2>/dev/null && ok "skipped, and said so: $4" || bad "no journal line when skipping: $4"
  else
    [ ! -e "$lgw/logged" ] && ok "runs as before: $4" || bad "a journal line although it runs: $4"
  fi
}
lgw_case '[Interface 0]\nType = Lan Interface\nSerial Number = LEQ0000001\nEncryption Key = x\n' - 0 "an RF LAN gateway (Lan Interface) in rfd.conf"
lgw_case 'Listen Port = 2001\n[Interface 0]\nType = HMLGW2\nDescription = HM-LGW-O-TW-W-EU\n' - 0 "an HM-LGW-O-TW-W-EU (HMLGW2) in rfd.conf"
lgw_case '[Interface 0]\nType = CCU2\nComPortFile = /dev/mmd_bidcos\n' '[Interface 0]\nType = HMWLGW\nSerial Number = JEQ0000001\n' 0 "a wired LAN gateway in hs485d.conf"
lgw_case '[Interface 0]\nType = CCU2\nComPortFile = /dev/mmd_bidcos\n' - 1 "only the radio module, no hs485d.conf"
lgw_case '[Interface 0]\nType = USB Interface\nDescription = HM-CFG-USB-2\n' '[Interface 0]\nType = HMW-Interface\n' 1 "a USB interface and no wired gateway"
lgw_case - - 1 "neither file"
lgw_case '#Type = Lan Interface\n  Type = HMLGW2\n' - 1 "a commented and an indented line (S58 anchors on ^Type)"
rm -rf "$lgw"

# every unit a lite unit names exists: the overlay's units, plus stand-ins for the ones systemd and
# the packages bring (a new name outside both lists is a typo or a unit that is gone)
refs_root=$(mktemp -d) || exit 2
mkdir -p "$refs_root/usr/lib/systemd/system"
cp -a "$U"/. "$refs_root/usr/lib/systemd/system/"
for n in local-fs.target multi-user.target network-online.target network-pre.target network.target remote-fs.target shutdown.target sysinit.target \
         basic.target timers.target systemd-journald.service systemd-tmpfiles-setup.service \
         occulited.service occulited-helper.service psplash-start.service sshd.service; do
  [ -e "$refs_root/usr/lib/systemd/system/$n" ] || : > "$refs_root/usr/lib/systemd/system/$n"
done
if sh "$HERE/scripts/lite-unit-refs.sh" "$refs_root" > "$refs_root.out" 2>&1; then
  ok "every unit the lite units name exists ($(tail -n 1 "$refs_root.out"))"
else
  bad "a lite unit names a unit that does not exist: $(grep MISSING "$refs_root.out" | tr '\n' ' ')"
fi
rm -f "$refs_root/usr/lib/systemd/system/occu-init-rtc.service"
printf '# openccu-lite: test\n[Unit]\nAfter=occu-no-such.service\n' > "$refs_root/usr/lib/systemd/system/occu-test.service"
if sh "$HERE/scripts/lite-unit-refs.sh" "$refs_root" > "$refs_root.out" 2>&1; then
  bad "lite-unit-refs.sh misses a unit that is gone"
elif grep -q 'MISSING: occu-no-such.service' "$refs_root.out" && grep -q 'MISSING: occu-init-rtc.service' "$refs_root.out" &&
     sh "$HERE/scripts/lite-unit-refs.sh" "$refs_root" occu-no-such.service occu-init-rtc.service > /dev/null 2>&1; then
  ok "lite-unit-refs.sh names a missing unit and takes an allowed one"
else
  bad "lite-unit-refs.sh: $(cat "$refs_root.out")"
fi
rm -rf "$refs_root" "$refs_root.out"
if grep -v '^[[:space:]]*#' "$HERE/buildroot-external/board/lite/post-build-systemd.sh" | grep -q 'lite-unit-refs\.sh'; then
  ok "the lite post-build checks the image's unit references"
else
  bad "post-build-systemd.sh must run lite-unit-refs.sh"
fi

# no cycle: "a b" means a starts before b; Before= of a unit is the same edge the other way round
edges=$(mktemp) || exit 2
trap 'rm -f "$edges"' EXIT
for f in "$U"/*.service "$U"/*.target "$U"/*.timer; do
  [ -f "$f" ] || continue
  n=${f##*/}
  after "$n" | while read -r d; do echo "$d $n"; done
  cat "$f" "$f.d/"*.conf 2>/dev/null | sed -n 's/^Before=//p' | tr ' ' '\n' | grep -v '^$' | while read -r d; do echo "$n $d"; done
done > "$edges"
# task 119: an early addon is ordered after the network, lighttpd, occulited and occu-addons only;
# none of those may itself come after an interface daemon, directly or through another unit, or the
# early start would wait for the interfaces all the same
pre=$(mktemp) || exit 2
printf '%s\n' network.target lighttpd.service occulited.service occu-addons.service > "$pre"
while :; do
  n_before=$(wc -l < "$pre")
  awk 'NR==FNR { want[$1] = 1; next } ($2 in want) { print $1 }' "$pre" "$edges" > "$pre.new"
  sort -u "$pre" "$pre.new" > "$pre.all"
  mv "$pre.all" "$pre"
  [ "$(wc -l < "$pre")" = "$n_before" ] && break
done
waits=$(grep -x 'rfd.service\|hmipserver.service\|hs485d.service\|multimacd.service\|hmipserver-ready.service' "$pre" | tr '\n' ' ')
if [ -z "$waits" ]; then
  ok "an early addon's base units wait for no interface daemon ($(wc -l < "$pre") units before them)"
else
  bad "an early addon's base units come after: $waits"
fi
rm -f "$pre" "$pre.new"
# task 158: the board LEDs are set once the radio hardware is known - not after the addons, the
# rc.local step, the network or an interface daemon, directly or through another unit
need occu-board-leds.service occu-init-rf-hardware.service
never occu-board-leds.service addons.target occu-rc-local.service occu-leds.service network.target
early=$(mktemp) || exit 2
echo occu-board-leds.service > "$early"
while :; do
  n_before=$(wc -l < "$early")
  awk 'NR==FNR { want[$1] = 1; next } ($2 in want) { print $1 }' "$early" "$edges" > "$early.new"
  sort -u "$early" "$early.new" > "$early.all"
  mv "$early.all" "$early"
  [ "$(wc -l < "$early")" = "$n_before" ] && break
done
late=$(grep -x 'addons.target\|occu-rc-local.service\|occu-leds.service\|network.target\|occu-network.service\|rfd.service\|hmipserver.service\|hs485d.service\|multimacd.service' "$early" | tr '\n' ' ')
if [ -z "$late" ]; then
  ok "occu-board-leds waits for none of the late units ($(wc -l < "$early") units before it)"
else
  bad "occu-board-leds comes after: $late"
fi
rm -f "$early" "$early.new"
# B-249: the LAN9514 reset runs before the network start, which gives up at once without eth0
if before occu-lan-reset.service | grep -qx occu-network.service; then
  ok "occu-lan-reset before occu-network"
else
  bad "occu-lan-reset must order before occu-network.service"
fi
never occu-lan-reset.service occu-network.service network.target network-online.target
if tsort "$edges" >/dev/null 2>"$edges.err"; then
  ok "no ordering cycle ($(wc -l < "$edges") edges)"
else
  bad "ordering cycle: $(cat "$edges.err")"
fi
rm -f "$edges.err"

[ "$fails" = 0 ] && echo "lite unit order: all cases passed" || { echo "lite unit order: $fails case(s) failed"; exit 1; }
