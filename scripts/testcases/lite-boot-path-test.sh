#!/bin/sh
# openccu-lite: the scripts behind the boot path's second pass, run against stand-ins.
#
#   - S47InitRFHardware: the wait for a route to a configured HB-RF-ETH (none configured, the
#     network early, late, never) and the board-serial fallback (eth0 with and without a default
#     route, no eth0, only virtual interfaces);
#   - S47InitRFHardware's probe (task 138): a GPIO node is probed with RF_GPIO_PROBE_TIMEOUT; when no
#     module was found at all, the other raw-uart nodes and then the cut GPIO node are probed again;
#   - S48UpdateRFHardware: with COPRO_UPDATE_AT_BOOT=no a newer firmware is reported and never
#     flashed, without it the flash runs as before;
#   - lite-clock-valid: a real-time clock passes at once, NTP early, chronyd late (the timeout
#     counts from its first answer), chronyd never;
#   - lite-radio-stop-wait: no wait outside a shutdown, the wait until the radio units are down,
#     the limit;
#   - lite-ca-certificates: the prebuilt bundle without user certificates, the cache built,
#     reused, and rebuilt when a certificate or the image changes;
#   - ca-prebuilt.sh: the links point to the box's paths, one hash link per certificate.
#
# S47 and S48 use busybox ash's [[ ]], so those parts run under bash. Their absolute paths are
# rewritten into a temporary root; nothing needs root, a radio module or a network.
#
# Usage: sh scripts/testcases/lite-boot-path-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
BASE="$HERE/buildroot-external/overlay/base"
LIBEXEC="$HERE/buildroot-external/overlay/lite/usr/libexec/occu"
command -v bash >/dev/null || { echo "bash is needed for the S47/S48 cases"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

# stand-ins on PATH: sleep counts instead of sleeping, ip answers from files
STUB="$T/stub"; mkdir -p "$STUB"
cat > "$STUB/sleep" <<'EOF'
#!/bin/sh
n=$(cat "$STUBSTATE/sleeps" 2>/dev/null || echo 0)
echo $((n + 1)) > "$STUBSTATE/sleeps"
[ -n "${STUBUPTIME:-}" ] && awk -v d="$1" '{printf "%.2f 0\n", $1 + d}' "$STUBUPTIME" > "$STUBUPTIME.n" && mv "$STUBUPTIME.n" "$STUBUPTIME"
exit 0
EOF
cat > "$STUB/ip" <<'EOF'
#!/bin/sh
# "ip route get X": fails until the call count reaches $STUBSTATE/route-after (never without it)
# "ip route show default": prints $STUBSTATE/default-route after that count
n=$(cat "$STUBSTATE/ipcalls" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$STUBSTATE/ipcalls"
after=$(cat "$STUBSTATE/route-after" 2>/dev/null || echo 999999)
case "$*" in
  "route get "*) [ "$n" -ge "$after" ] && { echo "$3 via 10.0.0.1 dev eth0"; exit 0; }; echo "RTNETLINK answers: Network is unreachable" >&2; exit 2 ;;
  "route show default") [ "$n" -ge "$after" ] && echo "default via 10.0.0.1 dev eth0"; exit 0 ;;
esac
exit 1
EOF
chmod 755 "$STUB/sleep" "$STUB/ip"
export STUBSTATE="$T/state"
reset_state() { rm -rf "$STUBSTATE"; mkdir -p "$STUBSTATE"; }

# --- S47: the HB-RF-ETH wait ------------------------------------------------------------------
S47="$BASE/etc/init.d/S47InitRFHardware"
sed -n '/^wait_for_hb_rf_eth_route() {/,/^}/p; /^board_mac() {/,/^}/p' "$S47" > "$T/s47-funcs.sh"
grep -q '^board_mac() {' "$T/s47-funcs.sh" && grep -q '^wait_for_hb_rf_eth_route() {' "$T/s47-funcs.sh" \
  || { bad "S47's two helper functions not found"; }

