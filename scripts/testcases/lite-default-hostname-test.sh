#!/bin/sh
# openccu-lite (task 327, #4): the host name of a fresh install, against stand-ins (no network,
# no root):
#   - openccu-lite's netconfig template leaves HOSTNAME empty, the rest as upstream's;
#   - occu-network.service runs lite-default-hostname before its start, never failing on it;
#   - an empty HOSTNAME becomes openccu-lite-<last four hex digits of eth0's MAC>, lower case, the
#     rest of netconfig and its mode kept;
#   - a configured name (a switched system's, an earlier install's "openccu") is never touched;
#   - no HOSTNAME line at all: one is added;
#   - no eth0: the next Ethernet or WLAN interface gives the digits; none with an address: plain
#     openccu-lite; a zero address does not count;
#   - eth0 coming late (a module udev loads) is waited for;
#   - no netconfig: nothing written, exit 0.
#
# Usage: sh scripts/testcases/lite-default-hostname-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-default-hostname"
UNIT="$HERE/buildroot-external/overlay/lite/usr/lib/systemd/system/occu-network.service"
TPL="$HERE/buildroot-external/overlay/lite/etc/config_templates/netconfig"
UPSTREAM_TPL="$HERE/buildroot-external/overlay/base-openccu/etc/config_templates/netconfig"

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

sh -n "$SCRIPT" && ok "lite-default-hostname parses" || bad "lite-default-hostname does not parse"
[ -x "$SCRIPT" ] && ok "lite-default-hostname is executable" || bad "lite-default-hostname is not executable"
grep -qx 'ExecStartPre=-/usr/libexec/occu/lite-default-hostname' "$UNIT" && ok "occu-network.service runs it before its start, never failing on it" || bad "no ExecStartPre=-…lite-default-hostname in occu-network.service"
# before S40network, whose eQ3StartNetwork reads the name
pre=$(grep -n 'lite-default-hostname' "$UNIT" | head -1 | cut -d: -f1)
start=$(grep -n '^ExecStart=' "$UNIT" | head -1 | cut -d: -f1)
[ -n "$pre" ] && [ -n "$start" ] && [ "$pre" -lt "$start" ] && ok "it comes before S40network" || bad "it does not come before S40network"

# the template: HOSTNAME empty, everything else upstream's
grep -qx 'HOSTNAME=' "$TPL" && ok "the lite netconfig template leaves HOSTNAME empty" || bad "the lite netconfig template sets a HOSTNAME"
if [ "$(grep -v '^HOSTNAME=' "$TPL")" = "$(grep -v '^HOSTNAME=' "$UPSTREAM_TPL")" ]; then
  ok "the rest of the template is upstream's"
else
  bad "the lite template differs from upstream's beyond HOSTNAME"
fi

# an interface stand-in: <name> <address>
iface() { mkdir -p "$T/net/$1"; printf '%s\n' "$2" > "$T/net/$1/address"; }
reset() { rm -rf "$T/net" "$T/netconfig"; mkdir -p "$T/net"; }
run() { OCCU_NETCONFIG="$T/netconfig" OCCU_SYSNET="$T/net" OCCU_HOSTNAME_WAIT="${WAIT:-3}" sh "$SCRIPT" > "$T/out" 2>&1; echo $?; }
host() { sed -n 's/^HOSTNAME=//p' "$T/netconfig"; }

# a fresh install: the template, eth0 with an upper-case MAC
reset
cp "$TPL" "$T/netconfig"; chmod 640 "$T/netconfig"
iface eth0 'B8:27:EB:12:3F:2A'; iface wlan0 'b8:27:eb:99:88:77'
rc=$(run)
if [ "$rc" = 0 ] && [ "$(host)" = openccu-lite-3f2a ] && grep -q 'default host name of a fresh install: openccu-lite-3f2a (from eth0)' "$T/out"; then
  ok "a fresh install: openccu-lite-3f2a from eth0, lower case"
else
  bad "a fresh install: rc=$rc host=$(host) out=$(cat "$T/out")"
fi
if [ "$(grep -v '^HOSTNAME=' "$T/netconfig")" = "$(grep -v '^HOSTNAME=' "$TPL")" ] && [ "$(grep -c '^HOSTNAME=' "$T/netconfig")" = 1 ]; then
  ok "the rest of netconfig is kept"
