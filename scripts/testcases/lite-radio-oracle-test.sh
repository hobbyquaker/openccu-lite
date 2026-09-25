#!/bin/sh
# openccu-lite: the differential harness of the radio rework (task 129, D-83).
#
# Upstream's radio chain - S47InitRFHardware, S49hs485d, S60hs485d, S60multimacd, S61rfd,
# S62HMServer and S61hmlangw, plus lite's lite-rfd-listen in front of S61rfd - is run in a
# sandbox, in the order the lite units run it, for every case of the hardware matrix: the
# scripts' absolute paths are rewritten into a temporary root, detect_radio_module and the
# daemons are stand-ins on PATH that record what they were asked, and a plain file stands in for
# a device node. What the chain decides per case is written out as a set of normalised files
# (below) and compared with the expected set in scripts/testcases/radio-oracle/<case>/:
#
#   hm_mode             /var/hm_mode, sorted, unquoted
#   var-files           /var/board_serial and the /var/rf_*, /var/hmip_* files
#   daemons             which daemon the chain starts, with its exact command line, or why not
#   messages            what the scripts printed
#   rfd.conf            /etc/config/rfd.conf after S61rfd (the userfs file it edits)
#   var-rfd.conf        /var/etc/rfd.conf
#   multimacd.conf      /var/etc/multimacd.conf
#   crRFD.conf          /var/etc/crRFD.conf
#   HMServer.conf       /var/etc/HMServer.conf
#   hs485d.conf         /var/etc/hs485d.conf
#   interfaces          /etc/config/InterfacesList.xml after S49hs485d, one "name|url|info" line per entry
#   userfs              the files under /etc/config and /usr/local afterwards
#
# The expected files are upstream's decisions as the scripts make them today, quirks included;
# they are the oracle. Two things are checked against them:
#
#   1. the scripts themselves, at every rebase: an upstream change in a decision shows as a
#      failing case here (task 94's rebase routine, task 126). "--update" rewrites the expected
#      files; review the diff before committing it;
#   2. occulited's own detection and plan (phase 1 of task 129): with RADIO_PLAN=<command> the
#      command is run once per case as
#          <command> --root <sandbox root> --out <sandbox root>/plan
#      against the same sandbox before the scripts run (the stand-in detect_radio_module is on
#      PATH and in <root>/bin), and what it writes into <root>/plan - files of the same names -
#      is compared with the expected set as well. Every difference is a bug of the plan or an
#      intended deviation; the intended ones are listed in RADIO_ORACLE_ALLOW (a file of
#      "<case-glob> <file> <sed expression>" lines applied to both sides before the diff;
#      radio-oracle/allow.txt unless set), each with its reason as a comment.
#
# The scripts use busybox ash's [[ ]], so they run under bash here. Nothing needs root, a radio
# module, systemd or a network.
#
# Usage: sh scripts/testcases/lite-radio-oracle-test.sh [--update] [--only <case-glob>]
#        RADIO_PLAN="go run ./cmd/occulited radio oracle" sh scripts/testcases/lite-radio-oracle-test.sh
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
EXT="$HERE/buildroot-external"
BASE="$EXT/overlay/base"
RFDO="$EXT/overlay/RFD"
LITE="$EXT/overlay/lite"
EXPECTED="$HERE/scripts/testcases/radio-oracle"
RADIO_ORACLE_ALLOW=${RADIO_ORACLE_ALLOW:-$EXPECTED/allow.txt}
command -v bash >/dev/null || { echo "bash is needed"; exit 2; }

UPDATE=0; ONLY='*'
while [ $# -gt 0 ]; do
  case "$1" in
    --update) UPDATE=1 ;;
    --only) ONLY=$2; shift ;;
    *) echo "usage: $0 [--update] [--only <case-glob>]"; exit 2 ;;
  esac
  shift