hb_case() {  # hb_case <address> <route after n calls or -> <want rc> <what>
  reset_state
  [ "$2" = - ] || echo "$2" > "$STUBSTATE/route-after"
  out=$(PATH="$STUB:$PATH" bash -c ". '$T/s47-funcs.sh'; wait_for_hb_rf_eth_route '$1'; echo rc=\$?")
  rc=${out##*rc=}
  sleeps=$(cat "$STUBSTATE/sleeps" 2>/dev/null || echo 0)
  if [ "$rc" = "$3" ]; then ok "HB-RF-ETH wait, $4 (rc $rc, $sleeps polls)"; else bad "HB-RF-ETH wait, $4: rc $rc, want $3 ($out)"; fi
}
hb_case 192.168.1.50 1 0 "the network already up: no poll"
reset_state; echo 1 > "$STUBSTATE/route-after"
PATH="$STUB:$PATH" bash -c ". '$T/s47-funcs.sh'; wait_for_hb_rf_eth_route 192.168.1.50" >/dev/null
[ ! -e "$STUBSTATE/sleeps" ] && ok "HB-RF-ETH wait: no sleep when the route is there" || bad "HB-RF-ETH wait slept although the route was there"
hb_case 192.168.1.50 20 0 "the network late (4 s)"
[ "$(cat "$STUBSTATE/sleeps")" = 19 ] && ok "late network: polled every 0.2 s until the route came" || bad "late network: $(cat "$STUBSTATE/sleeps") polls, want 19"
hb_case 192.168.1.50 - 1 "the network never comes"
[ "$(cat "$STUBSTATE/sleeps")" = 300 ] && ok "no network: gives up after 300 polls (60 s)" || bad "no network: $(cat "$STUBSTATE/sleeps") polls, want 300"
out=$(reset_state; PATH="$STUB:$PATH" bash -c ". '$T/s47-funcs.sh'; wait_for_hb_rf_eth_route 192.168.1.50")
[ "$out" = "$(printf '%.0s.' $(seq 1 30))" ] && ok "no network: a dot every 2 s, as the connect loop prints them" || bad "dots: '$out'"
hb_case fe80::1 5 0 "an IPv6 address"
hb_case hb-rf-eth.lan 3 0 "a name: waits for a default route"
# nothing configured: S47 does not call the wait at all (the call is inside the address check)
awk '/HB_RF_ETH_ADDRESS=\$\(head/{f=1} f&&/wait_for_hb_rf_eth_route/{print "inside"; exit} f&&/^  fi$/{print "outside"; exit}' "$S47" > "$T/where"
[ "$(cat "$T/where")" = inside ] && ok "without an address in /etc/config/hb_rf_eth there is no wait" || bad "the wait is not inside the HB-RF-ETH branch"

# --- S47: the board-serial fallback -----------------------------------------------------------
N="$T/net"
mknet() {  # mknet <name> <type> <mac> <physical: y|n>
  mkdir -p "$N/$1"; echo "$2" > "$N/$1/type"; echo "$3" > "$N/$1/address"
  [ "$4" = y ] && ln -sfn /dev/null "$N/$1/device"
  return 0
}
mac_case() {  # mac_case <want> <what>
  got=$(bash -c ". '$T/s47-funcs.sh'; board_mac '$N'")
  if [ "$got" = "$1" ]; then ok "board MAC, $2: ${got:-none}"; else bad "board MAC, $2: '$got', want '$1'"; fi
}
rm -rf "$N"; mknet lo 772 00:00:00:00:00:00 n; mknet eth0 1 dc:a6:32:03:a9:fa y; mknet wlan0 1 dc:a6:32:03:a9:fb y
mac_case dc:a6:32:03:a9:fa "eth0 and wlan0 (whichever holds the default route)"
full=$(bash -c ". '$T/s47-funcs.sh'; MAC=\$(board_mac '$N'); echo -n \"\$(echo \"\${MAC}\" | tr -d : | tail -c 10)\"")
want=$(echo dc:a6:32:03:a9:fa | tr -d : | tail -c 10)
[ "$full" = "$want" ] && ok "the serial is made from the MAC as before: $full" || bad "serial: $full, want $want"
rm -rf "$N"; mknet lo 772 00:00:00:00:00:00 n; mknet docker0 1 02:42:00:00:00:01 n; mknet enp1s0 1 bc:24:11:db:50:d9 y
mac_case bc:24:11:db:50:d9 "no eth0: the first physical interface, not a bridge"
rm -rf "$N"; mknet lo 772 00:00:00:00:00:00 n; mknet eth0 1 00:00:00:00:00:00 y; mknet eth1 1 bc:24:11:00:00:02 y
mac_case bc:24:11:00:00:02 "eth0 without an address of its own"
rm -rf "$N"; mknet lo 772 00:00:00:00:00:00 n; mknet veth0 1 02:42:00:00:00:02 n; mknet wg0 65534 "" n
mac_case "" "only virtual interfaces"
if grep -q 'MAC=$(board_mac)' "$S47"; then ok "S47's fallback uses board_mac (no default route needed)"; else bad "S47's fallback does not use board_mac"; fi

# --- S47: the GPIO probe with a short limit (task 138) -----------------------------------------
Q="$T/probe"
# probe_case <timeout value or -> <timeout rc> <preset HM_HMRF_DEV or -> <node|type|delay|answer>... ;
# answer is a module name or "none"; detect_radio_module answers after <delay> s, timeout kills it
# when the delay exceeds its limit
probe_case() {
  pc_to=$1; pc_rc=$2; pc_pre=$3; shift 3
  reset_state; rm -rf "$Q"; mkdir -p "$Q/sys" "$Q/dev" "$Q/var" "$Q/etc/config" "$Q/bin" "$Q/mods"
  pc_nodes=
  for spec in "$@"; do
    n=${spec%%|*}; r=${spec#*|}; ty=${r%%|*}; r=${r#*|}; dl=${r%%|*}; an=${r#*|}
    mkdir -p "$Q/sys/$n"; echo "$ty" > "$Q/sys/$n/device_type"; : > "$Q/sys/$n/reset_radio_module"; : > "$Q/dev/$n"
    echo "$dl $an" > "$Q/mods/$n"; pc_nodes="$pc_nodes $n"
  done
  cat > "$Q/bin/detect_radio_module" <<EOS
#!/bin/sh
n=\$(basename "\$1"); set -- \$(cat "$Q/mods/\$n")
echo "probe \$n \${LIMIT:-none}" >> "$Q/calls"
[ "\$2" = none ] && exit 1
case "\$2" in flaky:*)
  [ -e "$Q/mods/\$n.once" ] || { : > "$Q/mods/\$n.once"; echo "Error: Radio module was found, but did not respond correctly"; exit 255; }
  set -- "\$1" "\${2#flaky:}" ;;
esac
case "\$2" in
  HMIP-RFUSB) echo "HMIP-RFUSB 5A1709ADFA5B 3014F711A0001F5A1709ADFA5B 0x000000 0x7F7A50 4.4.18" ;;
  *) echo "\$2 58A9A728D4 3014F711A061A7D8A9A728D4 0xFF6C2E 0x3FAE2C 4.4.22" ;;
