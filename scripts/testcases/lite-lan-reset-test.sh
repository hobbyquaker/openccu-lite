#!/bin/sh
# openccu-lite (B-249): lite-lan-reset, the LAN9514 reset before the network start. Against a fake
# root with a small simulator that plays the kernel's part (the export makes the gpio directory,
# the re-powered port brings the hub and eth0 back, or not): nothing on other boards or with the
# hub there, the hub waited for during the grace, LAN_RUN found by its line name (not
# LAN_RUN_BOOT) and pulsed low then high before the port is re-powered (0, then 1), the line
# unexported again, dwc2's unbind/bind, and the outcome in /run/lite-lan-reset for a recovered,
# a hub-only and a failed reset. Nothing needs root.
#
# Usage: sh scripts/testcases/lite-lan-reset-test.sh    (from the fork's checkout)
#
# B-303: the recovery system carries the same logic as /bin/lan9514-reset (its record in
# /tmp/lan9514-reset), run from /etc/network/if-pre-up.d before eth0 comes up, and S90AutoUpdate
# keeps its log, the USB tree and the kernel log with the install log. Without an argument this
# runs every case against both scripts, checks that their code is the same apart from the record's
# path, and checks the recovery's hook and diagnostics.
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
LITE="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-lan-reset"
REC="$HERE/buildroot-external/package/recovery-system/external/overlay/base"
if [ $# -eq 0 ]; then
  rc=0
  sh "$0" lite || rc=1
  sh "$0" recovery || rc=1
  f=0
  if [ "$(sed -n '/^R=/,$p' "$LITE" | sed 's|^MARK=.*|MARK=|')" = "$(sed -n '/^R=/,$p' "$REC/bin/lan9514-reset" | sed 's|^MARK=.*|MARK=|')" ]; then
    echo "ok   the recovery's lan9514-reset is lite-lan-reset's code (only the record's path differs)"
  else
    echo "FAIL the recovery's lan9514-reset and lite-lan-reset differ beyond the record's path"; f=1
  fi
  H="$REC/etc/network/if-pre-up.d/lan9514-reset"
  if [ -x "$H" ] && grep -q '^\[ "${IFACE}" = "eth0" \] || exit 0$' "$H" && grep -q '^/bin/lan9514-reset 2>&1 | tee -a /tmp/lan9514-reset.log$' "$H" \
     && [ "$(ls "$REC/etc/network/if-pre-up.d" | sort | head -n 1)" = lan9514-reset ]; then
    echo "ok   the recovery runs it for eth0 before the other pre-up hooks"
  else
    echo "FAIL the recovery's if-pre-up.d hook is missing, not executable, or not first"; f=1
  fi
  S90="$REC/etc/init.d/S90AutoUpdate"
  fn=$(sed -n '/^recovery_diagnostics() {$/,/^}$/p' "$S90")
  if [ -n "$fn" ] && echo "$fn" | grep -q '/tmp/lan9514-reset.log' && echo "$fn" | grep -q '/sys/bus/usb/devices' \
     && echo "$fn" | grep -q 'dmesg' && grep -q 'recovery_diagnostics >>"${log}"' "$S90"; then
    echo "ok   the kept install log gets the reset's log, the USB tree and the kernel log"
  else
    echo "FAIL S90AutoUpdate does not keep the recovery's diagnostics with the install log"; f=1
  fi
  # the diagnostics themselves, in a shell: no failure without the files of a real system
  out=$( (eval "$fn"; recovery_diagnostics) 2>&1 ); drc=$?
  if [ "$drc" = 0 ] && echo "$out" | grep -q '^--- recovery system diagnostics ---$' && echo "$out" | grep -q '^usb devices:$'; then
    echo "ok   recovery_diagnostics runs and ends 0"
  else
    echo "FAIL recovery_diagnostics: rc $drc: $out"; f=1
  fi
  [ "$rc" = 0 ] && [ "$f" = 0 ] && { echo "LAN reset (lite and recovery): all cases passed"; exit 0; }
  exit 1
fi
case "$1" in
  lite) S=$LITE; MARKREL=/run/lite-lan-reset ;;
  recovery) S="$REC/bin/lan9514-reset"; MARKREL=/tmp/lan9514-reset ;;
  *) echo "usage: $0 [lite|recovery]"; exit 2 ;;