done

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
case "$T" in */var/*|*/etc/*|*/dev/*|*/sys/*|*/proc/*|*/opt/*|*/usr/local/*) echo "the temporary directory $T lies on a path the sandbox rewrites; set TMPDIR elsewhere"; exit 2 ;; esac
fails=0
cases=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

# --- the stand-ins ------------------------------------------------------------------------------
# Every stand-in reads $R (the sandbox root) from the environment. They are on PATH for the
# commands the scripts call by name, and the scripts' absolute program paths are rewritten to
# $R/bin/<name>.
STUB="$T/stub"; mkdir -p "$STUB"
mkstub() { cat > "$STUB/$1"; chmod 755 "$STUB/$1"; }
mkstub detect_radio_module <<'EOF'
#!/bin/sh
# answers from $R/modules/<node>: "none" fails as an empty UART does; anything else is the
# probe's six fields "hardware serial sgtin hmrf-address hmip-address version"
n=$(basename "$1")
echo "detect_radio_module $n" >> "$R/calls/probe"
a=$(cat "$R/modules/$n" 2>/dev/null || echo none)
if [ "$a" = none ]; then echo "Error: No radio module found on $1" >&2; exit 1; fi
echo "$a"
EOF
mkstub lsusb <<'EOF'
#!/bin/sh
cat "$R/usb/lsusb" 2>/dev/null
EOF
mkstub modprobe <<'EOF'
#!/bin/sh
echo "modprobe $*" >> "$R/calls/modprobe"
for a in "$@"; do
  case "$a" in
    hb_rf_eth) mkdir -p "$R/sys/module/hb_rf_eth/parameters"; : > "$R/sys/module/hb_rf_eth/parameters/connect" ;;
    eq3_char_loop) : > "$R/dev/eq3loop" ;;
  esac
done
exit 0
EOF
mkstub rmmod <<'EOF'
#!/bin/sh
echo "rmmod $*" >> "$R/calls/modprobe"; exit 0
EOF
mkstub ip <<'EOF'
#!/bin/sh
case "$*" in
  "route get "*) echo "$3 via 10.0.0.1 dev eth0"; exit 0 ;;
  "route show default") echo "default via 10.0.0.1 dev eth0"; exit 0 ;;
esac
exit 1
EOF
mkstub sleep <<'EOF'
#!/bin/sh
exit 0
EOF
mkstub hostname <<'EOF'
#!/bin/sh
echo sandbox
EOF
mkstub uname <<'EOF'
#!/bin/sh
cat "$R/arch"
EOF
mkstub chrt <<'EOF'
#!/bin/sh
exit 0
EOF
mkstub setserial <<'EOF'
#!/bin/sh
echo "setserial $*" >> "$R/calls/modprobe"; exit 0
EOF
mkstub logger <<'EOF'
#!/bin/sh
exit 0
EOF
mkstub rsync <<'EOF'
#!/bin/sh
echo "rsync $*" >> "$R/calls/modprobe"; exit 0
EOF
mkstub killall <<'EOF'
#!/bin/sh
exit 0
EOF
# busybox awk reads the hex literals S47's random-address line uses; the host's awk may not
mkstub awk <<'EOF'
#!/bin/sh
real=$(command -v -p gawk || command -v -p mawk || echo /usr/bin/awk)
n=0; for a in "$@"; do n=$((n+1)); done
set -- "$@" --; i=0
while [ $i -lt $n ]; do a=$1; shift; i=$((i+1)); set -- "$@" "$(printf '%s' "$a" | sed 's/0xFFFFFE/16777214/g; s/0xFF0000/16711680/g')"; done
shift
exec "$real" "$@"
EOF
mkstub pidof <<'EOF'
#!/bin/sh
echo 4242
EOF
mkstub timeout <<'EOF'
#!/bin/sh
shift; exec "$@"
EOF
# the daemons, as start-stop-daemon starts them: the line is recorded, and what the daemon would
# have created (multimacd's endpoints, the status files) appears
mkstub start-stop-daemon <<'EOF'
#!/bin/sh
line="$*"
case "$line" in
  *" -K "*) exit 0 ;;
esac
case "$line" in
  *"--exec /bin/multimacd "*)
    echo "multimacd: ${line##*--exec }" | sed 's| -- | |' >> "$R/calls/daemons"
    : > "$R/dev/mmd_bidcos"; : > "$R/dev/mmd_hmip"; echo 4242 > "$R/var/status/multimacd.status" ;;
  *"--exec /bin/rfd "*)
    echo "rfd: ${line##*--exec }" | sed 's| -- | |' >> "$R/calls/daemons"; echo 4242 > "$R/var/status/rfd.status" ;;
  *"--exec /bin/hs485dLoader "*)
    echo "hs485d: ${line##*--exec }" | sed 's| -- | |' >> "$R/calls/daemons" ;;
  *"--exec java "*)
    echo "hmipserver: ${line##*--exec }" | sed 's| -- | |' >> "$R/calls/daemons"; touch "$R/var/status/HMServerStarted" ;;
  *"--startas /bin/sh -- -c "*)
    echo "hmlangw: ${line##*-- -c }" >> "$R/calls/daemons" ;;
  *) echo "other: $line" >> "$R/calls/daemons" ;;
esac
exit 0
EOF
mkstub java <<'EOF'
#!/bin/sh
echo "hmipserver: java $*" >> "$R/calls/daemons"
touch "$R/var/status/HMServerStarted"
exit 0
EOF
mkstub hs485dLoader <<'EOF'
#!/bin/sh
echo "hs485d-init: /bin/hs485dLoader $*" >> "$R/calls/daemons"
exit 0
EOF

# --- the sandbox ---------------------------------------------------------------------------------
# rewrite <script> <output>: the script with its absolute paths inside $R and every device-node
# test turned into a plain existence test
rewrite() {
  sed -e 's/\[\[ -c /[[ -e /g' -e 's/\[\[ ! -c /[[ ! -e /g' -e 's|/proc/\$\$/oom_score_adj|/dev/null|g' \
      -e "s| /etc/HMServer.conf| $R/etc/HMServer.conf|g" -e "s| /etc/hmipserver.default| $R/etc/hmipserver.default|g" \
      -e "s|/etc/config_templates|$R/etc/config_templates|g" -e "s|/etc/config\([^_a-zA-Z0-9]\)|$R/etc/config\1|g" -e "s|/etc/config\$|$R/etc/config|" \
      -e "s|/sys/|$R/sys/|g" -e "s|/proc/|$R/proc/|g" -e "s|/var/|$R/var/|g" \
      -e "s|/usr/local/|$R/usr/local/|g" -e "s|/media/usb0|$R/media/usb0|g" -e "s|/tmp/measurement|$R/tmp/measurement|g" \
      -e "s|/firmware/|$R/firmware/|g" -e "s|/opt/|$R/opt/|g" \
      -e "s|/dev/\${|$R/dev/\${|g" -e "s|/dev/ttyAMA0|$R/dev/ttyAMA0|g" -e "s|/dev/mmd_|$R/dev/mmd_|g" -e "s|/dev/eq3loop|$R/dev/eq3loop|g" \
      -e "s|/bin/detect_radio_module|$R/bin/detect_radio_module|g" -e "s|/bin/setserial|$R/bin/setserial|g" \
      -e "s|/bin/hss_led|$R/bin/hss_led|g" -e "s|/usr/bin/timeout|$R/bin/timeout|g" -e "s|/usr/bin/chrt|$R/bin/chrt|g" \
      -e "s|/usr/bin/rsync|$R/bin/rsync|g" -e "s|/bin/hs485dLoader -l|$R/bin/hs485dLoader -l|g" \
      -e "s|grep -q \"$R/etc/config/rfd/keys\"|grep -q \"/etc/config/rfd/keys\"|" \
      "$1" > "$2"
  chmod 755 "$2"
}

# the case's description, set by the case functions
CASE_HOST=rpi3; CASE_RTC=rx8130; CASE_ARCH=aarch64; CASE_MEM=946000; CASE_MOUNT=/dev/mmcblk0p3
CASE_MODE=NORMAL; CASE_NOTE=

new_sandbox() {
  R="$T/r"; export R
  rm -rf "$R"
  mkdir -p "$R/sys/class/raw-uart" "$R/sys/class/net/eth0" "$R/sys/bus/usb/devices" "$R/sys/fs/cgroup" "$R/proc" \
    "$R/var/etc" "$R/var/status" "$R/var/run" "$R/dev" "$R/etc/config" "$R/etc/config_templates" "$R/usr/local" \
    "$R/media" "$R/tmp" "$R/firmware" "$R/opt/java/bin" "$R/bin" "$R/calls" "$R/modules" "$R/usb" "$R/out"
  echo 1 > "$R/sys/class/net/eth0/type"; echo "dc:a6:32:03:a9:fa" > "$R/sys/class/net/eth0/address"; ln -s /dev/null "$R/sys/class/net/eth0/device"
  # the templates the image ships: lite's rfd.conf and log4j2.xml win over RFD's and base's
  cp "$LITE/etc/config_templates/rfd.conf" "$LITE/etc/config_templates/log4j2.xml" "$R/etc/config_templates/"
  cp "$RFDO/etc/config_templates/multimacd.conf" "$BASE/etc/config_templates/InterfacesList.xml" "$R/etc/config_templates/"
  cp "$HERE/scripts/testcases/radio-oracle/templates/crRFD.conf" "$R/etc/config_templates/"
  cp "$BASE/etc/HMServer.conf" "$R/etc/HMServer.conf"
  cp "$LITE/etc/hmipserver.default" "$R/etc/hmipserver.default"
  for s in detect_radio_module timeout chrt setserial rsync hs485dLoader java; do ln -s "$STUB/$s" "$R/bin/$s"; done
  ln -s "$STUB/java" "$R/opt/java/bin/java"
  CASE_HOST=rpi3; CASE_RTC=rx8130; CASE_ARCH=aarch64; CASE_MEM=946000; CASE_MOUNT=/dev/mmcblk0p3; CASE_MODE=NORMAL; CASE_NOTE=
}
# node <name> <device_type> <answer>: a raw-uart node and what detect_radio_module says about it
node() {
  mkdir -p "$R/sys/class/raw-uart/$1"; echo "$2" > "$R/sys/class/raw-uart/$1/device_type"
  : > "$R/sys/class/raw-uart/$1/reset_radio_module"; : > "$R/dev/$1"
  echo "$3" > "$R/modules/$1"
}
# hbrf <name>: the LED pins an HB-RF-USB/-ETH exposes for an RPI-RF-MOD
hbrf() {
  echo 22 > "$R/sys/class/raw-uart/$1/red_gpio_pin"; echo 23 > "$R/sys/class/raw-uart/$1/green_gpio_pin"; echo 24 > "$R/sys/class/raw-uart/$1/blue_gpio_pin"
}
# usb <id> [serial]: a USB device lsusb lists, with its sysfs serial
usb() {
  echo "Bus 001 Device 003: ID $1" >> "$R/usb/lsusb"
  d="$R/sys/bus/usb/devices/1-1.$(wc -l < "$R/usb/lsusb")"; mkdir -p "$d"
  echo "${1%%:*}" > "$d/idVendor"; echo "${1#*:}" > "$d/idProduct"; echo 1 > "$d/busnum"; wc -l < "$R/usb/lsusb" > "$d/devnum"
  [ -n "${2:-}" ] && echo "$2" > "$d/serial"
  return 0
}
host() { CASE_HOST=$1; CASE_RTC=$2; CASE_ARCH=$3; CASE_MEM=$4; CASE_MOUNT=$5; }
# the answers of the modules the lab has, and of the ones it does not (from the item's survey)
RPIRFMOD="RPI-RF-MOD 58A9A728D4 3014F711A0001F58A9A728D4 0x1F6C2E 0x3FAE2C 4.4.22"
# an HmIP-RFUSB reports a BidCos address of its own in the 0xFF range (0xFF01B6 on .119, the same
# in every boot); S47's random address is only for a module that answers 0x000000 (the ids case)
RFUSB="HMIP-RFUSB 1709ADFA5B 3014F711A000041709ADFA5B 0xFF01B5 0x7F7A50 4.4.18"
RFUSB2="HMIP-RFUSB 1709ADFA5E 3014F711A000041709ADFA5E 0xFF01B6 0xBCEDC1 4.4.18"
RFUSBTK="HMIP-RFUSB-TK 1709ADFB01 3014F711A000041709ADFB01 0xFF01B7 0x7F7B01 4.4.18"
# the legacy module has no HmIP side: its probe answers 0x000000 there (recorded as the survey's
# assumption; the exact line of a real HM-MOD-RPI-PCB is to be taken when one is in the lab)
PCB="HM-MOD-RPI-PCB MEQ0123456 - 0xABC123 0x000000 2.8.6"
# the dual-protocol PCB of the lab box .170 (task 129): a BidCos and an HmIP address
PCBDUAL="HM-MOD-RPI-PCB MEQ0835626 3014F711A061A7D3C996282A 0x3D1BAE 0x1EE437 2.8.6"
GPIO3="GPIO@3f201000.serial"; GPIO4="GPIO@fe201000.serial"
USBTYPE="eQ-3 HmIP-RFUSB@usb-0000:01:00.0-1.3"; USBTYPE2="eQ-3 HmIP-RFUSB@usb-0000:01:00.0-1.4"

# the userfs of a CCU3 that ran upstream: rfd.conf without the loopback line, a LAN gateway
ccu3_rfd_conf() {
  cat > "$R/etc/config/rfd.conf" <<'EOF'
# TCP Port for XmlRpc connections
Listen Port = 32001

Log Destination = Syslog
Log Identifier = rfd
Log Level = 1

Persist Keys = 1

Device Description Dir = /firmware/rftypes
Device Files Dir = /etc/config/rfd
Key File = /etc/config/keys
Address File = /etc/config/ids
Firmware Dir = /firmware
Replacemap File = /firmware/rftypes/replaceMap/rfReplaceMap.xml
Fire NACK Error Events = true
Improved Coprocessor Initialization = true

[Interface 0]
Type = CCU2
ComPortFile = /dev/mmd_bidcos
AccessFile = /dev/null
ResetFile = /dev/null

[Interface 1]
Type = HMLGW2
Name = Garage
Serial Number = KEQ0987654
Encryption Key = gwsecret
IP Address = 192.168.1.61

EOF
}
lgw_only_rfd_conf() {
  ccu3_rfd_conf
  sed -i '/^\[Interface 0\]/,/^\s*$/ s/^/#/' "$R/etc/config/rfd.conf"
}
wired_hs485d_conf() {
  cat > "$R/etc/config/hs485d.conf" <<'EOF'
# This File was automatically generated
# TCP Port for XmlRpc connections
Listen Port = 32000

Log Destination = Syslog
Log Identifier = hs485d

[Interface 0]
Type = HMWLGW
Name = Wired
Serial Number = LEQ0123456
Encryption Key = wiredkey
IP Address = 192.168.1.60

EOF
}
ids_file() { printf 'BidCoS-Address = %s\n' "$1" > "$R/etc/config/ids"; }
hmip_address_file() { printf 'Adapter.1.Address=%s\n' "$1" > "$R/etc/config/hmip_address.conf"; }
foreign_interfaces_list() {
  sed 's|</interfaces>|\t<ipc>\n\t\t<name>CCU-Jack</name>\n\t\t<url>xmlrpc://127.0.0.1:2121/RPC3</url>\n\t\t<info>CCU-Jack</info>\n\t</ipc>\n</interfaces>|' \
    "$BASE/etc/config_templates/InterfacesList.xml" > "$R/etc/config/InterfacesList.xml"
}

# run_chain: the units' order - the seed of /var/hm_mode as S01/S02/S06 leave it, then S47, S49,
# S60hs485d, lite-rfd-listen, S60multimacd, S61rfd, S62HMServer, S61hmlangw
seed_env() {
  echo "$CASE_ARCH" > "$R/arch"
  printf 'MemTotal:       %s kB\n' "$CASE_MEM" > "$R/proc/meminfo"
  printf '%s /usr/local ext4 rw,noatime 0 0\n' "$CASE_MOUNT" > "$R/proc/mounts"
  : > "$R/proc/modules"
  [ -e "$R/usr/local/HMLGW" ] && CASE_MODE=HM-LGW
  cat > "$R/var/hm_mode" <<EOF
HM_HOST='$CASE_HOST'
HM_LED_GREEN=''
HM_LED_GREEN_MODE1='none'
HM_LED_GREEN_MODE2='heartbeat'
HM_LED_RED=''
HM_LED_RED_MODE1='timer'
HM_LED_RED_MODE2='none'
HM_LED_YELLOW=''
HM_LED_YELLOW_MODE1='none'
HM_LED_YELLOW_MODE2='none'
HM_MODE='$CASE_MODE'
HM_RTC='$CASE_RTC'
EOF
}
run_chain() {
  seed_env
  for s in "$BASE/etc/init.d/S47InitRFHardware" "$BASE/etc/init.d/S49hs485d" "$BASE/etc/init.d/S60hs485d" \
           "$RFDO/etc/init.d/S60multimacd" "$RFDO/etc/init.d/S61rfd" "$BASE/etc/init.d/S62HMServer" \
           "$EXT/package/hmlangw/S61hmlangw"; do
    rewrite "$s" "$R/bin/$(basename "$s")"
  done
  sed -e "s|^CONF=/etc/config/rfd.conf|CONF=$R/etc/config/rfd.conf|" "$HERE/scripts/testcases/radio-oracle/lite-rfd-listen" > "$R/bin/lite-rfd-listen"
  chmod 755 "$R/bin/lite-rfd-listen"
  for s in S47InitRFHardware S49hs485d S60hs485d lite-rfd-listen S60multimacd S61rfd S62HMServer S61hmlangw; do
    if [ "$s" = lite-rfd-listen ]; then
      PATH="$STUB:$PATH" sh "$R/bin/$s" > "$R/out/$s" 2>&1; rc=$?
    else
      PATH="$STUB:$PATH" bash "$R/bin/$s" start > "$R/out/$s" 2>&1; rc=$?
    fi
    [ "$rc" -eq 0 ] || echo "(exit $rc)" >> "$R/out/$s"
  done
}

# collect <dir>: the chain's decisions as the normalised file set
# the random BidCos address (0xFF0000-0xFFFFFE) is normalised only in a case whose probe answered
# 0x000000; a module's own address is in that range too (the HmIP-RFUSB's)
strip() {
  if grep -qs ' 0x000000 ' "$R"/modules/* 2>/dev/null; then
    sed -e "s|$R||g" -e 's/ids_old-[0-9]*-[0-9]*/ids_old-<date>/g' -e 's/0xFF[0-9A-F]\{4\}\b/0xFFxxxx/g'
  else
    sed -e "s|$R||g" -e 's/ids_old-[0-9]*-[0-9]*/ids_old-<date>/g'
  fi
}
collect() {
  d=$1; mkdir -p "$d"
  sed -e "s/^\([A-Z_0-9]*\)='\(.*\)'$/\1=\2/" "$R/var/hm_mode" | grep '^HM_' | strip | LC_ALL=C sort > "$d/hm_mode"
  : > "$d/var-files"
  for f in board_serial board_sgtin rf_board_serial rf_address rf_firmware_version hmip_board_serial hmip_firmware_version hmip_address hmip_board_sgtin; do
    [ -e "$R/var/$f" ] && printf '%s=%s\n' "$f" "$(cat "$R/var/$f")" >> "$d/var-files"
  done
  strip < "$d/var-files" > "$d/var-files.n" && mv "$d/var-files.n" "$d/var-files"
  : > "$d/daemons"
  for n in multimacd rfd hmipserver hs485d-init hs485d hmlangw; do
    if grep -q "^$n: " "$R/calls/daemons" 2>/dev/null; then
      grep "^$n: " "$R/calls/daemons"
    else
      echo "$n: not started"
    fi
  done | strip > "$d/daemons"
  for s in S47InitRFHardware S49hs485d S60hs485d lite-rfd-listen S60multimacd S61rfd S62HMServer S61hmlangw; do
    # the progress dots go, a dot inside a word (rfd.conf, 4.4.22, usb-0000:01:00.0-1.3) stays
    printf '%s: ' "$s"; strip < "$R/out/$s" | sed -e 's/\([^A-Za-z0-9]\)\.\{1,\}/\1/g' -e 's/^\.\{1,\}//' -e 's/^ *//' | tr '\n' ' '; echo
  done | sed 's/ *$//' > "$d/messages"
  for f in rfd.conf:etc/config/rfd.conf var-rfd.conf:var/etc/rfd.conf multimacd.conf:var/etc/multimacd.conf crRFD.conf:var/etc/crRFD.conf \
           HMServer.conf:var/etc/HMServer.conf hs485d.conf:var/etc/hs485d.conf; do
    o=${f%%:*}; p=${f#*:}
    if [ -e "$R/$p" ]; then strip < "$R/$p" > "$d/$o"; else echo "(absent)" > "$d/$o"; fi
  done
  # InterfacesList.xml as one "name|url|info" line per entry, in file order
  if [ -e "$R/etc/config/InterfacesList.xml" ]; then
    tr -d '\n\t' < "$R/etc/config/InterfacesList.xml" | sed 's|<ipc>|\n<ipc>|g' | grep '^<ipc>' |
      sed -e 's|<ipc> *<name> *\([^<]*[^< ]\) *</name> *<url> *\([^<]*[^< ]\) *</url> *<info> *\([^<]*[^< ]\) *</info> *</ipc>.*|\1\|\2\|\3|' > "$d/interfaces"
  else
    echo "(absent)" > "$d/interfaces"
  fi
  (cd "$R" && find etc/config usr/local media -mindepth 1 \( -type f -o -type l \) 2>/dev/null | LC_ALL=C sort) | strip > "$d/userfs"
}

# compare <case> <got dir> <want dir> <what>
compare() {
  c=$1; got=$2; what=$4
  if [ ! -d "$3" ]; then bad "$c ($what): no expected files in $3 (run with --update)"; return; fi
  # a copy of the expected files: the allow expressions edit both sides, never the committed set
  want="$T/want.$c"; rm -rf "$want"; cp -r "$3" "$want"
  if [ -n "${RADIO_ORACLE_ALLOW:-}" ] && [ -r "$RADIO_ORACLE_ALLOW" ]; then
    while read -r glob file expr; do
      case "$glob" in ''|'#'*) continue ;; esac
      # shellcheck disable=SC2254
      case "$c" in $glob) for side in "$got" "$want"; do [ -e "$side/$file" ] && sed -i -e "$expr" "$side/$file"; done ;; esac
    done < "$RADIO_ORACLE_ALLOW"
  fi
  if diff -r "$want" "$got" > "$T/diff.$c" 2>&1; then
    ok "$c ($what)"
  else
    bad "$c ($what):"; sed 's/^/     /' "$T/diff.$c" | head -60
  fi
}