esac
EOS
  cat > "$Q/bin/timeout" <<EOS
#!/bin/sh
lim=\$1; shift
n=\$(basename "\$2"); d=\$(cut -d' ' -f1 "$Q/mods/\$n")
if awk -v d="\$d" -v l="\$lim" 'BEGIN{exit !(d > l)}'; then echo "probe \$n \$lim killed" >> "$Q/calls"; exit $pc_rc; fi
LIMIT=\$lim exec "\$@"
EOS
  chmod 755 "$Q/bin/detect_radio_module" "$Q/bin/timeout"
  sed -n '/^board_mac() {/,/^}/p; /^probe_radio_module() {/,/^}/p; /^query_rf_parameters() {/,/^}/p' "$S47" |
    sed -e "s|/usr/bin/timeout|$Q/bin/timeout|g" -e "s|/bin/detect_radio_module|$Q/bin/detect_radio_module|g" \
        -e "s|/sys/class/raw-uart/|$Q/sys/|g" -e "s|-c /dev/|-e $Q/dev/|g" -e "s|\"/dev/\${|\"$Q/dev/\${|g" \
        -e "s|/var/|$Q/var/|g" -e "s|/etc/config/|$Q/etc/config/|g" -e "s|/usr/local/|$Q/|g" > "$Q/funcs.sh"
  pc_env=PROBE_TEST=1; [ "$pc_to" = - ] || pc_env="RF_GPIO_PROBE_TIMEOUT=$pc_to"
  pc_hm=:; [ "$pc_pre" = - ] || pc_hm="HM_HMRF_DEV=$pc_pre"
  env "$pc_env" PATH="$STUB:$PATH" bash -c "$pc_hm; RF_DEVNODES='$pc_nodes'; . '$Q/funcs.sh'; query_rf_parameters; echo; echo \"HMRF=\${HM_HMRF_DEV} HMIP=\${HM_HMIP_DEV} HMIPNODE=\${HM_HMIP_DEVNODE##*/}\"" > "$Q/out" 2>&1
  PC_CALLS=$(tr '\n' ',' < "$Q/calls" 2>/dev/null); PC_OUT=$(tail -1 "$Q/out")
  PC_SLEEPS=$(cat "$STUBSTATE/sleeps" 2>/dev/null || echo 0)
}
pc_check() {  # pc_check <what> <want calls> <want result> [<want sleeps>]
  if [ "$PC_CALLS" = "$2" ] && [ "$PC_OUT" = "$3" ] && { [ -z "${4:-}" ] || [ "$PC_SLEEPS" = "$4" ]; }; then
    ok "GPIO probe, $1 ($PC_CALLS $PC_OUT)"
  else
    bad "GPIO probe, $1: calls '$PC_CALLS' want '$2'; '$PC_OUT' want '$3'; sleeps $PC_SLEEPS want ${4:-any} ($(head -3 "$Q/out"))"
  fi
}
GPIO="GPIO@fe201000.serial"; USB="eQ-3 HmIP-RFUSB@usb-0000:01:00.0-1.3"
probe_case 6 143 - "raw-uart|$GPIO|18.35|none" "raw-uart1|$USB|1.67|HMIP-RFUSB"
pc_check "the Pi 4 (empty header, a USB stick): 6 s on the header, no second probe" \
  "probe raw-uart 6 killed,probe raw-uart1 none," "HMRF=HMIP-RFUSB HMIP=HMIP-RFUSB HMIPNODE=raw-uart1" 0
probe_case 6 124 - "raw-uart|$GPIO|18.35|none" "raw-uart1|$USB|1.67|HMIP-RFUSB"
pc_check "coreutils' timeout status 124 is a timeout too" \
  "probe raw-uart 6 killed,probe raw-uart1 none," "HMRF=HMIP-RFUSB HMIP=HMIP-RFUSB HMIPNODE=raw-uart1" 0
probe_case 6 143 - "raw-uart|GPIO@3f201000.serial|2.8|RPI-RF-MOD"
pc_check "the Charly (an RPI-RF-MOD on the header): found within the limit, probed once" \
  "probe raw-uart 6," "HMRF=RPI-RF-MOD HMIP=RPI-RF-MOD HMIPNODE=raw-uart" 0
probe_case 6 143 - "raw-uart|$GPIO|9|RPI-RF-MOD"
pc_check "a slow module alone on the header: found by the second probe, after a reset and 2 s" \
  "probe raw-uart 6 killed,probe raw-uart none," "HMRF=RPI-RF-MOD HMIP=RPI-RF-MOD HMIPNODE=raw-uart" 1