esac
echo "--- $1: $S"
[ -x "$S" ] || { echo "the script is not found or not executable at $S"; exit 2; }
T=$(mktemp -d) || exit 2
sim_pid=""
trap '[ -n "$sim_pid" ] && kill "$sim_pid" 2>/dev/null; rm -rf "$T" "$T.out" "$T.log"' EXIT

fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }
has() { # <key=value> <what>: a line of the marker
  grep -qx "$1" "$T$MARKREL" 2>/dev/null && ok "$2" || bad "$2: /run/lite-lan-reset has $(tr '\n' ' ' < "$T$MARKREL" 2>/dev/null), want $1"
}

# a Pi 3 B as the kernel shows it; the hub and eth0 only with "hub"
board() { # <model> [hub]
  rm -rf "${T:?}"/* "$T.log"
  mkdir -p "$T/proc/device-tree" "$T/run" "$T/tmp" "$T/sys/class/gpio" "$T/sys/bus/usb/devices" "$T/sys/class/net"
  printf '%s\000' "$1" > "$T/proc/device-tree/model"
  : > "$T/sys/class/gpio/export"; : > "$T/sys/class/gpio/unexport"
  mkdir -p "$T/sys/class/gpio/gpiochip512/device/of_node" "$T/sys/class/gpio/gpiochip568/device/of_node"
  echo 512 > "$T/sys/class/gpio/gpiochip512/base"
  printf 'ID_SDA\000ID_SCL\000GPIO2\000LAN_RUN_BOOT\000GPIO30\000' > "$T/sys/class/gpio/gpiochip512/device/of_node/gpio-line-names"
  echo 568 > "$T/sys/class/gpio/gpiochip568/base"
  printf 'BT_ON\000WL_ON\000STATUS_LED\000LAN_RUN\000HDMI_HPD_N\000CAM_GPIO0\000CAM_GPIO1\000PWR_LOW_N\000' \
    > "$T/sys/class/gpio/gpiochip568/device/of_node/gpio-line-names"
  mkdir -p "$T/sys/devices/platform/soc/3f980000.usb"
  echo 'Bus Power = 0x1' > "$T/sys/devices/platform/soc/3f980000.usb/buspower"
  if [ "${2:-}" = hub ]; then hub; mkdir -p "$T/sys/class/net/eth0"; fi
}
hub() { mkdir -p "$T/sys/bus/usb/devices/1-1"; echo 0424 > "$T/sys/bus/usb/devices/1-1/idVendor"; }

# the kernel's part, polled every 10 ms; every change goes to $T.log. <after the port's power
# comes back>: recover (hub, then eth0), hub-only, none; "grace" brings the hub after 0.2 s alone
sim() {
  mode=$1; last=""; off=""
  if [ "$mode" = grace ]; then sleep 0.2; hub; mkdir -p "$T/sys/class/net/eth0"; return; fi
  while :; do
    g="$T/sys/class/gpio/gpio571"
    if [ "$(cat "$T/sys/class/gpio/export")" = 571 ] && [ ! -d "$g" ]; then
      mkdir -p "$g"; echo out > "$g/direction"; echo 1 > "$g/value"; : > "$T/sys/class/gpio/export"; echo "export" >> "$T.log"
    fi
    case "$(cat "$g/direction" 2>/dev/null)" in  # the kernel's "low"/"high": an output at that level
      low) echo out > "$g/direction"; echo 0 > "$g/value" ;;
      high) echo out > "$g/direction"; echo 1 > "$g/value" ;;
    esac
    if [ "$(cat "$T/sys/class/gpio/unexport")" = 571 ]; then
      echo "unexport at $(cat "$g/direction")/$(cat "$g/value")" >> "$T.log"; rm -rf "$g"; : > "$T/sys/class/gpio/unexport"
    fi
    now="$(cat "$g/direction" 2>/dev/null)/$(cat "$g/value" 2>/dev/null) $(cat "$T/sys/devices/platform/soc/3f980000.usb/buspower" 2>/dev/null) $(cat "$T/sys/bus/platform/drivers/dwc2/unbind" "$T/sys/bus/platform/drivers/dwc2/bind" 2>/dev/null | tr '\n' ,)"
    [ "$now" != "$last" ] && { echo "$now" >> "$T.log"; last=$now; }
    case "$now" in *" 0 "*|*" 0"|*"3f980000.usb,") off=1 ;; esac
    if [ -n "$off" ]; then
      case "$now" in
        *" 1 "*|*" 1"|*"3f980000.usb,3f980000.usb,")
          case "$mode" in
            recover) sleep 0.2; hub; sleep 0.2; mkdir -p "$T/sys/class/net/eth0" ;;
            hub-only) sleep 0.2; hub ;;
          esac
          echo "powered" >> "$T.log"; return ;;
      esac
    fi
    sleep 0.01
  done
}
run() { # <simulator mode>
  sim_pid=""
  [ "$1" != none ] && { sim "$1" & sim_pid=$!; }
  LITE_ROOT="$T" LAN_RESET_GRACE=5 LAN_RESET_HUB_WAIT=20 LAN_RESET_ETH_WAIT=10 LAN_RESET_PULSE=0.3 sh "$S" > "$T.out" 2>&1
  rc=$?
  [ -n "$sim_pid" ] && { kill "$sim_pid" 2>/dev/null; wait "$sim_pid" 2>/dev/null; sim_pid=""; }
  return $rc
}
order() { # <what> <pattern>...: the patterns appear in the simulator's log in this order
  what=$1; shift; line=0
  for p in "$@"; do
    n=$(awk -v s="$line" -v p="$p" 'NR > s && index($0, p) { print NR; exit }' "$T.log" 2>/dev/null)
    [ -n "$n" ] || { bad "$what: '$p' not seen after line $line of: $(tr '\n' '|' < "$T.log" 2>/dev/null)"; return; }
    line=$n
  done
  ok "$what"
}

# other boards: nothing, even without a hub
board "Raspberry Pi 4 Model B Rev 1.1"; run none; rc=$?
[ "$rc" = 0 ] && [ ! -e "$T$MARKREL" ] && [ ! -s "$T/sys/class/gpio/export" ] && [ "$(cat "$T/sys/devices/platform/soc/3f980000.usb/buspower")" = 'Bus Power = 0x1' ] \
  && ok "a Pi 4: nothing done, exit 0" || bad "a Pi 4: rc $rc, $(cat "$T.out")"
rm -rf "$T/proc"; run none; rc=$?
[ "$rc" = 0 ] && [ ! -e "$T$MARKREL" ] && ok "no device tree (x86_64): nothing done, exit 0" || bad "no device tree: rc $rc"

# the hub there: no reset
board "Raspberry Pi 3 Model B Rev 1.2" hub; run none; rc=$?
[ "$rc" = 0 ] && [ ! -s "$T/sys/class/gpio/export" ] && [ "$(cat "$T/sys/devices/platform/soc/3f980000.usb/buspower")" = 'Bus Power = 0x1' ] \
  && ok "hub present: no reset" || bad "hub present: rc $rc, $(cat "$T.out")"
has result=present "hub present: result=present"
[ ! -s "$T.out" ] && ok "hub present at once: nothing in the journal" || bad "hub present at once: said $(cat "$T.out")"

# the hub comes during the grace: no reset
board "Raspberry Pi 3 Model B Rev 1.2"; run grace
has result=present "hub during the grace: result=present"
[ ! -e "$T/sys/class/gpio/gpio571" ] && [ "$(cat "$T/sys/devices/platform/soc/3f980000.usb/buspower")" = 'Bus Power = 0x1' ] \
  && ok "hub during the grace: no reset" || bad "hub during the grace: reset anyway"

# missing, and the reset brings it back
board "Raspberry Pi 3 Model B Rev 1.2"; run recover; rc=$?
[ "$rc" = 0 ] && ok "recovered: exit 0" || bad "recovered: rc $rc"
order "recovered: export, LAN_RUN low, then high, unexport, then the port off and on" \
  export "out/0 Bus" "unexport at out/1" " 0 " " 1 "
has result=recovered "recovered: result=recovered"
has lan_run_gpio=571 "recovered: LAN_RUN is gpio571 (the expander's line 3, not LAN_RUN_BOOT)"
has lan_run_before=out/1 "recovered: the line's state before the pulse"
has controller=dwc_otg "recovered: dwc_otg's buspower"
[ ! -d "$T/sys/class/gpio/gpio571" ] && ok "recovered: the line unexported again" || bad "recovered: gpio571 still exported"
grep -q 'no LAN9514 hub at USB 1-1' "$T.out" && grep -q 'LAN9514 back: hub after' "$T.out" \
  && ok "recovered: the journal says missing and back" || bad "recovered: journal $(cat "$T.out")"

# the hub comes back, eth0 does not
board "Raspberry Pi 3 Model B Plus Rev 1.3"; run hub-only
has result=hub-only "a 3 B+ with the hub back but no eth0: result=hub-only"

# nothing comes back
board "Raspberry Pi 3 Model B Rev 1.2"; run nothing; rc=$?
[ "$rc" = 0 ] && ok "failed: still exit 0" || bad "failed: rc $rc"
has result=failed "failed: result=failed"
grep -q 'still missing' "$T.out" && ok "failed: the journal says so" || bad "failed: journal $(cat "$T.out")"

# dwc2 instead of dwc_otg: unbind and bind
board "Raspberry Pi 3 Model B Rev 1.2"; rm -rf "$T/sys/devices/platform/soc/3f980000.usb"
mkdir -p "$T/sys/bus/platform/drivers/dwc2/3f980000.usb"
: > "$T/sys/bus/platform/drivers/dwc2/unbind"; : > "$T/sys/bus/platform/drivers/dwc2/bind"
run recover
has controller=dwc2 "dwc2: controller=dwc2"
[ "$(cat "$T/sys/bus/platform/drivers/dwc2/unbind")" = 3f980000.usb ] && [ "$(cat "$T/sys/bus/platform/drivers/dwc2/bind")" = 3f980000.usb ] \
  && ok "dwc2: unbound and bound again" || bad "dwc2: unbind '$(cat "$T/sys/bus/platform/drivers/dwc2/unbind")' bind '$(cat "$T/sys/bus/platform/drivers/dwc2/bind")'"
has result=recovered "dwc2: result=recovered"

# no line named LAN_RUN: the port is still re-powered
board "Raspberry Pi 3 Model B Rev 1.2"
printf 'BT_ON\000WL_ON\000' > "$T/sys/class/gpio/gpiochip568/device/of_node/gpio-line-names"
run recover
has lan_run_gpio= "no LAN_RUN line: no gpio"
has result=recovered "no LAN_RUN line: the bus reset alone"
grep -q 'no GPIO line named LAN_RUN' "$T.out" && ok "no LAN_RUN line: the journal says so" || bad "no LAN_RUN line: journal $(cat "$T.out")"

[ "$fails" = 0 ] && echo "lite LAN reset: all cases passed" || { echo "lite LAN reset: $fails case(s) failed"; exit 1; }