# run_case <name> <function>: the sandbox, the plan (with RADIO_PLAN), the chain, the comparison
run_case() {
  c=$1
  # shellcheck disable=SC2254
  case "$c" in $ONLY) ;; *) return ;; esac
  cases=$((cases+1))
  new_sandbox
  "$2"
  if [ -n "${RADIO_PLAN:-}" ]; then
    seed_env
    mkdir -p "$R/plan"
    # shellcheck disable=SC2086
    PATH="$STUB:$PATH" $RADIO_PLAN --root "$R" --out "$R/plan" > "$R/out/plan" 2>&1 || echo "(exit $?)" >> "$R/out/plan"
    mkdir -p "$T/plan.$c"; cp -r "$R/plan/." "$T/plan.$c/" 2>/dev/null
    for f in "$T/plan.$c"/*; do [ -f "$f" ] && { strip < "$f" > "$f.n"; mv "$f.n" "$f"; }; done
  fi
  run_chain
  collect "$T/got.$c"
  [ -n "$CASE_NOTE" ] && echo "$CASE_NOTE" > "$T/got.$c/NOTE"
  if [ "$UPDATE" = 1 ]; then
    rm -rf "${EXPECTED:?}/${c:?}"; mkdir -p "$EXPECTED/$c"; cp "$T/got.$c"/* "$EXPECTED/$c/"
    ok "$c: expected files written"
  else
    compare "$c" "$T/got.$c" "$EXPECTED/$c" "the scripts"
  fi
  if [ -n "${RADIO_PLAN:-}" ]; then
    rm -f "$T/plan.$c/NOTE" "$T/plan.$c/messages"; cp "$EXPECTED/$c/NOTE" "$EXPECTED/$c/messages" "$T/plan.$c/" 2>/dev/null
    compare "$c" "$T/plan.$c" "$EXPECTED/$c" "the plan"
  fi
}

# --- the hardware matrix ---------------------------------------------------------------------------
# Fresh installation (an empty userfs: only what the image ships; D-82's rule and the refinement of
# 2026-09-16: the plan's auto gives exactly this setup), one case per hardware.
c_rpi3_rpi_rf_mod_fresh() {
  CASE_NOTE="the Charly: an RPI-RF-MOD on the GPIO header, nothing on the userfs"
  node raw-uart "$GPIO3" "$RPIRFMOD"
}
c_rpi4_hmip_rfusb_fresh() {
  CASE_NOTE="the Pi 4: the header's empty UART and an HmIP-RFUSB"
  host rpi4 "" aarch64 3884000 /dev/mmcblk0p3
  node raw-uart "$GPIO4" none; node raw-uart1 "$USBTYPE" "$RFUSB"; usb 1b1f:c020 3014F711A000041709ADFA5B
}
c_rpi4_hmip_rfusb_first_fresh() {
  CASE_NOTE="the Pi 4 with the kernel naming the stick raw-uart and the header raw-uart1 (either order between boots, task 138)"
  host rpi4 "" aarch64 3884000 /dev/mmcblk0p3
  node raw-uart "$USBTYPE" "$RFUSB"; node raw-uart1 "$GPIO4" none; usb 1b1f:c020 3014F711A000041709ADFA5B
}
c_ova_hmip_rfusb_fresh() {
  CASE_NOTE="the x86_64 VM (.119): an HmIP-RFUSB passed through, no GPIO node"
  host ova-proxmox rtc_cmos x86_64 1536000 /dev/sda3
  node raw-uart "$USBTYPE" "$RFUSB2"; usb 1b1f:c020 3014F711A000041709ADFA5E
}
c_rpi3_hm_mod_rpi_pcb_fresh() {
  CASE_NOTE="an HM-MOD-RPI-PCB on the header (BidCos-RF only; hmipserver runs the HMServer half alone)"
  host rpi3 "" aarch64 946000 /dev/mmcblk0p3
  node raw-uart "$GPIO3" "$PCB"
}
c_rpi4_hmip_rfusb_tk_fresh() {
  CASE_NOTE="an HmIP-RFUSB-TK: HmIP only, hmipserver on the stick directly, no multimacd, no rfd"
  host rpi4 "" aarch64 3884000 /dev/mmcblk0p3
  node raw-uart "$GPIO4" none; node raw-uart1 "eQ-3 HmIP-RFUSB-TK@usb-0000:01:00.0-1.3" "$RFUSBTK"; usb 1b1f:c020 3014F711A000041709ADFB01
}
c_rpi4_hm_cfg_usb_2_fresh() {
  CASE_NOTE="an HM-CFG-USB-2 alone: rfd on the USB interface (quirk: the section is always [Interface 1]), no HmIP"
  host rpi4 "" aarch64 3884000 /dev/mmcblk0p3
  node raw-uart "$GPIO4" none; usb 1b1f:c00f KEQ0123456
}
c_rpi4_hmip_rfusb_plus_hm_cfg_usb_2_fresh() {
  CASE_NOTE="an HmIP-RFUSB beside an HM-CFG-USB-2: multimacd not required, hmipserver on the stick directly, rfd on the USB interface"
  host rpi4 "" aarch64 3884000 /dev/mmcblk0p3
  node raw-uart "$GPIO4" none; node raw-uart1 "$USBTYPE" "$RFUSB"; usb 1b1f:c00f KEQ0123456; usb 1b1f:c020 3014F711A000041709ADFA5B
}
c_rpi3_rpi_rf_mod_plus_hm_cfg_usb_2_fresh() {
  CASE_NOTE="an RPI-RF-MOD on the header beside an HM-CFG-USB-2: the adapter takes HmRF before the probe, the module only HmIP; quirk: S60 starts multimacd with an empty device path (the adapter has no node) while S62 uses the module directly"
  node raw-uart "$GPIO3" "$RPIRFMOD"; usb 1b1f:c00f KEQ0123456
}
c_rpi4_pcb_hb_rf_usb_plus_hm_cfg_usb_2_fresh() {
  CASE_NOTE="the lab box .170: a dual-protocol HM-MOD-RPI-PCB on an HB-RF-USB beside an HM-CFG-USB-2 - the adapter takes HmRF, the PCB only HmIP; quirk: S60 starts multimacd with an empty device path and S62 opens the PCB directly, where hmipserver hangs after every reset of the module (deviation 15)"
  node raw-uart "$GPIO4" none; node raw-uart1 "HB-RF-USB@usb-0000:01:00.0-1.3" "$PCBDUAL"; usb 1b1f:c00f JEQ0534849
}
c_rpi3_rpi_rf_mod_hb_rf_usb_fresh() {
  CASE_NOTE="an RPI-RF-MOD on an HB-RF-USB-2 (the header empty): the LED driver is loaded with the adapter's pins"
  node raw-uart "$GPIO3" none; node raw-uart1 "HB-RF-USB-2@usb-0000:01:00.0-1.2" "$RPIRFMOD"; hbrf raw-uart1; usb 1b1f:c020
}
c_rpi3_hb_rf_eth_fresh() {
  CASE_NOTE="an RPI-RF-MOD on an HB-RF-ETH configured in /etc/config/hb_rf_eth: the module is loaded and connected first"
  echo 192.168.1.50 > "$R/etc/config/hb_rf_eth"
  node raw-uart "$GPIO3" none; node raw-uart1 "HB-RF-ETH@192.168.1.50" "$RPIRFMOD"; hbrf raw-uart1
}
c_rpi3_two_modules_pcb_on_usb_fresh() {
  CASE_NOTE="two modules: an RPI-RF-MOD on the header and an HM-MOD-RPI-PCB on an HB-RF-USB - HmRF prefers the PCB, HmIP the RPI-RF-MOD, multimacd runs on the PCB's node for rfd alone, hmipserver uses the RPI-RF-MOD directly"
  node raw-uart "$GPIO3" "$RPIRFMOD"; node raw-uart1 "HB-RF-USB-2@usb-0000:01:00.0-1.2" "$PCB"; hbrf raw-uart1
}
c_rpi3_two_modules_pcb_first_fresh() {
  CASE_NOTE="the same two modules with the PCB on the header and the RPI-RF-MOD on the HB-RF-USB"
  node raw-uart "$GPIO3" "$PCB"; node raw-uart1 "HB-RF-USB-2@usb-0000:01:00.0-1.2" "$RPIRFMOD"; hbrf raw-uart1
}
c_rpi4_two_rfusb_fresh() {
  CASE_NOTE="two HmIP-RFUSB sticks: the first takes both roles, the second is left unused (measurement 7's oracle)"
  host rpi4 "" aarch64 3884000 /dev/mmcblk0p3
  node raw-uart "$GPIO4" none; node raw-uart1 "$USBTYPE" "$RFUSB"; node raw-uart2 "$USBTYPE2" "$RFUSB2"
  usb 1b1f:c020 3014F711A000041709ADFA5B; usb 1b1f:c020 3014F711A000041709ADFA5E
}
c_rpi4_no_radio_fresh() {
  CASE_NOTE="a Pi without any module: the board serial from eth0's MAC, hmipserver's HMServer half alone, no rfd, InterfacesList without both radio interfaces"
  host rpi4 "" aarch64 3884000 /dev/mmcblk0p3
  node raw-uart "$GPIO4" none
}
c_ova_no_radio_fresh() {
  CASE_NOTE="a VM without any radio (the stock OpenCCU box .230): no raw-uart node at all"
  host ova-proxmox rtc_cmos x86_64 1536000 /dev/sda3
}
c_rpi4_hmip_rfusb_ids_userfs() {
  CASE_NOTE="a stick that answers 0x000000 as its BidCos address, after the first boot: /etc/config/ids holds the address rfd was given, S47 makes a new random HM_HMRF_ADDRESS up (normalised) while the active one stays the file's"
  host rpi4 "" aarch64 3884000 /dev/mmcblk0p3
  node raw-uart "$GPIO4" none; node raw-uart1 "$USBTYPE" "HMIP-RFUSB 1709ADFA5B 3014F711A000041709ADFA5B 0x000000 0x7F7A50 4.4.18"; usb 1b1f:c020 3014F711A061A7C00010CECF
  printf 'BidCoS-Address=0xFE42E5\nSerialNumber=1709ADFA5B\n' > "$R/etc/config/ids"
  printf '#Create random address\n#Thu Sep 03 20:52:45 CEST 2026\nAdapter.1.Address=7F7A50\n' > "$R/etc/config/hmip_address.conf"
}
# A switched CCU3 / OpenCCU (the userfs it had), and the userfs states the scripts repair.
c_rpi3_rpi_rf_mod_ccu3_userfs() {
  CASE_NOTE="a CCU3's userfs restored: rfd.conf without the loopback line and with a LAN gateway, a wired gateway, a BidCos address and an HmIP address of its own, a foreign entry in InterfacesList.xml (lost: S49 re-copies the template)"
  node raw-uart "$GPIO3" "$RPIRFMOD"
  ccu3_rfd_conf; wired_hs485d_conf; ids_file 0xABCDEF; hmip_address_file 12ABCD; foreign_interfaces_list
}
c_rpi4_rfusb_tk_plus_lgw_userfs() {
  CASE_NOTE="an HmIP-RFUSB-TK beside a BidCos LAN gateway: hmipserver on the stick, rfd through the gateway alone, no multimacd"
  host rpi4 "" aarch64 3884000 /dev/mmcblk0p3
  node raw-uart "$GPIO4" none; node raw-uart1 "eQ-3 HmIP-RFUSB-TK@usb-0000:01:00.0-1.3" "$RFUSBTK"; usb 1b1f:c020
  lgw_only_rfd_conf
}
c_rpi4_lgw_only_userfs() {
  CASE_NOTE="no radio module at all, a BidCos LAN gateway in rfd.conf: rfd runs on the gateway, BidCos-RF stays in InterfacesList.xml, no HmIP"
  host rpi4 "" aarch64 3884000 /dev/mmcblk0p3
  node raw-uart "$GPIO4" none
  lgw_only_rfd_conf
}
c_rpi3_rpi_rf_mod_commented_interface0_userfs() {
  CASE_NOTE="rfd.conf with [Interface 0] commented out by an earlier boot without the module: uncommented again"
  node raw-uart "$GPIO3" "$RPIRFMOD"
  lgw_only_rfd_conf
}
c_rpi3_rpi_rf_mod_rfd_keys_spoiled_userfs() {
  CASE_NOTE="rfd.conf naming /etc/config/rfd/keys: reset to the template (quirk: the LAN gateway section is lost with it)"
  node raw-uart "$GPIO3" "$RPIRFMOD"
  ccu3_rfd_conf; sed -i 's|^Key File = /etc/config/keys|Key File = /etc/config/rfd/keys|' "$R/etc/config/rfd.conf"
}
c_rpi3_rpi_rf_mod_ids_zero_userfs() {
  CASE_NOTE="/etc/config/ids with the address 0x000000: moved aside, the module's address becomes the active one"
  node raw-uart "$GPIO3" "$RPIRFMOD"
  ids_file 0x000000
}
c_rpi3_rpi_rf_mod_wired_userfs() {
  CASE_NOTE="an RPI-RF-MOD and a wired LAN gateway in hs485d.conf: hs485d runs (the template's InterfacesList.xml carries no BidCos-Wired entry)"
  node raw-uart "$GPIO3" "$RPIRFMOD"
  wired_hs485d_conf
}
c_rpi4_hmip_rfusb_usb2_gone_userfs() {
  CASE_NOTE="rfd.conf with an HM-CFG-USB section and a LAN gateway after it, the adapter unplugged: S61rfd comments the LAST section out (quirk: the gateway, not the adapter)"
  host rpi4 "" aarch64 3884000 /dev/mmcblk0p3
  node raw-uart "$GPIO4" none; node raw-uart1 "$USBTYPE" "$RFUSB"; usb 1b1f:c020
  cat > "$R/etc/config/rfd.conf" <<'EOF'
Listen IP = 127.0.0.1
Listen Port = 32001

Log Destination = Syslog
Log Identifier = rfd
Log Level = 1

Persist Keys = 1

Device Description Dir = /firmware/rftypes
Device Files Dir = /etc/config/rfd
Key File = /etc/config/keys
Address File = /etc/config/ids
Firmware Dir = /firmware
Replacemap File = /firmware/rftypes/replaceMap/rfReplaceMap.xml
Fire NACK Error Events = true
Improved Coprocessor Initialization = true

[Interface 0]
Type = CCU2
ComPortFile = /dev/mmd_bidcos
#AccessFile = /dev/null
#ResetFile = /dev/null

[Interface 1]
Type = USB Interface
Name = HM-CFG-USB
Serial Number = KEQ0123456
Encryption Key =

[Interface 2]
Type = HMLGW2
Name = Garage
Serial Number = KEQ0987654
Encryption Key = gwsecret
IP Address = 192.168.1.61

EOF
}
c_rpi3_rpi_rf_mod_hmlgw_mode() {
  CASE_NOTE="LAN-gateway mode (/usr/local/HMLGW, HM_MODE=HM-LGW): multimacd and hmlangw run, rfd, hmipserver and the wired setup are skipped"
  node raw-uart "$GPIO3" "$RPIRFMOD"
  : > "$R/usr/local/HMLGW"
}

run_case rpi3-rpi-rf-mod-fresh c_rpi3_rpi_rf_mod_fresh
run_case rpi4-hmip-rfusb-fresh c_rpi4_hmip_rfusb_fresh
run_case rpi4-hmip-rfusb-first-fresh c_rpi4_hmip_rfusb_first_fresh
run_case ova-hmip-rfusb-fresh c_ova_hmip_rfusb_fresh
run_case rpi3-hm-mod-rpi-pcb-fresh c_rpi3_hm_mod_rpi_pcb_fresh
run_case rpi4-hmip-rfusb-tk-fresh c_rpi4_hmip_rfusb_tk_fresh
run_case rpi4-hm-cfg-usb-2-fresh c_rpi4_hm_cfg_usb_2_fresh
run_case rpi4-hmip-rfusb-plus-hm-cfg-usb-2-fresh c_rpi4_hmip_rfusb_plus_hm_cfg_usb_2_fresh
run_case rpi3-rpi-rf-mod-plus-hm-cfg-usb-2-fresh c_rpi3_rpi_rf_mod_plus_hm_cfg_usb_2_fresh
run_case rpi3-rpi-rf-mod-hb-rf-usb-fresh c_rpi3_rpi_rf_mod_hb_rf_usb_fresh
run_case rpi4-pcb-hb-rf-usb-plus-hm-cfg-usb-2-fresh c_rpi4_pcb_hb_rf_usb_plus_hm_cfg_usb_2_fresh
run_case rpi3-hb-rf-eth-fresh c_rpi3_hb_rf_eth_fresh
run_case rpi3-two-modules-pcb-on-usb-fresh c_rpi3_two_modules_pcb_on_usb_fresh
run_case rpi3-two-modules-pcb-first-fresh c_rpi3_two_modules_pcb_first_fresh
run_case rpi4-two-rfusb-fresh c_rpi4_two_rfusb_fresh
run_case rpi4-no-radio-fresh c_rpi4_no_radio_fresh
run_case ova-no-radio-fresh c_ova_no_radio_fresh
run_case rpi4-hmip-rfusb-ids-userfs c_rpi4_hmip_rfusb_ids_userfs
run_case rpi3-rpi-rf-mod-ccu3-userfs c_rpi3_rpi_rf_mod_ccu3_userfs
run_case rpi4-rfusb-tk-plus-lgw-userfs c_rpi4_rfusb_tk_plus_lgw_userfs
run_case rpi4-lgw-only-userfs c_rpi4_lgw_only_userfs
run_case rpi3-rpi-rf-mod-commented-interface0-userfs c_rpi3_rpi_rf_mod_commented_interface0_userfs
run_case rpi3-rpi-rf-mod-rfd-keys-spoiled-userfs c_rpi3_rpi_rf_mod_rfd_keys_spoiled_userfs
run_case rpi3-rpi-rf-mod-ids-zero-userfs c_rpi3_rpi_rf_mod_ids_zero_userfs
run_case rpi3-rpi-rf-mod-wired-userfs c_rpi3_rpi_rf_mod_wired_userfs
run_case rpi4-hmip-rfusb-usb2-gone-userfs c_rpi4_hmip_rfusb_usb2_gone_userfs
run_case rpi3-rpi-rf-mod-hmlgw-mode c_rpi3_rpi_rf_mod_hmlgw_mode

echo "$cases cases, $fails failures"
[ "$fails" -eq 0 ]