probe_case 6 143 - "raw-uart|$GPIO|18.35|none"
pc_check "an empty header and nothing else: probed a second time without a limit, nothing found" \
  "probe raw-uart 6 killed,probe raw-uart none," "HMRF= HMIP= HMIPNODE=" 1
probe_case 6 143 - "raw-uart|$GPIO|18.35|none" "raw-uart1|$USB|1.67|none"
pc_check "a USB node that is no module: both probed again, the USB node first" \
  "probe raw-uart 6 killed,probe raw-uart1 none,probe raw-uart1 none,probe raw-uart none," "HMRF= HMIP= HMIPNODE=" 1
probe_case 6 143 - "raw-uart|$GPIO|18.35|none" "raw-uart1|$USB|1.33|flaky:HMIP-RFUSB"
pc_check "the stick answers wrongly once after the cut probe (the Pi 4, dev.2): found again, the header not probed again" \
  "probe raw-uart 6 killed,probe raw-uart1 none,probe raw-uart1 none," "HMRF=HMIP-RFUSB HMIP=HMIP-RFUSB HMIPNODE=raw-uart1" 1
probe_case 6 143 - "raw-uart1|$USB|1.33|flaky:HMIP-RFUSB" "raw-uart|$GPIO|18.35|none"
pc_check "the same with the node names swapped (the kernel names them in either order)" \
  "probe raw-uart1 none,probe raw-uart 6 killed,probe raw-uart1 none," "HMRF=HMIP-RFUSB HMIP=HMIP-RFUSB HMIPNODE=raw-uart1" 1
probe_case 6 143 - "raw-uart|$GPIO|9|RPI-RF-MOD" "raw-uart1|$USB|1.67|none"
pc_check "a slow header module beside a USB node that is no module: found by the second pass" \
  "probe raw-uart 6 killed,probe raw-uart1 none,probe raw-uart1 none,probe raw-uart none," "HMRF=RPI-RF-MOD HMIP=RPI-RF-MOD HMIPNODE=raw-uart" 1
probe_case - 143 - "raw-uart|$GPIO|18.35|none" "raw-uart1|$USB|1.67|flaky:HMIP-RFUSB"
pc_check "without the variable a failed stick is not probed again (upstream)" \
  "probe raw-uart none,probe raw-uart1 none," "HMRF= HMIP= HMIPNODE=" 0
probe_case 6 143 HM-CFG-USB-2 "raw-uart|$GPIO|18.35|none"
pc_check "an HM-CFG-USB-2 found before: no second probe" \
  "probe raw-uart 6 killed," "HMRF=HM-CFG-USB-2 HMIP= HMIPNODE=" 0
probe_case 6 143 - "raw-uart|$GPIO|1|none" "raw-uart1|$USB|1.67|none"
pc_check "an empty header that fails fast: not probed again (only a cut GPIO probe is), the USB node is" \
  "probe raw-uart 6,probe raw-uart1 none,probe raw-uart1 none," "HMRF= HMIP= HMIPNODE=" 1
probe_case - 143 - "raw-uart|$GPIO|18.35|none" "raw-uart1|$USB|1.67|HMIP-RFUSB"
pc_check "without RF_GPIO_PROBE_TIMEOUT (upstream): no limit, as before" \
  "probe raw-uart none,probe raw-uart1 none," "HMRF=HMIP-RFUSB HMIP=HMIP-RFUSB HMIPNODE=raw-uart1" 0
probe_case 0 143 - "raw-uart|$GPIO|18.35|none" "raw-uart1|$USB|1.67|HMIP-RFUSB"
pc_check "RF_GPIO_PROBE_TIMEOUT=0: no limit" \
  "probe raw-uart none,probe raw-uart1 none," "HMRF=HMIP-RFUSB HMIP=HMIP-RFUSB HMIPNODE=raw-uart1" 0
U="$HERE/buildroot-external/overlay/lite/usr/lib/systemd/system/occu-init-rf-hardware.service"
# task 129: the detection unit runs occulited's own detection, which carries the 6 s limit and the
# second pass as its defaults (--gpio-limit 6s; occulited's internal/radio tests cover both passes);
# the script above is the harness's oracle and keeps the rule for the differential test
if grep -qx 'ExecStart=/usr/bin/occulited radio run' "$U"; then ok "the detection unit runs occulited radio run (the 6 s limit is its default)"; else bad "occu-init-rf-hardware.service does not run /usr/bin/occulited radio run"; fi