else
  bad "netconfig changed beyond HOSTNAME: $(cat "$T/netconfig")"
fi
[ "$(stat -c %a "$T/netconfig")" = 640 ] && ok "netconfig keeps its mode" || bad "netconfig's mode is $(stat -c %a "$T/netconfig")"
[ ! -e "$T/netconfig.lite-default-hostname" ] && ok "no temporary file left" || bad "a temporary file is left"

# a second boot: the name is there, nothing changes (and nothing is waited for)
cp "$T/netconfig" "$T/before"
iface eth0 'b8:27:eb:12:aa:bb'
rc=$(run)
[ "$rc" = 0 ] && cmp -s "$T/before" "$T/netconfig" && [ ! -s "$T/out" ] && ok "a name once set stays, silently" || bad "a set name was changed: $(host)"

# a system switched from OpenCCU, or installed before: its name stays, "openccu" too
for name in openccu attic-ccu; do
  reset
  sed "s/^HOSTNAME=.*/HOSTNAME=$name/" "$TPL" > "$T/netconfig"; cp "$T/netconfig" "$T/before"
  iface eth0 'b8:27:eb:12:3f:2a'
  rc=$(run)
  [ "$rc" = 0 ] && cmp -s "$T/before" "$T/netconfig" && ok "a configured name stays: $name" || bad "a configured name was changed: $name -> $(host)"
done

# no HOSTNAME line at all: one is added, the rest kept
reset
grep -v '^HOSTNAME=' "$TPL" > "$T/netconfig"
iface eth0 '02:00:00:00:a0:01'
rc=$(run)
[ "$rc" = 0 ] && [ "$(host)" = openccu-lite-a001 ] && grep -q '^MODE=DHCP$' "$T/netconfig" && ok "no HOSTNAME line: one is added" || bad "no HOSTNAME line: host=$(host)"

# no eth0: the WLAN interface's address
reset
cp "$TPL" "$T/netconfig"
iface wlan0 'dc:a6:32:00:be:ef'
rc=$(run)
[ "$rc" = 0 ] && [ "$(host)" = openccu-lite-beef ] && grep -q '(from wlan0)' "$T/out" && ok "no eth0: wlan0 gives the digits" || bad "no eth0: host=$(host) out=$(cat "$T/out")"

# eth0 with a zero address: the next interface
reset
cp "$TPL" "$T/netconfig"
iface eth0 '00:00:00:00:00:00'; iface eth1 '52:54:00:12:34:56'
rc=$(run)
[ "$rc" = 0 ] && [ "$(host)" = openccu-lite-3456 ] && ok "a zero address does not count: eth1" || bad "a zero address: host=$(host)"

# no interface with an address: plain openccu-lite
reset
cp "$TPL" "$T/netconfig"
rc=$(run)
[ "$rc" = 0 ] && [ "$(host)" = openccu-lite ] && ok "no address anywhere: openccu-lite" || bad "no address: host=$(host)"

# eth0 comes late: it is waited for
reset
cp "$TPL" "$T/netconfig"
iface wlan0 'dc:a6:32:00:be:ef'
( sleep 0.5; mkdir -p "$T/net/eth0.new"; printf 'b8:27:eb:00:1a:2b\n' > "$T/net/eth0.new/address"; mv "$T/net/eth0.new" "$T/net/eth0" ) &
rc=$(WAIT=50 run)
wait
[ "$rc" = 0 ] && [ "$(host)" = openccu-lite-1a2b ] && ok "a late eth0 is waited for" || bad "a late eth0: host=$(host) out=$(cat "$T/out")"

# no netconfig: nothing written, exit 0
reset
iface eth0 'b8:27:eb:12:3f:2a'
rc=$(run)
[ "$rc" = 0 ] && [ ! -e "$T/netconfig" ] && grep -q 'no .*netconfig' "$T/out" && ok "no netconfig: nothing written, exit 0" || bad "no netconfig: rc=$rc"

if [ "$fails" -gt 0 ]; then
  echo "$fails failed"
  exit 1
fi
echo "all passed"