# --- S48: the coprocessor is never flashed at boot --------------------------------------------
R="$T/s48"
s48_run() {  # s48_run <COPRO_UPDATE_AT_BOOT value or -> ; runs the rewritten S48 against $R
  rm -rf "$R"; mkdir -p "$R/var" "$R/etc/config" "$R/firmware/RPI-RF-MOD" "$R/firmware/HmIP-RFUSB" "$R/bin" "$R/calls"
  printf "HM_HMIP_DEV='RPI-RF-MOD'\nHM_HMIP_DEVNODE='/dev/raw-uart'\nHM_HMRF_DEV='RPI-RF-MOD'\nHM_HMRF_DEVNODE='/dev/raw-uart'\nHM_MODE='NORMAL'\n" > "$R/var/hm_mode"
  echo 4.4.22 > "$R/var/rf_firmware_version"; echo 4.4.22 > "$R/var/hmip_firmware_version"
  : > "$R/firmware/RPI-RF-MOD/dualcopro_update_blhmip-4.4.22.eq3"
  : > "$R/firmware/RPI-RF-MOD/dualcopro_update_blhmip-4.4.24.eq3"
  printf '#!/bin/sh\necho "$*" >> "%s/calls/timeout"\n' "$R" > "$R/bin/timeout"
  printf '#!/bin/sh\necho "x x x x x 4.4.24"\n' > "$R/bin/detect_radio_module"
  printf '#!/bin/sh\nexit 1\n' > "$STUB/lsusb"
  chmod 755 "$R/bin/timeout" "$R/bin/detect_radio_module" "$STUB/lsusb"
  sed -e "s|/usr/bin/timeout|$R/bin/timeout|g" -e "s|/bin/detect_radio_module|$R/bin/detect_radio_module|g" \
      -e "s|/var/|$R/var/|g" -e "s|/etc/config/|$R/etc/config/|g" -e "s|/firmware/|$R/firmware/|g" \
      -e "s|/etc/init.d/S47InitRFHardware|true|g" "$BASE/etc/init.d/S48UpdateRFHardware" > "$R/S48"
  if [ "$1" = - ]; then
    PATH="$STUB:$PATH" bash "$R/S48" start > "$R/out" 2>&1
  else
    COPRO_UPDATE_AT_BOOT=$1 PATH="$STUB:$PATH" bash "$R/S48" start > "$R/out" 2>&1
  fi
}
reset_state; s48_run no
if [ ! -e "$R/calls/timeout" ]; then ok "COPRO_UPDATE_AT_BOOT=no: the flasher is not run"; else bad "COPRO_UPDATE_AT_BOOT=no ran: $(cat "$R/calls/timeout")"; fi
grep -q 'RPI-RF-MOD: 4.4.22, 4.4.24 available (not flashed at boot)' "$R/out" && ok "the newer firmware is reported: $(cat "$R/out")" || bad "output: $(cat "$R/out")"
# (busybox ash's "set" quotes every value, bash's only where needed)
grep -Eqx "HM_HMIP_DEV='?RPI-RF-MOD'?" "$R/var/hm_mode" && grep -Eqx "HM_MODE='?NORMAL'?" "$R/var/hm_mode" && ok "/var/hm_mode is written back complete" || bad "hm_mode: $(cat "$R/var/hm_mode")"
[ "$(cat "$R/var/hmip_firmware_version")" = 4.4.22 ] && ok "the running version stays what S47 read" || bad "hmip_firmware_version: $(cat "$R/var/hmip_firmware_version")"
reset_state; s48_run -
if grep -q 'hmip-copro-update.jar -p /dev/raw-uart -o -f .*dualcopro_update_blhmip-4.4.24.eq3' "$R/calls/timeout" 2>/dev/null; then
  ok "without the variable the flash runs as upstream's"
else
  bad "without the variable: no flash ($(cat "$R/calls/timeout" 2>/dev/null)) $(cat "$R/out")"
fi
reset_state; s48_run no; rm -f "$R/firmware/RPI-RF-MOD/dualcopro_update_blhmip-4.4.24.eq3"
sed -e "s|/usr/bin/timeout|$R/bin/timeout|g" -e "s|/bin/detect_radio_module|$R/bin/detect_radio_module|g" -e "s|/var/|$R/var/|g" -e "s|/etc/config/|$R/etc/config/|g" -e "s|/firmware/|$R/firmware/|g" "$BASE/etc/init.d/S48UpdateRFHardware" > "$R/S48"
COPRO_UPDATE_AT_BOOT=no PATH="$STUB:$PATH" bash "$R/S48" start > "$R/out" 2>&1
grep -q 'RPI-RF-MOD: 4.4.22, not necessary, OK' "$R/out" && ok "the same version: 'not necessary' as before" || bad "same version: $(cat "$R/out")"
# an HmIP-RFUSB without a readable firmware (no device node): upstream re-flashes and re-runs S47
reset_state; s48_run no
printf "HM_HMIP_DEV=''\nHM_HMRF_DEV=''\nHM_MODE='NORMAL'\n" > "$R/var/hm_mode"; : > "$R/var/hmip_firmware_version"
: > "$R/firmware/HmIP-RFUSB/dualcopro_update_blhmip-4.4.22.eq3"
printf '#!/bin/sh\necho "1b1f:c020"\n' > "$STUB/lsusb"
sed -i "s|/sys/class/raw-uart/|$R/sys/|g; s|/etc/init.d/S47InitRFHardware start|echo REINIT >> $R/calls/reinit|" "$R/S48"
mkdir -p "$R/sys/raw-uart1"; echo "eQ-3 HmIP-RFUSB@usb-1" > "$R/sys/raw-uart1/device_type"
COPRO_UPDATE_AT_BOOT=no PATH="$STUB:$PATH" bash "$R/S48" start > "$R/out" 2>&1
[ ! -e "$R/calls/timeout" ] && [ ! -e "$R/calls/reinit" ] && grep -q 'HMIP-RFUSB: unknown, 4.4.22 available (not flashed at boot)' "$R/out" \
  && ok "a stick with an unreadable firmware: reported, not flashed, no re-detection" || bad "unreadable stick: calls $(cat "$R/calls/"* 2>/dev/null), $(cat "$R/out")"
rm -f "$STUB/lsusb"

# --- lite-clock-valid -------------------------------------------------------------------------
C="$T/clock"
cat > "$STUB/chronyc" <<'EOF'
#!/bin/sh
# answers from the fake uptime: not running before $STUBSTATE/chronyd-at, synchronised from $STUBSTATE/sync-at
now=$(cut -d. -f1 "$STUBUPTIME")
at=$(cat "$STUBSTATE/chronyd-at" 2>/dev/null || echo 999999)
sync=$(cat "$STUBSTATE/sync-at" 2>/dev/null || echo 999999)
[ "$now" -ge "$at" ] || { echo "506 Cannot talk to daemon" >&2; exit 1; }
[ "$now" -ge "$sync" ] && echo "Leap status     : Normal" || echo "Leap status     : Not synchronised"
EOF
chmod 755 "$STUB/chronyc"
clock_case() {  # clock_case <HM_RTC> <chronyd at s or -> <sync at s or -> <want state> <want end uptime or -> <what>
  reset_state; rm -rf "$C"; mkdir -p "$C"
  echo "HM_RTC='$1'" > "$C/hm_mode"; : > "$C/VERSION"; touch -d '2020-01-01' "$C/VERSION"
  echo "10.00 0" > "$C/uptime"
  [ "$2" = - ] || echo "$2" > "$STUBSTATE/chronyd-at"
  [ "$3" = - ] || echo "$3" > "$STUBSTATE/sync-at"
  STUBUPTIME="$C/uptime" CLOCK_UPTIME="$C/uptime" CLOCK_STATE_DIR="$C/run" CLOCK_HM_MODE="$C/hm_mode" \
    CLOCK_VERSION_FILE="$C/VERSION" CLOCK_CHRONYC="$STUB/chronyc" PATH="$STUB:$PATH" \
    sh "$LIBEXEC/lite-clock-valid" 60 > "$C/out" 2>&1
  st=$(cat "$C/run/clock-state" 2>/dev/null)
  end=$(cut -d. -f1 "$C/uptime")
  if [ "$st" = "$4" ] && { [ "$5" = - ] || [ "$end" = "$5" ]; }; then
    ok "clock gate, $6: $st at $end s ($(cat "$C/out"))"
  else
    bad "clock gate, $6: state '$st' at $end s, want $4 at $5 ($(cat "$C/out"))"
  fi
}
clock_case rx8130 - - rtc 10 "a real-time clock passes at once, chronyd not asked"
clock_case "" 12 14 ntp 14 "no RTC, chronyd at 12 s, synchronised at 14 s"
clock_case "" 40 45 ntp 45 "no RTC, the network late: chronyd at 40 s, synchronised at 45 s"
clock_case "" 40 - timeout 100 "no RTC, chronyd at 40 s, never synchronised: 60 s after chronyd's first answer"
clock_case "" - - timeout 160 "no RTC, chronyd never answers: 60 + 90 s after the start"
grep -q '^<4>' "$C/out" && ok "the timeout is a warning line" || bad "timeout line: $(cat "$C/out")"
rm -f "$STUB/chronyc"

# --- lite-radio-stop-wait ---------------------------------------------------------------------
W="$T/wait"; mkdir -p "$W"
cat > "$W/systemctl" <<'EOF'
#!/bin/sh
case "$1" in
  is-system-running) cat "$STUBSTATE/system"; exit 1 ;;
  is-active)
    n=$(cat "$STUBSTATE/sleeps" 2>/dev/null || echo 0)
    down=$(cat "$STUBSTATE/down-after" 2>/dev/null || echo 999999)
    shift
    for u in "$@"; do
      if [ "$n" -ge "$down" ]; then echo inactive; elif [ "$u" = hmipserver.service ]; then echo deactivating; else echo active; fi
    done
    exit 0 ;;
esac
EOF
chmod 755 "$W/systemctl"
wait_case() {  # wait_case <system state> <down after n polls or -> <limit> <want polls> <what>
  reset_state; echo "$1" > "$STUBSTATE/system"; [ "$2" = - ] || echo "$2" > "$STUBSTATE/down-after"
  RADIO_STOP_SYSTEMCTL="$W/systemctl" PATH="$STUB:$PATH" sh "$LIBEXEC/lite-radio-stop-wait" "$3" > "$W/out" 2>&1
  rc=$?
  polls=$(cat "$STUBSTATE/sleeps" 2>/dev/null || echo 0)
  if [ "$rc" = 0 ] && [ "$polls" = "$4" ]; then ok "stop wait, $5: $polls polls ($(cat "$W/out"))"; else bad "stop wait, $5: rc $rc, $polls polls, want $4 ($(cat "$W/out"))"; fi
}
wait_case running - 120 0 "a plain stop or restart does not wait"
wait_case stopping 0 120 0 "shutdown with the radio stack already down"
wait_case stopping 15 120 15 "shutdown: serves until the radio units are inactive (3 s)"
wait_case stopping - 2 10 "shutdown, the radio stack never stops: gives up at the limit"
grep -q '^<4>the radio stack is not down after 2 s' "$W/out" && ok "the limit is a warning line" || bad "limit line: $(cat "$W/out")"

# --- lite-ca-certificates ---------------------------------------------------------------------
K="$T/ca"
mkdir -p "$K/prebuilt" "$K/local" "$K/bin"
printf 'CERT-A\n' > "$K/prebuilt/ca-certificates.crt"; ln -s /usr/share/ca-certificates/mozilla/A.crt "$K/prebuilt/A.pem"; ln -s A.pem "$K/prebuilt/1234abcd.0"
cat > "$K/bin/update" <<'EOF'
#!/bin/sh
# a stand-in for update-ca-certificates --default --etccertsdir <dir>
echo run >> "$STUBSTATE/updates"
[ "$1" = --default ] && [ "$2" = --etccertsdir ] && [ "$4" = --localcertsdir ] && [ "$6" = --certsconf ] || exit 3
[ -z "$(ls -A "$3")" ] || exit 5
cd "$3" || exit 4
find "$5" -name '*.crt' | sort | while read -r c; do ln -sf "$c" "$(basename "$c" .crt).pem"; done
{ echo CERT-A; find "$5" -name '*.crt' | sort | xargs cat; } > ca-certificates.crt
EOF
chmod 755 "$K/bin/update"
echo "VERSION=3.89.9 LITE=1.0.0-dev.2" > "$K/VERSION"
: > "$K/conf"
ca_run() {
  CA_ETCCERTSDIR="$K/var/etc/ssl/certs" CA_PREBUILT="$K/prebuilt" CA_LOCALCERTSDIR="$K/local" CA_CERTSCONF="$K/conf" \
    CA_CACHE="$K/cache" CA_VERSION_FILE="$K/VERSION" CA_UPDATE="$K/bin/update" sh "$LIBEXEC/lite-ca-certificates" > "$K/out" 2>&1
}
updates() { cat "$STUBSTATE/updates" 2>/dev/null | wc -l | tr -d ' '; }
reset_state; ca_run
if [ "$?" = 0 ] && [ "$(updates)" = 0 ] && cmp -s "$K/prebuilt/ca-certificates.crt" "$K/var/etc/ssl/certs/ca-certificates.crt" &&
   [ "$(readlink "$K/var/etc/ssl/certs/A.pem")" = /usr/share/ca-certificates/mozilla/A.crt ] && [ "$(readlink "$K/var/etc/ssl/certs/1234abcd.0")" = A.pem ] &&
   [ ! -e "$K/cache" ]; then
  ok "no user certificate: the prebuilt bundle is copied, links kept, nothing built or cached ($(cat "$K/out"))"
else
  bad "no user certificate: updates $(updates), $(cat "$K/out"), $(ls -la "$K/var/etc/ssl/certs" 2>&1)"
fi
touch "$K/var/etc/ssl/certs/writable" 2>/dev/null && ok "the copied directory stays writable" || bad "the bundle directory is not writable"
ca_run; [ ! -e "$K/var/etc/ssl/certs/writable" ] && [ -f "$K/var/etc/ssl/certs/ca-certificates.crt" ] && ok "a second run replaces the directory" || bad "second run: $(ls "$K/var/etc/ssl/certs")"
printf 'CERT-LAN\n' > "$K/local/lan-ca.crt"
reset_state; ca_run
if [ "$(updates)" = 1 ] && grep -q CERT-LAN "$K/var/etc/ssl/certs/ca-certificates.crt" && [ -f "$K/cache/.key" ] && [ -f "$K/cache/.nobackup" ] &&
   grep -q CERT-LAN "$K/cache/ca-certificates.crt"; then
  ok "a user certificate: built once and cached, left out of backups ($(cat "$K/out"))"
else
  bad "user certificate: updates $(updates), $(cat "$K/out"), cache: $(ls -a "$K/cache" 2>&1)"
fi
rm -rf "${K:?}/var"
reset_state; ca_run
if [ "$(updates)" = 0 ] && grep -q CERT-LAN "$K/var/etc/ssl/certs/ca-certificates.crt" && [ ! -e "$K/var/etc/ssl/certs/.key" ] && [ ! -e "$K/var/etc/ssl/certs/.nobackup" ]; then
  ok "the next boot: the cached bundle, no build ($(cat "$K/out"))"
else
  bad "cached boot: updates $(updates), $(cat "$K/out")"
fi
printf 'CERT-LAN-2\n' > "$K/local/lan-ca.crt"
reset_state; ca_run
[ "$(updates)" = 1 ] && grep -q CERT-LAN-2 "$K/var/etc/ssl/certs/ca-certificates.crt" && ok "a changed certificate: built again" || bad "changed certificate: updates $(updates), $(cat "$K/out")"
reset_state; ca_run; [ "$(updates)" = 0 ] && ok "and cached again" || bad "not cached after the rebuild: $(updates)"
echo "VERSION=3.89.9 LITE=1.0.0-dev.3" > "$K/VERSION"
reset_state; ca_run; [ "$(updates)" = 1 ] && ok "a new image: built again" || bad "new image: updates $(updates)"
mkdir -p "$K/local/sub"; printf 'CERT-SUB\n' > "$K/local/sub/other.crt"
reset_state; ca_run; [ "$(updates)" = 1 ] && grep -q CERT-SUB "$K/var/etc/ssl/certs/ca-certificates.crt" && ok "an added certificate: built again" || bad "added certificate: updates $(updates)"
rm -f "$K/local/lan-ca.crt" "$K/local/sub/other.crt"
reset_state; ca_run
[ "$(updates)" = 0 ] && ! grep -q CERT-LAN "$K/var/etc/ssl/certs/ca-certificates.crt" && ok "the user certificates removed: back to the prebuilt bundle" || bad "removed: updates $(updates), $(cat "$K/out")"
echo "!mozilla/A.crt" > "$K/conf"
reset_state; ca_run; [ "$(updates)" = 1 ] && ok "a certificate deselected in ca-certificates.conf: built, not the prebuilt" || bad "conf: updates $(updates)"
: > "$K/conf"; mv "$K/prebuilt" "$K/prebuilt.away"
reset_state; ca_run
[ "$(updates)" = 1 ] && grep -q '^<4>' "$K/out" && ok "no prebuilt bundle in the image: built, with a warning" || bad "no prebuilt: updates $(updates), $(cat "$K/out")"
mv "$K/prebuilt.away" "$K/prebuilt"
printf 'CERT-RO\n' > "$K/local/ro.crt"; rm -rf "$K/cache"; mkdir -p "$K/ro"; chmod 555 "$K/ro"
reset_state
CA_ETCCERTSDIR="$K/var/etc/ssl/certs" CA_PREBUILT="$K/prebuilt" CA_LOCALCERTSDIR="$K/local" CA_CERTSCONF="$K/conf" \
  CA_CACHE="$K/ro/cache" CA_VERSION_FILE="$K/VERSION" CA_UPDATE="$K/bin/update" sh "$LIBEXEC/lite-ca-certificates" > "$K/out" 2>&1
rc=$?
if [ "$(id -u)" != 0 ]; then
  [ "$rc" = 0 ] && grep -q CERT-RO "$K/var/etc/ssl/certs/ca-certificates.crt" && grep -q '^<4>.*could not be cached' "$K/out" \
    && ok "an unwritable userfs: the bundle is still built, with a warning" || bad "unwritable cache: rc $rc, $(cat "$K/out")"
fi
chmod 755 "$K/ro"

# --- ca-prebuilt.sh ---------------------------------------------------------------------------
if command -v openssl >/dev/null; then
  P="$T/prebuilt-target"
  mkdir -p "$P/usr/sbin" "$P/usr/share/ca-certificates/mozilla" "$P/etc"
  : > "$P/etc/ca-certificates.conf"
  for n in "Test Root A" "Test_Root_B"; do
    openssl req -x509 -newkey rsa:1024 -nodes -keyout /dev/null -subj "/CN=$n" -days 1 -out "$P/usr/share/ca-certificates/mozilla/$(echo "$n" | tr ' ' '_').crt" >/dev/null 2>&1
  done
  # the stand-in behaves like update-ca-certificates: links named after the file, the bundle, openssl rehash
  cat > "$P/usr/sbin/update-ca-certificates" <<'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do case $1 in --certsdir) shift; D=$1;; --etccertsdir) shift; E=$1;; esac; shift; done
cd "$E" || exit 1
find -L "$D" -type f -name '*.crt' | sort | while read -r c; do ln -sf "$c" "$(basename "$c" .crt).pem"; sed -e '$a\' "$c" >> ca-certificates.crt.new; done
openssl rehash . >/dev/null && mv ca-certificates.crt.new ca-certificates.crt
EOF
  if sh "$HERE/buildroot-external/board/lite/ca-prebuilt.sh" "$P" > "$T/prebuilt.out" 2>&1 &&
     [ "$(readlink "$P/usr/share/ca-certificates-prebuilt/Test_Root_A.pem")" = /usr/share/ca-certificates/mozilla/Test_Root_A.crt ] &&
     [ "$(find "$P/usr/share/ca-certificates-prebuilt" -name '*.0' -type l | wc -l)" = 2 ] &&
     [ "$(grep -c 'BEGIN CERTIFICATE' "$P/usr/share/ca-certificates-prebuilt/ca-certificates.crt")" = 2 ]; then
    ok "ca-prebuilt.sh: box paths in the links, a hash link per certificate ($(cat "$T/prebuilt.out"))"
  else
    bad "ca-prebuilt.sh: $(cat "$T/prebuilt.out"); $(ls -l "$P/usr/share/ca-certificates-prebuilt" 2>&1)"
  fi
  echo "mozilla/Test_Root_A.crt" > "$P/etc/ca-certificates.conf"
  if sh "$HERE/buildroot-external/board/lite/ca-prebuilt.sh" "$P" > "$T/prebuilt.out" 2>&1; then
    bad "ca-prebuilt.sh accepts a non-empty ca-certificates.conf"
  else
    ok "ca-prebuilt.sh stops the build on a non-empty ca-certificates.conf"
  fi
else
  echo "skip ca-prebuilt.sh (no openssl on this host)"
fi

[ "$fails" = 0 ] && echo "lite boot path: all cases passed" || { echo "lite boot path: $fails case(s) failed"; exit 1; }
